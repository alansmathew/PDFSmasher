import Foundation
import PDFKit
import Quartz
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum CompressionError: LocalizedError, Sendable {
    case cannotOpen
    case passwordProtected
    case writeFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .cannotOpen: return "The file could not be opened. It may be damaged or not a PDF."
        case .passwordProtected: return "This file is password protected."
        case .writeFailed: return "The compressed PDF could not be written."
        case .cancelled: return "Compression was cancelled."
        }
    }
}

/// Editable document information written into the compressed file.
public struct PDFMetadata: Codable, Hashable, Sendable {
    public var title = ""
    public var author = ""
    public var subject = ""
    public var keywords = ""

    public init(title: String = "", author: String = "", subject: String = "", keywords: String = "") {
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
    }

    public init(document: PDFDocument) {
        let attrs = document.documentAttributes ?? [:]
        title = attrs[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        author = attrs[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        subject = attrs[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
        if let list = attrs[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            keywords = list.joined(separator: ", ")
        } else {
            keywords = attrs[PDFDocumentAttribute.keywordsAttribute] as? String ?? ""
        }
    }

    var keywordList: [String] {
        keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

public struct CompressionResult: Sendable, Hashable {
    public var outputURL: URL
    public var originalSize: Int64
    public var compressedSize: Int64

    /// Fraction of the original size that was removed (0.25 == 25 % smaller).
    public var savedFraction: Double {
        guard originalSize > 0 else { return 0 }
        return 1 - Double(compressedSize) / Double(originalSize)
    }

    public var isSmaller: Bool { compressedSize < originalSize }
}

public enum PDFCompressor {
    /// Compresses `input` into `output` using `profile`.
    ///
    /// The output is always written, even when it is larger than the input;
    /// callers decide whether to keep it by checking `CompressionResult.isSmaller`.
    public static func compress(
        input: URL,
        output: URL,
        profile: CompressionProfile,
        metadata: PDFMetadata? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> CompressionResult {
        guard let document = PDFDocument(url: input) else { throw CompressionError.cannotOpen }
        if document.isLocked { throw CompressionError.passwordProtected }
        let originalMetadata = PDFMetadata(document: document)

        let fm = FileManager.default
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let work = output.deletingLastPathComponent()
            .appendingPathComponent(".smash-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // The engine produces a few candidates and keeps the smallest one.
        let primary = work.appendingPathComponent("primary.pdf")
        let optimizing = profile.losslessOptimization && LosslessOptimizer.isAvailable
        let stage: (@Sendable (Double) -> Void)? = progress.map { report in
            { @Sendable value in report(value * (optimizing ? 0.75 : 1)) }
        }
        if profile.convertToBitmap {
            try rasterize(document, to: primary, profile: profile, metadata: metadata, progress: stage)
        } else {
            try rewrite(document, to: primary, profile: profile, metadata: metadata, progress: stage)
        }
        var candidates = [primary]

        if optimizing {
            let packed = work.appendingPathComponent("primary-packed.pdf")
            if LosslessOptimizer.optimize(input: primary, output: packed) { candidates.append(packed) }
            progress?(0.9)

            let metadataUnchanged = metadata == nil || metadata == originalMetadata
            if profile.allowsLosslessOnlyResult && metadataUnchanged {
                let lossless = work.appendingPathComponent("lossless.pdf")
                if LosslessOptimizer.optimize(
                    input: input, output: lossless, flattenAnnotations: profile.flattenAnnotations) { candidates.append(lossless) }
            }
        }

        let best = candidates.min { fileSize($0) < fileSize($1) }!
        try? fm.removeItem(at: output)
        try fm.moveItem(at: best, to: output)

        progress?(1)
        return CompressionResult(
            outputURL: output,
            originalSize: fileSize(input),
            compressedSize: fileSize(output))
    }

    public static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    // MARK: - Vector-preserving rewrite

    private static func rewrite(
        _ document: PDFDocument,
        to output: URL,
        profile: CompressionProfile,
        metadata: PDFMetadata?,
        progress: (@Sendable (Double) -> Void)?
    ) throws {
        if profile.removeAnnotations {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                // Links are navigation, not markup, so they are kept.
                for annotation in page.annotations where annotation.type != "Link" {
                    page.removeAnnotation(annotation)
                }
            }
        }
        progress?(0.1)

        document.documentAttributes = attributes(for: document, profile: profile, metadata: metadata)

        var options: [PDFDocumentWriteOption: Any] = [:]
        if profile.flattenAnnotations {
            options[.burnInAnnotationsOption] = true
        }
        if profile.optimizeImages, let filter = makeQuartzFilter(for: profile) {
            options[PDFDocumentWriteOption(rawValue: "QuartzFilter")] = filter
        }

        guard document.write(to: output, withOptions: options) else { throw CompressionError.writeFailed }
    }

    private static func attributes(
        for document: PDFDocument, profile: CompressionProfile, metadata: PDFMetadata?
    ) -> [AnyHashable: Any] {
        if profile.removeMetadata {
            return [PDFDocumentAttribute.producerAttribute: "PDF Smasher"]
        }
        var attrs = document.documentAttributes ?? [:]
        if let metadata {
            attrs[PDFDocumentAttribute.titleAttribute] = metadata.title
            attrs[PDFDocumentAttribute.authorAttribute] = metadata.author
            attrs[PDFDocumentAttribute.subjectAttribute] = metadata.subject
            attrs[PDFDocumentAttribute.keywordsAttribute] = metadata.keywordList
        }
        attrs[PDFDocumentAttribute.modificationDateAttribute] = Date()
        return attrs
    }

    /// Builds a Quartz filter that re-encodes images as JPEG and downsamples them.
    static func makeQuartzFilter(for profile: CompressionProfile) -> QuartzFilter? {
        let imageSettings: [String: Any] = [
            "Compression Quality": max(0.05, min(1, profile.jpegQuality)),
            "ImageCompression": "ImageJPEGCompress",
            "ImageScaleSettings": [
                "ImageResolution": profile.maxImageDPI,
                "ImageScaleInterpolate": true,
                // Longest side of an image may not exceed a 17" page at the chosen resolution.
                "ImageSizeMax": profile.maxImageDPI * 17,
                "ImageSizeMin": 0,
            ] as [String: Any],
        ]

        var filterData: [String: Any] = [:]
        var colorSettings: [String: Any] = [:]

        if profile.grayscale,
           let gray = NSDictionary(contentsOfFile: "/System/Library/Filters/Gray Tone.qfilter") as? [String: Any],
           let grayData = gray["FilterData"] as? [String: Any] {
            // Reuse the gray conversion profile that ships with macOS.
            filterData = grayData
            colorSettings = grayData["ColorSettings"] as? [String: Any] ?? [:]
        }
        colorSettings["ImageSettings"] = imageSettings
        filterData["ColorSettings"] = colorSettings

        let properties: [String: Any] = [
            "Domains": ["Applications": true, "Printing": true],
            "FilterData": filterData,
            "FilterType": 1,
            "Name": profile.name,
        ]
        return QuartzFilter(properties: properties)
    }

    // MARK: - Rasterize pages

    private static func rasterize(
        _ document: PDFDocument,
        to output: URL,
        profile: CompressionProfile,
        metadata: PDFMetadata?,
        progress: (@Sendable (Double) -> Void)?
    ) throws {
        var info: [CFString: Any] = [kCGPDFContextCreator: "PDF Smasher"]
        if !profile.removeMetadata {
            let source = metadata ?? PDFMetadata(document: document)
            if !source.title.isEmpty { info[kCGPDFContextTitle] = source.title }
            if !source.author.isEmpty { info[kCGPDFContextAuthor] = source.author }
            if !source.subject.isEmpty { info[kCGPDFContextSubject] = source.subject }
            if !source.keywordList.isEmpty { info[kCGPDFContextKeywords] = source.keywordList }
        }

        guard let context = CGContext(output as CFURL, mediaBox: nil, info as CFDictionary) else {
            throw CompressionError.writeFailed
        }

        let scale = CGFloat(max(36, profile.bitmapDPI)) / 72
        let pageCount = document.pageCount

        for index in 0..<pageCount {
            guard let pdfPage = document.page(at: index), let page = pdfPage.pageRef else { continue }
            if profile.removeAnnotations {
                for annotation in pdfPage.annotations { pdfPage.removeAnnotation(annotation) }
            }

            let box = page.getBoxRect(.cropBox)
            let rotated = page.rotationAngle % 180 != 0
            let pageSize = rotated ? CGSize(width: box.height, height: box.width) : box.size
            let pixelWidth = Int((pageSize.width * scale).rounded())
            let pixelHeight = Int((pageSize.height * scale).rounded())

            guard let image = try autoreleasepool(invoking: {
                try renderPage(pdfPage, size: pageSize, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                               profile: profile)
            }) else { throw CompressionError.writeFailed }

            var mediaBox = CGRect(origin: .zero, size: pageSize)
            context.beginPage(mediaBox: &mediaBox)
            context.draw(image, in: mediaBox)
            context.endPage()

            progress?(Double(index + 1) / Double(max(pageCount, 1)) * 0.95)
        }
        context.closePDF()
    }

    private static func renderPage(
        _ page: PDFPage, size: CGSize, pixelWidth: Int, pixelHeight: Int, profile: CompressionProfile
    ) throws -> CGImage? {
        let colorSpace = profile.grayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = profile.grayscale
            ? CGImageAlphaInfo.none.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue
        guard let bitmap = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo)
        else { return nil }

        bitmap.interpolationQuality = .high
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        bitmap.scaleBy(x: CGFloat(pixelWidth) / size.width, y: CGFloat(pixelHeight) / size.height)

        // PDFPage.draw applies the page rotation and includes annotations.
        page.draw(with: .cropBox, to: bitmap)

        guard let raw = bitmap.makeImage() else { return nil }

        // Re-encode as JPEG so Quartz embeds the compressed stream directly.
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, raw, [
            kCGImageDestinationLossyCompressionQuality: max(0.05, min(1, profile.jpegQuality)),
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}
