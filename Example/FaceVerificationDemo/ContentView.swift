import FaceVerificationSDK
import SwiftUI

/// How the demo's `verify` closure behaves, to exercise every SDK outcome.
enum VerificationMode: String, CaseIterable, Identifiable {
    case captureOnly = "Capture only (no verify)"
    case accept = "Verify → accept"
    case reject = "Verify → reject"
    case error = "Verify → throw error"

    var id: String { rawValue }
}

extension LivenessChallenge {
    var title: String {
        switch self {
        case .turnLeft: return "Turn left"
        case .turnRight: return "Turn right"
        case .lookUp: return "Look up"
        case .lookDown: return "Look down"
        case .blink: return "Blink"
        }
    }
}

struct DemoError: LocalizedError {
    var errorDescription: String? { "Simulated verification error" }
}

struct ContentView: View {
    /// Liveness prompts to run, in `LivenessChallenge.allCases` order.
    @State private var challenges = Set(LivenessChallenge.allCases)
    @State private var challengeTimeout = 8.0
    @State private var showsDebugInfo = false
    @State private var mode = VerificationMode.accept
    @State private var verifyDelay = 1.5
    @State private var timeout = 30.0
    @State private var customTheme = false

    @State private var showVerification = false
    @State private var resultText = "No result yet"
    @State private var resultImage: UIImage?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ForEach(LivenessChallenge.allCases, id: \.self) { challenge in
                        Toggle(challenge.title, isOn: binding(for: challenge))
                    }
                    Stepper("Time per step: \(Int(challengeTimeout))s", value: $challengeTimeout, in: 3...20)
                } header: {
                    Text("Liveness steps")
                } footer: {
                    Text("Selected steps run one after another, in the order shown.")
                }

                Section("Options") {
                    Picker("Verification", selection: $mode) {
                        ForEach(VerificationMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if mode != .captureOnly {
                        Stepper("Verify delay: \(verifyDelay, specifier: "%.1f")s", value: $verifyDelay, in: 0...5, step: 0.5)
                    }
                    Stepper("Timeout: \(Int(timeout))s", value: $timeout, in: 5...60, step: 5)
                    Toggle("Custom theme & strings", isOn: $customTheme)
                    Toggle("Show debug info (head angles)", isOn: $showsDebugInfo)
                }

                Section {
                    Button("Start face verification") { showVerification = true }
                }

                Section("Last result") {
                    Text(resultText)
                        .font(.callout.monospaced())
                    if let resultImage {
                        HStack {
                            Spacer()
                            Image(uiImage: resultImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 160, height: 160)
                                .clipShape(Circle())
                            Spacer()
                        }
                        Text("Image size: \(Int(resultImage.size.width)) × \(Int(resultImage.size.height))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Face Verification")
        }
        .navigationViewStyle(.stack)
        .faceVerification(isPresented: $showVerification, config: config, verify: verifier, completion: handle)
    }

    // MARK: - SDK setup

    private var config: FaceVerificationConfig {
        var config = FaceVerificationConfig()
        config.challenges = LivenessChallenge.allCases.filter(challenges.contains)
        config.challengeTimeout = challengeTimeout
        config.showsDebugInfo = showsDebugInfo
        config.timeout = timeout
        if customTheme {
            config.strings.navigationTitle = "Verify identity"
            config.strings.continueButton = "Done"
            config.theme.buttonBackground = Color(red: 0.16, green: 0.36, blue: 0.95)
            config.theme.success = Color(red: 0.16, green: 0.36, blue: 0.95)
        }
        return config
    }

    private func binding(for challenge: LivenessChallenge) -> Binding<Bool> {
        Binding(
            get: { challenges.contains(challenge) },
            set: { isOn in
                if isOn { challenges.insert(challenge) } else { challenges.remove(challenge) }
            }
        )
    }

    private var verifier: FaceVerifier? {
        let delay = verifyDelay
        switch mode {
        case .captureOnly:
            return nil
        case .accept:
            return { _ in try await Self.sleep(delay); return true }
        case .reject:
            return { _ in try await Self.sleep(delay); return false }
        case .error:
            return { _ in try await Self.sleep(delay); throw DemoError() }
        }
    }

    private static func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func handle(_ result: FaceVerificationResult) {
        switch result {
        case .success(let image):
            resultText = "✅ success"
            resultImage = image
        case .failure(let error):
            resultText = "❌ failure: \(error)"
            resultImage = nil
        case .cancelled:
            resultText = "↩️ cancelled"
            resultImage = nil
        }
    }
}
