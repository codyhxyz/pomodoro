// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomodoroOverlay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PomodoroOverlay", targets: ["PomodoroOverlay"])
    ],
    targets: [
        .executableTarget(name: "PomodoroOverlay")
    ]
)
