import AppKit
import Observation
import PDFKit
import SmasherCore

@MainActor
@Observable
final class PDFItem: Identifiable {
    enum Status: Equatable {
        case waiting
        case compressing(Double)
        case done(CompressionResult)
        case notSmaller(CompressionResult)
        case protected
        case failed(String)
    }

    let id = UUID()
    let url: URL
    let dateAdded = Date()

    var status: Status = .waiting
    var originalSize: Int64
    var pageCount = 0
    var originalThumbnail: NSImage?
    var compressedThumbnail: NSImage?
    var originalMetadata = PDFMetadata()
    /// Edits to title/author/etc. made in the info popover; nil means keep the original.
    var metadata: PDFMetadata?
    /// Copy of the original file kept after it has been overwritten, so it can be restored.
    var backupURL: URL?
    var isSaved = false

    @ObservationIgnored var task: Task<Void, Never>?

    init(url: URL) {
        self.url = url
        self.originalSize = PDFCompressor.fileSize(url)
    }

    var name: String { url.deletingPathExtension().lastPathComponent }

    var result: CompressionResult? {
        switch status {
        case .done(let result), .notSmaller(let result): return result
        default: return nil
        }
    }

    /// The compressed file, only when compression actually made it smaller.
    var outputURL: URL? {
        if case .done(let result) = status { return result.outputURL }
        return nil
    }

    var isBusy: Bool {
        switch status {
        case .waiting, .compressing: return true
        default: return false
        }
    }

    var savedFraction: Double {
        if case .done(let result) = status { return result.savedFraction }
        return 0
    }

    var compressedSize: Int64 {
        if case .done(let result) = status { return result.compressedSize }
        return originalSize
    }
}
