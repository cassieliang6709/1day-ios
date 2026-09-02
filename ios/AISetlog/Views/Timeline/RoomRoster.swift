import SwiftUI

/// The shared-room chrome: who's here, who has filmed, and who we're waiting
/// on. Three lines, all of them about people.
///
/// Nothing in here exists in a solo story. A diary that labels every clip with
/// your own name and then tells you you're the only one filming is an app that
/// has forgotten who's holding it, so `RoomCast` is built only for a shared
/// challenge and every view below takes it as a given.

/// Who's in this room, as one row of faces — the one place the page answers
/// "who's here".
///
/// The header used to draw each member as a 44pt avatar over their name, and
/// the page separately grew a 120pt card for every person who hadn't filmed a
/// given moment. Both said the same thing at wildly different sizes. One row,
/// hollow where somebody hasn't filmed yet.
struct RoomRoster: View {
    let cast: RoomCast

    var body: some View {
        HStack(spacing: 10) {
            AvatarStack(
                names: cast.rosterNames,
                maxShown: 4,
                size: 30,
                pending: cast.namesYetToFilm,
                you: cast.myName)

            Text(cast.rosterLine)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One line about some of the people in a room: a few small faces and a
/// sentence. Both the "who filmed" line and the "who we're waiting on" line
/// are this shape, because both are one statement about the room rather than a
/// row under every moment.
struct RoomNote: View {
    let note: RoomCast.Note
    /// Ink for the sentence — white inside the next-up card, quiet on canvas.
    var tint: Color = OneDay.inkFaint
    /// Hollow faces, for the people the sentence is still waiting for.
    var isPending = false

    var body: some View {
        HStack(spacing: 6) {
            if !note.names.isEmpty {
                AvatarStack(
                    names: note.names,
                    maxShown: 3,
                    size: 19,
                    pending: isPending ? Set(note.names) : [])
            }

            Text(note.text)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }
}
