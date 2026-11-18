import SwiftUI

extension Identity {
    static func tint(for name: String?) -> Color {
        Color(uiColor: uiColor(for: name))
    }
}
