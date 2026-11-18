import Foundation

struct MomentProgress: Equatable {
    let count: Int
    let activeIndex: Int

    init?(day: Int, momentCount: Int) {
        guard momentCount > 1, day >= 1, day <= momentCount else { return nil }
        self.count = momentCount
        self.activeIndex = day - 1
    }

    var position: Int { activeIndex + 1 }

    func isActive(_ index: Int) -> Bool { index == activeIndex }
}
