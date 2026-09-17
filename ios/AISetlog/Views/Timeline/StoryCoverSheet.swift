import AVFoundation
import PhotosUI
import SwiftUI

/// Choosing the picture that stands for a story.
///
/// A story had no cover of its own before this. The card showed whichever clip
/// was filmed most recently, and the template's painted poster until one was —
/// both automatic, and neither of them something you could change. The poster
/// is also the wrong picture surprisingly often: a story called 搬家这一天 with
/// hand-written moments gets whatever art its words happened to match.
///
/// Three sources, in the order people reach for them: a frame out of what you
/// already filmed (it *is* the day), your own photo, or one of the bundled
/// scenes. The fourth choice puts it back the way it was.
struct StoryCoverSheet: View {
    let challenge: Challenge
    /// The story's clips, newest first — the caller already has them and in a
    /// room they include everybody's.
    let clips: [DayClip]
    /// What the card is showing right now, so "现在这张" isn't a guess.
    var currentCoverURL: URL?
    let onChoose: (ChallengeStore.StoryCoverChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    /// A frame lifted from a clip, waiting for 用这张. Held rather than applied
    /// straight away so tapping a clip is a preview and not a commitment.
    @State private var liftedFrame: UIImage?
    @State private var liftingFrom: Int?
    @State private var failed = false

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    private var hasOwnCover: Bool {
        challenge.coverFileName != nil || challenge.presetCoverAssetName != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        preview
                        if !clips.isEmpty { fromYourClips }
                        fromYourPhotos
                        fromTheLibrary
                        if hasOwnCover { putItBack }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(Strings.storyCoverTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
            }
            .alert(Strings.coverFrameFailed, isPresented: $failed) {
                Button(Strings.ok, role: .cancel) {}
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        failed = true
                        return
                    }
                    apply(.picked(data))
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - What it looks like now

    /// The chosen frame if there is one, otherwise exactly what the card shows.
    private var preview: some View {
        Group {
            if let liftedFrame {
                Image(uiImage: liftedFrame).resizable().scaledToFill()
            } else if let currentCoverURL {
                ClipThumbnail(url: currentCoverURL, refreshToken: nil)
            } else {
                Image(presenter.coverAssetName).resizable().scaledToFill()
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if liftedFrame != nil {
                Button(Strings.useThisFrame) {
                    guard let data = liftedFrame?.jpegData(compressionQuality: 0.9) else {
                        failed = true
                        return
                    }
                    apply(.picked(data))
                }
                .buttonStyle(.primaryAction)
                .padding(12)
                .accessibilityIdentifier("cover-use-frame")
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(OneDay.hairline, lineWidth: 1)
        }
    }

    // MARK: - Three places a cover can come from

    private var fromYourClips: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: Strings.coverFromClips)
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(clips, id: \.day) { clip in
                        Button { lift(from: clip) } label: {
                            ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt)
                                .frame(width: 66, height: 90)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(alignment: .bottom) {
                                    Text(presenter.title(forSlot: clip.day))
                                        .font(.system(
                                            size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 4)
                                        .padding(.bottom, 4)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(
                                            liftingFrom == clip.day
                                                ? Color.oneDayBrand : .white.opacity(0.25),
                                            lineWidth: liftingFrom == clip.day ? 2.5 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("cover-clips")
    }

    private var fromYourPhotos: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack(spacing: 11) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.oneDayBrand)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.oneDayBrand.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(Strings.coverFromPhotos)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OneDay.inkFaint)
            }
            .padding(12)
            .glassSurface(radius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cover-from-photos")
    }

    private var fromTheLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: Strings.coverFromLibrary)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible())],
                spacing: 9
            ) {
                ForEach(TemplateCoverPreset.all) { preset in
                    let chosen = challenge.presetCoverAssetName == preset.assetName
                    Button { apply(.preset(preset.assetName)) } label: {
                        Image(preset.assetName)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 84)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                Text(preset.name.resolved())
                                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                                    .padding(7)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        chosen ? Color.oneDayBrand : .white.opacity(0.3),
                                        lineWidth: chosen ? 2.5 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name.resolved())
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
        .accessibilityIdentifier("cover-library")
    }

    private var putItBack: some View {
        Button { apply(.keepFilming) } label: {
            Text(Strings.coverKeepFilming)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassSurface(radius: 99)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cover-keep-filming")
    }

    // MARK: - Actions

    /// One frame out of a clip, at the same moment `ClipThumbnail` draws, so
    /// what you tapped is what you get.
    private func lift(from clip: DayClip) {
        liftingFrom = clip.day
        Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1400, height: 1400)
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            guard let cgImage = try? await generator.image(at: time).image else {
                liftingFrom = nil
                failed = true
                return
            }
            liftedFrame = UIImage(cgImage: cgImage)
        }
    }

    private func apply(_ choice: ChallengeStore.StoryCoverChoice) {
        onChoose(choice)
        dismiss()
    }
}
