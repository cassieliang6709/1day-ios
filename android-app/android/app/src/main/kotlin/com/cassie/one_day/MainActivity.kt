package com.cassie.one_day

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var media: OneDayMedia

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        media = OneDayMedia(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cassie.one_day/media")
            .setMethodCallHandler(media::handle)
    }

    override fun onDestroy() {
        if (::media.isInitialized) media.dispose()
        super.onDestroy()
    }
}
