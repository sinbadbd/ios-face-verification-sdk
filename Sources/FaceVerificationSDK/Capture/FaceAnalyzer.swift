import CoreVideo
import Vision

/// Runs Vision face requests on a camera frame.
final class FaceAnalyzer {
    private let detectLandmarks: Bool

    init(detectLandmarks: Bool) {
        self.detectLandmarks = detectLandmarks
    }

    /// `pixelBuffer` must be upright (portrait) — `CameraSession` configures that.
    func analyze(_ pixelBuffer: CVPixelBuffer) -> FrameAnalysis {
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)

        let rectangles = VNDetectFaceRectanglesRequest()
        // Revision 3 reports continuous roll/yaw/pitch.
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
        let quality = VNDetectFaceCaptureQualityRequest()

        do {
            try handler.perform([rectangles, quality])
        } catch {
            return FrameAnalysis(faces: [], imageSize: size)
        }

        let faceObservations = rectangles.results ?? []
        var landmarkObservations: [VNFaceObservation] = []
        if detectLandmarks, !faceObservations.isEmpty {
            let landmarks = VNDetectFaceLandmarksRequest()
            landmarks.inputFaceObservations = faceObservations
            try? handler.perform([landmarks])
            landmarkObservations = landmarks.results ?? []
        }
        let qualityObservations = quality.results ?? []

        let faces = faceObservations.map { face -> FaceObservation in
            FaceObservation(
                boundingBox: face.boundingBox,
                roll: face.roll?.doubleValue,
                yaw: face.yaw?.doubleValue,
                pitch: face.pitch?.doubleValue,
                captureQuality: Self.nearest(to: face, in: qualityObservations)?.faceCaptureQuality,
                eyeOpenness: Self.nearest(to: face, in: landmarkObservations).flatMap(Self.eyeOpenness)
            )
        }
        return FrameAnalysis(faces: faces, imageSize: size)
    }

    private static func nearest(to face: VNFaceObservation, in candidates: [VNFaceObservation]) -> VNFaceObservation? {
        candidates.min { distance($0.boundingBox, face.boundingBox) < distance($1.boundingBox, face.boundingBox) }
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }

    private static func eyeOpenness(_ face: VNFaceObservation) -> Double? {
        let ratios = [face.landmarks?.leftEye, face.landmarks?.rightEye].compactMap { region -> Double? in
            guard let points = region?.normalizedPoints, points.count > 2 else { return nil }
            let xs = points.map(\.x), ys = points.map(\.y)
            let width = (xs.max() ?? 0) - (xs.min() ?? 0)
            guard width > 0 else { return nil }
            return Double(((ys.max() ?? 0) - (ys.min() ?? 0)) / width)
        }
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }
}
