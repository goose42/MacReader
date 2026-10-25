import MacReaderKit
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    let library: LibraryViewModel
    @Binding var isChoosingLibrary: Bool
    @Binding var isImporting: Bool
    @State private var selection: MacReaderKit.LibraryItem.ID?
    @State private var pendingDeletion: MacReaderKit.LibraryItem?
    @FocusState private var isSidebarFocused: Bool

    var body: some View {
        Group {
            if library.state == .noLibrary {
                LibraryPickerView { isChoosingLibrary = true }
            } else {
                splitView
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .fileImporter(isPresented: $isChoosingLibrary, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { library.chooseLibrary(url) }
        }
        // Folders are allowed so a saved page's "…_files" folder can be chosen along with it, which is what lets the
        // sandboxed app read its images.
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf, .html, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await library.addDocuments(urls) } }
        }
        .overlay {
            if library.isWorking {
                ProgressView("Reading…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.title ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                if selection == item.id { selection = nil }
                library.delete(item)
            }
        } message: { _ in
            Text("This permanently removes it from your library. The original file is not affected.")
        }
        .alert("Something Went Wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(library.items, selection: $selection) { item in
                Label {
                    VStack(alignment: .leading) {
                        Text(item.title).lineLimit(2)
                        Text(subtitle(of: item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: item.sourceKind == .html ? "globe" : "doc.text")
                }
                .accessibilityElement(children: .combine)
                .contextMenu {
                    Button("Delete…", systemImage: "trash", role: .destructive) { pendingDeletion = item }
                }
            }
            .focused($isSidebarFocused)
            .onDeleteCommand {
                pendingDeletion = library.items.first { $0.id == selection }
            }
            .navigationTitle("Library")
            .navigationSplitViewColumnWidth(min: 200, ideal: 260)
            .overlay {
                if library.state == .empty {
                    ContentUnavailableView {
                        Label("No Documents", systemImage: "books.vertical")
                    } description: {
                        Text("Add a PDF or a saved web page to start reading.")
                    } actions: {
                        Button("Import…") { isImporting = true }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button("Import", systemImage: "plus") { isImporting = true }
                        .help("Add a PDF or a saved web page to the library")
                }
            }
        } detail: {
            if let document = library.selectedDocument {
                ReaderView(
                    document: document,
                    initialPosition: library.selectedPosition,
                    stepsWithArrowKeys: !isSidebarFocused,
                    imageScale: library.selectedItem?.sourceKind == .html ? 1 : 2,
                    originalPageURL: library.selectedPageURL,
                    imageURL: { library.selectedImageURL(named: $0) },
                    onPositionChange: { library.saveReadingPosition($0) })
            } else {
                ContentUnavailableView("Select a Document", systemImage: "doc.text")
            }
        }
        .onChange(of: selection) { _, id in
            if let item = library.items.first(where: { $0.id == id }) { library.select(item) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { ["pdf", "html", "htm"].contains($0.pathExtension.lowercased()) || $0.hasDirectoryPath }
            guard !accepted.isEmpty else { return false }
            Task { await library.addDocuments(accepted) }
            return true
        }
    }

    private func subtitle(of item: MacReaderKit.LibraryItem) -> String {
        let date = item.dateAdded.formatted(.dateTime.month().day().year())
        return item.siteName.map { "\($0) · \(date)" } ?? date
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.dismissError() } })
    }
}
