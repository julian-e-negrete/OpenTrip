# Testing on iOS (no Mac of your own required — borrow one)

This project has never been built or run on iOS before — every feature
in it was built and tested on Android only (see `/README.md`). The
Dart/Flutter code and the iOS project files (`apps/mobile/ios/`) are set
up as far as they reasonably can be without actually running on a Mac,
but this guide is the first real test of that setup, on whoever's Mac +
iPhone you have access to.

**No paid Apple Developer account needed** — this whole guide uses a
free Apple ID. The one real limitation that comes with that: the app has
to be installed by physically plugging the iPhone into the Mac and
building from there (no shareable link, no TestFlight), and the install
**expires after 7 days** — after that, just plug in and re-run to renew
it. If you (or whoever's Mac this is) later get a paid Apple Developer
Program membership ($99/year), the same project can be set up for
TestFlight instead, which removes both limits.

## What you'll need

- A Mac, with an internet connection.
- [Xcode](https://apps.apple.com/us/app/xcode/id497799835) installed from
  the Mac App Store (multi-GB download — start this first, it's the
  slowest step).
- A free Apple ID (the same one used for iCloud/the App Store is fine).
- An iPhone, and a cable to connect it to the Mac.
- This repo cloned onto that Mac, and [Flutter](https://docs.flutter.dev/get-started/install/macos)
  installed there — matching version `3.47.0` (stable channel) is what
  this project's CI builds with; run `flutter --version` to check
  whatever's already installed, or install fresh if Flutter isn't there
  yet.

## What's expected to work vs. what's genuinely untested

Being upfront about this so testing feedback is useful, not just "it's
broken" reports for things that were never claimed to work yet:

- **Should work**: GPS trip recording, the whole UI/theme, vehicle
  management, driving-behavior stats, phone lean-angle tracking (uses
  the accelerometer, no special permission on iOS either), the
  territory map, leaderboard/friends, guest mode (no sign-in needed at
  all to try the app).
- **Untested, likely works, worth reporting on specifically**:
  Bluetooth (Kawasaki Rideology connector — `flutter_blue_plus` supports
  iOS, but this is its first real-device test), and recording a trip
  with the phone locked/backgrounded (iOS's background-location model
  is different from Android's, and `ios/Runner/Info.plist` has never
  been verified against a real device — see the comments in
  `trip/location_recorder.dart`'s `_buildLocationSettings`).
- **Won't work, not a bug**: music logging (the "now playing" readout
  and a trip's Soundtrack section). That feature is built entirely on
  an Android-only mechanism (Spotify's `com.spotify.music.metadatachanged`
  broadcast — see `docs/ROADMAP.md`) with no iOS equivalent implemented.
  It'll just silently do nothing on iOS, same as it does on Android
  without Spotify's broadcast setting turned on.
- **Won't work unless you also do the Google Sign-In iOS setup below**:
  Google sign-in specifically. Guest mode and email sign-in don't need
  any of this.

## 1. One-time signing setup, in Xcode

This part has to happen in Xcode's UI once — after this, everyday builds
can happen from Terminal instead.

1. `cd apps/mobile && flutter pub get` — resolves Dart packages and
   generates `ios/Podfile` (CocoaPods manages this project's iOS native
   dependencies; if `pod` isn't installed, `flutter pub get` will say so
   — install it with `sudo gem install cocoapods` and try again).
2. Open `ios/Runner.xcworkspace` in Xcode — **not** `Runner.xcodeproj`;
   opening the `.xcodeproj` directly skips CocoaPods' dependencies and
   the build will fail.
3. In Xcode's left sidebar, select the **Runner** project, then the
   **Runner** target, then the **Signing & Capabilities** tab.
4. Check **Automatically manage signing**. Under **Team**, pick your
   Apple ID — if it's not listed, click "Add an Account…" and sign in;
   Xcode adds it as a free "Personal Team" with no extra steps.
5. Plug the iPhone in. If it's the first time this Mac has seen this
   phone, tap **Trust This Computer** on the phone when prompted.

## 2. Run it

From Terminal (simpler than Xcode's Run button for passing the same
`--dart-define` flags Android builds already use):

```bash
cd apps/mobile
flutter devices   # confirm the iPhone shows up in the list
flutter run --release \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Leave off every `--dart-define` entirely to still test the app — guest
mode (no sign-in) works with zero configuration. See
`docs/AUTH_SETUP.md` for what those three values are and where they
come from; add `--dart-define=GOOGLE_IOS_CLIENT_ID=...` too (and fill in
`ios/Runner/Info.plist`'s placeholder, both documented there) only if
you want to test Google sign-in specifically.

The first build compiles everything from scratch and can take a while.
Once it finishes, the app installs and launches automatically.

## 3. Trust the developer certificate (once)

The very first launch will likely fail with an "Untrusted Developer"
alert on the phone instead of opening. On the iPhone: **Settings →
General → VPN & Device Management**, tap the developer profile under
"Developer App", tap **Trust**. Re-run `flutter run` (or just reopen the
app from the home screen) — it should launch normally from here on.

## 4. Keeping it running past 7 days

Free-tier signing expires weekly. When the app stops opening after about
a week, that's why — no data is lost, just plug the phone back into the
Mac and run `flutter run --release` (with the same flags as before)
again to refresh it.

## Reporting back

Logs land in the app's own Logs screen (Account tab → the article/log
icon in the top-right) the same way they do on Android — screenshotting
or copying that is more useful than "it crashed," especially for the
untested items above (BLE, backgrounded recording).
