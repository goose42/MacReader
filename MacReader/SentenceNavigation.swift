import SwiftUI

/// Sentence-stepping actions published by the reader while it is on screen, so the menu commands and the sidebar's
/// arrow keys step through the text rather than through the library.
struct SentenceNavigation {
    let next: () -> Void
    let previous: () -> Void
}

extension FocusedValues {
    @Entry var sentenceNavigation: SentenceNavigation?
}

/// Moves to the document above or below the selected one, or is nil at either end of the library.
struct DocumentNavigation {
    let next: (() -> Void)?
    let previous: (() -> Void)?
}

extension FocusedValues {
    @Entry var documentNavigation: DocumentNavigation?
}
