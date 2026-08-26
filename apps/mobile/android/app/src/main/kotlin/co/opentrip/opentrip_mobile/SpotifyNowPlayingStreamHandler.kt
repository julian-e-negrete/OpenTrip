package co.opentrip.opentrip_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

/**
 * Streams Spotify's own "now playing" broadcasts to Dart — see
 * trip/spotify_now_playing.dart for why this exists instead of Spotify's
 * Web API: this needs zero OAuth, zero developer-account registration,
 * and works for every install, not just a handful of accounts
 * authorized against a rate-limited API app.
 *
 * Spotify's Android app sends `com.spotify.music.metadatachanged` as a
 * broadcast whenever a new track starts, once the user has turned on
 * "Device Broadcast Status" in Spotify's own Settings -> Playback — a
 * local Android intent, not a network call. Documented at
 * https://developer.spotify.com/documentation/android/tutorials/android-media-notifications
 * (extras: id/artist/album/track/length/timeSent).
 *
 * Registered dynamically (not declared in the manifest) since Android
 * 8+ (API 26+) blocks most manifest-declared implicit broadcast
 * receivers — Spotify's own tutorial registers this way too. On API 33+,
 * a context-registered receiver for a broadcast from another app must
 * explicitly opt into RECEIVER_EXPORTED or the OS throws a
 * SecurityException at registration time; ContextCompat.registerReceiver
 * handles that version branching so this doesn't need its own
 * Build.VERSION.SDK_INT check.
 */
class SpotifyNowPlayingStreamHandler(private val context: Context) : EventChannel.StreamHandler {
    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val newReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent == null) return
                val track = intent.getStringExtra("track") ?: return
                val artist = intent.getStringExtra("artist")
                val album = intent.getStringExtra("album")
                val spotifyUri = intent.getStringExtra("id")
                val lengthSeconds = intent.getIntExtra("length", -1)
                val timeSentMs = intent.getLongExtra("timeSent", System.currentTimeMillis())

                events.success(
                    mapOf(
                        "track" to track,
                        "artist" to artist,
                        "album" to album,
                        "spotifyUri" to spotifyUri,
                        "lengthSeconds" to if (lengthSeconds >= 0) lengthSeconds else null,
                        "timeSentMs" to timeSentMs,
                    )
                )
            }
        }
        receiver = newReceiver
        ContextCompat.registerReceiver(
            context,
            newReceiver,
            IntentFilter("com.spotify.music.metadatachanged"),
            ContextCompat.RECEIVER_EXPORTED,
        )
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let { context.unregisterReceiver(it) }
        receiver = null
    }
}
