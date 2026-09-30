# Face Verification SDK — Design

## Goal
Drop-in iOS SDK that shows the 4-state "Face recognition" screen from the design
(positioning → processing → success | failure), captures a good face image using
native Vision/AVFoundation only, and returns the result via callback. No networking.

## Decisions
- Swift Package, iOS 15+, SwiftUI UI with UIKit entry point (`UIHostingController`).
- Capture checks (Vision): exactly one face, centered in circle, correct size,
  roll/yaw within ~20°. Best frame chosen via `VNDetectFaceCaptureQualityRequest`.
- Optional blink liveness (`requireBlink`, off by default) using eye-landmark openness
  relative to the user's own open-eye baseline.
- Optional async `verify: (UIImage) async throws -> Bool` closure. If present, the
  SDK shows Processing while it runs and shows Success/Failure based on its result.
  If absent, a valid capture = success.
- Result: `.success(UIImage)`, `.failure(FaceVerificationError)`, `.cancelled`.
- Errors: camera permission denied (failure state shows "Open Settings"), camera
  unavailable, timeout (default 30s), rejected (verify returned false),
  verificationFailed(Error) (verify threw).
- All strings and colors configurable via `FaceVerificationConfig`.

## Units
- `FaceQualityEvaluator` (pure): frame analysis → `FaceHint`.
- `BlinkDetector` (pure): eye openness stream → blinked?
- `FaceAnalyzer`: CVPixelBuffer → `FrameAnalysis` via Vision.
- `CameraSession`: AVCaptureSession, front camera, portrait, mirrored frames.
- `VerificationViewModel` (@MainActor): state machine; camera injected via
  `CameraControlling` protocol so it is unit-testable.
- UI: `VerificationScreen`, `FaceCircleView`, `CameraPreviewView`.

## Testing
Unit tests for evaluator, blink detector and view-model state machine (mock camera).
Camera/Vision paths verified on a physical device (simulator has no camera).
