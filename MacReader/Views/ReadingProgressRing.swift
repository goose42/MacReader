import SwiftUI

/// A small ring for the toolbar: a thin track with a bolder arc showing how much of the document has been read.
struct ReadingProgressRing: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var percent: String { progress.formatted(.percent.precision(.fractionLength(0))) }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
        .frame(width: 18, height: 18)
        .animation(reduceMotion ? nil : .default, value: progress)
        .help("\(percent) read")
        .accessibilityElement()
        .accessibilityLabel("Reading Progress")
        .accessibilityValue("\(percent) read")
    }
}
