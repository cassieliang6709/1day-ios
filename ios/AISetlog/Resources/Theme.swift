import SwiftUI
import UIKit

/// The app's blue/cyan palette, shared across every view. UIColor is the
/// source of truth (the identity hash in Models needs it without SwiftUI);
/// the SwiftUI colors derive from it.
extension UIColor {
    static let oneDayBlue = UIColor(red: 0.0, green: 0.55, blue: 0.95, alpha: 1)
    static let oneDayCyan = UIColor(red: 0.0, green: 0.76, blue: 0.88, alpha: 1)
    static let oneDaySky = UIColor(red: 0.48, green: 0.86, blue: 1.0, alpha: 1)
    static let oneDayNavy = UIColor(red: 0.02, green: 0.28, blue: 0.74, alpha: 1)
    static let oneDayMist = UIColor(red: 0.89, green: 0.98, blue: 1.0, alpha: 1)
}

extension Color {
    static let oneDayBlue = Color(uiColor: .oneDayBlue)
    static let oneDayCyan = Color(uiColor: .oneDayCyan)
    static let oneDaySky = Color(uiColor: .oneDaySky)
    static let oneDayNavy = Color(uiColor: .oneDayNavy)
    static let oneDayMist = Color(uiColor: .oneDayMist)
}
