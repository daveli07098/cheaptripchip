# Shared boards

Collaborative boards with roles (owner / editor / viewer). Signed-in only.

## Data model (Firestore)

- `sharedBoards/{boardId}` — `{ownerId, ownerName, name, emoji, sections:[{title, placeIds}],
  members:{uid: 'owner'|'editor'|'viewer'}, memberIds:[uid], memberNames:{uid: name},
  linkRole: 'viewer'|'editor'|null, inviteCode, includeOwnerNotes, joinCode?, createdAt, updatedAt}`.
  `memberIds` mirrors `members`' keys so the Boards tab can query
  `where('memberIds', arrayContains: uid)` (map keys aren't queryable).
- `sharedBoards/{boardId}/places/{placeId}` — `Place.toJson` copies (`sharedCopyOf`: score,
  notes, favourite dropped unless `includeOwnerNotes`; the photo marker always dropped).
- Code: `lib/models/shared_board.dart` (model, `BoardRole`, `BoardPermissions` — the UI's
  single source of truth for edit affordances), `lib/data/shared_board_repository.dart`
  (+ `firestore_shared_board_repository.dart`), `lib/data/shared_board_store.dart`,
  `lib/widgets/sharing_sheet.dart`, `lib/widgets/board_invite_flow.dart`,
  `lib/services/board_invite_link.dart`.

## Links and joining

`https://cheaptripchip-api.vercel.app/b/{id}?c={inviteCode}` (Android App Link; otherwise the
server page `server/lib/board_page.ts` opens `cheaptripchip://board/{id}?c=...`). Joining is a
**blind update** — a non-member can't read the board, but update rules still see
`resource.data`. The client doesn't know the link's role, so it tries `editor`, then `viewer`;
the rules accept only `members.<uid> == linkRole` with `joinCode == inviteCode`.

Known trade-off: every member can read `inviteCode`, so anyone on the board can forward a
working link (and with an editor link, a viewer could leave and rejoin as editor). "Reset link"
invalidates all earlier links. Removing a member doesn't revoke the link either — while it's on
they can rejoin, so the remove dialog tells the owner to reset it.

## Rules tests

```
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$HOME/.npm-global/bin:$PATH"
cd rules-test && npm install && npm run test:emulator
```

Runs `firebase emulators:exec --only firestore --project demo-cheaptripchip` (firebase-tools
at `~/.npm-global/bin/firebase`; needs Java 21 — Android Studio's JBR works).

## Deploy

1. `firebase deploy --only firestore:rules --project cheaptripchip-app`
2. `cd server && vercel --prod` (adds `/b/:id` and `/.well-known/assetlinks.json`).
3. Check `curl -s https://cheaptripchip-api.vercel.app/.well-known/assetlinks.json` and
   `adb shell pm verify-app-links --re-verify com.cheaptripchip.cheaptripchip`.

`assetlinks.json` lists only the **debug** keystore's SHA-256 — add the release key's
fingerprint before shipping a release build. iOS universal links need an Apple team id.

## Follow-ups

- Shared boards' places don't appear on the map (only your own Saved places do).
- The owner's later edits to their own Saved place don't sync to the shared copy.
- Place detail editing (score/notes/type) only affects your own Saved places; editors can't
  edit a shared place's fields yet. The board picker (add place → board) lists personal
  boards only.
