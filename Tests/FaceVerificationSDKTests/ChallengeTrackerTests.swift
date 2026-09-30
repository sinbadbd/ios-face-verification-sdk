import XCTest
@testable import FaceVerificationSDK

final class ChallengeTrackerTests: XCTestCase {
    private let left = 0.5 * ChallengeTracker.userLeftYawSign
    private let up = 0.4 * ChallengeTracker.lookUpPitchSign

    private func face(yaw: Double = 0, pitch: Double = 0, eyes: Double? = nil) -> FaceObservation {
        FaceObservation(boundingBox: .zero, roll: 0, yaw: yaw, pitch: pitch, eyeOpenness: eyes)
    }

    func testEachDirectionPasses() {
        let cases: [(LivenessChallenge, FaceObservation)] = [
            (.turnLeft, face(yaw: left)), (.turnRight, face(yaw: -left)),
            (.lookUp, face(pitch: up)), (.lookDown, face(pitch: -up))
        ]
        for (challenge, pose) in cases {
            var tracker = ChallengeTracker(challenges: [challenge])
            XCTAssertFalse(tracker.update(face()), "\(challenge) passed while centered")
            XCTAssertTrue(tracker.update(pose), "\(challenge) did not pass")
            XCTAssertTrue(tracker.isComplete)
        }
    }

    func testWrongDirectionDoesNotPass() {
        var tracker = ChallengeTracker(challenges: [.turnLeft])
        XCTAssertFalse(tracker.update(face(yaw: -left)))
        XCTAssertFalse(tracker.update(face(pitch: up)))
        XCTAssertEqual(tracker.current, .turnLeft)
    }

    func testSmallTurnDoesNotPass() {
        var tracker = ChallengeTracker(challenges: [.turnLeft])
        XCTAssertFalse(tracker.update(face(yaw: left * 0.5)))
    }

    func testRunsInOrder() {
        var tracker = ChallengeTracker(challenges: [.turnLeft, .turnRight])
        XCTAssertFalse(tracker.update(face(yaw: -left)))
        XCTAssertTrue(tracker.update(face(yaw: left)))
        XCTAssertEqual(tracker.current, .turnRight)
    }

    func testMustReturnToCenterBeforeNextChallenge() {
        var tracker = ChallengeTracker(challenges: [.turnLeft, .lookUp])
        XCTAssertTrue(tracker.update(face(yaw: left, pitch: up)))
        // Still turned: the diagonal pose must not also pass "look up".
        XCTAssertFalse(tracker.update(face(yaw: left, pitch: up)))
        XCTAssertFalse(tracker.update(face()))
        XCTAssertTrue(tracker.update(face(pitch: up)))
        XCTAssertTrue(tracker.isComplete)
    }

    func testBlinkChallenge() {
        var tracker = ChallengeTracker(challenges: [.blink])
        for eyes in [0.3, 0.3, 0.3, 0.1] { XCTAssertFalse(tracker.update(face(eyes: eyes))) }
        XCTAssertTrue(tracker.update(face(eyes: 0.3)))
    }

    func testReset() {
        var tracker = ChallengeTracker(challenges: [.turnLeft, .turnRight])
        tracker.update(face(yaw: left))
        tracker.reset()
        XCTAssertEqual(tracker.index, 0)
        XCTAssertEqual(tracker.current, .turnLeft)
    }
}
