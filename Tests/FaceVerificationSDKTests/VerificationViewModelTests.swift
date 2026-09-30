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

    private func makeViewModel(requireBlink: Bool = false, verify: FaceVerifier? = nil) -> VerificationViewModel {
        var config = FaceVerificationConfig()
        config.requireBlink = requireBlink
        config.minimumProcessingDuration = 0
        config.stabilityDuration = 1
        config.timeout = 10
        return VerificationViewModel(config: config, camera: camera, verify: verify) { [weak self] in
            self?.results.append($0)
        }
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

    func testBlinkRequiredBeforeCapture() async {
        let vm = makeViewModel(requireBlink: true)
        await vm.start()
        for (i, eyes) in [0.3, 0.3, 0.3, 0.3].enumerated() {
            camera.send([face(eyes: eyes)], at: Double(i) * 0.5)
        }
        XCTAssertEqual(vm.state, .positioning(.blink)) // stable 1.5s but no blink yet

        camera.send([face(eyes: 0.1)], at: 2.0)
        XCTAssertEqual(vm.state, .positioning(.blink))
        camera.send([face(eyes: 0.3)], at: 2.1)
        XCTAssertEqual(vm.state, .processing)
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
