import AVFoundation
import SwiftUI
import XCTest
@testable import FaceVerificationSDK

@MainActor private final class Cam: CameraControlling {
    var onFrame: ((FrameAnalysis, TimeInterval, () -> UIImage?) -> Void)?
    var onError: ((FaceVerificationError) -> Void)?
    var captureSession: AVCaptureSession? { nil }
    func requestAccess() async -> Bool { true }
    func start() {}
    func stop() {}
}

@available(iOS 16, *)
@MainActor final class TmpSnapshot: XCTestCase {
    func testRender() throws {
        let states: [(String, VerificationViewModel.State)] = [("1pos", .positioning(.centerFace)), ("2proc", .processing), ("3ok", .success), ("4fail", .failure(.rejected))]
        for (name, s) in states {
            let vm = VerificationViewModel(config: .init(), camera: Cam(), verify: nil, onFinish: { _ in }, initialState: s)
            let r = ImageRenderer(content: VerificationScreen(viewModel: vm).frame(width: 390, height: 844))
            r.scale = 2
            try r.uiImage!.pngData()!.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Volumes-Sinbad-dev-iOS-BnSApp-ios-face-verification-sdk/bcca8790-0e3f-4a83-9f33-ca7c2d39476e/scratchpad/\(name).png"))
        }
    }
}
