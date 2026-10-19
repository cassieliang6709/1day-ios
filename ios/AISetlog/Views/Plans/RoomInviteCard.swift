import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Why an image

// "发给朋友" used to hand the share sheet a `String` — the invite blurb with an
// `oneday://join?code=` link. WeChat, which is where nearly every one of these
// invites is headed, rejects that outright: its share extension only declares
// images, files and web URLs, so picking 微信 on a text item shows
// "暂不支持的文件类型" and sends nothing. The invite never left the phone.
//
// So the thing we share is now a picture of the invite: room, code, and the
// three taps it takes to use the code. Every chat app takes an image, and an
// image survives being forwarded, screenshotted or saved to a group album in a
// way a custom-scheme link does not (WeChat would not make `oneday://` tappable
// anyway). The blurb still rides along as the share's `message`, for the apps
// that take text too — Messages, Notes, Mail.

/// What the invite card says, worked out once from the room.
///
/// A plain value rather than reading `Challenge` inside the view, so the
/// words can be tested without rendering anything and so the `Transferable`
/// that carries it across to the share extension is `Sendable` by construction.
struct RoomInviteCardContent: Equatable, Sendable {
    let title: String
    let code: String
    /// Your display name. Nil before sign-in names you, in which case the card
    /// leads with the room instead of an invitation from nobody.
    let inviter: String?
    /// The inviter's avatar file (spec §4.3). Nil draws their initial instead.
    let inviterAvatarURL: URL?

    init(title: String, code: String, inviter: String?, inviterAvatarURL: URL? = nil) {
        self.title = title
        self.code = code
        let trimmed = inviter?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inviter = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.inviterAvatarURL = inviterAvatarURL
    }

    /// The avatar defaults to mine: every invite is sent by the person holding
    /// the phone.
    init(challenge: Challenge, inviter: String?,
         inviterAvatarURL: URL? = AvatarStore.savedFileOnDisk) {
        self.init(
            title: ChallengePresenter(challenge: challenge).displayTitle,
            code: challenge.roomCode ?? "",
            inviter: inviter,
            inviterAvatarURL: inviterAvatarURL)
    }

    var headline: String { Strings.inviteCardHeadline(inviter: inviter) }

    /// The image has no text layer for VoiceOver to find, so the preview and
    /// the in-app card carry this instead. The code is spelled out character by
    /// character: read as a word, "K7QX2M" is unintelligible.
    var accessibilityLabel: String {
        Strings.inviteCardAccessibility(title: title, code: code, inviter: inviter)
    }
}

// MARK: - The card

/// The invite as a portrait card — 4:5, the shape chat apps show largest
/// without cropping (WeChat and Instagram both letterbox anything taller).
///
/// Drawn at a fixed point size and always in light appearance: this is a
/// picture that leaves the app, and a friend should see the same card whether
/// the sender happens to be in dark mode or not. Skin still applies, so a
/// 奶油黄 user sends a yellow card — it is their invite.
struct RoomInviteCardView: View {
    let content: RoomInviteCardContent

    /// 360×450 pt drawn at 3× is 1080×1350 px.
    static let pointSize = CGSize(width: 360, height: 450)

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 18)
            codePanel
            Spacer(minLength: 18)
            footer
        }
        .padding(26)
        .frame(width: Self.pointSize.width, height: Self.pointSize.height)
        .background(
            LinearGradient(
                colors: [Color.oneDayBrand, Color.oneDayBrandLight],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(content.accessibilityLabel))
    }

    private var header: some View {
        VStack(spacing: 6) {
            inviterFace
                .padding(.bottom, 4)
            Text("1Day")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(OneDay.onBrand.opacity(0.85))
            Text(content.headline)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.onBrand)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// Who it's from: their avatar, or — for someone who skipped making one —
    /// their initial on 鹅黄, the spec's placeholder.
    @ViewBuilder
    private var inviterFace: some View {
        if let url = content.inviterAvatarURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(1.12)
                .frame(width: 72, height: 72)
                .background(Circle().fill(.white))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        } else if let inviter = content.inviter {
            Text(Identity.initial(for: inviter))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(uiColor: UIColor(hex: 0x7A5200)))
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.oneDayButter))
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        }
    }

    /// White panel so the code reads at a glance in a chat thumbnail, where
    /// the card is shown maybe 200 px wide.
    private var codePanel: some View {
        VStack(spacing: 12) {
            Text(content.title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(uiColor: UIColor(hex: 0x0F2E6B)))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(Strings.inviteCardCodeLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .kerning(1.5)
                .foregroundStyle(Color(uiColor: UIColor(hex: 0x5B7099)))
            Text(content.code)
                .font(.system(size: 46, weight: .heavy, design: .monospaced))
                .kerning(8)
                .foregroundStyle(OneDay.brandText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(Strings.inviteCardSteps)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(uiColor: UIColor(hex: 0x5B7099)))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(AppSkin.mascotImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
            Text(Strings.inviteCardFooter)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.onBrand.opacity(0.9))
        }
    }
}

// MARK: - Rendering

enum RoomInviteCardRenderer {
    /// 3× regardless of the device: the card is for someone else's screen, and
    /// a 2× phone would otherwise send 720×900, which WeChat then upscales.
    static let scale: CGFloat = 3

    enum RenderError: Error { case noImage }

    /// PNG rather than JPEG: flat colour and large type are exactly what JPEG
    /// smears, and the file is small either way (~100 KB).
    @MainActor
    static func pngData(for content: RoomInviteCardContent) throws -> Data {
        let renderer = ImageRenderer(content: RoomInviteCardView(content: content))
        renderer.scale = scale
        renderer.isOpaque = true
        guard let data = renderer.uiImage?.pngData() else { throw RenderError.noImage }
        return data
    }
}

/// The share item: the card, exported only as `public.png`.
///
/// Rendered lazily, when the share sheet (or the target app) asks for the
/// bytes, rather than when the button is drawn — the room page redraws every
/// ten seconds while it syncs, and rendering a 1080×1350 image on each pass
/// would be waste for a button that is rarely tapped.
///
/// Only one representation on purpose. If the item also offered `String`,
/// the share sheet would hand WeChat the text and we would be back to
/// "暂不支持的文件类型".
struct RoomInviteCardImage: Transferable, Sendable {
    let content: RoomInviteCardContent

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            try await RoomInviteCardRenderer.pngData(for: card.content)
        }
        .suggestedFileName { "1Day-\($0.content.code).png" }
    }
}

/// "发给朋友": the card image, with the old blurb as the message for apps that
/// take one. Both share points use this so the room page and the 朋友 tab can
/// never send different things again.
struct RoomInviteShareLink<Label: View>: View {
    let content: RoomInviteCardContent
    /// The blurb with the `oneday://` link — still useful in Messages, where it
    /// becomes tappable.
    let message: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        let card = RoomInviteCardImage(content: content)
        ShareLink(
            item: card,
            subject: Text(content.headline),
            message: Text(message),
            preview: SharePreview(content.headline, image: card),
            label: label)
    }
}
