import MacReaderKit
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    let library: LibraryViewModel
    @Binding var isChoosingLibrary: Bool
    @Binding var isAddingPDF: Bool
    @State private var selection: MacReaderKit.LibraryItem.ID?

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
        .fileImporter(isPresented: $isAddingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.addPDFs(urls) }
        }
        .alert("Couldn't Add Some Files", isPresented: errorBinding) {
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
                        Text(item.dateAdded, format: .dateTime.month().day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.text")
                }
            }
            .navigationTitle("Library")
            .navigationSplitViewColumnWidth(min: 200, ideal: 260)
            .overlay {
                if library.state == .empty {
                    ContentUnavailableView {
                        Label("No Documents", systemImage: "books.vertical")
                    } description: {
                        Text("Add a PDF to start reading.")
                    } actions: {
                        Button("Add PDF…") { isAddingPDF = true }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button("Add PDF", systemImage: "plus") { isAddingPDF = true }
                        .help("Add a PDF to the library")
                }
            }
        } detail: {
            if let item = library.items.first(where: { $0.id == selection }) {
                ReaderView(title: item.title, text: library.selectedText ?? "")
            } else {
                ContentUnavailableView("Select a Document", systemImage: "doc.text")
            }
        }
        .onChange(of: selection) { _, id in
            if let item = library.items.first(where: { $0.id == id }) { library.select(item) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            library.addPDFs(pdfs)
            return !pdfs.isEmpty
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { library.errorMessage != nil }, set: { _ in })
    }
}
