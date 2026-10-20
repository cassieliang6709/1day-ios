import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

/// A head on a transparent background, plus where its face is — what the
/// decoration layer needs from whoever made it.
struct AvatarHead {
    let image: CGImage
    /// The face inside `image`, unit square, top-left origin. Nil when none was found.
    let face: CGRect?
    /// Cheek centres from facial landmarks, same unit square. Nil without landmarks.
    let cheeks: [CGPoint]?
}

/// Cuts the head out of a picture with Vision: the subject's mask
/// (`VNGenerateForegroundInstanceMaskRequest`, falling back to person
/// segmentation), intersected with an oval around the face
/// (`VNDetectFaceLandmarksRequest`) so the shoulders and the background go.
///
/// Used both on the original photo (the fallback path) and on the picture
/// Apple's model drew (to get rid of its background and anything below the
/// chin). Runs entirely on the phone.
enum AvatarHeadExtractor {
    enum Failure: Error { case unreadableImage, renderFailed }

    /// Longest side the work is done at. Plenty for a 768pt avatar.
    static let workingSide: CGFloat = 1024

    static func extract(from source: CGImage) throws -> AvatarHead {
        let image = downscaled(source, to: workingSide)
        let size = CGSize(width: image.width, height: image.height)

        let face = largestFace(in: image)
        let mask = subjectMask(for: image)

        // The head's box, in pixels, top-left origin.
        let headBox: CGRect = {
            if let face {
                let f = face.rect
                return CGRect(
                    x: f.midX - f.width * 0.85, y: f.minY - f.height * 0.72,
                    width: f.width * 1.7, height: f.height * 1.84)
            }
            if let bounds = mask.flatMap({ maskBounds($0, size: size) }) {
                // No face: the top of whatever stands out, roughly head-shaped.
                let w = min(bounds.width, bounds.height * 0.62)
                return CGRect(x: bounds.midX - w / 2, y: bounds.minY, width: w, height: w * 1.12)
            }
            let side = min(size.width, size.height) * 0.72
            return CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        }()
        let crop = headBox.intersection(CGRect(origin: .zero, size: size)).integral
        guard !crop.isNull, crop.width > 8, crop.height > 8 else { throw Failure.renderFailed }

        // The oval, soft at the edge, drawn at full size.
        let oval = ovalMask(size: size, oval: headBox.insetBy(dx: headBox.width * 0.02, dy: 0))
        var alpha = oval
        if let mask {
            alpha = mask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: oval])
        }

        let input = CIImage(cgImage: image)
        let cut = input.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: alpha,
        ])
        // Core Image is bottom-left; the crop box is top-left.
        let ciCrop = CGRect(x: crop.minX, y: size.height - crop.maxY, width: crop.width, height: crop.height)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let out = context.createCGImage(
            cut.cropped(to: ciCrop), from: ciCrop, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        else { throw Failure.renderFailed }

        func unit(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - crop.minX) / crop.width, y: (p.y - crop.minY) / crop.height)
        }
        let faceUnit = face.map { f -> CGRect in
            let o = unit(f.rect.origin)
            return CGRect(x: o.x, y: o.y, width: f.rect.width / crop.width, height: f.rect.height / crop.height)
        }
        return AvatarHead(image: out, face: faceUnit, cheeks: face?.cheeks?.map(unit))
    }

    // MARK: - Face

    private struct Face {
        /// Pixels, top-left origin.
        let rect: CGRect
        let cheeks: [CGPoint]?
    }

    private static func largestFace(in image: CGImage) -> Face? {
        let request = VNDetectFaceLandmarksRequest()
        onCPUInSimulator(request)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch {
            print("[avatar] face detection failed: \(error)")
            return nil
        }
        guard let best = request.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let b = best.boundingBox
        let rect = CGRect(x: b.minX * w, y: (1 - b.maxY) * h, width: b.width * w, height: b.height * h)
        return Face(rect: rect, cheeks: cheeks(of: best, imageSize: CGSize(width: w, height: h)))
    }

    /// Below each eye and a little outward, level with the nose's middle.
    /// Vision has no cheek landmark; this is where blush goes on a drawn face.
    private static func cheeks(of face: VNFaceObservation, imageSize: CGSize) -> [CGPoint]? {
        guard let landmarks = face.landmarks,
              let left = landmarks.leftEye, let right = landmarks.rightEye,
              let nose = landmarks.nose
        else { return nil }
        func center(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
            let pts = region.pointsInImage(imageSize: imageSize)
            guard !pts.isEmpty else { return .zero }
            let sx = pts.reduce(0) { $0 + $1.x }, sy = pts.reduce(0) { $0 + $1.y }
            // Vision's image points are bottom-left.
            return CGPoint(x: sx / CGFloat(pts.count), y: imageSize.height - sy / CGFloat(pts.count))
        }
        let l = center(left), r = center(right), n = center(nose)
        let spread = (r.x - l.x) * 0.18
        let y = n.y + (n.y - (l.y + r.y) / 2) * 0.15
        let outward = l.x < r.x ? spread : -spread
        return [CGPoint(x: l.x - outward, y: y), CGPoint(x: r.x + outward, y: y)]
    }

    /// The Simulator has no Neural Engine, and Vision's default device fails
    /// there with "Could not create inference context". The CPU works. A phone
    /// keeps Vision's own choice.
    private static func onCPUInSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
        guard let stages = try? request.supportedComputeStageDevices else { return }
        for (stage, devices) in stages {
            if let cpu = devices.first(where: {
                if case .cpu = $0 { return true } else { return false }
            }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        #endif
    }

    // MARK: - Masks

    /// The picture's main subject as a grey mask (white = keep), image-sized.
    private static func subjectMask(for image: CGImage) -> CIImage? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        onCPUInSimulator(foreground)
        do {
            try handler.perform([foreground])
            if let result = foreground.results?.first {
                let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
                return CIImage(cvPixelBuffer: buffer).cropped(to: extent)
            }
        } catch {
            print("[avatar] foreground mask failed, trying person segmentation: \(error)")
        }
        let person = VNGeneratePersonSegmentationRequest()
        person.qualityLevel = .accurate
        onCPUInSimulator(person)
        do {
            try handler.perform([person])
            if let buffer = person.results?.first?.pixelBuffer {
                let raw = CIImage(cvPixelBuffer: buffer)
                let sx = extent.width / raw.extent.width, sy = extent.height / raw.extent.height
                return raw.transformed(by: CGAffineTransform(scaleX: sx, y: sy)).cropped(to: extent)
            }
        } catch {
            print("[avatar] person segmentation failed, using the oval alone: \(error)")
        }
        return nil
    }

    /// Bounding box of the mask's bright area, top-left origin.
    private static func maskBounds(_ mask: CIImage, size: CGSize) -> CGRect? {
        let w = 64, h = 64
        let scaled = mask.transformed(by: CGAffineTransform(
            scaleX: CGFloat(w) / size.width, y: CGFloat(h) / size.height))
        var pixels = [UInt8](repeating: 0, count: w * h)
        CIContext().render(scaled, toBitmap: &pixels, rowBytes: w, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                           format: .L8, colorSpace: nil)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where pixels[y * w + x] > 127 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Rows came out bottom-up.
        let fx = size.width / CGFloat(w), fy = size.height / CGFloat(h)
        return CGRect(x: CGFloat(minX) * fx, y: size.height - CGFloat(maxY + 1) * fy,
                      width: CGFloat(maxX - minX + 1) * fx, height: CGFloat(maxY - minY + 1) * fy)
    }

    /// White oval on black, blurred a little at the edge. `oval` is top-left.
    private static func ovalMask(size: CGSize, oval: CGRect) -> CIImage {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size)) }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 1, alpha: 1)
        // CGContext is bottom-left too.
        ctx.fillEllipse(in: CGRect(x: oval.minX, y: size.height - oval.maxY, width: oval.width, height: oval.height))
        guard let cg = ctx.makeImage() else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }
        let extent = CGRect(origin: .zero, size: size)
        return CIImage(cgImage: cg).clampedToExtent()
            .applyingGaussianBlur(sigma: Double(min(size.width, size.height) * 0.006))
            .cropped(to: extent)
    }

    static func downscaled(_ image: CGImage, to side: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > side else { return image }
        let scale = side / longest
        let w = Int(CGFloat(image.width) * scale), h = Int(CGFloat(image.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}
