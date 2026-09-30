import AVFoundation
import XCTest
@testable import FaceVerificationSDK

@MainActor
private final class MockCamera: CameraControlling {
    var onFrame: ((FrameAnalysis, TimeInterval, () -> UIImage?) -> Void)?
    var onError: ((FaceVerificationError) -> Void)?
    var captureSession: AVCaptureSession? { nil }
    var accessGranted = true
    var startCount = 0
    var stopCount = 0

    func requestAccess() async -> Bool { accessGranted }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }

    func send(_ faces: [FaceObservation], at time: TimeInterval) {
        onFrame?(FrameAnalysis(faces: faces, imageSize: CGSize(width: 720, height: 1280)), time, { UIImage() })
    }
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
final class VerificationViewModelTests: XCTestCase {
    private var camera: MockCamera!
    private var results: [FaceVerificationResult] = []

    private let goodFace = FaceObservation(
        boundingBox: CGRect(x: 0.2, y: 0.33, width: 0.6, height: 0.34), roll: 0, yaw: 0, captureQuality: 0.5
    )

    override func setUp() async throws {
        camera = MockCamera()
        results = []
    }

    private let left = 0.5 * ChallengeTracker.userLeftYawSign
    private let up = 0.4 * ChallengeTracker.lookUpPitchSign

    private func makeViewModel(requireBlink: Bool = false, challenges: [LivenessChallenge] = [],
                               verify: FaceVerifier? = nil) -> VerificationViewModel {
        var config = FaceVerificationConfig()
        config.requireBlink = requireBlink
        config.challenges = challenges
        config.challengeTimeout = 8
        config.minimumProcessingDuration = 0
        config.stabilityDuration = 1
        config.timeout = 10
        return VerificationViewModel(config: config, camera: camera, verify: verify) { [weak self] in
            self?.results.append($0)
        }
    }

    private func turned(yaw: Double = 0, pitch: Double = 0) -> FaceObservation {
        var face = goodFace
        face.yaw = yaw
        face.pitch = pitch
        return face
    }

    private func face(eyes: Double) -> FaceObservation {
        var face = goodFace
        face.eyeOpenness = eyes
        return face
    }

    private func waitForState(_ vm: VerificationViewModel, _ expected: VerificationViewModel.State,
                              file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 where vm.state != expected {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(vm.state, expected, file: file, line: line)
    }

    func testPermissionDeniedShowsFailureAndDoesNotStartCamera() async {
        camera.accessGranted = false
        let vm = makeViewModel()
        await vm.start()
        XCTAssertEqual(vm.state, .failure(.cameraPermissionDenied))
        XCTAssertEqual(camera.startCount, 0)
    }

    func testHintFollowsFaceQuality() async {
        let vm = makeViewModel()
        await vm.start()
        XCTAssertEqual(camera.startCount, 1)
        camera.send([], at: 0)
        XCTAssertEqual(vm.state, .positioning(.noFace))
        camera.send([goodFace], at: 0.1)
        XCTAssertEqual(vm.state, .positioning(.ready))
    }

    func testStableFaceCapturesAndSucceedsWithoutVerifier() async {
        let vm = makeViewModel()
        await vm.start()
        camera.send([goodFace], at: 0)
        camera.send([goodFace], at: 0.5)
        XCTAssertEqual(vm.state, .positioning(.ready))
        camera.send([goodFace], at: 1.1)
        XCTAssertNotNil(vm.capturedImage)
        await waitForState(vm, .success)

        vm.primaryAction()
        guard case .success = results.first else { return XCTFail("expected success result") }
        XCTAssertEqual(results.count, 1)
    }

    func testLosingFaceResetsStabilityTimer() async {
        let vm = makeViewModel()
        await vm.start()
        camera.send([goodFace], at: 0)
        camera.send([], at: 0.8)
        camera.send([goodFace], at: 1.2)
        XCTAssertEqual(vm.state, .positioning(.ready))
        camera.send([goodFace], at: 2.3)
        XCTAssertNotEqual(vm.state, .positioning(.ready))
    }

    func testVerifierRejectionShowsFailureAndRetryRestarts() async {
        let vm = makeViewModel(verify: { _ in false })
        await vm.start()
        camera.send([goodFace], at: 0)
        camera.send([goodFace], at: 1.1)
        await waitForState(vm, .failure(.rejected))

        vm.primaryAction() // Try again
        XCTAssertEqual(vm.state, .positioning(.noFace))
        XCTAssertNil(vm.capturedImage)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(camera.startCount, 2)
    }

    func testVerifierErrorShowsVerificationFailed() async {
        let vm = makeViewModel(verify: { _ in throw TestError() })
        await vm.start()
        camera.send([goodFace], at: 0)
        camera.send([goodFace], at: 1.1)
        await waitForState(vm, .failure(.verificationFailed(TestError())))
    }

    func testVerifierAcceptanceSucceeds() async {
        let vm = makeViewModel(verify: { _ in true })
        await vm.start()
        camera.send([goodFace], at: 0)
        camera.send([goodFace], at: 1.1)
        await waitForState(vm, .success)
    }

    func testTimeout() async {
        let vm = makeViewModel()
        await vm.start()
        camera.send([], at: 0)
        camera.send([], at: 10.5)
        XCTAssertEqual(vm.state, .failure(.timeout))
    }

    func testRequireBlinkRunsBlinkChallengeThenCapturesCentered() async {
        let vm = makeViewModel(requireBlink: true)
        await vm.start()
        camera.send([face(eyes: 0.3)], at: 0)
        camera.send([face(eyes: 0.3)], at: 1.0)
        XCTAssertEqual(vm.state, .challenge(.blink, step: 1, total: 1))

        [0.3, 0.3, 0.3, 0.1].enumerated().forEach { camera.send([face(eyes: $1)], at: 1.1 + Double($0) * 0.1) }
        XCTAssertEqual(vm.state, .challenge(.blink, step: 1, total: 1))
        camera.send([face(eyes: 0.3)], at: 1.6)
        XCTAssertEqual(vm.state, .positioning(.lookStraight))

        camera.send([face(eyes: 0.3)], at: 1.7)
        XCTAssertEqual(vm.state, .positioning(.ready))
        camera.send([face(eyes: 0.3)], at: 2.8)
        XCTAssertEqual(vm.state, .processing)
    }

    func testChallengesRunInOrder() async {
        let vm = makeViewModel(challenges: [.turnLeft, .turnRight, .lookUp, .lookDown])
        await vm.start()
        camera.send([goodFace], at: 0)
        camera.send([goodFace], at: 1.0)
        XCTAssertEqual(vm.state, .challenge(.turnLeft, step: 1, total: 4))

        camera.send([turned(yaw: -left)], at: 1.2) // right first: ignored
        XCTAssertEqual(vm.state, .challenge(.turnLeft, step: 1, total: 4))
        camera.send([turned(yaw: left)], at: 1.4)
        XCTAssertEqual(vm.state, .challenge(.turnRight, step: 2, total: 4))

        camera.send([goodFace], at: 1.6)
        camera.send([turned(yaw: -left)], at: 1.8)
        XCTAssertEqual(vm.state, .challenge(.lookUp, step: 3, total: 4))

        camera.send([goodFace], at: 2.0)
        camera.send([turned(pitch: up)], at: 2.2)
        XCTAssertEqual(vm.state, .challenge(.lookDown, step: 4, total: 4))

        camera.send([goodFace], at: 2.4)
        camera.send([turned(pitch: -up)], at: 2.6)
        XCTAssertEqual(vm.state, .positioning(.lookStraight))

        camera.send([goodFace], at: 2.8)
        camera.send([goodFace], at: 3.9)
        XCTAssertEqual(vm.state, .processing)
        await waitForState(vm, .success)
    }

    func testLosingFaceDuringChallengesRestartsFromPositioning() async {
        let vm = makeViewModel(challenges: [.turnLeft, .turnRight])
        await vm.start()
        camera.send([goodFace], at: 0)
        camera.send([goodFace], at: 1.0)
        camera.send([turned(yaw: left)], at: 1.2)
        XCTAssertEqual(vm.state, .challenge(.turnRight, step: 2, total: 2))

        camera.send([], at: 1.4)
        XCTAssertEqual(vm.state, .positioning(.noFace))
        camera.send([goodFace], at: 1.6)
        camera.send([goodFace], at: 2.6)
        XCTAssertEqual(vm.state, .challenge(.turnLeft, step: 1, total: 2))
    }

    func testChallengeTimeoutFailsWithLivenessFailed() async {
        let vm = makeViewModel(challenges: [.turnLeft])
        await vm.start()
        camera.send([goodFace], at: 0)
        camera.send([goodFace], at: 1.0)
        camera.send([goodFace], at: 5.0)
        XCTAssertEqual(vm.state, .challenge(.turnLeft, step: 1, total: 1))
        camera.send([goodFace], at: 9.1)
        XCTAssertEqual(vm.state, .failure(.livenessFailed))
    }

    func testCancelReportsCancelledOnce() async {
        let vm = makeViewModel()
        await vm.start()
        vm.cancel()
        vm.cancel()
        XCTAssertEqual(results.count, 1)
        guard case .cancelled = results.first else { return XCTFail("expected cancelled") }
    }

    func testCancelOnFailureReportsError() async {
        camera.accessGranted = false
        let vm = makeViewModel()
        await vm.start()
        vm.cancel()
        guard case .failure(.cameraPermissionDenied) = results.first else { return XCTFail("expected failure") }
    }
}
