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
- `sharedBoards/{boardId}/places/{placeId}/ratings/{uid}` — one member's rating
  (`lib/models/place_rating.dart`): `{uid, placeId, displayName, photoUrl?, score: 1..10 int,
  notes?: ≤1000 chars, updatedAt}`. Doc id = the rater's uid, so the rules check ownership
  directly. Any member (viewers too) reads all of a board's ratings; each writes/deletes only
  their own. `score` is required — clearing your stars deletes the doc, remark included.
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
invalidates all earlier links. Removing a member also resets the invite code in the same write
(`SharedBoardStore.removeMember` → `SharedBoardRepository.removeMemberResetLink`), so the
removed member's copy of the link stops working immediately — anyone else still on the board
needs the new link.

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

## Place detail

Opening a place from a shared board (any role, including the owner) shows
`PlaceDetailSheet` in read-only mode (`PlaceDetailSource.sharedBoard(board, role)`,
set by `lib/screens/boards_screen.dart`'s row `onTap`): header photo from `photoUrls`
only, name, read-only category/sub-type chips, area, description, the **Ratings / 評分**
section, "Open in Google Maps", and "Save to my places" (same dedupe as the Boards
tab's row action, `SharedBoardStore.isSaved`/`saveToMyPlaces`). No favourite toggle,
My review editor, photo controls, area/type/category edit, or "Add to board" — those
act on the user's own Saved/Photo stores, and a shared copy keeps the owner's own
place id, so the personal widgets' usual store lookups by id would leak the owner's
private data to every member. Editing the shared copy's fields themselves (for
owner/editor) is still out of scope.

### Ratings

`_SharedRatingsSection` (in `place_detail_sheet.dart`) subscribes once to
`SharedBoardStore.watchRatings(boardId, placeId)`:

- **Your rating** — `ScoreStars` + the remark box (`_RemarkBox`, the same widget as
  My review's remark), saved via `SharedBoardStore.setMyRating` (null score → delete).
  The remark box is disabled with "Rate first to add a remark" until you have a score.
- Below it, every **other current member's** rating, read-only: avatar (photo or
  initial), name (live `memberNames`, else the doc's `displayName`), an "Owner" tag,
  a `ScoreBadge` and the remark. Ratings by uids no longer in `members` are hidden
  (a removed member can't delete theirs any more).
- The owner's `myScore`/`myNotes` baked into the copy (`includeOwnerNotes`) show as the
  owner's entry until the owner saves a real rating — to other members only.
- "Avg 7.5 · 3 ratings" once there are 2+ scores (yours included); otherwise
  "No one else has rated this yet" when nobody else has.

## Follow-ups

- Shared boards' places don't appear on the map (only your own Saved places do).
- The owner's later edits to their own Saved place don't sync to the shared copy.
- Editors can't edit a shared place's own fields (name/score/notes/type) yet — only
  add/remove places and sections. The board picker (add place → board) lists personal
  boards only.
- Ratings aren't cascaded: removing a place from a board or deleting the board leaves its
  `ratings` docs behind (only their authors could delete them, and after a board delete
  nobody can read them). Re-adding a place with the same id brings its old ratings back.
  A Cloud Function (or owner delete rights on ratings) would be needed to clean up.
- Ratings aren't shown on the Boards tab rows or the map yet (only on the place page).
