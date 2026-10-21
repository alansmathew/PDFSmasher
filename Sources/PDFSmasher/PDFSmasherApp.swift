import AppKit
import SwiftUI

@main
struct PDFSmasherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("PDF Smasher", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 1000, height: 560)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running straight from `swift run` has no bundle; make sure we still get a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppModel.shared.add(urls: urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.cleanUp() }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { model.showOpenPanel() }
                .keyboardShortcut("o")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.overwrite(model.overwritableSelection) }
                .keyboardShortcut("s")
                .disabled(model.overwritableSelection.isEmpty)
            Button("Save As…") { model.saveAs(model.savableSelection) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.savableSelection.isEmpty)
            Button("Save All") { model.overwrite(model.savableFiles) }
                .disabled(!model.savableFiles.contains { !$0.isSaved })
            Button("Save All to Folder…") { model.saveToFolder(model.savableFiles) }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model.savableFiles.isEmpty)
            Divider()
            Button("Restore Original") { model.restore(model.selectedItems) }
                .disabled(!model.selectedItems.contains { $0.backupURL != nil })
            Button("Reveal in Finder") { model.reveal(model.selectedItems) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedItems.isEmpty)
            Divider()
            Button("Remove") { model.remove(model.selection) }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selection.isEmpty)
            Button("Remove All Files") { model.removeAll() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.files.isEmpty)
        }

        CommandMenu("Tools") {
            Button("Compress Again") { model.selectedItems.forEach(model.compress) }
                .keyboardShortcut("r")
                .disabled(model.selectedItems.isEmpty)
            Button("Stop Compression") { model.cancelAll() }
                .keyboardShortcut(".")
                .disabled(!model.files.contains { $0.isBusy })
            Divider()
            Button("Extract Text…") {
                if let item = model.selectedItems.first { model.extractText(from: item) }
            }
            .disabled(model.selectedItems.count != 1)
            Divider()
            Button("Import Profile…") { model.showImportPanel() }
            Button("Export Current Profile…") { model.exportProfile(model.currentProfile) }
        }

        CommandGroup(after: .sidebar) {
            Picker("Sort By", selection: Binding(get: { model.sortOrder }, set: { model.sortOrder = $0 })) {
                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            Toggle("Reverse Order", isOn: Binding(get: { model.sortReversed }, set: { model.sortReversed = $0 }))
            Toggle("Show Original", isOn: Binding(get: { model.showOriginal }, set: { model.showOriginal = $0 }))
                .keyboardShortcut("o", modifiers: [.command, .option])
            Divider()
        }

        CommandGroup(replacing: .help) {
            Link("PDF Smasher on GitHub", destination: URL(string: "https://github.com/pdfsmasher/PDFSmasher")!)
        }
    }
}
