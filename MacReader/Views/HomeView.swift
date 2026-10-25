import MacReaderKit
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    let library: LibraryViewModel
    @Binding var isChoosingLibrary: Bool
    @Binding var isImporting: Bool
    @Binding var isAddingWebPage: Bool
    @State private var droppedAddress = ""
    @State private var selection: MacReaderKit.LibraryItem.ID?
    @State private var pendingDeletion: MacReaderKit.LibraryItem?
    @FocusedValue(\.sentenceNavigation) private var sentenceNavigation

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
        .fileImporter(isPresented: $isImporting, allowedContentTypes: UTType.libraryDocuments, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await library.addDocuments(urls) } }
        }
        .sheet(isPresented: $isAddingWebPage) {
            AddURLSheet(library: library, initialAddress: droppedAddress) { selection = $0.id }
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
                HStack {
                    Label {
                        VStack(alignment: .leading) {
                            Text(item.title).lineLimit(2)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: item.symbolName)
                    }
                    if let progress = library.progress(of: item) {
                        Spacer()
                        ReadingProgressRing(progress: progress)
                    }
                }
                .accessibilityElement(children: .combine)
                .contextMenu {
                    Button("Delete…", systemImage: "trash", role: .destructive) { pendingDeletion = item }
                }
            }
            // Once a document is open the arrows read it; moving between documents is ⌥⌘↑ / ⌥⌘↓ in the Go menu.
            .onKeyPress(.downArrow) { step(sentenceNavigation?.next) }
            .onKeyPress(.upArrow) { step(sentenceNavigation?.previous) }
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
                        Text("Add a PDF, an ebook, a saved web page, or the address of an article to start reading.")
                    } actions: {
                        Button("Add File…", systemImage: "doc") { isImporting = true }
                        Button("Add Web Page from URL…", systemImage: "link") { addWebPage() }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Menu("Add", systemImage: "plus") {
                        Button("Add File…", systemImage: "doc") { isImporting = true }
                        Button("Add Web Page from URL…", systemImage: "link") { addWebPage() }
                    }
                    .help("Add a file or a web page to the library")
                }
            }
        } detail: {
            if let document = library.selectedDocument {
                ReaderView(
                    document: document,
                    initialPosition: library.selectedPosition,
                    imageScale: library.selectedItem?.sourceKind == .pdf ? 2 : 1,
                    originalPageURL: library.selectedPageURL,
                    imageURL: { library.selectedImageURL(named: $0) },
                    onPositionChange: { library.saveReadingPosition($0) })
            } else {
                ContentUnavailableView("Select a Document", systemImage: "doc.text")
            }
        }
        .focusedSceneValue(\.documentNavigation, DocumentNavigation(
            next: library.adjacentItem(1).map { item in { selection = item.id } },
            previous: library.adjacentItem(-1).map { item in { selection = item.id } }))
        .onChange(of: selection) { _, id in
            if let item = library.items.first(where: { $0.id == id }) { library.select(item) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            // A dropped web address opens the sheet with it filled in, so it can be checked before it is fetched.
            if let web = urls.first(where: { !$0.isFileURL && WebAddress.parse($0.absoluteString) != nil }) {
                addWebPage(prefilledWith: web.absoluteString)
                return true
            }
            let accepted = urls.filter(LibraryViewModel.canAdd)
            guard !accepted.isEmpty else { return false }
            Task { await library.addDocuments(accepted) }
            return true
        }
    }

    private func step(_ action: (() -> Void)?) -> KeyPress.Result {
        guard let action else { return .ignored }
        action()
        return .handled
    }

    private func addWebPage(prefilledWith address: String = "") {
        droppedAddress = address
        isAddingWebPage = true
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.dismissError() } })
    }
}
