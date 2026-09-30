import CoreGraphics

/// Guidance shown to the user while positioning their face.
public enum FaceHint: Equatable {
    case noFace
    case multipleFaces
    case moveCloser
    case moveBack
    case centerFace
    case lookStraight
    case blink
    case ready
}

/// A detected face in one camera frame.
struct FaceObservation: Equatable {
    /// Normalized (0...1) bounding box in Vision coordinates (origin bottom-left).
    var boundingBox: CGRect
    /// Radians. `nil` when Vision could not estimate it.
    var roll: Double?
    var yaw: Double?
    /// Vision capture quality (0...1), used to pick the best frame.
    var captureQuality: Float?
    /// Eye height / width ratio averaged over both eyes. Only set when landmarks are detected.
    var eyeOpenness: Double?
}

struct FrameAnalysis: Equatable {
    var faces: [FaceObservation]
    /// Pixel size of the (upright) frame.
    var imageSize: CGSize
}

/// Decides whether a face is positioned correctly inside the on-screen circle.
///
/// The circle preview shows the centered square of the frame (aspect fill), so the
/// guide circle is centered in the frame with diameter `min(width, height)`.
struct FaceQualityEvaluator {
    /// Max distance of face center from circle center, as a fraction of the radius.
    var maxCenterOffset: CGFloat = 0.25
    /// Face width as a fraction of the circle diameter.
    var minFaceWidth: CGFloat = 0.35
    var maxFaceWidth: CGFloat = 0.85
    /// Max roll / yaw in radians (~20°).
    var maxAngle: Double = 0.35

    func evaluate(_ frame: FrameAnalysis) -> FaceHint {
        guard !frame.faces.isEmpty else { return .noFace }
        guard frame.faces.count == 1, let face = frame.faces.first else { return .multipleFaces }

        let width = frame.imageSize.width
        let height = frame.imageSize.height
        let diameter = min(width, height)
        guard diameter > 0 else { return .noFace }

        let box = face.boundingBox
        let faceWidth = box.width * width / diameter
        if faceWidth < minFaceWidth { return .moveCloser }
        if faceWidth > maxFaceWidth { return .moveBack }

        let dx = (box.midX - 0.5) * width
        let dy = (box.midY - 0.5) * height
        let offset = (dx * dx + dy * dy).squareRoot() / (diameter / 2)
        if offset > maxCenterOffset { return .centerFace }

        if abs(face.roll ?? 0) > maxAngle || abs(face.yaw ?? 0) > maxAngle { return .lookStraight }

        return .ready
    }
}
