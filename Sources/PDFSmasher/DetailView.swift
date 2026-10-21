import AppKit
import SwiftUI

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.selectedItems
        Group {
            if model.files.isEmpty {
                DropPrompt()
            } else if items.count == 1, let item = items.first {
                SingleFileView(item: item, showOriginal: model.showOriginal)
            } else if items.count > 1 {
                MultipleFilesView(items: items, showOriginal: model.showOriginal)
            } else {
                Text("Select a file to see the result")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DropPrompt: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            Group {
                if let image = NSImage(named: "DropTarget") {
                    Image(nsImage: image).renderingMode(.template).resizable()
                } else {
                    Image(systemName: "tray.and.arrow.down").resizable()
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: 110, height: 110)
            .foregroundStyle(.tertiary)

            Text("Drop PDF files or folders here to smash them")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Choose Files…") { model.showOpenPanel() }
                .controlSize(.large)
        }
        .padding()
    }
}

struct PageCard: View {
    let image: NSImage?
    var badge: String?
    var maxHeight: CGFloat = 260

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.white)
                    .aspectRatio(0.77, contentMode: .fit)
                    .overlay { ProgressView() }
            }
        }
        .frame(maxHeight: maxHeight)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .overlay(alignment: .topTrailing) {
            if let badge {
                Text(badge)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.gradient))
                    .offset(x: 12, y: -10)
            }
        }
    }
}

struct SingleFileView: View {
    @Environment(AppModel.self) private var model
    let item: PDFItem
    let showOriginal: Bool

    var body: some View {
        VStack(spacing: 18) {
            PageCard(
                image: showOriginal ? item.originalThumbnail : (item.compressedThumbnail ?? item.originalThumbnail),
                badge: showOriginal || item.outputURL == nil ? nil : "−" + Format.percent(item.savedFraction))
            .onTapGesture(count: 2) { model.openPreview(item, original: showOriginal) }
            .help("Double-click to open")

            VStack(spacing: 6) {
                Text(sizeLine)
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .contentTransition(.numericText())
                statusLine
                    .font(.body)
            }
        }
        .padding(30)
        .animation(.snappy, value: item.status)
    }

    private var sizeLine: String {
        if showOriginal { return "Original (\(Format.size(item.originalSize)))" }
        if let result = item.result {
            return "\(Format.size(result.originalSize)) → \(Format.size(result.compressedSize))"
        }
        return Format.size(item.originalSize)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch item.status {
        case .waiting:
            Text("Waiting…").foregroundStyle(.secondary)
        case .compressing(let progress):
            ProgressView(value: progress)
                .frame(width: 180)
        case .done(let result):
            if item.isSaved {
                Label("Saved — \(Format.size(result.originalSize - result.compressedSize)) smaller", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Size reduced by \(Format.percent(result.savedFraction))").foregroundStyle(.secondary)
            }
        case .notSmaller:
            Text("This file can’t get any smaller with this profile. Try a stronger one.")
                .foregroundStyle(.secondary)
        case .protected:
            Label("This file is password protected.", systemImage: "lock.fill").foregroundStyle(.red)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}

struct MultipleFilesView: View {
    let items: [PDFItem]
    let showOriginal: Bool

    var body: some View {
        let original = items.reduce(0) { $0 + $1.originalSize }
        let compressed = items.reduce(0) { $0 + $1.compressedSize }
        let busy = items.filter(\.isBusy).count
        let failed = items.filter {
            switch $0.status {
            case .failed, .protected: return true
            default: return false
            }
        }.count

        VStack(spacing: 22) {
            ZStack {
                ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                    PageCard(
                        image: showOriginal ? item.originalThumbnail : (item.compressedThumbnail ?? item.originalThumbnail),
                        maxHeight: 220)
                    .rotationEffect(.degrees(Double(index) * 5 - 5))
                    .offset(x: CGFloat(index) * 26 - 26)
                }
            }

            VStack(spacing: 6) {
                Text("\(items.count) files")
                    .font(.headline)
                Text(showOriginal ? "Original (\(Format.size(original)))" : "\(Format.size(original)) → \(Format.size(compressed))")
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                if busy > 0 {
                    Text("\(busy) still compressing…").foregroundStyle(.secondary)
                } else if original > 0 {
                    Text("Size reduced by \(Format.percent(1 - Double(compressed) / Double(original)))")
                        .foregroundStyle(.secondary)
                }
                if failed > 0 {
                    Text("\(failed) could not be compressed").foregroundStyle(.red)
                }
            }
        }
        .padding(30)
    }
}
