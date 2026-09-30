import SwiftUI
import UIKit

/// Optional verification step run after capture. Return `true` to accept the face.
public typealias FaceVerifier = (UIImage) async throws -> Bool

public enum FaceVerificationResult {
    case success(UIImage)
    case failure(FaceVerificationError)
    case cancelled
}

public enum FaceVerificationError: Error, Equatable {
    case cameraPermissionDenied
    case cameraUnavailable
    case timeout
    /// The `verify` closure returned `false`.
    case rejected
    /// The `verify` closure threw.
    case verificationFailed(Error)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.cameraPermissionDenied, .cameraPermissionDenied),
             (.cameraUnavailable, .cameraUnavailable),
             (.timeout, .timeout),
             (.rejected, .rejected):
            return true
        case let (.verificationFailed(a), .verificationFailed(b)):
            return a.localizedDescription == b.localizedDescription
        default:
            return false
        }
    }
}

public enum FaceVerification {
    /// Presents the face verification screen full screen (UIKit).
    ///
    /// The host app's Info.plist must contain `NSCameraUsageDescription`.
    @MainActor
    public static func present(
        from presenter: UIViewController,
        config: FaceVerificationConfig = .init(),
        verify: FaceVerifier? = nil,
        completion: @escaping (FaceVerificationResult) -> Void
    ) {
        weak var host: UIViewController?
        let view = FaceVerificationView(config: config, verify: verify) { result in
            if let host {
                host.dismiss(animated: true) { completion(result) }
            } else {
                completion(result)
            }
        }
        let controller = UIHostingController(rootView: view)
        controller.modalPresentationStyle = .fullScreen
        host = controller
        presenter.present(controller, animated: true)
    }
}

/// The face verification screen as a SwiftUI view. `onFinish` is called exactly once.
public struct FaceVerificationView: View {
    @StateObject private var viewModel: VerificationViewModel

    public init(
        config: FaceVerificationConfig = .init(),
        verify: FaceVerifier? = nil,
        onFinish: @escaping (FaceVerificationResult) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: VerificationViewModel(
            config: config,
            camera: CameraSession(position: config.cameraPosition, detectLandmarks: config.requireBlink),
            verify: verify,
            onFinish: onFinish
        ))
    }

    public var body: some View {
        VerificationScreen(viewModel: viewModel)
            .task { await viewModel.start() }
            .onDisappear { viewModel.stopCamera() }
    }
}

extension View {
    /// Presents the face verification screen full screen (SwiftUI).
    public func faceVerification(
        isPresented: Binding<Bool>,
        config: FaceVerificationConfig = .init(),
        verify: FaceVerifier? = nil,
        completion: @escaping (FaceVerificationResult) -> Void
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            FaceVerificationView(config: config, verify: verify) { result in
                isPresented.wrappedValue = false
                completion(result)
            }
        }
    }
}
