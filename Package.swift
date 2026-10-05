// swift-tools-version: 6.0
import PackageDescription

// The Rust core is built into a static library by `make core`; see the Makefile.
let coreLibraryDirectory = "\(Context.packageDirectory)/core/target/release"

let package = Package(
    name: "Chime",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CChimeCore", path: "core/include"),
        .executableTarget(
            name: "Chime",
            dependencies: ["CChimeCore"],
            linkerSettings: [
                .unsafeFlags(["-L\(coreLibraryDirectory)"]),
                .linkedLibrary("chime_core"),
                .linkedLibrary("iconv"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
