import Foundation

/// A set of options describing how a PDF should be compressed.
public struct CompressionProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isBuiltIn: Bool

    // Images
    public var optimizeImages: Bool
    /// Images are downsampled to at most this resolution (dots per inch).
    public var maxImageDPI: Int
    /// JPEG quality, 0.0 (smallest) ... 1.0 (best).
    public var jpegQuality: Double
    public var grayscale: Bool

    // Pages
    /// Render every page to a single image. Smallest output, but text is no longer selectable.
    public var convertToBitmap: Bool
    public var bitmapDPI: Int

    // Document
    public var removeMetadata: Bool
    public var removeAnnotations: Bool
    public var flattenAnnotations: Bool
    /// Recompress the file structure losslessly with qpdf (when available).
    public var losslessOptimization: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        isBuiltIn: Bool = false,
        optimizeImages: Bool = true,
        maxImageDPI: Int = 150,
        jpegQuality: Double = 0.6,
        grayscale: Bool = false,
        convertToBitmap: Bool = false,
        bitmapDPI: Int = 150,
        removeMetadata: Bool = false,
        removeAnnotations: Bool = false,
        flattenAnnotations: Bool = false,
        losslessOptimization: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.optimizeImages = optimizeImages
        self.maxImageDPI = maxImageDPI
        self.jpegQuality = jpegQuality
        self.grayscale = grayscale
        self.convertToBitmap = convertToBitmap
        self.bitmapDPI = bitmapDPI
        self.removeMetadata = removeMetadata
        self.removeAnnotations = removeAnnotations
        self.flattenAnnotations = flattenAnnotations
        self.losslessOptimization = losslessOptimization
    }

    /// Whether the profile changes nothing but image data, so a purely lossless
    /// rewrite of the original file is an acceptable result too.
    var allowsLosslessOnlyResult: Bool {
        !convertToBitmap && !grayscale && !removeMetadata && !removeAnnotations
    }
}

extension CompressionProfile {
    private enum CodingKeys: String, CodingKey {
        case id, name, isBuiltIn, optimizeImages, maxImageDPI, jpegQuality, grayscale, convertToBitmap,
             bitmapDPI, removeMetadata, removeAnnotations, flattenAnnotations, losslessOptimization
    }

    /// Missing keys fall back to defaults so profiles exported by older versions still import.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CompressionProfile(name: "")
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Imported Profile",
            isBuiltIn: try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false,
            optimizeImages: try c.decodeIfPresent(Bool.self, forKey: .optimizeImages) ?? defaults.optimizeImages,
            maxImageDPI: try c.decodeIfPresent(Int.self, forKey: .maxImageDPI) ?? defaults.maxImageDPI,
            jpegQuality: try c.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? defaults.jpegQuality,
            grayscale: try c.decodeIfPresent(Bool.self, forKey: .grayscale) ?? defaults.grayscale,
            convertToBitmap: try c.decodeIfPresent(Bool.self, forKey: .convertToBitmap) ?? defaults.convertToBitmap,
            bitmapDPI: try c.decodeIfPresent(Int.self, forKey: .bitmapDPI) ?? defaults.bitmapDPI,
            removeMetadata: try c.decodeIfPresent(Bool.self, forKey: .removeMetadata) ?? defaults.removeMetadata,
            removeAnnotations: try c.decodeIfPresent(Bool.self, forKey: .removeAnnotations) ?? defaults.removeAnnotations,
            flattenAnnotations: try c.decodeIfPresent(Bool.self, forKey: .flattenAnnotations) ?? defaults.flattenAnnotations,
            losslessOptimization: try c.decodeIfPresent(Bool.self, forKey: .losslessOptimization)
                ?? defaults.losslessOptimization)
    }
}

public extension CompressionProfile {
    static let light = CompressionProfile(
        id: UUID(uuidString: "6B1C0E64-0000-4000-8000-000000000001")!,
        name: "Light Compression", isBuiltIn: true,
        maxImageDPI: 300, jpegQuality: 0.85)

    static let medium = CompressionProfile(
        id: UUID(uuidString: "6B1C0E64-0000-4000-8000-000000000002")!,
        name: "Medium Compression", isBuiltIn: true,
        maxImageDPI: 200, jpegQuality: 0.7)

    static let strong = CompressionProfile(
        id: UUID(uuidString: "6B1C0E64-0000-4000-8000-000000000003")!,
        name: "Strong Compression", isBuiltIn: true,
        maxImageDPI: 144, jpegQuality: 0.55)

    static let extreme = CompressionProfile(
        id: UUID(uuidString: "6B1C0E64-0000-4000-8000-000000000004")!,
        name: "Extreme Compression", isBuiltIn: true,
        maxImageDPI: 96, jpegQuality: 0.4)

    static let bitmap = CompressionProfile(
        id: UUID(uuidString: "6B1C0E64-0000-4000-8000-000000000005")!,
        name: "Flatten to Images", isBuiltIn: true,
        maxImageDPI: 120, jpegQuality: 0.5,
        convertToBitmap: true, bitmapDPI: 120, removeMetadata: true)

    static let builtIns: [CompressionProfile] = [.light, .medium, .strong, .extreme, .bitmap]

    /// Looks up a built-in profile by a short command-line name.
    static func builtIn(named name: String) -> CompressionProfile? {
        switch name.lowercased() {
        case "light": return .light
        case "medium": return .medium
        case "strong": return .strong
        case "extreme": return .extreme
        case "bitmap", "flatten": return .bitmap
        default: return nil
        }
    }
}
