import AppKit
import Observation
import PDFKit
import SmasherCore
import UniformTypeIdentifiers

extension UTType {
    static let smasherProfile = UTType(exportedAs: "io.github.pdfsmasher.profile", conformingTo: .json)
}

enum SortOrder: String, CaseIterable, Identifiable {
    case dateAdded = "Date Added"
    case name = "Name"
    case size = "Original Size"
    case ratio = "Compression Ratio"
    var id: String { rawValue }
}

enum DefaultsKey {
    static let suffix = "fileSuffix"
    static let selectedProfile = "selectedProfile"
    static let customProfiles = "customProfiles"
    static let totalSaved = "totalBytesSaved"
    static let confirmOverwrite = "confirmOverwrite"
    static let sortOrder = "sortOrder"
    static let sortReversed = "sortReversed"
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var files: [PDFItem] = []
    var selection: Set<PDFItem.ID> = []
    var showOriginal = false

    var sortOrder: SortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKey.sortOrder) }
    }
    var sortReversed: Bool {
        didSet { UserDefaults.standard.set(sortReversed, forKey: DefaultsKey.sortReversed) }
    }

    private(set) var customProfiles: [CompressionProfile]
    var selectedProfileID: UUID {
        didSet {
            guard selectedProfileID != oldValue else { return }
            UserDefaults.standard.set(selectedProfileID.uuidString, forKey: DefaultsKey.selectedProfile)
            recompressAll()
        }
    }

    private(set) var totalBytesSaved: Int64 {
        didSet { UserDefaults.standard.set(totalBytesSaved, forKey: DefaultsKey.totalSaved) }
    }

    @ObservationIgnored private let limiter = Limiter(limit: max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
    @ObservationIgnored private var recompressTask: Task<Void, Never>?
    @ObservationIgnored let workDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PDFSmasher-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    private init() {
        let defaults = UserDefaults.standard
        sortOrder = SortOrder(rawValue: defaults.string(forKey: DefaultsKey.sortOrder) ?? "") ?? .dateAdded
        sortReversed = defaults.bool(forKey: DefaultsKey.sortReversed)
        totalBytesSaved = Int64(defaults.integer(forKey: DefaultsKey.totalSaved))
        if let data = defaults.data(forKey: DefaultsKey.customProfiles),
           let decoded = try? JSONDecoder().decode([CompressionProfile].self, from: data) {
            customProfiles = decoded
        } else {
            customProfiles = []
        }
        selectedProfileID = defaults.string(forKey: DefaultsKey.selectedProfile).flatMap(UUID.init(uuidString:))
            ?? CompressionProfile.medium.id
        if !allProfiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = CompressionProfile.medium.id
        }
    }

    // MARK: - Derived state

    var allProfiles: [CompressionProfile] { CompressionProfile.builtIns + customProfiles }

    var currentProfile: CompressionProfile {
        allProfiles.first { $0.id == selectedProfileID } ?? .medium
    }

    var sortedFiles: [PDFItem] {
        let sorted: [PDFItem]
        switch sortOrder {
        case .dateAdded: sorted = files
        case .name: sorted = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size: sorted = files.sorted { $0.originalSize > $1.originalSize }
        case .ratio: sorted = files.sorted { $0.savedFraction > $1.savedFraction }
        }
        return sortReversed ? sorted.reversed() : sorted
    }

    var selectedItems: [PDFItem] { files.filter { selection.contains($0.id) } }

    /// Selected files that have a smaller compressed version ready to save.
    var savableSelection: [PDFItem] { selectedItems.filter { $0.outputURL != nil } }

    var savableFiles: [PDFItem] { files.filter { $0.outputURL != nil } }

    /// Selected files whose originals can still be replaced.
    var overwritableSelection: [PDFItem] { savableSelection.filter { !$0.isSaved } }

    var suffix: String { UserDefaults.standard.string(forKey: DefaultsKey.suffix) ?? "-smashed" }

    // MARK: - Adding & removing

    func add(urls: [URL]) {
        var newItems: [PDFItem] = []
        let known = Set(files.map { $0.url.standardizedFileURL })
        for url in expand(urls) where !known.contains(url.standardizedFileURL) {
            let item = PDFItem(url: url)
            files.append(item)
            newItems.append(item)
        }
        guard !newItems.isEmpty else { return }
        if selection.isEmpty { selection = [newItems[0].id] }
        for item in newItems {
            loadInfo(for: item)
            compress(item)
        }
    }

    private func expand(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let enumerator = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let file = enumerator?.nextObject() as? URL {
                    if file.pathExtension.lowercased() == "pdf" { result.append(file) }
                }
            } else if url.pathExtension.lowercased() == "pdf" {
                result.append(url)
            } else if url.pathExtension.lowercased() == UTType.smasherProfile.preferredFilenameExtension {
                importProfile(from: url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func remove(_ ids: Set<PDFItem.ID>) {
        for item in files where ids.contains(item.id) {
            item.task?.cancel()
        }
        files.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    func removeAll() { remove(Set(files.map(\.id))) }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .folder]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose PDF files or folders to compress"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    // MARK: - Compression

    private func loadInfo(for item: PDFItem) {
        let url = item.url
        Task {
            let info = await Task.detached(priority: .utility) { () -> (Int, PDFMetadata, NSImage?) in
                guard let document = PDFDocument(url: url) else { return (0, PDFMetadata(), nil) }
                return (document.pageCount, PDFMetadata(document: document), Self.thumbnail(of: document))
            }.value
            item.pageCount = info.0
            item.originalMetadata = info.1
            item.originalThumbnail = info.2
        }
    }

    nonisolated static func thumbnail(of document: PDFDocument) -> NSImage? {
        document.page(at: 0)?.thumbnail(of: NSSize(width: 480, height: 620), for: .cropBox)
    }

    func compress(_ item: PDFItem) {
        item.task?.cancel()
        item.status = .waiting
        item.compressedThumbnail = nil

        let profile = currentProfile
        let input = item.url
        let metadata = item.metadata
        let output = workDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(item.url.lastPathComponent)

        item.task = Task {
            await limiter.acquire()
            guard !Task.isCancelled else {
                await limiter.release()
                return
            }
            item.status = .compressing(0)

            let outcome = await Task.detached(priority: .userInitiated) {
                () -> Result<(CompressionResult, NSImage?), Error> in
                do {
                    let result = try PDFCompressor.compress(
                        input: input, output: output, profile: profile, metadata: metadata,
                        progress: { value in
                            Task { @MainActor in
                                if case .compressing = item.status { item.status = .compressing(value) }
                            }
                        })
                    let thumbnail = PDFDocument(url: output).flatMap(Self.thumbnail(of:))
                    return .success((result, thumbnail))
                } catch {
                    return .failure(error)
                }
            }.value
            await limiter.release()

            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let (result, thumbnail)):
                item.compressedThumbnail = thumbnail
                item.status = result.isSmaller ? .done(result) : .notSmaller(result)
            case .failure(CompressionError.passwordProtected):
                item.status = .protected
            case .failure(let error):
                item.status = .failed(error.localizedDescription)
            }
        }
    }

    func recompressAll() {
        for item in files where !item.isSaved { compress(item) }
    }

    func cancelAll() {
        for item in files where item.isBusy {
            item.task?.cancel()
            item.status = .failed("Compression was stopped.")
        }
    }

    // MARK: - Profiles

    func updateProfile(_ profile: CompressionProfile) {
        guard !profile.isBuiltIn, let index = customProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        guard customProfiles[index] != profile else { return }
        let needsRecompress = profile.name == customProfiles[index].name
        customProfiles[index] = profile
        persistProfiles()
        guard needsRecompress, profile.id == selectedProfileID else { return }
        // Debounce while sliders are being dragged.
        recompressTask?.cancel()
        recompressTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            recompressAll()
        }
    }

    @discardableResult
    func duplicateProfile(_ profile: CompressionProfile) -> CompressionProfile {
        var copy = profile
        copy.id = UUID()
        copy.isBuiltIn = false
        copy.name = uniqueName(profile.isBuiltIn ? "Custom" : "\(profile.name) copy")
        customProfiles.append(copy)
        persistProfiles()
        selectedProfileID = copy.id
        return copy
    }

    func deleteProfile(_ profile: CompressionProfile) {
        guard !profile.isBuiltIn else { return }
        customProfiles.removeAll { $0.id == profile.id }
        persistProfiles()
        if selectedProfileID == profile.id { selectedProfileID = CompressionProfile.medium.id }
    }

    func importProfile(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              var profile = try? JSONDecoder().decode(CompressionProfile.self, from: data) else {
            showError("“\(url.lastPathComponent)” is not a valid PDF Smasher profile.")
            return
        }
        profile.id = UUID()
        profile.isBuiltIn = false
        profile.name = uniqueName(profile.name)
        customProfiles.append(profile)
        persistProfiles()
        selectedProfileID = profile.id
    }

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.smasherProfile, .json]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(importProfile(from:)) }
    }

    func exportProfile(_ profile: CompressionProfile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.smasherProfile]
        panel.nameFieldStringValue = profile.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(profile).write(to: url)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(allProfiles.map(\.name))
        var name = base
        var counter = 2
        while names.contains(name) {
            name = "\(base) \(counter)"
            counter += 1
        }
        return name
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(customProfiles) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.customProfiles)
        }
    }

    // MARK: - Metadata

    func setMetadata(_ metadata: PDFMetadata, for item: PDFItem) {
        guard metadata != (item.metadata ?? item.originalMetadata) else { return }
        item.metadata = metadata
        compress(item)
    }

    // MARK: - Saving

    /// Replaces the originals of `items` with their compressed versions.
    func overwrite(_ items: [PDFItem]) {
        // Already-saved files are skipped so their backup keeps holding the true original.
        let items = items.filter { $0.outputURL != nil && !$0.isSaved }
        guard !items.isEmpty else { return }

        if UserDefaults.standard.object(forKey: DefaultsKey.confirmOverwrite) as? Bool ?? true {
            let alert = NSAlert()
            alert.messageText = items.count == 1
                ? "Replace “\(items[0].url.lastPathComponent)” with the compressed version?"
                : "Replace \(items.count) original files with their compressed versions?"
            alert.informativeText = "You can restore the originals with File ▸ Restore Original until you quit PDF Smasher."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don’t ask again"
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(false, forKey: DefaultsKey.confirmOverwrite)
            }
        }

        let backups = workDirectory.appendingPathComponent("Originals", isDirectory: true)
        try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)

        for item in items {
            guard let output = item.outputURL else { continue }
            do {
                let backup = backups.appendingPathComponent(UUID().uuidString + ".pdf")
                try FileManager.default.copyItem(at: item.url, to: backup)
                let staged = output.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".pdf")
                try FileManager.default.copyItem(at: output, to: staged)
                _ = try FileManager.default.replaceItemAt(item.url, withItemAt: staged)
                item.backupURL = backup
                item.isSaved = true
                totalBytesSaved += item.originalSize - item.compressedSize
            } catch {
                showError("Could not save “\(item.url.lastPathComponent)”: \(error.localizedDescription)")
            }
        }
    }

    func restore(_ items: [PDFItem]) {
        for item in items {
            guard let backup = item.backupURL else { continue }
            do {
                _ = try FileManager.default.replaceItemAt(item.url, withItemAt: backup)
                item.backupURL = nil
                item.isSaved = false
                totalBytesSaved -= item.originalSize - item.compressedSize
            } catch {
                showError("Could not restore “\(item.url.lastPathComponent)”: \(error.localizedDescription)")
            }
        }
    }

    func saveAs(_ items: [PDFItem]) {
        let items = items.filter { $0.outputURL != nil }
        if items.count > 1 {
            saveToFolder(items)
            return
        }
        guard let item = items.first, let output = item.outputURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = item.url.deletingLastPathComponent()
        panel.nameFieldStringValue = item.name + suffix + ".pdf"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        copy(output, to: destination, item: item)
    }

    func saveToFolder(_ items: [PDFItem]) {
        let items = items.filter { $0.outputURL != nil }
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose a folder for \(items.count) compressed files"
        panel.directoryURL = items[0].url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        for item in items {
            guard let output = item.outputURL else { continue }
            copy(output, to: folder.appendingPathComponent(item.name + suffix + ".pdf"), item: item)
        }
    }

    private func copy(_ output: URL, to destination: URL, item: PDFItem) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: output, to: destination)
            totalBytesSaved += item.originalSize - item.compressedSize
        } catch {
            showError("Could not save “\(destination.lastPathComponent)”: \(error.localizedDescription)")
        }
    }

    // MARK: - Extra tools

    func extractText(from item: PDFItem) {
        guard let document = PDFDocument(url: item.url) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = item.url.deletingLastPathComponent()
        panel.nameFieldStringValue = item.name + ".txt"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try (document.string ?? "").write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func reveal(_ items: [PDFItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    func openPreview(_ item: PDFItem, original: Bool) {
        let url = original ? item.url : (item.outputURL ?? item.url)
        NSWorkspace.shared.open(url)
    }

    func resetStatistics() { totalBytesSaved = 0 }

    func cleanUp() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.runModal()
    }
}
