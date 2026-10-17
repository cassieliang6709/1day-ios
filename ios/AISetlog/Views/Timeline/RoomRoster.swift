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
        VStack(alignment: .leading, spacing: 6) {
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

            // The hollow faces said "somebody hasn't filmed" but never who,
            // and a face with an initial is not a name. `RoomCast` had both
            // sentences written and tested; nothing drew them. Waiting first,
            // because who we're waiting on is the thing a room can act on —
            // nudge them — and once nobody is left, who filmed.
            if let note = cast.waitingNote ?? cast.filmedNote {
                RoomNote(
                    note: note,
                    isPending: cast.waitingNote != nil,
                    showsFaces: false)
            }
        }
    }
}

/// One line about some of the people in a room: a few small faces and a
/// sentence. Both the "who filmed" line and the "who we're waiting on" line
/// are this shape, because both are one statement about the room rather than a
/// row under every moment.
struct RoomNote: View {
    let note: RoomCast.Note
    /// Ink for the sentence. Both of these lines live on canvas now — the
    /// white variant belonged to the next-up card, which is gone.
    var tint: Color = OneDay.inkFaint
    /// Hollow faces, for the people the sentence is still waiting for.
    var isPending = false
    /// Off directly under the roster, whose row already draws every one of
    /// these faces — the sentence is the part it was missing.
    var showsFaces = true

    var body: some View {
        HStack(spacing: 6) {
            if showsFaces, !note.names.isEmpty {
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
