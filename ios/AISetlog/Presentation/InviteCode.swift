import Foundation

enum InviteCode {
    static let length = 6

    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let allowed = Set(alphabet)

    static func make() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    static func isValid(_ raw: String) -> Bool {
        raw.count == length && raw.allSatisfy(allowed.contains)
    }

    static func normalize(_ raw: String) -> String {
        String(
            raw.uppercased()
                .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
                .prefix(length))
    }

    static func isComplete(_ raw: String) -> Bool {
        normalize(raw).count == length
    }

    static func extract(from text: String) -> String? {
        let upper = text.uppercased()

        if let marker = upper.range(of: "CODE=") {
            let candidate = String(upper[marker.upperBound...].prefix {
                $0.isASCII && ($0.isLetter || $0.isNumber)
            })
            if isValid(candidate) { return candidate }
        }

        var run = ""
        for character in upper + " " {
            if character.isASCII && (character.isLetter || character.isNumber) {
                run.append(character)
            } else {
                if isValid(run) { return run }
                run = ""
            }
        }
        return nil
    }

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
