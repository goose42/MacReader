import SwiftUI

/// Sentence-stepping actions published by the reader while it is on screen and the sidebar is not focused, so the
/// menu commands (and the arrow keys bound to them) leave the sidebar's own arrow-key navigation alone.
struct SentenceNavigation {
    let next: () -> Void
    let previous: () -> Void
}

extension FocusedValues {
    @Entry var sentenceNavigation: SentenceNavigation?
}
