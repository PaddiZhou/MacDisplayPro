// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacDisplayPro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacDisplayPro", targets: ["MacDisplayPro"])
    ],
    targets: [
        .target(
            name: "CDisplayBridge",
            path: "Sources/CDisplayBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-Wno-deprecated-declarations"])
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ColorSync"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "MacDisplayPro",
            dependencies: ["CDisplayBridge"],
            path: "Sources/MacDisplayPro",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ]
)
