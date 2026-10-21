import Foundation

/// Lossless structural optimization using the bundled `qpdf` tool: recompresses streams at
/// maximum level, packs objects into object streams and drops unreferenced resources.
/// The page content itself is not changed.
public enum LosslessOptimizer {
    /// The `qpdf` executable to use, or nil if none is available (optimization is then skipped).
    public static let executable: URL? = locate()

    private static func locate() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["PDFSMASHER_QPDF"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        let executableDir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent()
        candidates += [
            // Inside the app bundle: Contents/Helpers/qpdf (the CLI lives next to it).
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/qpdf"),
            executableDir.appendingPathComponent("qpdf"),
            executableDir.appendingPathComponent("../Helpers/qpdf").standardizedFileURL,
            // Development builds run from the repository.
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/bin/qpdf"),
            URL(fileURLWithPath: "/opt/homebrew/bin/qpdf"),
            URL(fileURLWithPath: "/usr/local/bin/qpdf"),
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    public static var isAvailable: Bool { executable != nil }

    /// Writes an optimized copy of `input` to `output`. Returns false if qpdf is missing or failed.
    @discardableResult
    public static func optimize(input: URL, output: URL, flattenAnnotations: Bool = false) -> Bool {
        guard let executable else { return false }
        try? FileManager.default.removeItem(at: output)

        let process = Process()
        process.executableURL = executable
        var arguments = [
            "--object-streams=generate",
            "--compress-streams=y",
            "--recompress-flate",
            "--compression-level=9",
            "--decode-level=generalized",
            "--remove-unreferenced-resources=yes",
            "--no-warn",
            "--warning-exit-0",
            input.path,
            output.path,
        ]
        if flattenAnnotations { arguments.insert("--flatten-annotations=all", at: 0) }
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: output.path)
    }
}
