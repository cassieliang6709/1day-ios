import Foundation

/// The six characters between "I made a room" and "I'm in it".
///
/// The same code arrives three ways — typed into six slots, pasted out of a
/// share blurb, or carried in an `oneday://join?code=XXXXXX` link — and each
/// of those used to clean it up its own way. The sheet stripped punctuation and
/// capped at six; the store uppercased and trimmed the ends; the link handler
/// did nothing at all and passed whatever the URL said straight to CloudKit.
/// Three answers to one question is how a code that looks right on screen
/// comes back "no room with that code".
///
/// Pure on purpose: none of this needs a network, a clock, or a view, so all
/// of it can be checked without one.
enum InviteCode {
    /// Codes are exactly this long. Six is short enough to read down a phone
    /// line and long enough that guessing one isn't worth anybody's afternoon.
    static let length = 6

    /// Unambiguous alphabet: no O or 0, no I or 1. A code has to survive being
    /// said out loud across a table, which is the only way most of them travel.
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let allowed = Set(alphabet)

    /// A fresh code. Uniqueness is the caller's problem — CloudKit rejects a
    /// second room under a name already taken, which is the only check that
    /// can be trusted anyway.
    static func make() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// True only for something that could actually be a room's name: the right
    /// length, and nothing in it a listener could mishear.
    ///
    /// Deliberately stricter than ``normalize(_:)``. This is the gate in front
    /// of a network round trip, and "AB0DEF" cannot be a room no matter how
    /// hopefully it was typed.
    static func isValid(_ raw: String) -> Bool {
        raw.count == length && raw.allSatisfy(allowed.contains)
    }

    /// What the code field keeps as you type: uppercase, ASCII letters and
    /// digits, six at most.
    ///
    /// Looser than ``isValid(_:)`` by design — a half-typed code has to
    /// survive, and so does the O somebody typed where they meant a zero, or
    /// the slots would swallow the keystroke and leave them retyping a
    /// character that never appears. Non-ASCII goes, though: a Chinese
    /// character passes `isLetter` and would sit in a slot looking like
    /// progress toward a code it can never be part of.
    static func normalize(_ raw: String) -> String {
        String(
            raw.uppercased()
                .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
                .prefix(length))
    }

    /// Six slots full. What lights up the join button — not whether the code
    /// exists, only whether there's anything left to type.
    static func isComplete(_ raw: String) -> Bool {
        normalize(raw).count == length
    }

    /// Pull a join code out of arbitrary pasted text. The share blurb is a
    /// whole sentence with the code mid-string and a deep link at the end, so
    /// "first six alphanumerics" used to yield `1DAY` from the product name.
    /// Trust the deep link first, then any standalone run of exactly six
    /// characters from the code alphabet.
    static func extract(from text: String) -> String? {
        let upper = text.uppercased()

        if let marker = upper.range(of: "CODE=") {
            let candidate = String(upper[marker.upperBound...].prefix(length))
            if isValid(candidate) { return candidate }
        }

        var run = ""
        for character in upper + " " {
            if allowed.contains(character) {
                run.append(character)
            } else {
                if run.count == length { return run }
                run = ""
            }
        }
        return nil
    }

    /// The code in an `oneday://join?code=XXXXXX` link, or nil for anything
    /// that isn't one.
    ///
    /// Everything a link can get wrong ends up here — another app's scheme, a
    /// host we don't serve, a missing `code`, a code with an O in it — and all
    /// of them mean the same thing: there is no room to open, so don't push
    /// somebody through onboarding and into a join that was never going to
    /// land.
    static func fromDeepLink(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "oneday",
              url.host?.lowercased() == "join",
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?
                  .first(where: { $0.name == "code" })?
                  .value
        else { return nil }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return isValid(code) ? code : nil
    }
}
