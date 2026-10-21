import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            ForEach(model.sortedFiles) { item in
                FileRow(item: item)
                    .tag(item.id)
                    .contextMenu { contextMenu(for: item) }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand { model.remove(model.selection) }
        .overlay {
            if model.files.isEmpty {
                Text("No Files")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Menu {
                    Picker("Sort By", selection: $model.sortOrder) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Reverse Order", isOn: $model.sortReversed)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort files")

                Spacer()

                if !model.files.isEmpty {
                    Text(model.files.count == 1 ? "1 file" : "\(model.files.count) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button { model.showOpenPanel() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.borderless)
                .help("Add PDF files")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: PDFItem) -> some View {
        let targets = model.selection.contains(item.id) ? model.selectedItems : [item]
        Button("Save") { model.overwrite(targets) }
            .disabled(!targets.contains { $0.outputURL != nil && !$0.isSaved })
        Button("Save As…") { model.saveAs(targets) }
            .disabled(!targets.contains { $0.outputURL != nil })
        Button("Restore Original") { model.restore(targets) }
            .disabled(!targets.contains { $0.backupURL != nil })
        Divider()
        Button("Open Compressed File") { model.openPreview(item, original: false) }
            .disabled(item.outputURL == nil)
        Button("Reveal in Finder") { model.reveal(targets) }
        Button("Compress Again") { targets.forEach(model.compress) }
        Divider()
        Button("Remove", role: .destructive) { model.remove(Set(targets.map(\.id))) }
    }
}

struct FileRow: View {
    let item: PDFItem

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail = item.originalThumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.85))
                }
            }
            .frame(width: 26, height: 34)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    if case .compressing = item.status {
                        ProgressView().controlSize(.mini)
                    }
                    if item.isSaved {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Text(subtitle)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(subtitleStyle)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        switch item.status {
        case .waiting: return "Waiting…"
        case .compressing: return "Compressing…"
        case .done(let result):
            return "\(Format.size(result.originalSize)) → \(Format.size(result.compressedSize)), \(Format.percent(result.savedFraction))"
        case .notSmaller: return "\(Format.size(item.originalSize)), can’t be reduced"
        case .protected: return "Password protected"
        case .failed(let message): return message
        }
    }

    private var subtitleStyle: AnyShapeStyle {
        switch item.status {
        case .failed, .protected: return AnyShapeStyle(.red)
        default: return AnyShapeStyle(.secondary)
        }
    }
}
