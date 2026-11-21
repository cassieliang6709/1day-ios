import AVFoundation
import PhotosUI
import SwiftUI
import ImagePlayground
import UIKit

struct AvatarSetupFlow: View {
    let onFinish: (Bool) -> Void
    var skipLabel: String = Strings.avatarSkip

    enum Step: Equatable { case upload, generating, confirm, done }

    @State private var step: Step = .upload
    @State private var photo: CGImage?
    @State private var head: AvatarHeadResult?
    @State private var result: CGImage?
    @State private var frame: CGImage?
    @State private var error: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsPicker = false
    @State private var showsCamera = false
    @State private var work: Task<Void, Never>?
    @State private var showsEmojiPlayground = false
    @State private var showsStickerPicker = false

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 3)
            switch step {
            case .upload: upload
            case .generating: generating
            case .confirm: confirm
            case .done: done
            }
        }
        .animation(.smooth(duration: 0.35), value: step)
        .photosPicker(isPresented: $showsPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickerItem = nil
                if let data, let image = UIImage(data: data) { start(with: image) }
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPhotoPicker { image in
                showsCamera = false
                if let image { start(with: image) }
            }
            .ignoresSafeArea()
        }
        .task { startDebugSampleIfAsked() }
        .onDisappear { work?.cancel() }
    }


    private var upload: some View {
        // 小屏（iPhone SE）放不下时可以滚动，不然标题和「取消」会被切掉
        ViewThatFits(in: .vertical) {
            uploadContent
            ScrollView { uploadContent }
                .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showsStickerPicker) {
            StickerPickerSheet(onPick: useSticker)
                .presentationDetents([.large])
        }
        .modifier(PlaygroundSheet(
            isPresented: $showsEmojiPlayground, onImage: useEmojiImage))
    }

    private var uploadContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Text(Strings.avatarUploadHeadline)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            AvatarPlaceholderCard()
                .frame(width: 240, height: 240)
                .padding(.top, 40)

            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.oneDayEmber)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
            }

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                // 一排小卡片，三个来源同级（2026-11-21 Cassie：按钮别那么大）
                HStack(spacing: OneDay.Space.s) {
                    AvatarSourceTile(title: Strings.avatarTakePhoto, systemImage: "camera.fill", action: takePhoto)
                        .accessibilityIdentifier("avatar-take-photo")
                    AvatarSourceTile(title: Strings.avatarUseMemoji, systemImage: "face.smiling") {
                        showsStickerPicker = true
                    }
                    .accessibilityIdentifier("avatar-memoji")
                    AvatarSourceTile(title: Strings.avatarPickPhoto, systemImage: "photo.on.rectangle") {
                        showsPicker = true
                    }
                    .accessibilityIdentifier("avatar-pick-photo")
                    if Self.playgroundAvailable {
                        AvatarSourceTile(title: Strings.avatarMakeEmoji, systemImage: "sparkles") {
                            showsEmojiPlayground = true
                        }
                        .accessibilityIdentifier("avatar-genmoji")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)  // 文字折行时几张卡片一样高

                if !AvatarStore.shared.history.isEmpty {
                    Text(Strings.avatarHistory)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .padding(.top, 10)
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(AvatarStore.shared.history, id: \.self) { url in
                                Button { restore(url) } label: {
                                    Group {
                                        if let image = UIImage(contentsOfFile: url.path) {
                                            Image(uiImage: image).resizable().scaledToFit()
                                        }
                                    }
                                    .padding(4)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(AvatarCard<EmptyView>.cardColor))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Strings.avatarUseEarlier)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                Text(Strings.avatarOrBuddy)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .padding(.top, 10)
                HStack(spacing: 18) {
                    ForEach(Self.builtInAvatars, id: \.self) { name in
                        Button { pickBuiltIn(name) } label: {
                            Image(name)
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(AvatarCard<EmptyView>.cardColor))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Strings.avatarUseBuddy)
                        .accessibilityIdentifier("avatar-builtin-\(name)")
                    }
                }


                Button { onFinish(false) } label: {
                    Text(skipLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avatar-skip")
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 28)
    }

    private func restore(_ url: URL) {
        AvatarStore.shared.restore(url)
        onFinish(true)
    }

    private func useSticker(_ image: UIImage) {
        showsStickerPicker = false
        guard let cg = AvatarComposer.upright(image), let framed = Self.centred(cg) else {
            error = Strings.avatarFailed
            return
        }
        work?.cancel()
        error = nil
        head = AvatarHeadResult(head: AvatarHead(image: cg, face: nil, cheeks: nil), path: .sticker)
        result = framed
        step = .confirm
    }

    private func useEmojiImage(_ url: URL) {
        guard let image = UIImage(contentsOfFile: url.path) else { error = Strings.avatarFailed; return }
        useSticker(image)
    }

    static func centred(_ image: CGImage, side: CGFloat = 768) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let inset = side * 0.06
        let box = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let scale = min(box.width / w, box.height / h)
        let rect = CGRect(x: box.midX - w * scale / 2, y: box.midY - h * scale / 2,
                          width: w * scale, height: h * scale)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIImage(cgImage: image).draw(in: rect)
        }.cgImage
    }

    private func takePhoto() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showsPicker = true
            return
        }
        showsCamera = true
    }


    private var generating: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Text(Strings.avatarGeneratingHeadline)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)

            AvatarCard {
                if let frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .transition(.opacity)
                        .id(ObjectIdentifier(frame))
                } else if let photo {
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                        .padding(36)
                        .opacity(0.85)
                }
            }
            .frame(width: 290, height: 290)
            .animation(.easeInOut(duration: 0.6), value: frame.map(ObjectIdentifier.init))
            .padding(.top, 36)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 28)
    }


    private var confirm: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Text(Strings.avatarConfirmHeadline)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)

            if let result {
                Image(decorative: result, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 340, maxHeight: 340)
                    .padding(.top, 28)
                    .accessibilityLabel(Strings.avatarAccessibility)
                    .accessibilityIdentifier("avatar-result")
            }

            #if DEBUG
            if UserDefaults.standard.bool(forKey: "debugAvatarPath"), let path = head?.path {
                Text(Self.debugLabel(path))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(OneDay.inkFaint)
                    .padding(.top, 10)
                    .accessibilityIdentifier("avatar-debug-path")
            }
            #endif

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button(action: accept) { Text(Strings.avatarConfirm) }
                    .buttonStyle(.primaryAction)
                    .accessibilityIdentifier("avatar-confirm")
                Button(action: newPhoto) {
                    Text(Strings.avatarNewPhoto)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avatar-new-photo")
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 28)
    }

    static var playgroundAvailable: Bool {
        if #available(iOS 18.1, *) { return ImagePlaygroundViewController.isAvailable }
        return false
    }

    private var done: some View {
        VStack(spacing: 18) {
            if let result {
                Image(decorative: result, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .accessibilityIdentifier("avatar-done")
            }
        }
    }


    /// 抠图很快，白边动画至少放这么久，不让人干等
    static let minimumDrawSeconds: Double = 3
    static let frames = 12

    private func start(with image: UIImage) {
        guard let cg = AvatarComposer.upright(image) else { error = Strings.avatarFailed; return }
        photo = AvatarHeadExtractor.downscaled(cg, to: AvatarHeadExtractor.workingSide)
        head = nil
        run(minimum: Self.minimumDrawSeconds)
    }

    private func newPhoto() {
        work?.cancel()
        photo = nil
        head = nil
        result = nil
        frame = nil
        step = .upload
    }

    private func run(minimum: Double) {
        guard let photo else { return }
        work?.cancel()
        error = nil
        frame = nil
        result = nil
        step = .generating
        work = Task {
            let started = Date.now
            do {
                let made = try await Task.detached(priority: .userInitiated) {
                    try AvatarMaker.makeHead(from: photo)
                }.value
                try Task.checkCancellation()
                head = made
                let layout = AvatarComposer.layout(for: made.head)
                let images = await Task.detached(priority: .userInitiated) { () -> [CGImage] in
                    (0...Self.frames).compactMap {
                        AvatarDecorator.render(head: made.head.image, layout: layout,
                                               progress: CGFloat($0) / CGFloat(Self.frames))
                    }
                }.value
                guard let last = images.last else { throw AvatarHeadExtractor.Failure.renderFailed }
                let left = max(minimum - Date.now.timeIntervalSince(started), 2.5)
                let pause = left / Double(images.count)
                for image in images {
                    try Task.checkCancellation()
                    frame = image
                    try await Task.sleep(for: .seconds(pause))
                }
                result = last
                step = .confirm
            } catch is CancellationError {
                return
            } catch {
                print("[avatar] failed: \(error)")
                self.error = Strings.avatarFailed
                step = .upload
            }
        }
    }

    private func accept() {
        guard let result, let data = AvatarComposer.pngData(result) else { return }
        AvatarStore.shared.save(pngData: data)
        photo = nil
        head = nil
        step = .done
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            onFinish(true)
        }
    }

    static let builtInAvatars = ["OneDayBuddyYellow", "OneDayBuddyBlue", "OneDayBuddyMint"]

    private func pickBuiltIn(_ name: String) {
        guard let cg = UIImage(named: name)?.cgImage else { return }
        work?.cancel()
        result = cg
        accept()
    }


    private func startDebugSampleIfAsked() {
        #if DEBUG
        guard photo == nil, step == .upload,
              let path = UserDefaults.standard.string(forKey: "debugAvatarSample"),
              let image = UIImage(contentsOfFile: path)
        else { return }
        start(with: image)
        #endif
    }

    #if DEBUG
    static func debugLabel(_ path: AvatarPath) -> String {
        switch path {
        case .cutout: return "Vision cut-out"
        case .sticker: return "Memoji / Genmoji sticker"
        }
    }
    #endif
}

struct AvatarCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    static var cardColor: Color { Color(uiColor: UIColor(hex: 0xFDF3D8)) }

    var body: some View {
        ZStack { content() }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.cardColor, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            .oneDaySoftShadow(strength: 0.6)
    }
}

private struct AvatarPlaceholderCard: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AvatarCard<EmptyView>.cardColor)
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [8, 8]))
                .foregroundStyle(OneDay.inkFaint)
            Image(systemName: "face.smiling")
                .font(.system(size: 72, weight: .regular))
                .foregroundStyle(OneDay.inkFaint)
        }
        .accessibilityHidden(true)
    }
}

private struct CameraPhotoPicker: UIViewControllerRepresentable {
    let onDone: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void
        init(onDone: @escaping (UIImage?) -> Void) { self.onDone = onDone }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onDone(picker.cameraDevice == .front ? image.map(Self.mirrored) : image)
        }

        private static func mirrored(_ image: UIImage) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            return UIGraphicsImageRenderer(size: image.size, format: format)
                .image { context in
                    context.cgContext.translateBy(x: image.size.width, y: 0)
                    context.cgContext.scaleBy(x: -1, y: 1)
                    image.draw(at: .zero)
                }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
    }
}

private struct AvatarSourceTile: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: OneDay.Space.xs) {
                Image(systemName: systemImage)
                    .font(OneDay.Font.rounded(.title3, weight: .semibold))
                    .foregroundStyle(OneDay.brandText)
                Text(title)
                    .font(OneDay.Font.caption)
                    .foregroundStyle(OneDay.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.vertical, OneDay.Space.m)
            .padding(.horizontal, OneDay.Space.xs)
            .frame(maxWidth: .infinity, minHeight: 76, maxHeight: .infinity)
            .background(
                Color.oneDayBrand.opacity(0.12),
                in: RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PlaygroundSheet: ViewModifier {
    @Binding var isPresented: Bool
    let onImage: (URL) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.4, *) {
            sheet(content)
                .imagePlaygroundGenerationStyle(.emoji, in: [.emoji])
                .imagePlaygroundPersonalizationPolicy(.enabled)
        } else if #available(iOS 18.1, *) {
            sheet(content)
        } else {
            content
        }
    }

    @available(iOS 18.1, *)
    private func sheet(_ content: Content) -> some View {
        content.imagePlaygroundSheet(
            isPresented: $isPresented,
            concepts: [],
            sourceImage: nil,
            onCompletion: onImage)
    }
}

/// 在表情键盘里挑 Memoji 或普通 emoji。挑好后点「用这个」，键盘收起，进确认页。
private struct StickerPickerSheet: View {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: UIImage?
    @State private var focused = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(Strings.cancel) { dismiss() }
                    .foregroundStyle(OneDay.inkSoft)
                    .accessibilityIdentifier("sticker-cancel")
                Spacer()
                Button(Strings.avatarUseThis) {
                    focused = false
                    if let picked { onPick(picked) }
                }
                .fontWeight(.heavy)
                .foregroundStyle(picked == nil ? OneDay.inkFaint : OneDay.brandText)
                .disabled(picked == nil)
                .accessibilityIdentifier("sticker-use")
            }
            .font(OneDay.Font.callout)
            .frame(minHeight: 44)
            .padding(.horizontal, OneDay.Space.xl)
            .padding(.top, OneDay.Space.s)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Strings.avatarMemojiHint)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                    ForEach(Array(Strings.avatarMemojiSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(OneDay.onBrand)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.oneDayBrand))
                            Text(step)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(OneDay.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    StickerField(focused: $focused) { picked = $0 }
                        .frame(height: 64)
                        .padding(.horizontal, 12)
                        .background(OneDay.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(Strings.avatarMemojiNone)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct StickerField: UIViewRepresentable {
    @Binding var focused: Bool
    let onChange: (UIImage?) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .systemFont(ofSize: 40)
        view.backgroundColor = .clear
        if #available(iOS 18.0, *) { view.supportsAdaptiveImageGlyph = true }
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if focused, !view.isFirstResponder {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !focused, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: StickerField
        init(_ parent: StickerField) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.focused { DispatchQueue.main.async { self.parent.focused = true } }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focused { DispatchQueue.main.async { self.parent.focused = false } }
        }

        func textViewDidChange(_ view: UITextView) {
            parent.onChange(Self.lastImage(in: view.attributedText ?? NSAttributedString()))
        }

        /// 取最后放进去的那个：Memoji / Genmoji 贴纸、图片附件，或者普通 emoji（画成图）。
        static func lastImage(in text: NSAttributedString) -> UIImage? {
            var found: UIImage?
            let all = NSRange(location: 0, length: text.length)
            if #available(iOS 18.0, *) {
                text.enumerateAttribute(.adaptiveImageGlyph, in: all, options: .reverse) { value, _, stop in
                    if let glyph = value as? NSAdaptiveImageGlyph, let image = UIImage(data: glyph.imageContent) {
                        found = image
                        stop.pointee = true
                    }
                }
            }
            if found == nil {
                text.enumerateAttribute(.attachment, in: all, options: .reverse) { value, _, stop in
                    if let image = (value as? NSTextAttachment)?.image {
                        found = image
                        stop.pointee = true
                    }
                }
            }
            if found == nil, let emoji = text.string.last(where: { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation } || $0.unicodeScalars.count > 1 && $0.unicodeScalars.first?.properties.isEmoji == true }) {
                found = render(String(emoji))
            }
            return found
        }

        private static func render(_ emoji: String) -> UIImage {
            let side: CGFloat = 512
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: side * 0.8)])
            let size = text.size()
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
                text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
            }
        }
    }
}
