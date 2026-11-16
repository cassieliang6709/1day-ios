import AppIntents
import SwiftUI
import WidgetKit

@main
struct OneDayCaptureControls: WidgetBundle {
    var body: some Widget { OneDayCaptureControl() }
}

struct OneDayCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.cassie.oneday.capture") {
            ControlWidgetButton(action: OneDayCaptureIntent()) {
                Label(CaptureText.localized("Capture a moment", "拍个瞬间"), systemImage: "camera.fill")
            }
        }
        .displayName("1Day")
        .description(LocalizedStringResource(stringLiteral:
            CaptureText.localized("Film a moment for your story.", "拍下一个瞬间，留进你的故事。")))
    }
}
