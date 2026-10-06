# Getting the app onto friends' iPhones

Apple doesn't allow installing an app file the way Android does: every
iPhone app has to be signed. There are two ways to get OpenTrip to
testers, and the repo's CI supports both.

| | TestFlight | Free sideload (.ipa) |
|---|---|---|
| Cost | Apple Developer Program, $99/year (yours) | Free |
| What a tester needs | The free TestFlight app and your invite link | A Mac or Windows PC, a cable, their own Apple ID |
| How long an install lasts | 90 days per build | 7 days, then re-install |
| Built by | `.github/workflows/ios-testflight.yml` | the `verify-ios` job in `build-apk.yml` |

Either way, what to expect on iOS (Bluetooth and locked-screen recording
are untested; Spotify music logging is Android-only) is listed in
[`IOS_TESTING_SETUP.md`](IOS_TESTING_SETUP.md#whats-expected-to-work-vs-whats-genuinely-untested).

---

## Option A: TestFlight (one-time setup, then automatic)

After this setup, every push to `main` builds the app, signs it and
uploads it to TestFlight. Testers get the update in the TestFlight app.

### 1. Join the Apple Developer Program

Enroll at <https://developer.apple.com/programs/enroll/> ($99/year).
Approval can take a day or two. Then note your **Team ID**: in
<https://developer.apple.com/account>, under **Membership details**
(10 characters, e.g. `A1B2C3D4E5`).

### 2. Register the app

1. In **Certificates, Identifiers & Profiles → Identifiers**, add an
   **App ID** with Bundle ID `co.opentrip.opentripMobile` (explicit).
   If Apple says it's already taken by someone else, tell whoever
   maintains this repo: the bundle ID has to change in the Xcode
   project.
2. In [App Store Connect](https://appstoreconnect.apple.com) → **Apps →
   + → New App**: platform iOS, any name that's free on the App Store
   (e.g. "OpenTrip Ride Tracker"), the bundle ID above, and any SKU (e.g.
   `opentrip`).

### 3. Create an App Store Connect API key

App Store Connect → **Users and Access → Integrations → App Store Connect
API → Team Keys → +**. Give it the **Admin** role. Admin is needed
because CI lets Xcode create and manage the distribution certificate
for you ("cloud signing"); lower roles can't. Download the `.p8` file
(Apple only lets you download it once) and note the **Key ID** and the
**Issuer ID** shown above the list.

### 4. Add the GitHub secrets

Repo **Settings → Secrets and variables → Actions → New repository
secret**:

| Secret | Value |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | the Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID |
| `APP_STORE_CONNECT_KEY_P8` | the whole contents of the `.p8` file, including the `BEGIN`/`END` lines |
| `APPLE_TEAM_ID` | your Team ID |
| `GOOGLE_IOS_CLIENT_ID` | optional, only for Google sign-in on iPhone (see [`AUTH_SETUP.md`](AUTH_SETUP.md)) |

The existing `SUPABASE_URL` / `SUPABASE_ANON_KEY` /
`GOOGLE_WEB_CLIENT_ID` secrets are reused, so sign-in works like on
Android.

### 5. Run it

**Actions → iOS TestFlight → Run workflow** (or push to `main`). The
build takes about 15 minutes. Apple then processes it for another 5–30
minutes before it shows up under the app's **TestFlight** tab.

### 6. Invite testers

In App Store Connect → your app → **TestFlight**:

- **External testing** (friends): create a group, add the build and
  submit it for **Beta App Review**. The first build of a version takes
  about a day; later builds are usually approved automatically. Under
  **What to Test** / review notes, say the app works without an account
  ("Continue without an account"), and that it uses location in the
  background to record rides. Then turn on **Public Link** and send
  that link. Friends install **TestFlight** from the App Store and open
  the link. Up to 10,000 testers.
- **Internal testing** (no review, instant): only for people you've
  added to your App Store Connect team, up to 100.

Builds expire after 90 days; each new push to `main` uploads a fresh one.

---

## Option B: Free sideload with your own Apple ID

Every build on `main` attaches `OpenTrip-unsigned.ipa` to the
[Latest build](../../releases/tag/latest) release. It isn't signed, so
each tester signs it with their own free Apple ID while installing.

What a friend does:

1. On a computer, download `OpenTrip-unsigned.ipa` from the Latest
   build release.
2. Install [Sideloadly](https://sideloadly.io) (Mac or Windows). On
   Windows it also needs Apple's iTunes and iCloud installed from Apple's
   website, not the Microsoft Store versions. [AltStore](https://altstore.io)
   works too.
3. Connect the iPhone with a cable, unlock it and tap **Trust** on the
   phone.
4. In Sideloadly, drag in the `.ipa`, enter an Apple ID and press
   **Start**. Using a spare Apple ID is fine; it's only used to sign.
5. On the iPhone:
   - Turn on **Settings → Privacy & Security → Developer Mode** (iOS 16
     and later; the phone restarts).
   - Trust the developer under **Settings → General → VPN & Device
     Management**.
   - Open OpenTrip.

Limits of the free route:

- **7-day expiry:** the app stops opening after 7 days. Re-install the
  same way to renew it; recorded trips stay on the phone.
- **3-app limit:** a free Apple ID can have at most 3 sideloaded apps at
  once.
- **No Google sign-in:** sideloading tools usually re-sign under a
  different app ID, which Google's iOS sign-in rejects. Email sign-in
  and guest mode work.
