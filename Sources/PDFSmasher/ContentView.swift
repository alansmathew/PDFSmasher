import SmasherCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showProfile = false
    @State private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            DetailView()
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
        }
        // The app name is drawn as a toolbar item in front of the profile menu instead.
        .navigationTitle("")
        .toolbar { leadingToolbar }
        .modifier(ActionToolbar(showProfile: $showProfile))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            loadURLs(from: providers)
            return true
        }
    }

    @ToolbarContentBuilder
    private var leadingToolbar: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { AppTitle() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { AppTitle() }
        }
        ToolbarItem(placement: .navigation) {
            ProfileMenu(showProfile: $showProfile)
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            model.add(urls: urls)
        }
    }
}

/// Trailing toolbar: Compare | Info + Profile Settings | Share | Save | Save As.
private struct ActionToolbar: ViewModifier {
    @Binding var showProfile: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.toolbar {
                ToolbarSpacer(.flexible)
                ToolbarItem { CompareToggle() }
                ToolbarSpacer(.fixed)
                ToolbarItem { InspectorButtons(showProfile: $showProfile) }
                ToolbarSpacer(.fixed)
                ToolbarItem { ShareButton() }
                ToolbarSpacer(.fixed)
                ToolbarItem { SaveButton() }
                ToolbarItem { SaveAsButton() }
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .primaryAction) { CompareToggle() }
                ToolbarItem(placement: .primaryAction) { InspectorButtons(showProfile: $showProfile) }
                ToolbarItem(placement: .primaryAction) { ShareButton() }
                ToolbarItem(placement: .primaryAction) { SaveButton() }
                ToolbarItem(placement: .primaryAction) { SaveAsButton() }
            }
        }
    }
}

// MARK: - Toolbar items

private struct AppTitle: View {
    var body: some View {
        Text("PDF Smasher")
            .font(.headline)
            .fixedSize()
            .padding(.horizontal, 4)
    }
}

private struct ProfileMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var showProfile: Bool

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Compression Profile", selection: $model.selectedProfileID) {
                ForEach(CompressionProfile.builtIns) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if !model.customProfiles.isEmpty {
                Picker("Custom Profiles", selection: $model.selectedProfileID) {
                    ForEach(model.customProfiles) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
            }
            Divider()
            Button("Customize…") { showProfile = true }
            Button("Import Profile…") { model.showImportPanel() }
        } label: {
            Text(model.currentProfile.name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 200)
        .help("Compression profile")
    }
}

private struct CompareToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle(isOn: $model.showOriginal) {
            Label("Compare", systemImage: "arrow.left.arrow.right")
        }
        .help("Compare with the original")
        .disabled(model.selectedItems.isEmpty)
    }
}

private struct InspectorButtons: View {
    @Environment(AppModel.self) private var model
    @Binding var showProfile: Bool
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 0) {
            Button { showInfo.toggle() } label: {
                Label("Info", systemImage: "info.circle")
            }
            .help("Document information")
            .accessibilityLabel("Info")
            .disabled(model.selectedItems.count != 1)
            .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                if let item = model.selectedItems.first {
                    MetadataView(item: item)
                        .environment(model)
                }
            }

            Divider()
                .frame(height: 16)

            Button { showProfile.toggle() } label: {
                Label("Profile Settings", systemImage: "slider.horizontal.3")
            }
            .help("Compression profile settings")
            .accessibilityLabel("Profile Settings")
            .popover(isPresented: $showProfile, arrowEdge: .bottom) {
                ProfileEditorView()
                    .environment(model)
            }
        }
    }
}

private struct ShareButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ShareLink(items: model.savableSelection.compactMap(\.outputURL)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .help("Share the compressed files")
        .disabled(model.savableSelection.isEmpty)
    }
}

private struct SaveButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Save") { model.overwrite(model.overwritableSelection) }
            .help("Replace the original with the compressed file")
            .disabled(model.overwritableSelection.isEmpty)
    }
}

private struct SaveAsButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Save As…") { model.saveAs(model.savableSelection) }
            .help("Save the compressed file as a copy")
            .disabled(model.savableSelection.isEmpty)
    }
}
