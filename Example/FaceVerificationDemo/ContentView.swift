import FaceVerificationSDK
import SwiftUI
import UIKit

/// How the demo's `verify` closure behaves, to exercise every SDK outcome.
enum VerificationMode: String, CaseIterable, Identifiable {
    case captureOnly = "Capture only (no verify)"
    case accept = "Verify → accept"
    case reject = "Verify → reject"
    case error = "Verify → throw error"

    var id: String { rawValue }
}

struct DemoError: LocalizedError {
    var errorDescription: String? { "Simulated verification error" }
}

struct ContentView: View {
    @State private var requireBlink = false
    @State private var mode = VerificationMode.accept
    @State private var verifyDelay = 1.5
    @State private var timeout = 30.0
    @State private var customTheme = false

    @State private var showSwiftUIFlow = false
    @State private var resultText = "No result yet"
    @State private var resultImage: UIImage?

    var body: some View {
        NavigationView {
            Form {
                Section("Options") {
                    Toggle("Require blink (liveness)", isOn: $requireBlink)
                    Picker("Verification", selection: $mode) {
                        ForEach(VerificationMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if mode != .captureOnly {
                        Stepper("Verify delay: \(verifyDelay, specifier: "%.1f")s", value: $verifyDelay, in: 0...5, step: 0.5)
                    }
                    Stepper("Timeout: \(Int(timeout))s", value: $timeout, in: 5...60, step: 5)
                    Toggle("Custom theme & strings", isOn: $customTheme)
                }

                Section("Launch") {
                    Button("Start (SwiftUI modifier)") { showSwiftUIFlow = true }
                    Button("Start (UIKit present)", action: presentUIKit)
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
        .faceVerification(isPresented: $showSwiftUIFlow, config: config, verify: verifier, completion: handle)
    }

    // MARK: - SDK setup

    private var config: FaceVerificationConfig {
        var config = FaceVerificationConfig()
        config.requireBlink = requireBlink
        config.timeout = timeout
        if customTheme {
            config.strings.navigationTitle = "Verify identity"
            config.strings.continueButton = "Done"
            config.theme.buttonBackground = Color(red: 0.16, green: 0.36, blue: 0.95)
            config.theme.success = Color(red: 0.16, green: 0.36, blue: 0.95)
        }
        return config
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

    private func presentUIKit() {
        guard let presenter = Self.topViewController() else { return }
        FaceVerification.present(from: presenter, config: config, verify: verifier, completion: handle)
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

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
