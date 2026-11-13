# Strand

**A quiet space to understand your sleep.**

Strand reads your nights from Health Connect, turns them into plain-language summaries, and gives your dreams a page of their own.

> **Status:** in active development. Home, Dreams and Insights are wired and working; a number of screens in `lib/ui/screens/` are not yet reachable from navigation and are kept as work in progress.

## Screens

| | |
|---|---|
| **Home** | A greeting, one large number — the time you actually slept — and eight quiet facts about the night: stages, heart rate, time in bed. A figure that was not recorded says *No data* rather than becoming a zero. |
| **Dreams** | A dream journal with an interpretation attached to every entry. A blank full-page writer, not a cramped dialog. |
| **Insights** | Trends across your nights, computed on the device. |
| **Settings** | Profile, health data, account. |

Between them: **Welcome → Health Connect → Account → Sign in**, and nothing at cold start touches the platform's health service, so the app can never block or crash on it while opening.

## Dream interpretation

Write a dream, and Strand can read it back to you.

The interesting part is where it happens. **The Gemini key never leaves Cloudflare.** The app sends two things: your Firebase ID token, and the dream text. The worker validates the token, reads nothing else, stores nothing, and returns the reading once — which then lives in Hive on your phone, beside the entry it belongs to.

The dream is saved **before** the request leaves the device. Losing the network, the worker or the app mid-request costs you nothing but the reading; the words you wrote are already yours.

## Sleep

Strand asks Health Connect for `READ_SLEEP` and nothing else — one permission on the manifest, not ten. The plugin is the only place in the app that knows Health Connect exists; everything above `lib/health/` sees a neutral service interface instead.

Nights are stored locally in Hive and can be published to your account so friends can see them.

## Privacy

- **Sleep records** are stored on the device first. Cloud upload happens only when you are signed in, and only publishes nights for friends to see.
- **Dreams** are sent to your own worker for interpretation and stored locally. The interpretation provider never sees anything except the one dream you asked about, and keeps none of it.
- **Your API keys stay on the server.** Nothing in this repository is a secret; the Gemini key lives in Cloudflare Worker secrets.

## Install

**[Download the APK →](../../releases)**

Android will ask you to allow installs from unknown sources, since this is distributed directly rather than through a store.

## Build from source

```sh
flutter pub get
flutter analyze      # must be clean
flutter test
flutter build apk --release
```

Requires Flutter `>=3.44.0`.

`android/app/google-services.json` holds the Firebase project config (`com.strand.strand`). It is required for the build — the `google-services` Gradle plugin is applied only when the file exists. Regenerate it with `flutterfire configure`.

The Cloudflare workers behind dream interpretation and sleep commentary live in `backend/`. Their URLs are not secrets; their keys are held as Worker secrets and never shipped in an app.

## Tech stack

| | |
|---|---|
| Framework | Flutter / Dart |
| Local storage | Hive |
| Health | Health Connect (`READ_SLEEP` only) |
| Auth & sync | Firebase Auth, Cloud Firestore |
| Interpretation | Cloudflare Worker → Google Gemini (server-side key) |
| Typeface | Inter |

## Project layout

```
lib/
  auth/        sign-in, account creation, the AuthGateway contract
  health/      Health Connect, the sleep controller, analytics, Hive store
  social/      dream interpretation, sleep commentary, cloud sync
  ui/          theme, screens, widgets
  data/        storage and notifications
backend/       Cloudflare Workers
```

Dependencies point downward only. `package:firebase_*` is imported in a handful of files under `auth/` and `social/` and nowhere else.

---

Built by [Samrat](https://github.com/somearts).
