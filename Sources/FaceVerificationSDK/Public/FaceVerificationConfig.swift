import AVFoundation
import SwiftUI

/// Configuration for the face verification flow. All values have sensible defaults.
public struct FaceVerificationConfig {
    /// Require the user to blink once before capture (simple liveness check).
    public var requireBlink = false
    /// Seconds allowed in the positioning state before failing with `.timeout`.
    public var timeout: TimeInterval = 30
    /// Seconds the face must stay correctly positioned before capture.
    public var stabilityDuration: TimeInterval = 1.0
    /// Minimum time the "Processing" state is shown, so it doesn't just flash.
    public var minimumProcessingDuration: TimeInterval = 0.8
    public var cameraPosition: AVCaptureDevice.Position = .front
    public var strings = Strings()
    public var theme = Theme()

    public init() {}

    public struct Strings {
        public var navigationTitle = "Face recognition"
        public var positionFace = "Position your face to\nfit the frame"
        public var processing = "Processing"
        public var success = "Your face scan is\ncomplete"
        public var failure = "Could not complete\nface recognition"
        public var cameraPermissionDenied = "Camera access is needed\nto scan your face"
        public var continueButton = "Continue"
        public var tryAgainButton = "Try again"
        public var openSettingsButton = "Open Settings"

        public var hintNoFace = "No face detected"
        public var hintMultipleFaces = "Make sure only one face is visible"
        public var hintMoveCloser = "Move closer"
        public var hintMoveBack = "Move back a little"
        public var hintCenterFace = "Center your face in the circle"
        public var hintLookStraight = "Look straight at the camera"
        public var hintBlink = "Blink your eyes"
        public var hintReady = "Hold still"

        public init() {}

        func text(for hint: FaceHint) -> String {
            switch hint {
            case .noFace: return hintNoFace
            case .multipleFaces: return hintMultipleFaces
            case .moveCloser: return hintMoveCloser
            case .moveBack: return hintMoveBack
            case .centerFace: return hintCenterFace
            case .lookStraight: return hintLookStraight
            case .blink: return hintBlink
            case .ready: return hintReady
            }
        }
    }

    public struct Theme {
        public var background = Color(hex: 0xEFF1F6)
        public var card = Color.white
        public var textPrimary = Color(hex: 0x1B1B2F)
        public var textSecondary = Color(hex: 0x6B6B80)
        public var idleRing = Color(hex: 0xDCDAF0)
        public var success = Color(hex: 0x5DBB6E)
        public var failure = Color(hex: 0xE0665A)
        public var failureBadgeBackground = Color(hex: 0xF8D7D7)
        public var buttonBackground = Color(hex: 0x1E1B2E)
        public var buttonText = Color.white
        /// Custom font name (e.g. "Manrope-SemiBold"). `nil` uses the system font.
        public var fontName: String?

        public init() {}

        func font(size: CGFloat, weight: Font.Weight) -> Font {
            if let fontName { return .custom(fontName, size: size) }
            return .system(size: size, weight: weight)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
