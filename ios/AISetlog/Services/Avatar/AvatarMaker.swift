import CoreGraphics
import Foundation
import ImagePlayground
import UIKit

/// The avatar's first layer: turn a photo into a head on a transparent
/// background. Swappable — today Apple's on-device model with a Vision
/// cut-out behind it, later perhaps a cloud model — and whatever fills it,
/// the decorations on top stay ours (`AvatarDecorLayout`).
protocol AvatarHeadMaking {
    func makeHead(from photo: CGImage) async throws -> AvatarHeadResult
}

struct AvatarHeadResult {
    let head: AvatarHead
    let path: AvatarPath
}

/// Which way an avatar was made, and if it fell back, why. Logged, and shown
/// in Debug builds so a screenshot says which path it came from.
enum AvatarPath: Equatable {
    /// Apple's `ImageCreator` drew it.
    case imageCreator
    /// The photo itself, cut out with Vision.
    case visionFallback(AvatarFallbackReason)
}

enum AvatarFallbackReason: String, Error, Equatable {
    /// Below iOS 18.4, which is when `ImageCreator` arrived.
    case systemTooOld
    /// The device can't run Apple Intelligence at all (or it's the Simulator).
    case notSupported
    /// Supported, but switched off, still downloading, or busy.
    case unavailable
    case faceTooSmall
    case unsupportedInputImage
    case unsupportedLanguage
    /// The app went to the background mid-generation.
    case backgroundCreationForbidden
    case creationCancelled
    case creationFailed
    /// iOS 26: the model won't draw a photo's person without a known identity.
    case conceptsRequirePersonIdentity
    /// No answer inside `AvatarMaker.imageCreatorTimeout`.
    case timedOut
    /// The model answered with nothing.
    case noImage
    /// The style we ask for isn't offered on this device.
    case styleUnavailable
    /// A launch argument asked for it (Debug only).
    case forced
    case unknown
}

/// Default head maker: Apple's model when it can, the Vision cut-out when it can't.
struct AvatarMaker: AvatarHeadMaking {
    /// The model is slow on older phones; past this we stop waiting.
    static let imageCreatorTimeout: Duration = .seconds(45)

    /// The text concept beside the photo. English on purpose: `ImageCreator`
    /// refuses text in languages it doesn't support (`.unsupportedLanguage`),
    /// and the description doesn't depend on the app's language. Says what the
    /// spec asks for — 可爱、大头、圆脸、只要头部.
    static let prompt = "cute chibi portrait, big head, round face, head only, no body, plain white background"

    var forceFallback = false

    func makeHead(from photo: CGImage) async throws -> AvatarHeadResult {
        let reason: AvatarFallbackReason
        if forceFallback {
            reason = .forced
        } else if #available(iOS 18.4, *) {
            switch await Self.drawWithImageCreator(photo) {
            case .success(let drawn):
                // The model draws a whole picture; we still keep only the head.
                if let head = try? AvatarHeadExtractor.extract(from: drawn) {
                    print("[avatar] made with ImageCreator")
                    return AvatarHeadResult(head: head, path: .imageCreator)
                }
                reason = .noImage
            case .failure(let why):
                reason = why
            }
        } else {
            reason = .systemTooOld
        }
        try Task.checkCancellation()
        print("[avatar] falling back to the Vision cut-out: \(reason.rawValue)")
        let head = try AvatarHeadExtractor.extract(from: photo)
        return AvatarHeadResult(head: head, path: .visionFallback(reason))
    }

    @available(iOS 18.4, *)
    private static func drawWithImageCreator(_ photo: CGImage) async -> Result<CGImage, AvatarFallbackReason> {
        do {
            return try await withThrowingTaskGroup(of: CGImage?.self) { group in
                group.addTask {
                    let creator = try await ImageCreator()
                    // 「可爱小孩大头贴」 is closest to `.animation`; take another
                    // style only if this device doesn't offer it.
                    let styles = creator.availableStyles
                    let preferred: ImagePlaygroundStyle? = styles.contains(.animation) ? .animation : styles.first
                    guard let style = preferred else { throw ImageCreator.Error.notSupported }
                    let concepts: [ImagePlaygroundConcept] = [.image(photo), .text(prompt)]
                    for try await created in creator.images(for: concepts, style: style, limit: 1) {
                        return created.cgImage
                    }
                    return nil
                }
                group.addTask {
                    try await Task.sleep(for: imageCreatorTimeout)
                    throw TimedOut()
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let image = first else {
                    return .failure(.noImage)
                }
                return .success(image)
            }
        } catch is TimedOut {
            return .failure(.timedOut)
        } catch let error as ImageCreator.Error {
            return .failure(reason(for: error))
        } catch {
            print("[avatar] ImageCreator failed: \(error)")
            return .failure(.unknown)
        }
    }

    private struct TimedOut: Error {}

    @available(iOS 18.4, *)
    static func reason(for error: ImageCreator.Error) -> AvatarFallbackReason {
        switch error {
        case .notSupported: return .notSupported
        case .unavailable: return .unavailable
        case .creationCancelled: return .creationCancelled
        case .faceInImageTooSmall: return .faceTooSmall
        case .unsupportedLanguage: return .unsupportedLanguage
        case .unsupportedInputImage: return .unsupportedInputImage
        case .backgroundCreationForbidden: return .backgroundCreationForbidden
        case .creationFailed: return .creationFailed
        default:
            if #available(iOS 26.0, *), error == .conceptsRequirePersonIdentity {
                return .conceptsRequirePersonIdentity
            }
            return .unknown
        }
    }
}

/// Photo in, finished avatar out: layer one, then our decorations.
enum AvatarComposer {
    /// Pixel side of the stored avatar. Small enough to sync as a CKAsset to
    /// every room, large enough for the confirm screen's big card.
    static let side: CGFloat = 768

    /// Orientation applied, so a portrait selfie isn't drawn on its side.
    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }.cgImage
    }

    static func layout(for head: AvatarHead, seed: UInt64) -> AvatarDecorLayout {
        AvatarDecorLayout.make(
            canvas: side,
            headSize: CGSize(width: head.image.width, height: head.image.height),
            face: head.face, cheeks: head.cheeks, seed: seed)
    }

    static func pngData(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).pngData()
    }
}
