// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ShukaWhisper",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ShukaWhisper", targets: ["ShukaWhisper"]),
    ],
    targets: [
        // Pure domain logic: styles, prompts, dictation state machine, persistence.
        // No AppKit / SwiftUI so everything here is unit-testable.
        .target(
            name: "ShukaCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Thin clients for the Gemini API (live transcription, batch transcription, text generation).
        .target(name: "GeminiKit"),
        // The macOS app: system integration (hotkeys, audio, pasteboard) and SwiftUI interface.
        .executableTarget(
            name: "ShukaWhisper",
            dependencies: ["ShukaCore", "GeminiKit"]
        ),
        .testTarget(name: "ShukaCoreTests", dependencies: ["ShukaCore"]),
        .testTarget(name: "GeminiKitTests", dependencies: ["GeminiKit"]),
    ],
    swiftLanguageModes: [.v6]
)
