import AVFoundation
import CoreImage
import SwiftUI
import UIKit

enum CameraStyle: String, CaseIterable, Identifiable, Codable {
    case standard, camcorder, film, instant

    var id: String { rawValue }
    static let storageKey = "cameraStyle"
    static let selectable: [CameraStyle] = [.camcorder]
    static let defaultCamera: CameraStyle = .camcorder

    var displayName: String {
        switch self {
        case .standard: Strings.cameraStandard
        case .camcorder: Strings.cameraCamcorder
        case .film: Strings.cameraFilm
        case .instant: Strings.cameraInstant
        }
    }

    var symbolName: String {
        switch self {
        case .standard: "camera"
        case .camcorder: "video"
        case .film: "camera.aperture"
        case .instant: "photo"
        }
    }

    var tone: PersonalEffectParameters {
        switch self {
        case .standard, .camcorder, .instant: .none
        case .film: PersonalEffectParameters(temperature: 12)
        }
    }

    func aspectRatio(for orientation: Challenge.Orientation) -> CGFloat? {
        let upright: CGFloat
        switch self {
        case .standard: return nil
        case .camcorder: upright = 3 / 4
        case .film: upright = 2 / 3
        case .instant: upright = 3 / 4
        }
        switch orientation {
        case .portrait: return upright
        case .landscape: return 1 / upright
        case .square: return nil
        }
    }

    var previewWash: (color: Color, opacity: Double) {
        switch self {
        case .standard, .camcorder, .instant: (.clear, 0)
        case .film: (Color(red: 1, green: 0.62, blue: 0.25), 0.06)
        }
    }


    func overlay(size: CGSize, date: Date) -> UIImage? {
        guard self != .standard, size.width >= 2, size.height >= 2 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let minEdge = min(size.width, size.height)
            switch self {
            case .standard:
                break
            case .camcorder:
                drawCamcorder(in: cg, size: size, minEdge: minEdge, date: date)
            case .film:
                drawFilm(in: cg, size: size, minEdge: minEdge, date: date)
            case .instant:
                drawInstant(in: cg, size: size, minEdge: minEdge, date: date)
            }
        }
    }

    private func drawCamcorder(in cg: CGContext, size: CGSize, minEdge: CGFloat, date: Date) {
        let inset = minEdge * 0.06
        let arm = minEdge * 0.09
        let line = max(minEdge * 0.008, 2)
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        cg.setLineWidth(line)
        cg.setLineCap(.square)
        let l = inset, r = size.width - inset, t = inset, b = size.height - inset
        for (corner, dx, dy) in [
            (CGPoint(x: l, y: t), 1.0, 1.0), (CGPoint(x: r, y: t), -1.0, 1.0),
            (CGPoint(x: l, y: b), 1.0, -1.0), (CGPoint(x: r, y: b), -1.0, -1.0),
        ] {
            cg.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            cg.addLine(to: corner)
            cg.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        cg.strokePath()

        let font = UIFont.monospacedSystemFont(ofSize: minEdge * 0.045, weight: .bold)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = minEdge * 0.006
        shadow.shadowOffset = CGSize(width: 0, height: minEdge * 0.003)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.white, .shadow: shadow,
        ]

        let pad = inset + minEdge * 0.035
        let dot = font.pointSize * 0.62
        let recSize = ("REC" as NSString).size(withAttributes: attributes)
        let recX = size.width - pad - recSize.width
        cg.setFillColor(UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 1).cgColor)
        cg.fillEllipse(in: CGRect(
            x: recX - dot * 1.6, y: pad + (font.lineHeight - dot) / 2, width: dot, height: dot))
        ("REC" as NSString).draw(at: CGPoint(x: recX, y: pad), withAttributes: attributes)

        let day = Self.formatted(date, "MMM d yyyy").uppercased()
        let time = Self.formatted(date, "h:mm a")
        let timeSize = (time as NSString).size(withAttributes: attributes)
        let bottom = size.height - pad - timeSize.height
        (time as NSString).draw(at: CGPoint(x: pad, y: bottom), withAttributes: attributes)
        (day as NSString).draw(
            at: CGPoint(x: pad, y: bottom - timeSize.height * 1.05), withAttributes: attributes)
    }

    private func drawFilm(in cg: CGContext, size: CGSize, minEdge: CGFloat, date: Date) {
        let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.38).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.55, 1]) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.drawRadialGradient(
                gradient, startCenter: center, startRadius: 0,
                endCenter: center, endRadius: hypot(size.width, size.height) / 2,
                options: [.drawsAfterEndLocation])
        }

        let orange = UIColor(red: 1, green: 0.55, blue: 0.12, alpha: 1)
        let glow = NSShadow()
        glow.shadowColor = orange.withAlphaComponent(0.85)
        glow.shadowBlurRadius = minEdge * 0.012
        let font = UIFont(name: "Menlo-Bold", size: minEdge * 0.055)
            ?? .monospacedDigitSystemFont(ofSize: minEdge * 0.055, weight: .bold)
        let text = Self.formatted(date, "''yy  M  d") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: orange, .shadow: glow, .kern: minEdge * 0.004,
        ]
        let textSize = text.size(withAttributes: attributes)
        let margin = minEdge * 0.07
        text.draw(
            at: CGPoint(
                x: size.width - margin - textSize.width,
                y: size.height - margin - textSize.height),
            withAttributes: attributes)
    }

    private func drawInstant(in cg: CGContext, size: CGSize, minEdge: CGFloat, date: Date) {
        let side = minEdge * 0.055
        let bottomStrip = max(minEdge * 0.2, side * 3)
        let window = CGRect(
            x: side, y: side,
            width: size.width - side * 2,
            height: size.height - side - bottomStrip)
        cg.setFillColor(UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1).cgColor)
        cg.addRect(CGRect(origin: .zero, size: size))
        cg.addRect(window)
        cg.fillPath(using: .evenOdd)

        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
        cg.setLineWidth(max(minEdge * 0.002, 1))
        cg.stroke(window)

        let font = UIFont(name: "Noteworthy-Bold", size: minEdge * 0.06)
            ?? .systemFont(ofSize: minEdge * 0.06, weight: .semibold)
        let text = Self.formatted(date, "yyyy.M.d") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 0.27, green: 0.24, blue: 0.22, alpha: 0.9),
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(
                x: size.width - side * 1.4 - textSize.width,
                y: window.maxY + (bottomStrip - textSize.height) / 2),
            withAttributes: attributes)
    }

    private static func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}


enum CameraStyleBaker {
    static let metadataKey = "com.cassie.oneday.camera-style"

    private static var metadataIdentifier: AVMetadataIdentifier {
        AVMetadataItem.identifier(forKey: metadataKey, keySpace: .quickTimeMetadata)
            ?? AVMetadataIdentifier(rawValue: "mdta/\(metadataKey)")
    }

    static func bake(
        _ url: URL, style: CameraStyle, orientation: Challenge.Orientation, recordedAt: Date?
    ) async -> URL {
        guard style != .standard else { return url }
        guard let baked = try? await render(
            url, style: style, aspect: style.aspectRatio(for: orientation),
            date: recordedAt ?? .now)
        else { return url }
        try? FileManager.default.removeItem(at: url)
        return baked
    }

    static func hasCameraStamp(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata) else { return false }
        return items.contains { $0.identifier == metadataIdentifier }
    }

    static func cameraStyle(of url: URL) async -> CameraStyle? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata),
              let item = items.first(where: { $0.identifier == metadataIdentifier }),
              let raw = try? await item.load(.stringValue)
        else { return nil }
        return CameraStyle(rawValue: raw)
    }

    private final class OverlayBox: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: CIImage?
        private var cachedExtent: CGRect = .null

        func image(for extent: CGRect, make: (CGSize) -> UIImage?) -> CIImage? {
            lock.lock()
            defer { lock.unlock() }
            if extent == cachedExtent { return cached }
            cachedExtent = extent
            cached = make(extent.size)
                .flatMap { $0.cgImage }
                .map { CIImage(cgImage: $0).transformed(by: CGAffineTransform(
                    translationX: extent.minX, y: extent.minY)) }
            return cached
        }
    }

    static func centredCrop(of size: CGSize, aspect: CGFloat) -> CGRect? {
        guard size.width > 0, size.height > 0, aspect > 0 else { return nil }
        var width = size.width
        var height = size.height
        if width / height > aspect { width = height * aspect } else { height = width / aspect }
        width = (width / 2).rounded(.down) * 2
        height = (height / 2).rounded(.down) * 2
        guard width >= 2, height >= 2,
              abs(width - size.width) >= 2 || abs(height - size.height) >= 2
        else { return nil }
        return CGRect(
            x: ((size.width - width) / 2).rounded(.down),
            y: ((size.height - height) / 2).rounded(.down),
            width: width, height: height)
    }

    private static func render(
        _ url: URL, style: CameraStyle, aspect: CGFloat?, date: Date
    ) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let tone = style.tone
        let box = OverlayBox()
        let composition = try await AVMutableVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                let source = request.sourceImage
                var frame = source.extent
                if let aspect, let cut = centredCrop(of: frame.size, aspect: aspect) {
                    frame = cut.offsetBy(dx: frame.minX, dy: frame.minY)
                }
                let cropped = source.cropped(to: frame)
                    .transformed(by: CGAffineTransform(translationX: -frame.minX, y: -frame.minY))
                let extent = CGRect(origin: .zero, size: frame.size)
                let graded = PersonalEffectFilter.apply(tone, to: cropped)
                let overlay = box.image(for: extent) { style.overlay(size: $0, date: date) }
                let output = overlay.map { $0.composited(over: graded) } ?? graded
                request.finish(with: output.cropped(to: extent), context: nil)
            })
        if let aspect, let cut = centredCrop(of: composition.renderSize, aspect: aspect) {
            composition.renderSize = cut.size
        }

        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else { throw PersonalEffectFilter.ExportError.sessionUnavailable }

        let tag = AVMutableMetadataItem()
        tag.identifier = metadataIdentifier
        tag.value = style.rawValue as NSString
        tag.dataType = kCMMetadataBaseDataType_UTF8 as String

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera-\(UUID().uuidString).mov")
        export.outputURL = output
        export.outputFileType = .mov
        export.videoComposition = composition
        export.metadata = (try? await asset.load(.metadata)).map { $0 + [tag] } ?? [tag]

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw PersonalEffectFilter.ExportError.failed(export.error?.localizedDescription ?? "unknown")
        }
        return output
    }
}


struct CameraStyleOverlay: View {
    let style: CameraStyle
    var date: Date?

    var body: some View {
        if style != .standard {
            GeometryReader { proxy in
                TimelineView(.everyMinute) { context in
                    let scale = UIScreen.main.scale
                    let pixels = CGSize(
                        width: proxy.size.width * scale, height: proxy.size.height * scale)
                    ZStack {
                        if style.previewWash.opacity > 0 {
                            style.previewWash.color.opacity(style.previewWash.opacity)
                                .blendMode(.softLight)
                        }
                        if let image = style.overlay(size: pixels, date: date ?? context.date) {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
