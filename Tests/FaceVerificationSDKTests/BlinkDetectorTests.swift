import XCTest
@testable import FaceVerificationSDK

final class BlinkDetectorTests: XCTestCase {
    func testDetectsOpenClosedOpen() {
        var detector = BlinkDetector()
        [0.30, 0.31, 0.30, 0.10, 0.08].forEach { detector.update(openness: $0) }
        XCTAssertTrue(detector.eyesClosed)
        XCTAssertFalse(detector.hasBlinked)

        detector.update(openness: 0.29)
        XCTAssertFalse(detector.eyesClosed)
        XCTAssertTrue(detector.hasBlinked)
    }

    func testSteadyOpenEyesIsNotABlink() {
        var detector = BlinkDetector()
        [0.30, 0.28, 0.31, 0.29, 0.30, 0.27].forEach { detector.update(openness: $0) }
        XCTAssertFalse(detector.hasBlinked)
    }

    func testIgnoresClosureBeforeBaselineIsEstablished() {
        var detector = BlinkDetector()
        [0.30, 0.05, 0.30].forEach { detector.update(openness: $0) }
        XCTAssertFalse(detector.hasBlinked)
    }

    func testMissingValuesAreIgnored() {
        var detector = BlinkDetector()
        [0.30, nil, 0.30, 0.30, nil, 0.1, 0.3].forEach { detector.update(openness: $0) }
        XCTAssertTrue(detector.hasBlinked)
    }

    func testReset() {
        var detector = BlinkDetector()
        [0.3, 0.3, 0.3, 0.1, 0.3].forEach { detector.update(openness: $0) }
        detector.reset()
        XCTAssertFalse(detector.hasBlinked)
        XCTAssertFalse(detector.eyesClosed)
    }
}
