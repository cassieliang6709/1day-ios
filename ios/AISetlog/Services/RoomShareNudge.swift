import Foundation

enum RoomShareNudge {
    private static let key = "room.shareNudge.offered"

    private static var offered: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func shouldOffer(code: String, isEmptyRoom: Bool) -> Bool {
        isEmptyRoom && !offered.contains(code)
    }

    static func markOffered(code: String) {
        var codes = offered
        codes.insert(code)
        UserDefaults.standard.set(Array(codes), forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
