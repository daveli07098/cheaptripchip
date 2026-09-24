# Firebase setup (Google sign-in + Firestore)

The app runs fine in guest mode with zero Firebase config (`lib/firebase_options.dart`
is a stub that throws, `AuthService.isConfigured` is `false`, all data stays local).
Follow these steps once to turn on sign-in and cross-device sync.

1. **Create/choose the Firebase project.** Firebase console → Add project →
   choose the existing Google Cloud project `1048089107968`, or create a new one.
2. **Enable Google sign-in.** Authentication → Sign-in method → enable the
   Google provider → set a support email.
3. **Install the FlutterFire CLI** (once): `dart pub global activate flutterfire_cli`
4. **Log into Firebase.** `firebase login` is interactive; in Claude Code run
   it as `! firebase login` so it can open a browser. If the `firebase` CLI
   isn't installed: `npm i -g firebase-tools` or `curl -sL https://firebase.tools | bash`.
5. **Generate platform config:**
   ```
   flutterfire configure --project=<project-id> --platforms=android,ios,web
   ```
   This overwrites `lib/firebase_options.dart` with real values, and adds
   `android/app/google-services.json` + the Android Gradle plugin, and
   `ios/Runner/GoogleService-Info.plist`. Commit all of these — the web
   `FirebaseOptions` are public client identifiers, not secrets, and the
   Android/iOS config files are also safe to commit (they gate on Firebase
   project rules, not on being secret).
6. **Android SHA-1.** From the repo root:
   ```
   cd android && ./gradlew signingReport
   ```
   Copy the debug `SHA-1` into Firebase console → Project settings → your
   Android app → Add fingerprint (add the release SHA-1 too once you have a
   release keystore). Re-download `google-services.json` afterwards if it
   changed.
7. **iOS Info.plist keys.** Open the generated `ios/Runner/GoogleService-Info.plist`
   and copy two values into `ios/Runner/Info.plist` (see the comment already
   there). Add `GIDClientID` as a new key:
   ```xml
   <key>GIDClientID</key>
   <string>YOUR_CLIENT_ID_FROM_GoogleService-Info.plist</string>
   ```
   `CFBundleURLTypes` **already exists** (it registers the `cheaptripchip://`
   trip-import scheme). Do not add a second `CFBundleURLTypes` key — a
   duplicate key silently replaces the first and breaks import links. Instead
   add the reversed client id as a second `<dict>` inside the existing array:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLName</key>
       <string>com.cheaptripchip.import</string>
       <key>CFBundleURLSchemes</key>
       <array>
         <string>cheaptripchip</string>
       </array>
     </dict>
     <!-- added for Google Sign-In: -->
     <dict>
       <key>CFBundleURLSchemes</key>
       <array>
         <string>YOUR_REVERSED_CLIENT_ID_FROM_GoogleService-Info.plist</string>
       </array>
     </dict>
   </array>
   ```
8. **Create Firestore.** Firebase console → Firestore Database → Create
   database → production mode → pick a region near Tokyo, e.g.
   `asia-northeast1`.
9. **Deploy the security rules** (already in this repo as `firestore.rules` /
   `firebase.json`):
   ```
   firebase deploy --only firestore:rules
   ```
10. **Authorize the web preview.** Authentication → Settings → Authorized
    domains → add `localhost` (and any other dev host you use).
11. **Verify.** Run the app, tap the account button, sign in with Google. Add
    a find — a document should appear under `users/<uid>/places` in the
    Firestore console.

## How data is scoped

- Signed-in data lives at `users/{uid}/places/{placeId}` and
  `users/{uid}/boards/{boardId}`, readable/writable only by that `uid`
  (enforced by `firestore.rules`).
- Guest (signed-out) data stays on-device only — it is never uploaded, even
  after a later sign-in. This is deliberate, not a bug: signing in switches
  the app to Firestore-backed stores rather than migrating local state.
- The Gemini API key is still bundled client-side
  (`--dart-define-from-file=env/dev.json`, see `lib/services/gemini_service.dart`).
  A Cloud Functions proxy to hide it server-side is the logical next step, and
  requires upgrading the Firebase project to the Blaze (pay-as-you-go) plan.
