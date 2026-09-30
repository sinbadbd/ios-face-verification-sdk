/// An active liveness prompt. Directions are from the user's point of view.
public enum LivenessChallenge: CaseIterable, Equatable {
    case turnLeft
    case turnRight
    case lookUp
    case lookDown
    case blink
}

/// Walks through liveness challenges in order, one frame at a time.
struct ChallengeTracker {
    /// Signs of Vision's yaw / pitch for the user's left / up on the mirrored selfie frame.
    /// Verify on a device with `showsDebugInfo`; flip here if a direction is inverted.
    static let userLeftYawSign = -1.0
    static let lookUpPitchSign = -1.0

    /// Radians the head must turn (~20°) or tilt (~15°) for a challenge to pass.
    var turnThreshold = 0.35
    var tiltThreshold = 0.26
    /// After a challenge passes, the head must come back within this of center
    /// before the next one counts, so one diagonal pose can't pass two prompts.
    var neutralThreshold = 0.15

    let challenges: [LivenessChallenge]
    private(set) var index = 0
    private var awaitingNeutral = false
    private var blink = BlinkDetector()

    init(challenges: [LivenessChallenge]) {
        self.challenges = challenges
    }

    var current: LivenessChallenge? {
        index < challenges.count ? challenges[index] : nil
    }

    var isComplete: Bool { index >= challenges.count }

    /// Feeds one frame's face. Returns `true` when the current challenge just passed.
    @discardableResult
    mutating func update(_ face: FaceObservation) -> Bool {
        guard let current else { return false }
        let yaw = face.yaw ?? 0
        let pitch = face.pitch ?? 0

        if awaitingNeutral {
            guard abs(yaw) < neutralThreshold, abs(pitch) < neutralThreshold else { return false }
            awaitingNeutral = false
        }

        let passed: Bool
        switch current {
        case .turnLeft: passed = yaw * Self.userLeftYawSign > turnThreshold
        case .turnRight: passed = -yaw * Self.userLeftYawSign > turnThreshold
        case .lookUp: passed = pitch * Self.lookUpPitchSign > tiltThreshold
        case .lookDown: passed = -pitch * Self.lookUpPitchSign > tiltThreshold
        case .blink:
            blink.update(openness: face.eyeOpenness)
            passed = blink.hasBlinked
        }
        guard passed else { return false }

        index += 1
        awaitingNeutral = true
        blink.reset()
        return true
    }

    mutating func reset() {
        index = 0
        awaitingNeutral = false
        blink.reset()
    }
}
