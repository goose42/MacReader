import SwiftUI

struct LibraryPickerView: View {
    let choose: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Welcome to MacReader", systemImage: "books.vertical")
        } description: {
            Text("Choose a folder to hold your library. Documents you add are stored there as plain text.")
        } actions: {
            Button("Choose Library Folder…", action: choose)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
