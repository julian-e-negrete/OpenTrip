package co.opentrip.opentrip_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "co.opentrip.opentrip_mobile/spotify_now_playing")
            .setStreamHandler(SpotifyNowPlayingStreamHandler(applicationContext))
    }
}
