import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(DefaultsKey.suffix) private var suffix = "-smashed"
    @AppStorage(DefaultsKey.confirmOverwrite) private var confirmOverwrite = true

    var body: some View {
        Form {
            Section("Saving") {
                TextField("File name suffix", text: $suffix, prompt: Text("-smashed"))
                Text("“Save As” names files like “Report\(suffix).pdf”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Ask before replacing original files", isOn: $confirmOverwrite)
            }

            Section("Statistics") {
                LabeledContent("Disk space saved", value: Format.size(model.totalBytesSaved))
                Button("Reset Statistics") { model.resetStatistics() }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                Text("PDF Smasher is free and open source (MIT). Files never leave your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
