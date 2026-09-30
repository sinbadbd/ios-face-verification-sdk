import AVFoundation
import SwiftUI

/// Full "Face recognition" screen: nav bar, card with face circle + message, bottom button.
struct VerificationScreen: View {
    @ObservedObject var viewModel: VerificationViewModel

    private var strings: FaceVerificationConfig.Strings { viewModel.config.strings }
    private var theme: FaceVerificationConfig.Theme { viewModel.config.theme }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            card
                .padding(.horizontal, 16)
                .padding(.top, 24)
            Spacer(minLength: 0)
            if let buttonTitle {
                bottomBar(title: buttonTitle)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(theme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: viewModel.state)
    }

    // MARK: - Sections

    private var navigationBar: some View {
        ZStack {
            Text(strings.navigationTitle)
                .font(theme.font(size: 16, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            HStack {
                Button(action: viewModel.cancel) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    private var card: some View {
        VStack(spacing: 20) {
            FaceCircleView(
                state: viewModel.state,
                session: viewModel.captureSession,
                capturedImage: viewModel.capturedImage,
                theme: theme
            )

            Text(title)
                .font(theme.font(size: 18, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(hint ?? " ")
                .font(theme.font(size: 14, weight: .regular))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .opacity(hint == nil ? 0 : 1)

            if let debugText = viewModel.debugText {
                Text(debugText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 56)
        .frame(maxWidth: .infinity)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func bottomBar(title: String) -> some View {
        Button(action: viewModel.primaryAction) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "arrow.right")
            }
            .font(theme.font(size: 15, weight: .semibold))
            .foregroundColor(theme.buttonText)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(theme.buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(12)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - State → content

    private var title: String {
        switch viewModel.state {
        case .positioning: return strings.positionFace
        case .challenge(let challenge, _, _): return strings.text(for: challenge)
        case .processing: return strings.processing
        case .success: return strings.success
        case .failure(.cameraPermissionDenied): return strings.cameraPermissionDenied
        case .failure: return strings.failure
        }
    }

    private var hint: String? {
        switch viewModel.state {
        case .positioning(let hint):
            return strings.text(for: hint)
        case .challenge(_, let step, let total):
            return String(format: strings.challengeStepFormat, step, total)
        case .processing, .success, .failure:
            return nil
        }
    }

    private var buttonTitle: String? {
        switch viewModel.state {
        case .success: return strings.continueButton
        case .failure(.cameraPermissionDenied): return strings.openSettingsButton
        case .failure: return strings.tryAgainButton
        case .positioning, .challenge, .processing: return nil
        }
    }
}

// MARK: - Previews

@MainActor
private final class PreviewCamera: CameraControlling {
    var onFrame: ((FrameAnalysis, TimeInterval, () -> UIImage?) -> Void)?
    var onError: ((FaceVerificationError) -> Void)?
    var captureSession: AVCaptureSession? { nil }
    func requestAccess() async -> Bool { true }
    func start() {}
    func stop() {}
}

@MainActor
private func previewScreen(_ state: VerificationViewModel.State) -> some View {
    VerificationScreen(viewModel: VerificationViewModel(
        config: .init(), camera: PreviewCamera(), verify: nil, onFinish: { _ in }, initialState: state
    ))
}

#Preview("Positioning") { previewScreen(.positioning(.centerFace)) }
#Preview("Challenge") { previewScreen(.challenge(.turnLeft, step: 2, total: 5)) }
#Preview("Processing") { previewScreen(.processing) }
#Preview("Success") { previewScreen(.success) }
#Preview("Failure") { previewScreen(.failure(.rejected)) }
