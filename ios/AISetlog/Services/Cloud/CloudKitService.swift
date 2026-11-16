import Foundation

/// Backend for shared rooms: the Worker in `workers/api` (D1 for rows, R2 for
/// videos and avatars). The name is left over from CloudKit, which this
/// replaced; the shapes below and the record names are the same ones, so
/// nothing that calls in here had to change, and rows copied over from
/// CloudKit keep their ids.
///
/// - Room: the 6-char join code is its id, so joining is a direct fetch.
/// - Clip: `code_author_dayN` for a person's first take of a moment; every
///   later take is `code_author_dayN_<takeID>`, so filming again adds
///   instead of overwriting. The video goes up to R2 first.
/// - Member: `code_authorID`, written when someone joins; joining again
///   rewrites the same row.
///
/// Every call needs a 1Day session (see `OneDayAPI`); without one it throws
/// `.notSignedIn`, and the UI asks the person to sign in.
enum CloudKitService {
    private static var api: OneDayAPI { OneDayAPI.shared }

    enum CKServiceError: LocalizedError {
        case notSignedIn
        case roomNotFound
        case networkUnavailable
        case roomCreateFailed
        case roomJoinFailed
        case roomFull

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return Strings.errorSignedOut
            case .roomNotFound:
                return Strings.errorNoRoom
            case .networkUnavailable:
                return Strings.errorNetwork
            case .roomCreateFailed:
                return Strings.errorRoomCreateFailed
            case .roomJoinFailed:
                return Strings.errorRoomJoinFailed
            case .roomFull:
                return Strings.errorRoomFull
            }
        }
    }

    /// What the UI is shown for a failed call: never the raw error, which
    /// would say "OneDayAPI.Failure error 4" to somebody trying to film with
    /// a friend. `fallback` is what anything unrecognised says.
    static func serviceError(from error: Error, fallback: CKServiceError) -> Error {
        if error is CancellationError { return error }
        switch error as? OneDayAPI.Failure {
        case .notSignedIn: return CKServiceError.notSignedIn
        case .notFound: return CKServiceError.roomNotFound
        case .unavailable: return CKServiceError.networkUnavailable
        default: return error is CKServiceError ? error : fallback
        }
    }

    /// Runs `body`, turning its failure into a `CKServiceError`.
    private static func mapped<T>(_ fallback: CKServiceError, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw serviceError(from: error, fallback: fallback)
        }
    }

    // MARK: - Rooms

    struct RemoteRoom {
        let code: String
        let title: String
        let startDate: Date
        let ownerID: String
        let ownerName: String
        let mode: Challenge.Mode
        let clipLength: Challenge.ClipLength
        let orientation: Challenge.Orientation
        let cameraStyle: CameraStyle?
        let templateName: String?
        let momentTitles: [String]?
    }

    /// A room as the Worker sends it.
    struct RoomBody: Codable {
        let code: String
        let title: String
        var startDate: Int64? = nil
        var ownerID: String? = nil
        let ownerName: String
        let mode: String
        let clipLength: String
        let orientation: String
        var cameraStyle: String? = nil
        var templateName: String? = nil
        var momentTitles: String? = nil

        var room: RemoteRoom {
            RemoteRoom(
                code: code,
                title: title,
                startDate: startDate.map(Date.init(apiMillis:)) ?? .now,
                ownerID: ownerID ?? "",
                ownerName: ownerName,
                mode: Challenge.Mode(rawValue: mode) ?? .sevenDay,
                clipLength: Challenge.ClipLength(rawValue: clipLength) ?? .tiny,
                orientation: Challenge.Orientation(rawValue: orientation) ?? .portrait,
                cameraStyle: cameraStyle.flatMap(CameraStyle.init),
                templateName: templateName,
                momentTitles: momentTitles?
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init))
        }
    }

    static func createRoom(
        title: String,
        ownerID: String,
        ownerName: String,
        mode: Challenge.Mode = .sevenDay,
        clipLength: Challenge.ClipLength = .tiny,
        orientation: Challenge.Orientation = .portrait,
        cameraStyle: CameraStyle? = nil,
        templateName: String? = nil,
        momentTitles: [String]? = nil
    ) async throws -> RemoteRoom {
        // The owner is whoever the session says; `ownerID` is not sent.
        for _ in 0..<5 {
            let body = RoomBody(
                code: InviteCode.make(), title: title, ownerName: ownerName,
                mode: mode.rawValue, clipLength: clipLength.rawValue,
                orientation: orientation.rawValue, cameraStyle: cameraStyle?.rawValue,
                templateName: templateName)
            do {
                let data = try await api.send("POST", ["rooms"], json: body)
                let room = try api.decode(RoomBody.self, from: data).room
                print("[room] created room code=\(room.code)")
                return room
            } catch OneDayAPI.Failure.conflict {
                continue // code taken, try another
            } catch {
                print("[room] create room failed: \(error)")
                throw serviceError(from: error, fallback: .roomCreateFailed)
            }
        }
        throw CKServiceError.roomCreateFailed
    }

    static func fetchRoom(code: String) async throws -> RemoteRoom {
        // Only a 404 means "no room with that code" — a network drop or a
        // lapsed sign-in must reach the person as what it is.
        try await mapped(.roomJoinFailed) {
            try await api.get(RoomBody.self, ["rooms", code]).room
        }
    }

    // MARK: - Members

    /// Deterministic (`code_authorID`) for the same reason clip names are:
    /// joining again rewrites the one row, and account deletion can name it
    /// without a query.
    static func memberRecordName(code: String, authorID: String) -> String {
        "\(code)_\(authorID)"
    }

    /// Everything a member write can carry; a field left nil keeps what the
    /// row already had, so joining, the avatar and a rename never undo each
    /// other.
    private struct MemberWrite: Encodable {
        var displayName: String? = nil
        var joinedAt: Int64? = nil
        var avatarKey: String? = nil
        var moodKind: String? = nil
        var moodDay: Int64? = nil
        var roomTitle: String? = nil
        var roomTitleAt: Int64? = nil
    }

    private static func writeMember(code: String, _ write: MemberWrite) async throws {
        try await mapped(.networkUnavailable) {
            try await api.send("PUT", ["rooms", code, "members", "me"], json: write)
        }
    }

    /// Upsert my member row for a room. `joinedAt` is the latest join.
    /// An empty name is "not known on this phone": the row keeps its name.
    static func saveMember(
        code: String, authorID: String, displayName: String, joinedAt: Date
    ) async throws {
        try await writeMember(code: code, MemberWrite(
            displayName: displayName.isEmpty ? nil : displayName, joinedAt: joinedAt.apiMillis))
        print("[room] saved member code=\(code)")
    }

    /// What I show the people in a room: my avatar and today's mood face.
    /// Never the mood's note — that stays private (`MoodSync`).
    struct MemberProfileWrite: Equatable {
        let code: String
        let authorID: String
        let displayName: String
        /// The finished avatar on disk. Nil leaves whatever the row had.
        let avatarURL: URL?
        /// Nil leaves the row's mood alone; it stops showing on its own once
        /// its day is over.
        let moodKind: String?
        /// When the mood was picked. A friend shows it only on that same day.
        let moodDay: Date?
    }

    /// A room member as their member row describes them.
    struct RemoteMember: Equatable {
        let userID: String
        let displayName: String
        /// The downloaded avatar, cached on disk.
        let avatarURL: URL?
        let moodKind: String?
        let moodDay: Date?
        /// The room name this member last gave the room, and when. The
        /// newest across the room is the room's name for everyone.
        var roomTitle: String? = nil
        var roomTitleAt: Date? = nil
    }

    static func saveMemberProfile(_ write: MemberProfileWrite) async throws {
        var body = MemberWrite(displayName: write.displayName.isEmpty ? nil : write.displayName)
        if let avatarURL = write.avatarURL {
            body.avatarKey = try await mapped(.networkUnavailable) {
                try await api.upload(avatarURL, contentType: "image/png")
            }
        }
        if let mood = write.moodKind, let day = write.moodDay {
            body.moodKind = mood
            body.moodDay = day.apiMillis
        }
        try await writeMember(code: write.code, body)
        print("[room] saved member profile code=\(write.code)")
    }

    /// Renames the room for everyone: the name goes on my own member row and
    /// whoever renamed last wins.
    static func saveRoomTitle(
        code: String, authorID: String, displayName: String, title: String, at: Date
    ) async throws {
        try await writeMember(code: code, MemberWrite(
            displayName: displayName.isEmpty ? nil : displayName,
            roomTitle: title, roomTitleAt: at.apiMillis))
        print("[room] saved room title code=\(code)")
    }

    /// The rooms someone is in, from the server rather than this phone: the
    /// codes on their member rows, plus every room they made.
    struct MyRooms {
        var memberCodes: [String]
        var owned: [RemoteRoom]
        /// The name and avatar on my newest member row that has one — what a
        /// phone that never saw me sign in before puts back, since Apple hands
        /// the name over only once. Defaulted for test fakes.
        var displayName: String? = nil
        var avatarFile: URL? = nil
    }

    static func myRooms(userID: String) async throws -> MyRooms {
        struct Body: Decodable {
            let memberCodes: [String]
            let owned: [RoomBody]
            let displayName: String?
            let avatarKey: String?
        }
        let body = try await mapped(.networkUnavailable) {
            try await api.get(Body.self, ["me", "rooms"])
        }
        var avatar: URL?
        if let key = body.avatarKey {
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("my-avatar-\(UUID().uuidString).png")
            if (try? await api.download(key: key, to: dst)) != nil { avatar = dst }
        }
        return MyRooms(
            memberCodes: body.memberCodes,
            owned: body.owned.map(\.room),
            displayName: body.displayName.flatMap { $0.isEmpty ? nil : $0 },
            avatarFile: avatar)
    }

    private struct MemberBody: Decodable {
        let userID: String
        let displayName: String
        let avatarKey: String?
        let moodKind: String?
        let moodDay: Int64?
        let roomTitle: String?
        let roomTitleAt: Int64?
    }

    /// Every member of a room, avatars downloaded into `cacheDir`. An avatar
    /// already there under the same key isn't fetched again.
    static func fetchMembers(code: String, into cacheDir: URL) async throws -> [RemoteMember] {
        try Task.checkCancellation()
        struct Body: Decodable { let members: [MemberBody] }
        let members = try await mapped(.networkUnavailable) {
            try await api.get(Body.self, ["rooms", code, "members"]).members
        }
        try Task.checkCancellation()
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        var out: [RemoteMember] = []
        for m in members {
            var local: URL?
            if let key = m.avatarKey {
                let dst = cacheDir.appendingPathComponent(memberAvatarFileName(userID: m.userID))
                let marker = dst.appendingPathExtension("key")
                if (try? String(contentsOf: marker, encoding: .utf8)) == key, fm.fileExists(atPath: dst.path) {
                    local = dst
                } else if (try? await api.download(key: key, to: dst)) != nil {
                    try? key.write(to: marker, atomically: true, encoding: .utf8)
                    local = dst
                }
            }
            out.append(RemoteMember(
                userID: m.userID,
                displayName: m.displayName,
                avatarURL: local,
                moodKind: m.moodKind,
                moodDay: m.moodDay.map(Date.init(apiMillis:)),
                roomTitle: m.roomTitle,
                roomTitleAt: m.roomTitleAt.map(Date.init(apiMillis:))))
        }
        return out
    }

    /// Apple user IDs carry dots; keep the file name to safe characters.
    static func memberAvatarFileName(userID: String) -> String {
        let safe = userID.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return "avatar_\(safe).png"
    }

    // MARK: - Clips

    struct RemoteClip: Identifiable, Equatable {
        let id: String          // record name
        let day: Int
        let authorID: String
        let authorName: String
        let recordedAt: Date
        let localURL: URL       // downloaded video, cached on disk
        let overlayText: String?
        /// Where the author put their caption. Nil in practice: nothing
        /// writes it any more, but rows copied from CloudKit may carry one.
        var captionSticker: CaptionSticker? = nil
        /// Every caption, as the newer phones write it (`Caption.cloudJSON`).
        var captionsJSON: String? = nil

        /// What to draw: the full list when the row has one that still
        /// agrees with `overlayText`, otherwise the one caption older phones
        /// wrote. See `Caption.fromCloud`.
        var captions: [Caption] {
            Caption.fromCloud(json: captionsJSON, overlayText: overlayText, sticker: captionSticker)
        }
    }

    /// Internal rather than private so the naming rule can be checked without a
    /// network: "writing this again is harmless" is only true while the same
    /// clip keeps deriving the same name. The Worker checks the same rule.
    ///
    /// `takeID` nil is take 1, whose name is the one every version has used.
    static func clipRecordName(code: String, authorID: String, day: Int, takeID: UUID? = nil) -> String {
        let first = "\(code)_\(authorID)_day\(day)"
        guard let takeID else { return first }
        return "\(first)_\(takeID.uuidString)"
    }

    /// Which take a clip record holds, read back off its name: nil for take 1
    /// (or a name this app didn't write).
    static func takeID(fromClipRecordName name: String, code: String, authorID: String, day: Int) -> UUID? {
        let prefix = clipRecordName(code: code, authorID: authorID, day: day) + "_"
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }

    private struct CaptionPatch: Encodable {
        let overlayText: String?
        let captionsJSON: String?
    }

    /// Rewrites just the caption on a clip that is already in the room, so
    /// changing three words doesn't cost the friend a download of the same
    /// take. A clip that isn't up yet is not an error — the next upload
    /// carries whatever the caption says by then.
    static func updateClipCaption(
        code: String, day: Int, authorID: String, captions: [Caption], takeID: UUID? = nil
    ) async throws {
        let id = clipRecordName(code: code, authorID: authorID, day: day, takeID: takeID)
        do {
            try await api.send("PATCH", ["clips", id], json: CaptionPatch(
                overlayText: captions.firstText, captionsJSON: Caption.cloudJSON(captions)))
        } catch OneDayAPI.Failure.notFound {
            return
        } catch {
            throw serviceError(from: error, fallback: .networkUnavailable)
        }
    }

    private struct ClipWrite: Encodable {
        let roomCode: String
        let day: Int
        let authorName: String
        let recordedAt: Int64
        let videoKey: String
        let overlayText: String?
        let captionsJSON: String?
    }

    /// Upload (or upload again) one take: the video to R2, then the row.
    static func uploadClip(
        code: String,
        day: Int,
        authorID: String,
        authorName: String,
        fileURL: URL,
        captions: [Caption] = [],
        recordedAt: Date,
        takeID: UUID? = nil
    ) async throws {
        let id = clipRecordName(code: code, authorID: authorID, day: day, takeID: takeID)
        let type = fileURL.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
        try await mapped(.networkUnavailable) {
            let key = try await api.upload(fileURL, contentType: type)
            // When the take was filmed, not when it reached the room: a failed
            // upload is retried on a later sync, and a draft can sit for an
            // hour before it is filed.
            try await api.send("PUT", ["clips", id], json: ClipWrite(
                roomCode: code, day: day, authorName: authorName,
                recordedAt: recordedAt.apiMillis, videoKey: key,
                overlayText: captions.firstText, captionsJSON: Caption.cloudJSON(captions)))
        }
        print("[room] uploaded clip code=\(code) day=\(day) recordedAt=\(recordedAt) take=\(takeID?.uuidString ?? "1")")
    }

    private struct ClipBody: Decodable {
        let id: String
        let day: Int
        let authorID: String
        let authorName: String
        let recordedAt: Int64
        let videoKey: String
        let overlayText: String?
        let captionSticker: String?
        let captionsJSON: String?
    }

    /// Videos fetched at once. Enough to fill a room quickly, few enough not
    /// to starve the other rooms syncing alongside.
    private static let parallelDownloads = 4

    /// All clips in a room, videos cached on disk.
    ///
    /// Only clips that are new or whose video changed since the last sync are
    /// downloaded (see `RoomClipCache`); a sync of a room nobody has filmed in
    /// since costs one small request.
    static func fetchClips(code: String, into cacheDir: URL) async throws -> [RemoteClip] {
        try Task.checkCancellation()
        struct Body: Decodable { let clips: [ClipBody] }
        let clips = try await mapped(.networkUnavailable) {
            try await api.get(Body.self, ["rooms", code, "clips"]).clips
        }
        try Task.checkCancellation()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // A video key is never reused for different contents, so it is the
        // version: a new take or a re-upload gets a new key.
        let remote = clips.map {
            RoomClipCache.RemoteEntry(
                recordName: $0.id,
                version: RoomClipCache.videoVersion(recordedAt: nil, changeTag: $0.videoKey))
        }
        let previous = RoomClipCache.loadManifest(in: cacheDir)
        let plan = RoomClipCache.plan(
            remote: remote, manifest: previous,
            cachedFiles: RoomClipCache.cachedRecordNames(in: cacheDir))
        let keys = Dictionary(clips.map { ($0.id, $0.videoKey) }, uniquingKeysWith: { a, _ in a })
        let downloaded = try await downloadClipVideos(plan.download, keys: keys, into: cacheDir)
        try Task.checkCancellation()
        RoomClipCache.removeFiles(plan.remove, in: cacheDir)
        try? RoomClipCache.saveManifest(
            RoomClipCache.manifest(
                after: plan, remote: remote, downloaded: downloaded, previous: previous),
            in: cacheDir)

        // A clip whose video couldn't be fetched is left out; its old file (if
        // any) stays on disk for the next sync to retry over.
        let available = Set(plan.reuse).union(downloaded)
        return clips.compactMap { c in
            guard available.contains(c.id) else { return nil }
            return RemoteClip(
                id: c.id,
                day: c.day,
                authorID: c.authorID,
                authorName: c.authorName,
                recordedAt: Date(apiMillis: c.recordedAt),
                localURL: RoomClipCache.fileURL(recordName: c.id, in: cacheDir),
                overlayText: c.overlayText,
                captionSticker: c.captionSticker.flatMap(CaptionSticker.init(cloudValue:)),
                captionsJSON: c.captionsJSON)
        }
    }

    /// Fetch each named clip's video into the cache, returning the names that
    /// made it. A failed one is just missing from the result.
    private static func downloadClipVideos(
        _ names: [String], keys: [String: String], into cacheDir: URL
    ) async throws -> Set<String> {
        var done = Set<String>()
        for start in stride(from: 0, to: names.count, by: parallelDownloads) {
            try Task.checkCancellation()
            let batch = names[start..<min(start + parallelDownloads, names.count)]
            await withTaskGroup(of: String?.self) { group in
                for name in batch {
                    guard let key = keys[name] else { continue }
                    group.addTask {
                        let temp = FileManager.default.temporaryDirectory
                            .appendingPathComponent("clip-\(UUID().uuidString).mov")
                        defer { try? FileManager.default.removeItem(at: temp) }
                        guard (try? await api.download(key: key, to: temp)) != nil,
                              (try? RoomClipCache.install(temp, recordName: name, in: cacheDir)) != nil
                        else { return nil }
                        return name
                    }
                }
                for await name in group { if let name { done.insert(name) } }
            }
        }
        return done
    }

    // MARK: - Reactions & comments

    struct RemoteReaction: Equatable {
        let day: Int
        let emoji: String
        let authorID: String
        let authorName: String
        let targetAuthorID: String
        let createdAt: Date
    }

    struct RemoteComment: Equatable {
        let id: String          // the local ClipComment UUID
        let day: Int
        let text: String
        let authorID: String
        let authorName: String
        let targetAuthorID: String
        let createdAt: Date
    }

    /// Deterministic name so re-adding the same emoji is idempotent and a
    /// toggle-off deletes exactly the same row. The Worker derives the same
    /// name from the fields and refuses a write whose name doesn't match.
    static func reactionRecordName(code: String, targetAuthorID: String, authorID: String, day: Int, emoji: String) -> String {
        "\(code)_\(targetAuthorID)_day\(day)_\(authorID)_\(emoji.unicodeScalars.map { String($0.value) }.joined(separator: "-"))"
    }

    private struct ReactionWrite: Encodable {
        let roomCode: String
        let day: Int
        let emoji: String
        let authorName: String
        let targetAuthorID: String
    }

    /// Add (on) or remove (off) one emoji from a day's clip for one author.
    static func setReaction(
        code: String, day: Int, authorID: String, authorName: String, targetAuthorID: String,
        emoji: String, on: Bool
    ) async throws {
        let id = reactionRecordName(
            code: code, targetAuthorID: targetAuthorID, authorID: authorID, day: day, emoji: emoji)
        try await mapped(.networkUnavailable) {
            if on {
                try await api.send("PUT", ["reactions", id], json: ReactionWrite(
                    roomCode: code, day: day, emoji: emoji,
                    authorName: authorName, targetAuthorID: targetAuthorID))
            } else {
                try await api.send("DELETE", ["reactions", id])
            }
        }
    }

    struct CommentWrite: Encodable {
        let roomCode: String
        let day: Int?
        let text: String
        let authorName: String
        let targetAuthorID: String?
        let createdAt: Int64?
    }

    /// Post a comment. `id` is the local ClipComment UUID so both sides dedupe.
    static func postComment(
        code: String, day: Int, id: String,
        text: String, authorID: String, authorName: String, targetAuthorID: String
    ) async throws {
        try await mapped(.networkUnavailable) {
            try await api.send("PUT", ["comments", id], json: CommentWrite(
                roomCode: code, day: day, text: text, authorName: authorName,
                targetAuthorID: targetAuthorID, createdAt: nil))
        }
    }

    /// Deleting a comment that's already gone succeeds.
    static func deleteComment(id: String) async throws {
        try await mapped(.networkUnavailable) {
            try await api.send("DELETE", ["comments", id])
        }
    }

    // MARK: - Leaving a room, deleting an account

    /// Deletes rows by name and reports back only what the Worker confirmed
    /// gone: mine that it deleted, and names nobody has (the state asked for).
    /// Someone else's row is neither, so an account-deletion journal keeps it
    /// as still to do rather than looking finished.
    static func deleteRecordsConfirmingEachOne(_ names: Set<String>) async throws -> Set<String> {
        guard !names.isEmpty else { return [] }
        struct Request: Encodable { let names: [String] }
        struct Response: Decodable { let confirmed: [String] }
        var confirmed: Set<String> = []
        let sorted = names.sorted()
        for start in stride(from: 0, to: sorted.count, by: 500) {
            let chunk = Array(sorted[start..<min(start + 500, sorted.count)])
            let data = try await mapped(.networkUnavailable) {
                try await api.send("POST", ["records", "delete"], json: Request(names: chunk))
            }
            confirmed.formUnion(try api.decode(Response.self, from: data).confirmed)
        }
        return confirmed
    }

    /// Everything I put in one room, by name: my clips (every take), my
    /// reactions, comments and pokes, and my member row. What leaving a room
    /// deletes, so friends no longer see me there.
    static func myRecordNames(inRoom code: String, authorID: String) async throws -> Set<String> {
        struct Body: Decodable { let names: [String] }
        let names = try await mapped(.networkUnavailable) {
            try await api.get(Body.self, ["rooms", code, "mine"]).names
        }
        return Set(names).union([memberRecordName(code: code, authorID: authorID)])
    }

    /// Best effort, for a leave or a sign-out sweep: deletes what it can and
    /// doesn't report back. Account deletion uses
    /// `deleteRecordsConfirmingEachOne` instead.
    ///
    /// Rooms the person created are kept but lose their name: the room holds
    /// other people's clips too.
    static func deleteMyRoomData(
        authorID: String,
        clips: [(code: String, day: Int)],
        reactions: [(code: String, targetAuthorID: String, day: Int, emoji: String)],
        commentIDs: [String],
        roomCodes: [String],
        otherRecordNames: [String] = []
    ) async throws {
        var names = Set(otherRecordNames)
        for clip in clips {
            names.insert(clipRecordName(code: clip.code, authorID: authorID, day: clip.day))
        }
        for reaction in reactions {
            names.insert(reactionRecordName(
                code: reaction.code, targetAuthorID: reaction.targetAuthorID,
                authorID: authorID, day: reaction.day, emoji: reaction.emoji))
        }
        names.formUnion(commentIDs)
        _ = try? await deleteRecordsConfirmingEachOne(names)

        for code in roomCodes {
            _ = try? await anonymizeOwnedRoom(code: code)
        }
    }

    /// Replaces my name as a room's owner with "deleted member". A room I
    /// don't own answers 403 and is left alone.
    static func anonymizeOwnedRoom(code: String) async throws {
        struct Body: Encodable { let ownerName: String }
        do {
            try await api.send("PATCH", ["rooms", code], json: Body(ownerName: Strings.deletedMemberName))
        } catch OneDayAPI.Failure.forbidden {
            return
        } catch OneDayAPI.Failure.notFound {
            return
        }
    }

    private struct ReactionBody: Decodable {
        let day: Int
        let emoji: String
        let authorID: String
        let authorName: String
        let targetAuthorID: String
        let createdAt: Int64
    }

    struct CommentBody: Decodable {
        let id: String
        let roomCode: String
        let day: Int?
        let text: String
        let authorID: String
        let authorName: String
        let targetAuthorID: String?
        let createdAt: Int64
    }

    /// Every reaction and comment in a room.
    static func fetchInteractions(code: String) async throws -> (reactions: [RemoteReaction], comments: [RemoteComment]) {
        struct Body: Decodable { let reactions: [ReactionBody]; let comments: [CommentBody] }
        let body = try await mapped(.networkUnavailable) {
            try await api.get(Body.self, ["rooms", code, "interactions"])
        }
        return (
            body.reactions.map {
                RemoteReaction(
                    day: $0.day, emoji: $0.emoji, authorID: $0.authorID,
                    authorName: $0.authorName, targetAuthorID: $0.targetAuthorID,
                    createdAt: Date(apiMillis: $0.createdAt))
            },
            body.comments.map {
                RemoteComment(
                    id: $0.id, day: $0.day ?? 0, text: $0.text, authorID: $0.authorID,
                    authorName: $0.authorName, targetAuthorID: $0.targetAuthorID ?? "",
                    createdAt: Date(apiMillis: $0.createdAt))
            })
    }
}
