@preconcurrency import AVFoundation
import CoreImage
import UIKit

/// Camera abstraction so the view model can be tested without hardware.
@MainActor
protocol CameraControlling: AnyObject {
    /// Delivered on the main actor: analysis, frame timestamp (seconds), lazy image factory.
    var onFrame: ((FrameAnalysis, TimeInterval, () -> UIImage?) -> Void)? { get set }
    var onError: ((FaceVerificationError) -> Void)? { get set }
    /// Session for the live preview. `nil` for mocks.
    var captureSession: AVCaptureSession? { get }
    func requestAccess() async -> Bool
    func start()
    func stop()
}

/// AVFoundation camera that delivers upright, mirrored (selfie-style) frames analyzed by Vision.
@MainActor
final class CameraSession: NSObject, CameraControlling {
    var onFrame: ((FrameAnalysis, TimeInterval, () -> UIImage?) -> Void)?
    var onError: ((FaceVerificationError) -> Void)?
    var captureSession: AVCaptureSession? { session }

    private let session = AVCaptureSession()
    private let position: AVCaptureDevice.Position
    // Only used on `videoQueue`.
    nonisolated(unsafe) private let analyzer: FaceAnalyzer
    private let sessionQueue = DispatchQueue(label: "FaceVerificationSDK.session")
    private let videoQueue = DispatchQueue(label: "FaceVerificationSDK.video")
    private var isConfigured = false
    nonisolated private static let ciContext = CIContext()

    init(position: AVCaptureDevice.Position, detectLandmarks: Bool) {
        self.position = position
        self.analyzer = FaceAnalyzer(detectLandmarks: detectLandmarks)
    }

    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start() {
        let needsConfiguration = !isConfigured
        isConfigured = true
        sessionQueue.async { [session, position, weak self] in
            if needsConfiguration, !Self.configure(session, position: position, delegate: self) {
                Task { @MainActor in self?.onError?(.cameraUnavailable) }
                return
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private nonisolated static func configure(
        _ session: AVCaptureSession,
        position: AVCaptureDevice.Position,
        delegate: CameraSession?
    ) -> Bool {
        guard let delegate,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        guard session.canAddInput(input) else { return false }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(delegate, queue: delegate.videoQueue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
        return true
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let analysis = analyzer.analyze(pixelBuffer)
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let makeImage: () -> UIImage? = {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = CameraSession.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: cgImage)
        }
        Task { @MainActor [weak self] in
            self?.onFrame?(analysis, time, makeImage)
        }
    }
}
