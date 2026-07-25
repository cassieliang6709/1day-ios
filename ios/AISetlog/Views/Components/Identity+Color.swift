import SwiftUI

/// Presentation-layer color for a recorder's identity. The hash (which name →
/// which palette slot) is a business rule and stays in `Identity`; which blue
/// a slot *renders as* is a design decision and lives here.
extension Identity {
    static func tint(for name: String?) -> Color {
        Color(uiColor: uiColor(for: name))
    }
}
