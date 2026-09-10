// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpeakDraft",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SpeakDraft",
            path: "Sources/SpeakDraft"
        )
    ]
)
