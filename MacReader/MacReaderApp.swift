import MacReaderKit
import SwiftUI

@main
struct MacReaderApp: App {
    @State private var library = LibraryViewModel()
    @State private var isChoosingLibrary = false
    @State private var isAddingPDF = false
    @AppStorage("readerColumnWidth") private var columnWidth = ReaderColumnWidth.narrow
    @FocusedValue(\.sentenceNavigation) private var sentenceNavigation

    var body: some Scene {
        WindowGroup {
            HomeView(library: library, isChoosingLibrary: $isChoosingLibrary, isAddingPDF: $isAddingPDF)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add PDF…") { isAddingPDF = true }
                    .keyboardShortcut("o")
                    .disabled(library.state == .noLibrary)
                Button("Choose Library Folder…") { isChoosingLibrary = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                columnWidthToggle(.narrow, shortcut: "1")
                columnWidthToggle(.wide, shortcut: "2")
                Divider()
            }
            CommandMenu("Go") {
                Button("Next Sentence") { sentenceNavigation?.next() }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .disabled(sentenceNavigation == nil)
                Button("Previous Sentence") { sentenceNavigation?.previous() }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .disabled(sentenceNavigation == nil)
            }
        }
        Settings { SettingsView() }
    }

    private func columnWidthToggle(_ width: ReaderColumnWidth, shortcut: KeyEquivalent) -> some View {
        Toggle(
            "\(width.title) Column",
            systemImage: width.systemImage,
            isOn: Binding(get: { columnWidth == width }, set: { _ in columnWidth = width })
        )
        .keyboardShortcut(shortcut, modifiers: [.command, .option])
    }
}
