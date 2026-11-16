import CoreGraphics
import Foundation
import ImagePlayground
import UIKit

protocol AvatarHeadMaking {
    func makeHead(from photo: CGImage) async throws -> AvatarHeadResult
}

struct AvatarHeadResult {
    let head: AvatarHead
    let path: AvatarPath
}

enum AvatarPath: Equatable {
    case imageCreator
    case imagePlayground
    case sticker
    case visionFallback(AvatarFallbackReason)
}

enum AvatarFallbackReason: String, Error, Equatable {
    case systemTooOld
    case notSupported
    case unavailable
    case faceTooSmall
    case unsupportedInputImage
    case unsupportedLanguage
    case backgroundCreationForbidden
    case creationCancelled
    case creationFailed
    case conceptsRequirePersonIdentity
    case timedOut
    case noImage
    case styleUnavailable
    case forced
    case unknown
}

struct AvatarMaker: AvatarHeadMaking {
    static let imageCreatorTimeout: Duration = .seconds(45)

    static let prompt = "cute chibi portrait, big head, round face, head only, no body, plain white background"

    var forceFallback = false

    func makeHead(from photo: CGImage) async throws -> AvatarHeadResult {
        let reason: AvatarFallbackReason
        if forceFallback {
            reason = .forced
        } else if #available(iOS 18.4, *) {
            switch await Self.drawWithImageCreator(photo) {
            case .success(let drawn):
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

enum AvatarComposer {
    static let side: CGFloat = 768

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
