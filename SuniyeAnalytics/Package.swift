// swift-tools-version:5.9
import PackageDescription

// SuniyeAnalytics is a self-contained, Foundation-only analytics client.
// It has ZERO dependencies on the Suniye app and no knowledge of dictation
// domain types — the app assembles typed events and hands them in. This is
// what lets the package be lifted into its own repo later without a rewrite
// (see docs/superpowers/specs/2026-07-05-privacy-analytics-design.md §11).
let package = Package(
    name: "SuniyeAnalytics",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SuniyeAnalytics", targets: ["SuniyeAnalytics"])
    ],
    targets: [
        .target(name: "SuniyeAnalytics"),
        .testTarget(
            name: "SuniyeAnalyticsTests",
            dependencies: ["SuniyeAnalytics"]
        )
    ]
)
