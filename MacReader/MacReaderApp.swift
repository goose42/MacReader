import MacReaderKit
import SwiftUI

@main
struct MacReaderApp: App {
    @State private var library = LibraryViewModel()
    @State private var isChoosingLibrary = false
    @State private var isAddingPDF = false

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
        }
    }
}
