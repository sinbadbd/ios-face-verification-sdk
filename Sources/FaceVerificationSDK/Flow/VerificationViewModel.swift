import AVFoundation
import UIKit

@MainActor
final class VerificationViewModel: ObservableObject {
    enum State: Equatable {
        case positioning(FaceHint)
        /// A liveness prompt; `step` is 1-based.
        case challenge(LivenessChallenge, step: Int, total: Int)
        case processing
        case success
        case failure(FaceVerificationError)
    }

    /// Scanning runs positioning → each challenge in order → a final centered hold that captures the photo.
    private enum Phase {
        case positioning
        case challenges
        case final
    }

    @Published private(set) var state: State
    @Published private(set) var capturedImage: UIImage?
    /// Head angles and eye openness of the last frame, when `showsDebugInfo` is on.
    @Published private(set) var debugText: String?

    let config: FaceVerificationConfig
    var captureSession: AVCaptureSession? { camera.captureSession }

    private let camera: CameraControlling
    private let verify: FaceVerifier?
    private let onFinish: (FaceVerificationResult) -> Void
    private let evaluator = FaceQualityEvaluator()

    private var phase = Phase.positioning
    private var tracker: ChallengeTracker
    private var eyes = BlinkDetector()
    private var startedAt: TimeInterval?
    private var phaseStartedAt: TimeInterval?
    private var stableSince: TimeInterval?
    private var best: (image: UIImage, quality: Float)?
    private var processingTask: Task<Void, Never>?
    private var isFinished = false

    init(
        config: FaceVerificationConfig,
        camera: CameraControlling,
        verify: FaceVerifier?,
        onFinish: @escaping (FaceVerificationResult) -> Void,
        initialState: State = .positioning(.noFace)
    ) {
        self.config = config
        self.camera = camera
        self.verify = verify
        self.onFinish = onFinish
        self.state = initialState
        self.tracker = ChallengeTracker(challenges: config.effectiveChallenges)

        camera.onFrame = { [weak self] analysis, time, makeImage in
            self?.process(analysis, at: time, makeImage: makeImage)
        }
        camera.onError = { [weak self] error in
            self?.fail(error)
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard await camera.requestAccess() else {
            fail(.cameraPermissionDenied)
            return
        }
        guard case .positioning = state else { return }
        camera.start()
    }

    func stopCamera() {
        camera.stop()
    }

    // MARK: - User actions

    /// Bottom button: Continue (success), Try again / Open Settings (failure).
    func primaryAction() {
        switch state {
        case .success:
            if let capturedImage { finish(.success(capturedImage)) }
        case .failure(.cameraPermissionDenied):
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .failure:
            retry()
        case .positioning, .challenge, .processing:
            break
        }
    }

    /// Back button.
    func cancel() {
        if case .failure(let error) = state {
            finish(.failure(error))
        } else {
            finish(.cancelled)
        }
    }

    func retry() {
        processingTask?.cancel()
        restartScan()
        capturedImage = nil
        startedAt = nil
        state = .positioning(.noFace)
        Task { await start() }
    }

    // MARK: - Frame processing

    func process(_ frame: FrameAnalysis, at time: TimeInterval, makeImage: () -> UIImage?) {
        switch state {
        case .positioning, .challenge: break
        case .processing, .success, .failure: return
        }
        if config.showsDebugInfo { debugText = Self.debugDescription(of: frame) }
        if startedAt == nil { startedAt = time }

        switch phase {
        case .positioning:
            if let startedAt, time - startedAt > config.timeout {
                fail(.timeout)
                return
            }
            guard holdStill(frame, at: time, makeImage: makeImage) else { return }
            if tracker.isComplete {
                captureBest()
            } else {
                phase = .challenges
                phaseStartedAt = time
                publishChallenge()
            }

        case .challenges:
            // A lost or second face may be a different person: start over.
            guard frame.faces.count == 1, let face = frame.faces.first else {
                restartScan(at: time)
                state = .positioning(evaluator.evaluate(frame))
                return
            }
            if tracker.update(face) { phaseStartedAt = time }
            if tracker.isComplete {
                phase = .final
                phaseStartedAt = time
                resetHold()
                state = .positioning(.lookStraight)
                return
            }
            if let phaseStartedAt, time - phaseStartedAt > config.challengeTimeout {
                fail(.livenessFailed)
                return
            }
            publishChallenge()

        case .final:
            if frame.faces.count != 1 {
                restartScan(at: time)
                state = .positioning(evaluator.evaluate(frame))
                return
            }
            if let phaseStartedAt, time - phaseStartedAt > config.challengeTimeout {
                fail(.livenessFailed)
                return
            }
            if holdStill(frame, at: time, makeImage: makeImage) { captureBest() }
        }
    }

    // MARK: - Private

    /// Tracks the face being well placed; keeps the sharpest eyes-open frame.
    /// Returns `true` once it has been held for `stabilityDuration`.
    private func holdStill(_ frame: FrameAnalysis, at time: TimeInterval, makeImage: () -> UIImage?) -> Bool {
        let hint = evaluator.evaluate(frame)
        guard hint == .ready, let face = frame.faces.first else {
            resetHold()
            state = .positioning(hint)
            return false
        }

        eyes.update(openness: face.eyeOpenness)
        let quality = face.captureQuality ?? 0
        if !eyes.eyesClosed, best == nil || quality > best!.quality, let image = makeImage() {
            best = (image, quality)
        }
        if stableSince == nil { stableSince = time }
        state = .positioning(.ready)

        guard let stableSince, time - stableSince >= config.stabilityDuration, best != nil else { return false }
        return true
    }

    private func publishChallenge() {
        guard let challenge = tracker.current else { return }
        state = .challenge(challenge, step: tracker.index + 1, total: tracker.challenges.count)
    }

    private func captureBest() {
        guard let image = best?.image else { return }
        camera.stop()
        capturedImage = image
        state = .processing

        let verify = verify
        let minimumDuration = config.minimumProcessingDuration
        processingTask = Task { [weak self] in
            let started = Date()
            let outcome: State
            if let verify {
                do {
                    outcome = try await verify(image) ? .success : .failure(.rejected)
                } catch {
                    outcome = .failure(.verificationFailed(error))
                }
            } else {
                outcome = .success
            }
            let remaining = minimumDuration - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            guard !Task.isCancelled, let self, self.state == .processing else { return }
            self.state = outcome
        }
    }

    private func fail(_ error: FaceVerificationError) {
        camera.stop()
        restartScan()
        state = .failure(error)
    }

    /// Back to the first phase. `time` restarts the positioning timeout.
    private func restartScan(at time: TimeInterval? = nil) {
        phase = .positioning
        phaseStartedAt = nil
        tracker.reset()
        eyes.reset()
        resetHold()
        if let time { startedAt = time }
    }

    private func resetHold() {
        stableSince = nil
        best = nil
    }

    private func finish(_ result: FaceVerificationResult) {
        guard !isFinished else { return }
        isFinished = true
        processingTask?.cancel()
        camera.stop()
        onFinish(result)
    }

    private static func debugDescription(of frame: FrameAnalysis) -> String {
        guard let face = frame.faces.first else { return "faces: 0" }
        func deg(_ radians: Double?) -> String {
            radians.map { String(format: "%.0f°", $0 * 180 / .pi) } ?? "–"
        }
        let eyes = face.eyeOpenness.map { String(format: "%.2f", $0) } ?? "–"
        return "faces: \(frame.faces.count)  yaw: \(deg(face.yaw))  pitch: \(deg(face.pitch))  roll: \(deg(face.roll))  eyes: \(eyes)"
    }
}
