# Setting up login (Google + email)

Login needs a real backend to validate against — there's no way around that
for either Google or email sign-in. This project uses
[Supabase](https://supabase.com) for that: it's open-source and
self-hostable (matching this project's whole premise), but the easiest way
to get started is their free hosted tier, which is what these steps use.
Self-hosting Supabase instead is possible or reasonable long term but out of scope here.

Nothing below is optional if you want login to work — the app is built to
fail loudly with setup instructions rather than crash when these aren't
configured yet (see `auth/supabase_not_configured_screen.dart`), so you'll
know immediately if a step was missed.

## What you'll end up with

Three values, none of them secret in the "don't share this" sense —
they're all meant to be embedded in a shipped app:

| Value | Where it's used |
|---|---|
| `SUPABASE_URL` | Your project's API URL |
| `SUPABASE_ANON_KEY` | Public/anon key — safe to embed in a client app by design |
| `GOOGLE_WEB_CLIENT_ID` | Identifies your app to Google's OAuth for the sign-in flow |

The one value that **is** actually secret — the Google OAuth **client
secret** — never goes into the app or into git. It's typed once into the
Supabase dashboard and stays there.

## 1. Create a Supabase project

1. Sign up / log in at [supabase.com](https://supabase.com), create a new
   project (any name/region/password — the DB password isn't used by this
   app yet since trips are stored locally on-device for now, see
   `docs/ROADMAP.md`).
2. Once it's provisioned: **Project Settings → API**. Copy:
   - **Project URL** → this is `SUPABASE_URL`.
   - **anon / public key** (Supabase's newer dashboards may call this
     "publishable key") → this is `SUPABASE_ANON_KEY`.

## 2. Set up Google OAuth (Google Cloud Console)

1. Go to [console.cloud.google.com](https://console.cloud.google.com),
   create a project (or reuse one).
2. **APIs & Services → OAuth consent screen**: set it up as "External",
   fill in the required fields. "Testing" publishing status is fine for
   personal use — you don't need to submit it for Google verification.
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**,
   twice:
   - **Type: Web application.** Name it anything. No redirect URIs needed
     for this flow. Save it — its **Client ID** is `GOOGLE_WEB_CLIENT_ID`,
     and its **Client Secret** goes into Supabase in the next step (nowhere
     else).
   - **Type: Android.** Package name: `co.opentrip.opentrip_mobile`. SHA-1
     fingerprint: run this and copy the `SHA1:` line —
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
     ```
     (That's the debug keystore Flutter signs release-without-your-own-key
     builds with — the same one used for the APKs built so far. If you
     later set up your own release signing key, you'll need to add that
     key's SHA-1 here too.)
     This Android client's ID is never referenced in code — Google's SDK
     finds it automatically via the package name + SHA-1 match.
4. Back in **Supabase Dashboard → Authentication → Sign In / Providers →
   Google**: enable it, paste the **Web** client's Client ID and Client
   Secret (not the Android one).

## 3. Email sign-in

Nothing extra to configure — Supabase's email provider is on by default
and `AuthService.sendEmailCode` (`signInWithOtp`) sends a 6-digit code
using Supabase's built-in mailer. That mailer is rate-limited on the free
tier (fine for personal testing; if you hit limits, Project Settings →
Auth → SMTP Settings lets you plug in your own mail provider).

## 4. Build with these values

```bash
cd apps/mobile
flutter build apk --release --split-per-abi \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Or for `flutter run` during development, the same three `--dart-define`
flags work.

## Want me to build it instead of you?

If you'd rather I produce the APK: paste the three values above into the
chat (project URL, anon/publishable key, Google Web client ID) — none of
them are secrets, they're designed to ship inside a client app. The one
value you should never paste anywhere but the Supabase dashboard is the
Google **Client Secret**.
