import SmasherCore
import SwiftUI

struct MetadataView: View {
    @Environment(AppModel.self) private var model
    let item: PDFItem
    @State private var draft = PDFMetadata()

    var body: some View {
        Form {
            Section("Document Information") {
                TextField("Title", text: $draft.title)
                TextField("Author", text: $draft.author)
                TextField("Subject", text: $draft.subject)
                TextField("Keywords", text: $draft.keywords, prompt: Text("comma, separated"))
            }

            Section("File") {
                LabeledContent("Name", value: item.url.lastPathComponent)
                LabeledContent("Pages", value: "\(item.pageCount)")
                LabeledContent("Original size", value: Format.size(item.originalSize))
                if let result = item.result {
                    LabeledContent("Compressed size", value: Format.size(result.compressedSize))
                }
                LabeledContent("Location") {
                    Button(item.url.deletingLastPathComponent().lastPathComponent) { model.reveal([item]) }
                        .buttonStyle(.link)
                }
            }

            if model.currentProfile.removeMetadata {
                Text("The current profile removes all document information from the compressed file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { draft = item.metadata ?? item.originalMetadata }
        .onSubmit { model.setMetadata(draft, for: item) }
        .onDisappear { model.setMetadata(draft, for: item) }
    }
}
