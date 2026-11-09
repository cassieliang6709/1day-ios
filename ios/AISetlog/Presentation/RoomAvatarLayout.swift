import Foundation

/// Centers in the room list's fixed-size identity area. Every member is shown.
struct RoomAvatarLayout {
    static let width: CGFloat = 86
    static let height: CGFloat = 68

    let centers: [CGPoint]
    let diameter: CGFloat

    init(memberCount: Int) {
        precondition(memberCount > 0)
        switch memberCount {
        case 1:
            diameter = 42
            centers = [CGPoint(x: 43, y: 34)]
        case 2:
            diameter = 36
            centers = [CGPoint(x: 28, y: 26), CGPoint(x: 57, y: 42)]
        case 3:
            diameter = 32
            centers = [CGPoint(x: 43, y: 18), CGPoint(x: 25, y: 48), CGPoint(x: 61, y: 48)]
        case 4:
            diameter = 30
            centers = [CGPoint(x: 26, y: 18), CGPoint(x: 60, y: 18),
                       CGPoint(x: 26, y: 50), CGPoint(x: 60, y: 50)]
        case 5:
            diameter = 28
            centers = [CGPoint(x: 15, y: 23), CGPoint(x: 43, y: 23), CGPoint(x: 71, y: 23),
                       CGPoint(x: 29, y: 45), CGPoint(x: 57, y: 45)]
        default:
            let columns = 3
            let rows = (memberCount + columns - 1) / columns
            diameter = min(27, Self.height / CGFloat(rows) * 0.88)
            centers = (0..<memberCount).map { index in
                CGPoint(x: (CGFloat(index % columns) + 0.5) * Self.width / CGFloat(columns),
                        y: (CGFloat(index / columns) + 0.5) * Self.height / CGFloat(rows))
            }
        }
    }
}
