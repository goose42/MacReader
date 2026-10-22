import SwiftUI

/// Sentence-stepping actions published by the reader while it has keyboard focus, so menu commands (and the arrow
/// keys bound to them) only act when the reader is the focused view.
struct SentenceNavigation {
    let next: () -> Void
    let previous: () -> Void
}

extension FocusedValues {
    @Entry var sentenceNavigation: SentenceNavigation?
}
