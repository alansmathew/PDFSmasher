import SmasherCore
import SwiftUI

struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = CompressionProfile.medium

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)

            Form {
                Section("Images") {
                    Toggle("Optimize images", isOn: $draft.optimizeImages)
                        .help("Turn off to keep all images in their original quality and resolution.")
                    Group {
                        LabeledContent("Maximum resolution") {
                            HStack {
                                Slider(value: dpiBinding(\.maxImageDPI), in: 50...600)
                                Text("\(draft.maxImageDPI) dpi").monospacedDigit().frame(width: 60, alignment: .trailing)
                            }
                        }
                        LabeledContent("Image quality") {
                            HStack {
                                Slider(value: $draft.jpegQuality, in: 0.05...1)
                                Text(Format.percent(draft.jpegQuality.rounded(toPlaces: 2)))
                                    .monospacedDigit().frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                    .disabled(!draft.optimizeImages && !draft.convertToBitmap)
                    Toggle("Convert to grayscale", isOn: $draft.grayscale)
                }

                Section {
                    Toggle("Convert pages to images", isOn: $draft.convertToBitmap)
                    if draft.convertToBitmap {
                        LabeledContent("Page resolution") {
                            HStack {
                                Slider(value: dpiBinding(\.bitmapDPI), in: 50...400)
                                Text("\(draft.bitmapDPI) dpi").monospacedDigit().frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text("Pages")
                } footer: {
                    Text("Best for scans. Text will no longer be selectable or searchable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Document") {
                    Toggle("Remove metadata", isOn: $draft.removeMetadata)
                        .help("Removes title, author, keywords and other document information.")
                    Toggle("Remove annotations", isOn: $draft.removeAnnotations)
                        .help("Removes comments, highlights and form markup. Links are kept.")
                    Toggle("Flatten annotations", isOn: $draft.flattenAnnotations)
                        .help("Draws annotations into the page so they can no longer be edited.")
                        .disabled(draft.removeAnnotations)
                    Toggle("Lossless structure optimization", isOn: $draft.losslessOptimization)
                        .help("Recompresses text, fonts and the file structure without any quality loss.")
                        .disabled(!LosslessOptimizer.isAvailable)
                }
            }
            .formStyle(.grouped)
            .disabled(draft.isBuiltIn)
            .scrollDisabled(true)

            footer
                .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { draft = model.currentProfile }
        .onChange(of: model.selectedProfileID) { draft = model.currentProfile }
        .onChange(of: draft) { model.updateProfile(draft) }
    }

    private var header: some View {
        HStack {
            if draft.isBuiltIn {
                Text(draft.name).font(.headline)
                Spacer()
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    .help("Built-in profiles can’t be changed. Duplicate one to customize it.")
            } else {
                TextField("Profile name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(draft.isBuiltIn ? "Duplicate to Customize" : "Duplicate") {
                draft = model.duplicateProfile(draft)
            }
            Spacer()
            Menu {
                Button("Import Profile…") { model.showImportPanel() }
                Button("Export Profile…") { model.exportProfile(draft) }
                if !draft.isBuiltIn {
                    Divider()
                    Button("Delete Profile", role: .destructive) { model.deleteProfile(draft) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func dpiBinding(_ keyPath: WritableKeyPath<CompressionProfile, Int>) -> Binding<Double> {
        Binding(get: { Double(draft[keyPath: keyPath]) }, set: { draft[keyPath: keyPath] = Int($0) })
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
