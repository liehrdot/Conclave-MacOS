// swift-tools-version: 6.2
// ConclaveEngine: everything the Mac app needs to run and talk to Conclave's engine (the same Python backend the
// Windows app ships), without any UI. No AppKit or SwiftUI here, so its tests also run on Linux in CI.
import PackageDescription

let package = Package(
    name: "ConclaveEngine",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ConclaveEngine", targets: ["ConclaveEngine"])],
    targets: [
        .target(name: "ConclaveEngine"),
        .testTarget(name: "ConclaveEngineTests", dependencies: ["ConclaveEngine"]),
    ]
)
