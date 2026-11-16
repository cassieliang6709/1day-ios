import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers



struct RoomInviteCardContent: Equatable, Sendable {
    let title: String
    let code: String
    let inviter: String?
    let inviterAvatarURL: URL?

    init(title: String, code: String, inviter: String?, inviterAvatarURL: URL? = nil) {
        self.title = title
        self.code = code
        let trimmed = inviter?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inviter = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.inviterAvatarURL = inviterAvatarURL
    }

    init(challenge: Challenge, inviter: String?,
         inviterAvatarURL: URL? = AvatarStore.savedFileOnDisk) {
        self.init(
            title: ChallengePresenter(challenge: challenge).displayTitle,
            code: challenge.roomCode ?? "",
            inviter: inviter,
            inviterAvatarURL: inviterAvatarURL)
    }

    var headline: String { Strings.inviteCardHeadline(inviter: inviter) }

    var accessibilityLabel: String {
        Strings.inviteCardAccessibility(title: title, code: code, inviter: inviter)
    }
}


struct RoomInviteCardView: View {
    let content: RoomInviteCardContent

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
        }
    }
}


enum RoomInviteCardRenderer {
    static let scale: CGFloat = 3

    enum RenderError: Error { case noImage }

    @MainActor
    static func pngData(for content: RoomInviteCardContent) throws -> Data {
        let renderer = ImageRenderer(content: RoomInviteCardView(content: content))
        renderer.scale = scale
        renderer.isOpaque = true
        guard let data = renderer.uiImage?.pngData() else { throw RenderError.noImage }
        return data
    }
}

struct RoomInviteCardImage: Transferable, Sendable {
    let content: RoomInviteCardContent

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            try await RoomInviteCardRenderer.pngData(for: card.content)
        }
        .suggestedFileName { "1Day-\($0.content.code).png" }
    }
}

struct RoomInviteShareLink<Label: View>: View {
    let content: RoomInviteCardContent
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
