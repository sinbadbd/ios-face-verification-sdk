import XCTest
@testable import FaceVerificationSDK

final class FaceQualityEvaluatorTests: XCTestCase {
    private let evaluator = FaceQualityEvaluator()
    // Portrait 720x1280: circle diameter 720 = full width, 0.5625 of height.
    private let size = CGSize(width: 720, height: 1280)

    private func frame(_ faces: [FaceObservation]) -> FrameAnalysis {
        FrameAnalysis(faces: faces, imageSize: size)
    }

    /// Face centered at (cx, cy) whose width is `widthFraction` of the circle diameter.
    private func face(cx: CGFloat = 0.5, cy: CGFloat = 0.5, widthFraction: CGFloat = 0.6,
                      roll: Double? = 0, yaw: Double? = 0) -> FaceObservation {
        let w = widthFraction                 // normalized to image width (== diameter)
        let h = widthFraction * 720 / 1280    // square face in pixels
        return FaceObservation(boundingBox: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h),
                               roll: roll, yaw: yaw)
    }

    func testNoFace() {
        XCTAssertEqual(evaluator.evaluate(frame([])), .noFace)
    }

    func testMultipleFaces() {
        XCTAssertEqual(evaluator.evaluate(frame([face(), face(cx: 0.3)])), .multipleFaces)
    }

    func testTooSmallAsksToMoveCloser() {
        XCTAssertEqual(evaluator.evaluate(frame([face(widthFraction: 0.2)])), .moveCloser)
    }

    func testTooLargeAsksToMoveBack() {
        XCTAssertEqual(evaluator.evaluate(frame([face(widthFraction: 0.95)])), .moveBack)
    }

    func testOffCenterHorizontally() {
        XCTAssertEqual(evaluator.evaluate(frame([face(cx: 0.75)])), .centerFace)
    }

    func testOffCenterVertically() {
        XCTAssertEqual(evaluator.evaluate(frame([face(cy: 0.62)])), .centerFace)
    }

    func testTiltedHead() {
        XCTAssertEqual(evaluator.evaluate(frame([face(roll: 0.6)])), .lookStraight)
        XCTAssertEqual(evaluator.evaluate(frame([face(yaw: -0.6)])), .lookStraight)
    }

    func testWellPositionedFaceIsReady() {
        XCTAssertEqual(evaluator.evaluate(frame([face()])), .ready)
        XCTAssertEqual(evaluator.evaluate(frame([face(roll: nil, yaw: nil)])), .ready)
    }
}
