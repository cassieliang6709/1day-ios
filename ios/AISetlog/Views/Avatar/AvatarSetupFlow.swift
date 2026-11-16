import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// 注册里的头像三步：给我看看你 → 正在画你 → 画好了。
///
/// Shown once after sign-in (skippable), and again whenever someone taps
/// their own avatar in Settings. The photo stays in memory on this screen and
/// is dropped when it closes; only the finished avatar is saved
/// (`AvatarStore`) and, from there, synced to rooms.
struct AvatarSetupFlow: View {
    /// `true` when an avatar was saved, `false` for 「先不用头像」 / close.
    let onFinish: (Bool) -> Void
    /// The skip line on the first step. Settings shows a close button instead.
    var skipLabel: String = Strings.avatarSkip

    enum Step: Equatable { case upload, generating, confirm, done }

    @State private var step: Step = .upload
    @State private var photo: CGImage?
    /// Layer one's output, kept so 「重画一张」 on the Vision path only
    /// re-decorates instead of cutting the photo out again.
    @State private var head: AvatarHeadResult?
    @State private var seed = UInt64.random(in: 1...UInt64.max)
    /// The finished avatar.
    @State private var result: CGImage?
    /// What the generating screen is showing: the photo, then the head
    /// growing its outline and stickers.
    @State private var frame: CGImage?
    @State private var error: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsPicker = false
    @State private var showsCamera = false
    @State private var work: Task<Void, Never>?

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 3)
            // Instant swap, not a spring cross-fade. `.smooth` left the
            // outgoing full-screen step in the ZStack, still taking hits:
            // 「就是这样」 was visible and in the tree, but the tap landed on
            // the generating view that had not quite finished leaving. The
            // generating screen already has its own nine-second animation.
            switch step {
            case .upload: upload
            case .generating: generating
            case .confirm: confirm
            case .done: done
            }
        }
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
        .onAppear {
            AvatarFlowTrace.log("flow appear step=\(step)")
            #if DEBUG
            AvatarTouchTraceRecognizer.installIfTracing()
            #endif
        }
        .onChange(of: step) { old, new in
            AvatarFlowTrace.log("step \(old) -> \(new)")
            #if DEBUG
            AvatarTouchTraceRecognizer.installIfTracing()
            #endif
        }
        .onDisappear {
            AvatarFlowTrace.log("flow disappear step=\(step)")
            work?.cancel()
        }
    }

    // MARK: - 1. 给我看看你

    private var upload: some View {
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

            // Only a failure says anything here.
            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.oneDayEmber)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
            }

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button(action: takePhoto) {
                    Label(Strings.avatarTakePhoto, systemImage: "camera.fill")
                }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("avatar-take-photo")

                // A line under the one button, not a second button as heavy
                // as 拍一张: there is one thing to do first on this screen.
                Button { showsPicker = true } label: {
                    Label(Strings.avatarPickPhoto, systemImage: "photo.on.rectangle")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.brandText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avatar-pick-photo")

                // No photo: one of the buddies, as is. Not the mood faces —
                // a room pins today's mood on the avatar's corner. The line
                // above says so; three faces on their own read as decoration.
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

    /// The camera explains itself before iOS asks, in the spec's words.
    private func takePhoto() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            // The Simulator, or a device with the camera restricted.
            showsPicker = true
            return
        }
        // The system prompt explains the camera; nothing of ours before it.
        showsCamera = true
    }

    // MARK: - 2. 正在画你

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
                    // Before the head is cut out: the photo itself, softened.
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

    // MARK: - 3. 画好了

    private var confirm: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Text(Strings.avatarConfirmHeadline)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)

            // Straight on the page, as large as it fits: the sticker has its
            // own outline, and a pale card around it was a frame in a frame.
            if let result {
                Image(decorative: result, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 340, maxHeight: 340)
                    .clipped()
                    .contentShape(Rectangle())
                    .padding(.top, 28)
                    .accessibilityLabel(Strings.avatarAccessibility)
                    .accessibilityIdentifier("avatar-result")
            }

            // Which drawing path ran, for working on the drawing. Off unless
            // `-debugAvatarPath YES`: every Debug build is one Cassie uses, and
            // 「Vision fallback: notSupported」 under her face read as an error.
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
                Button(action: redraw) { Text(Strings.avatarRedraw) }
                    .buttonStyle(.softAction)
                    .accessibilityIdentifier("avatar-redraw")
                // 重画一张 keeps the photo and draws it again; this is the way
                // back when the photo itself was the problem.
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

    // MARK: - Work

    /// The generating screen lasts at least this long, so the drawing is
    /// something you watch rather than a flash. The spec says 8–15 seconds.
    static let minimumDrawSeconds: Double = 9
    /// 「重画一张」 is quicker: the photo has been looked at already.
    static let redrawSeconds: Double = 4
    /// Steps of the outline-and-stickers growing in.
    static let frames = 12

    private func start(with image: UIImage) {
        guard let cg = AvatarComposer.upright(image) else { error = Strings.avatarFailed; return }
        photo = AvatarHeadExtractor.downscaled(cg, to: AvatarHeadExtractor.workingSide)
        head = nil
        run(minimum: Self.minimumDrawSeconds)
    }

    private func redraw() {
        seed = UInt64.random(in: 1...UInt64.max)
        // A model drawing is drawn again; a cut-out keeps the cut and gets
        // new stickers and a new wobble.
        if head?.path == .imageCreator { head = nil }
        run(minimum: head == nil ? Self.minimumDrawSeconds : Self.redrawSeconds)
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
        let seed = seed
        let known = head
        let maker = AvatarMaker(forceFallback: Self.forcesFallback)
        work = Task {
            let started = Date.now
            do {
                let made: AvatarHeadResult
                if let known {
                    made = known
                } else {
                    made = try await Task.detached(priority: .userInitiated) {
                        try await maker.makeHead(from: photo)
                    }.value
                }
                try Task.checkCancellation()
                head = made
                let layout = AvatarComposer.layout(for: made.head, seed: seed)
                let images = await Task.detached(priority: .userInitiated) { () -> [CGImage] in
                    (0...Self.frames).compactMap {
                        AvatarDecorator.render(head: made.head.image, layout: layout,
                                               progress: CGFloat($0) / CGFloat(Self.frames))
                    }
                }.value
                guard let last = images.last else { throw AvatarHeadExtractor.Failure.renderFailed }
                // Whatever time is left of the minimum goes to the growing.
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
        AvatarFlowTrace.log("accept tapped step=\(step) result=\(result != nil)")
        guard let result else { return }
        guard let data = AvatarComposer.pngData(result) else {
            AvatarFlowTrace.log("accept png failed")
            // Don't leave 「就是这样」 on screen doing nothing.
            error = Strings.avatarFailed
            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) { step = .upload }
            return
        }
        AvatarStore.shared.save(pngData: data)
        // The photo is done with.
        photo = nil
        head = nil
        // A lingering confirm→done transition keeps avatar-confirm in the
        // accessibility tree after the tap; drop it immediately.
        var txn = Transaction()
        txn.disablesAnimations = true
        withTransaction(txn) { step = .done }
        AvatarFlowTrace.log("accept set done")
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            AvatarFlowTrace.log("onFinish(true)")
            onFinish(true)
        }
    }

    static let builtInAvatars = ["OneDayBuddyYellow", "OneDayBuddyBlue", "OneDayBuddyMint"]

    /// Saved like a drawn avatar, so rooms get it the same way.
    private func pickBuiltIn(_ name: String) {
        guard let cg = UIImage(named: name)?.cgImage else { return }
        work?.cancel()
        result = cg
        accept()
    }

    // MARK: - Debug

    private static var forcesFallback: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "debugAvatarForceFallback")
        #else
        false
        #endif
    }

    /// `-debugAvatarSample /path/to/photo.jpg` feeds a photo straight in, for
    /// screenshots on a Simulator with no camera and no faces in its library.
    private func startDebugSampleIfAsked() {
        #if DEBUG
        guard photo == nil, step == .upload,
              let path = UserDefaults.standard.string(forKey: "debugAvatarSample"),
              let image = UIImage(contentsOfFile: path)
        else {
            AvatarFlowTrace.log("debug sample skipped photo=\(photo != nil) step=\(step)")
            return
        }
        AvatarFlowTrace.log("debug sample start")
        start(with: image)
        #endif
    }

    #if DEBUG
    static func debugLabel(_ path: AvatarPath) -> String {
        switch path {
        case .imageCreator: return "ImageCreator"
        case .visionFallback(let reason): return "Vision fallback: \(reason.rawValue)"
        }
    }
    #endif
}

/// The pale yellow card the avatar sits on (`#FDF3D8`, from the spec).
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

/// The upload step's picture: an empty face waiting to be drawn.
/// Straight on the page, no card: a card behind a dashed circle on a
/// cream page was a box in a box.
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

/// The system camera, front-facing, one still.
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
            // The front camera's preview is a mirror and its photo isn't, so
            // the avatar came out the other way round from the face you saw.
            // Flip it to match the preview.
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
