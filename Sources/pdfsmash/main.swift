import Foundation
import SmasherCore

let usage = """
usage: pdfsmash [options] <file.pdf>...

Compresses PDF files. By default the result is written next to the
original as "<name>-smashed.pdf" and only kept when it is smaller.

options:
  -p, --profile <name>   light | medium | strong | extreme | bitmap  (default: strong)
      --dpi <n>          maximum image resolution
  -q, --quality <0-100>  JPEG quality
      --gray             convert to grayscale
      --strip            remove document metadata
      --no-lossless      skip lossless structure optimization (qpdf)
  -o, --output <path>    output file (single input) or folder (multiple inputs)
      --suffix <text>    file name suffix (default: -smashed)
  -f, --force            keep the output even if it is not smaller
  -h, --help             show this help
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

var profile = CompressionProfile.strong
var inputs: [URL] = []
var output: String?
var suffix = "-smashed"
var force = false

var args = CommandLine.arguments.dropFirst().makeIterator()
func value(for flag: String) -> String {
    guard let next = args.next() else { fail("missing value for \(flag)") }
    return next
}

while let arg = args.next() {
    switch arg {
    case "-h", "--help":
        print(usage)
        exit(0)
    case "-p", "--profile":
        let name = value(for: arg)
        guard let found = CompressionProfile.builtIn(named: name) else { fail("unknown profile: \(name)") }
        profile = found
    case "--dpi":
        guard let dpi = Int(value(for: arg)), dpi > 0 else { fail("invalid --dpi") }
        profile.maxImageDPI = dpi
        profile.bitmapDPI = dpi
    case "-q", "--quality":
        guard let q = Double(value(for: arg)), (0...100).contains(q) else { fail("invalid --quality") }
        profile.jpegQuality = q / 100
    case "--gray": profile.grayscale = true
    case "--strip": profile.removeMetadata = true
    case "--no-lossless": profile.losslessOptimization = false
    case "-o", "--output": output = value(for: arg)
    case "--suffix": suffix = value(for: arg)
    case "-f", "--force": force = true
    default:
        if arg.hasPrefix("-") { fail("unknown option: \(arg)\n\n\(usage)") }
        inputs.append(URL(fileURLWithPath: arg))
    }
}

if inputs.isEmpty { fail(usage) }

let formatter = ByteCountFormatter()
formatter.countStyle = .file
var failures = 0

for input in inputs {
    let destination: URL
    if let output, inputs.count == 1, !output.hasSuffix("/") {
        destination = URL(fileURLWithPath: output)
    } else {
        let folder = output.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? input.deletingLastPathComponent()
        destination = folder.appendingPathComponent(
            input.deletingPathExtension().lastPathComponent + suffix + ".pdf")
    }

    do {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        let result = try PDFCompressor.compress(input: input, output: temp, profile: profile)
        let sizes = "\(formatter.string(fromByteCount: result.originalSize)) → \(formatter.string(fromByteCount: result.compressedSize))"
        if result.isSmaller || force {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            print("\(input.lastPathComponent): \(sizes) (\(String(format: "%.1f", result.savedFraction * 100))% smaller) → \(destination.path)")
        } else {
            try? FileManager.default.removeItem(at: temp)
            print("\(input.lastPathComponent): \(sizes) — could not be reduced, skipped")
        }
    } catch {
        failures += 1
        FileHandle.standardError.write("\(input.lastPathComponent): \(error.localizedDescription)\n".data(using: .utf8)!)
    }
}

exit(failures == 0 ? 0 : 1)
