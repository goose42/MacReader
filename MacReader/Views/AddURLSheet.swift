import AppKit
import MacReaderKit
import SwiftUI

/// Asks for a web address and fetches the page into the library. It stays open on failure so the address can be
/// corrected, and closes once the page has been added.
struct AddURLSheet: View {
    let library: LibraryViewModel
    let onAdded: (MacReaderKit.LibraryItem) -> Void

    @State private var address: String
    @State private var fetch: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(library: LibraryViewModel, initialAddress: String = "", onAdded: @escaping (MacReaderKit.LibraryItem) -> Void) {
        self.library = library
        self.onAdded = onAdded
        _address = State(initialValue: initialAddress)
    }

    private var isFetching: Bool { fetch != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Web Page")
                .font(.headline)
            Text("Paste the address of an article to add it to your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Web address", text: $address, prompt: Text("https://example.com/article"))
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .disabled(isFetching)
                .onSubmit(add)
                .accessibilityLabel("Web address")

            if isFetching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching page…").foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if let message = library.webPageError {
                Text(message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(message)")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isFetching || WebAddress.parse(address) == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            library.dismissWebPageError()
            if address.isEmpty, let copied = NSPasteboard.general.string(forType: .string), WebAddress.parse(copied) != nil {
                address = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            isFieldFocused = true
        }
    }

    private func add() {
        guard !isFetching, WebAddress.parse(address) != nil else { return }
        fetch = Task {
            let item = await library.addWebPage(address)
            fetch = nil
            if let item, !Task.isCancelled {
                onAdded(item)
                dismiss()
            }
        }
    }

    private func cancel() {
        fetch?.cancel()
        dismiss()
    }
}
