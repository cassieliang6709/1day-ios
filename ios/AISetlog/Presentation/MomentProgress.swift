import Foundation

/// Where you are in a story, while you're still filming it.
///
/// The camera used to draw three white bars with the middle one lit — the same
/// three bars, lit in the same place, whether the story had two moments or
/// fifteen and whether you were on the first one or the last. It was shaped
/// like a progress indicator and indicated nothing.
///
/// This is that indicator's whole brain: how many segments there are and which
/// one is you. It knows nothing about SwiftUI, so the answer can be checked
/// without a screen.
struct MomentProgress: Equatable {
    /// How many segments to draw — one per moment in the story.
    let count: Int
    /// Which of them is the moment being filmed, counting from zero.
    let activeIndex: Int

    /// - Returns: nil when there is nothing true to draw.
    ///
    /// That covers three cases, and all three should show no indicator rather
    /// than a decorative one:
    /// - free-form capture, which has no story behind it yet (`momentCount` 0);
    /// - a one-moment story, where a single bar says nothing the title doesn't;
    /// - a day that isn't in the story at all, which means somebody upstream is
    ///   confused and the honest thing is to stay quiet about it.
    init?(day: Int, momentCount: Int) {
        guard momentCount > 1, day >= 1, day <= momentCount else { return nil }
        self.count = momentCount
        self.activeIndex = day - 1
    }

    /// Which moment this is, counting from one — for the spoken label.
    var position: Int { activeIndex + 1 }

    func isActive(_ index: Int) -> Bool { index == activeIndex }
}
