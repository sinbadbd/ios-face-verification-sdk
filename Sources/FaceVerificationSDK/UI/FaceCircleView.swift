import AVFoundation
import SwiftUI

/// Circular face frame: live preview / captured image with a state-colored ring and badge.
struct FaceCircleView: View {
    let state: VerificationViewModel.State
    let session: AVCaptureSession?
    let capturedImage: UIImage?
    let theme: FaceVerificationConfig.Theme
    var diameter: CGFloat = 180

    @State private var spin = false

    var body: some View {
        ZStack {
            content
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())

            ring
                .frame(width: diameter + 10, height: diameter + 10)

            badge
        }
        .frame(width: diameter + 14, height: diameter + 14)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .positioning, .challenge:
            CameraPreviewView(session: session)
        case .processing, .success:
            if let capturedImage {
                Image(uiImage: capturedImage).resizable().scaledToFill()
            } else {
                Color.black
            }
        case .failure:
            Color.black
        }
    }

    @ViewBuilder
    private var ring: some View {
        switch state {
        case .positioning(let hint):
            Circle().stroke(hint == .ready ? theme.success : theme.idleRing, lineWidth: 3)
        case .challenge(_, let step, let total):
            ZStack {
                Circle().stroke(theme.idleRing, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(step - 1) / CGFloat(max(total, 1)))
                    .stroke(theme.success, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: step)
            }
        case .processing:
            Circle()
                .stroke(theme.success, style: StrokeStyle(lineWidth: 4, dash: [7, 5]))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear {
                    withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true }
                }
                .onDisappear { spin = false }
        case .success:
            Circle().stroke(theme.success, lineWidth: 4)
        case .failure:
            Circle().stroke(theme.failure, lineWidth: 4)
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .success:
            Circle()
                .fill(theme.success)
                .frame(width: diameter * 0.32, height: diameter * 0.32)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: diameter * 0.15, weight: .bold))
                        .foregroundColor(.white)
                )
                .transition(.scale.combined(with: .opacity))
        case .failure:
            Circle()
                .fill(theme.failureBadgeBackground)
                .frame(width: diameter * 0.3, height: diameter * 0.3)
                .overlay(
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: diameter * 0.12, weight: .semibold))
                        .foregroundColor(theme.failure)
                )
                .transition(.scale.combined(with: .opacity))
        case .challenge(let challenge, _, _):
            challengeCue(challenge)
                .id(challenge)
                .transition(.opacity)
        case .positioning, .processing:
            EmptyView()
        }
    }

    /// Arrow at the edge of the circle the user should turn toward (the preview is mirrored,
    /// so the user's left is the screen's left), or an eye for blink.
    private func challengeCue(_ challenge: LivenessChallenge) -> some View {
        let edge = diameter / 2 - 26
        let (symbol, offset): (String, CGSize) = {
            switch challenge {
            case .turnLeft: return ("arrow.left", CGSize(width: -edge, height: 0))
            case .turnRight: return ("arrow.right", CGSize(width: edge, height: 0))
            case .lookUp: return ("arrow.up", CGSize(width: 0, height: -edge))
            case .lookDown: return ("arrow.down", CGSize(width: 0, height: edge))
            case .blink: return ("eye", CGSize(width: 0, height: edge))
            }
        }()
        return Image(systemName: symbol)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(theme.success))
            .offset(offset)
    }
}
