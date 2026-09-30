import AVFoundation
import UIKit

@MainActor
final class VerificationViewModel: ObservableObject {
    enum State: Equatable {
        case positioning(FaceHint)
        case processing
        case success
        case failure(FaceVerificationError)
    }

    @Published private(set) var state: State
    @Published private(set) var capturedImage: UIImage?

    let config: FaceVerificationConfig
    var captureSession: AVCaptureSession? { camera.captureSession }

    private let camera: CameraControlling
    private let verify: FaceVerifier?
    private let onFinish: (FaceVerificationResult) -> Void
    private let evaluator = FaceQualityEvaluator()

    private var blink = BlinkDetector()
    private var startedAt: TimeInterval?
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
        case .positioning, .processing:
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
        resetCapture()
        capturedImage = nil
        startedAt = nil
        state = .positioning(.noFace)
        Task { await start() }
    }

    // MARK: - Frame processing

    func process(_ frame: FrameAnalysis, at time: TimeInterval, makeImage: () -> UIImage?) {
        guard case .positioning = state else { return }

        if startedAt == nil { startedAt = time }
        if let startedAt, time - startedAt > config.timeout {
            fail(.timeout)
            return
        }

        let hint = evaluator.evaluate(frame)
        guard hint == .ready, let face = frame.faces.first else {
            // A different face may appear after losing the face, so liveness must restart.
            if hint == .noFace || hint == .multipleFaces { blink.reset() }
            resetCapture(keepBlink: true)
            state = .positioning(hint)
            return
        }

        if config.requireBlink { blink.update(openness: face.eyeOpenness) }
        let eyesOpen = !config.requireBlink || !blink.eyesClosed
        let quality = face.captureQuality ?? 0
        if eyesOpen, best == nil || quality > best!.quality, let image = makeImage() {
            best = (image, quality)
        }

        if stableSince == nil { stableSince = time }

        if config.requireBlink, !blink.hasBlinked {
            state = .positioning(.blink)
            return
        }
        state = .positioning(.ready)

        if let stableSince, time - stableSince >= config.stabilityDuration, let best {
            capture(best.image)
        }
    }

    // MARK: - Private

    private func capture(_ image: UIImage) {
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
        resetCapture()
        state = .failure(error)
    }

    private func resetCapture(keepBlink: Bool = false) {
        stableSince = nil
        best = nil
        if !keepBlink { blink.reset() }
    }

    private func finish(_ result: FaceVerificationResult) {
        guard !isFinished else { return }
        isFinished = true
        processingTask?.cancel()
        camera.stop()
        onFinish(result)
    }
}
