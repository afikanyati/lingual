// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "RecognitionLifecycle", products: [.library(name: "RecognitionLifecycle", targets: ["RecognitionLifecycle"])], targets: [.target(name: "RecognitionLifecycle"), .testTarget(name: "RecognitionLifecycleTests", dependencies: ["RecognitionLifecycle"])])
