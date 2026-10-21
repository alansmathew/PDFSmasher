// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PDFSmasher",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PDFSmasher", targets: ["PDFSmasher"]),
        .executable(name: "pdfsmash", targets: ["pdfsmash"]),
        .library(name: "SmasherCore", targets: ["SmasherCore"]),
    ],
    targets: [
        .target(name: "SmasherCore"),
        .executableTarget(name: "PDFSmasher", dependencies: ["SmasherCore"]),
        .executableTarget(name: "pdfsmash", dependencies: ["SmasherCore"]),
    ]
)
