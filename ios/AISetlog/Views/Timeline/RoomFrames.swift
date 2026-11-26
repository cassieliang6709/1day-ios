import SwiftUI

struct RoomFrames: View {
    let clips: [DayClip]
    var members: [(id: String, name: String)] = []
    let myID: String
    let nextToFilm: Int?
    var slotTitle: (Int) -> String? = { _ in nil }
    let onPlay: (DayClip) -> Void
    let onFilm: (Int) -> Void
    let onOpenPerson: (RoomFeed.Column) -> Void
    var hasPoked: (String) -> Bool = { _ in false }
    var onPoke: (String) -> Void = { _ in }
    var orientation: Challenge.Orientation = .portrait
    var latestComment: (DayClip) -> ClipComment? = { _ in nil }
    var reactions: (DayClip) -> [ClipReaction] = { _ in [] }
    var onReact: (DayClip, String) -> Void = { _, _ in }
    var signedOut = false
    var onSignIn: () -> Void = {}

    private static let minimumFrameHeight: CGFloat = 150
    private static let spacing: CGFloat = 12

    static func filmedFirst(_ columns: [RoomFeed.Column]) -> [RoomFeed.Column] {
        columns.enumerated().sorted { a, b in
            let rank: (RoomFeed.Column) -> Int = { $0.isMine ? 0 : ($0.clips.isEmpty ? 2 : 1) }
            return rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
        }.map(\.element)
    }

    static func grid(for count: Int, landscape: Bool) -> (columns: Int, rows: Int) {
        if landscape || count <= 1 { return (1, max(count, 1)) }
        return (2, (count + 1) / 2)
    }

    static func cellSize(
        in space: CGSize, count: Int, aspect: CGFloat, landscape: Bool
    ) -> CGSize {
        let grid = grid(for: count, landscape: landscape)
        let columns = CGFloat(grid.columns)
        let rows = CGFloat(grid.rows)
        let byWidth = (space.width - spacing * (columns - 1)) / columns
        let byHeight = (space.height - spacing * (rows - 1)) / rows
        let height = max(min(byWidth / aspect, byHeight), minimumFrameHeight)
        return CGSize(width: min(height * aspect, byWidth), height: height)
    }

    private var columns: [RoomFeed.Column] {
        Self.filmedFirst(RoomFeed.columns(clips: clips, members: members, myID: myID))
            .filter { !$0.clips.isEmpty }
    }

    private var aspect: CGFloat {
        CameraStyle.defaultCamera.aspectRatio(for: orientation) ?? 3 / 4
    }

    var body: some View {
        let columns = columns
        let landscape = orientation == .landscape
        let grid = Self.grid(for: columns.count, landscape: landscape)
        let rows = stride(from: 0, to: columns.count, by: grid.columns).map {
            Array(columns[$0..<min($0 + grid.columns, columns.count)])
        }
        return GeometryReader { proxy in
            let cell = Self.cellSize(
                in: proxy.size, count: columns.count, aspect: aspect, landscape: landscape)
            let total = cell.height * CGFloat(grid.rows) + Self.spacing * CGFloat(grid.rows - 1)
            ScrollView(.vertical) {
                VStack(spacing: Self.spacing) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: Self.spacing) {
                            ForEach(rows[index]) { column in
                                frame(column).frame(width: cell.width, height: cell.height)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(total <= proxy.size.height + 1)
        }
    }

    private func frame(_ column: RoomFeed.Column) -> some View {
        PersonFrame(
            column: column,
            nextToFilm: nextToFilm,
            slotTitle: slotTitle,
            onPlay: onPlay,
            onFilm: onFilm,
            onOpenPerson: { onOpenPerson(column) },
            hasPoked: hasPoked,
            onPoke: onPoke,
            latestComment: latestComment,
            myID: myID,
            reactions: reactions,
            onReact: onReact,
            signedOut: signedOut,
            onSignIn: onSignIn)
    }
}
