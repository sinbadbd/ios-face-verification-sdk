// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FaceVerificationSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "FaceVerificationSDK", targets: ["FaceVerificationSDK"])
    ],
    targets: [
        .target(name: "FaceVerificationSDK"),
        .testTarget(name: "FaceVerificationSDKTests", dependencies: ["FaceVerificationSDK"])
    ]
)
