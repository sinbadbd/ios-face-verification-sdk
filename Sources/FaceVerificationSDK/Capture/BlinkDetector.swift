/// Detects a single blink from a stream of eye-openness values.
///
/// Thresholds are relative to the user's own open-eye baseline (the largest openness
/// seen while eyes were open), so it works across different eye shapes.
struct BlinkDetector {
    var closeRatio = 0.6
    var reopenRatio = 0.8
    /// Open-eye samples needed before a baseline is trusted.
    var minBaselineSamples = 3

    private(set) var hasBlinked = false
    private(set) var eyesClosed = false
    private var baseline = 0.0
    private var samples = 0

    mutating func update(openness: Double?) {
        guard let openness else { return }
        if !eyesClosed {
            baseline = max(baseline, openness)
            samples += 1
        }
        guard samples >= minBaselineSamples, baseline > 0 else { return }

        if !eyesClosed, openness < baseline * closeRatio {
            eyesClosed = true
        } else if eyesClosed, openness > baseline * reopenRatio {
            eyesClosed = false
            hasBlinked = true
        }
    }

    mutating func reset() {
        self = BlinkDetector(closeRatio: closeRatio, reopenRatio: reopenRatio, minBaselineSamples: minBaselineSamples)
    }
}
