// swift-tools-version:6.0
import PackageDescription

// Standalone eval harness for the Apple Intelligence Magic Format prompt.
// Mirrors scripts/eval_magic_format.py (the Gemma harness) so scores are
// directly comparable to the Gemma version table, but drives the on-device
// FoundationModels model instead of a llama.cpp HTTP endpoint.
//
// Requires macOS 26 with Apple Intelligence enabled on eligible hardware.
let package = Package(
    name: "apple-magic-eval",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "apple-magic-eval",
            path: "Sources/apple-magic-eval"
        )
    ]
)
