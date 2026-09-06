import PhotosUI
import SwiftUI

/// A template's cover, wherever it came from: the picture the user chose out
/// of their photo library, or the bundled art matched to its moments. One view
/// so a template looks the same on every card that shows it.
struct TemplateCoverImage: View {
    /// Bundled art to fall back to — `template.matchedCoverAssetName`.
    let assetName: String
    /// The user's own cover, handed over by `ChallengeStore.coverURL(for:)`.
    /// The view never goes looking for it: files are the store's business.
    var fileURL: URL?

    var body: some View {
        Group {
            if let fileURL, let picked = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: picked).resizable()
            } else {
                Image(assetName).resizable()
            }
        }
    }
}

/// What the cover editor is currently holding. Distinguishing "leave it alone"
/// from "put it back to the matched one" matters: both look identical on a
/// template that never had an uploaded cover, and only one of them should
/// delete a file.
enum TemplateCoverChoice: Equatable {
    /// Whatever the template already has.
    case unchanged
    /// Hand the cover back to `TemplateCoverMatcher`.
    case matched
    /// A picture from the photo library, not yet on disk.
    case picked(Data)

    var pickedData: Data? {
        if case .picked(let data) = self { return data }
        return nil
    }

    var clearsUploadedCover: Bool { self == .matched }
}

/// Pick a cover, or don't — the app has one either way. Presented as the
/// picture itself rather than a row saying "Cover ›", because the whole point
/// is seeing what your template will look like on the shelf.
struct TemplateCoverField: View {
    /// The art shown before anyone picks anything.
    let matchedAssetName: String
    /// An uploaded cover this template already carries, if any.
    var existingCoverURL: URL?
    @Binding var choice: TemplateCoverChoice

    @State private var pickerItem: PhotosPickerItem?

    private var showsUploadedCover: Bool {
        switch choice {
        case .picked: true
        case .matched: false
        case .unchanged: existingCoverURL != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview

            HStack(spacing: 8) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(Strings.chooseCoverFromPhotos, systemImage: "photo.on.rectangle")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.softAction)
                .accessibilityIdentifier("template-cover-picker")

                if showsUploadedCover {
                    Button(Strings.useMatchedCover) { choice = .matched }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .buttonStyle(.plain)
                }
            }

            if !showsUploadedCover {
                Text(Strings.matchedCoverNote)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(OneDay.Motion.soft, value: showsUploadedCover)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                // A picture that won't load is not worth an alert: the matched
                // cover is still there and still fine.
                if let data = try? await item.loadTransferable(type: Data.self) {
                    choice = .picked(data)
                }
                pickerItem = nil
            }
        }
    }

    private var preview: some View {
        Group {
            if let data = choice.pickedData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable()
            } else if choice == .unchanged, let existingCoverURL {
                TemplateCoverImage(assetName: matchedAssetName, fileURL: existingCoverURL)
            } else {
                Image(matchedAssetName).resizable()
            }
        }
        .scaledToFill()
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OneDay.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
