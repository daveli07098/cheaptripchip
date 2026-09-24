# Claude Code Instructions

## Project Context

cheaptripchip — mobile-first Flutter app that saves scattered Instagram/TikTok travel finds
into map-based plans. Share a post into the app → Gemini extracts the place → geocode →
it appears on the map, in the Saved feed, and on Boards. iOS/Android are the targets;
the web build is a preview only.

**Stack:** Flutter (Dart `^3.11`, Material 3), `flutter_map` + `latlong2` (OSM tiles),
`receive_sharing_intent` / `share_plus`, `shared_preferences`, Firebase (Auth with Google
sign-in + Cloud Firestore), `http` for Gemini and geocoding.

**Layout:**

- `lib/screens/` — `home_shell` (tabs), `map_screen`, `feed_screen`, `boards_screen`,
  `place_detail_sheet`, `account_sheet`
- `lib/widgets/` — `place_list_sheet` (persistent map sheet), `marker_clustering`, `map_pin`,
  `place_card`, `account_button`
- `lib/data/` — `repositories.dart` (`PlaceRepository`/`BoardRepository` interfaces),
  `local_repositories.dart` (guest mode), `firestore_repositories.dart` (signed in),
  `place_store` / `board_store` on top of them
- `lib/services/` — `gemini_service`, `geocoding_service`, `place_extractor`, `auth_service`
- `lib/theme/` — `app_theme` (incl. map tile URL), `theme_controller` (light/dark, persisted)
- `test/` — unit tests for JSON models, stores, and the "New finds" board

**Run / test:**

- Secrets come from git-ignored `env/dev.json` (copy `env/dev.example.json`):
  `flutter run --dart-define-from-file=env/dev.json`. Keys: `GEMINI_API_KEY`,
  optional `GEMINI_BASE_URL`, `MAP_TILE_URL`. VS Code passes this via `.vscode/settings.json`.
- `flutter test`, `flutter analyze`, `dart format lib test`.
- After `flutter pub add` of a plugin, run `flutter clean` before a web build — a stale
  plugin registrant otherwise causes `MissingPluginException`.

**Conventions:**

- Emoji is the category marker everywhere (pins, chips, cards); wrap every emoji in a
  `Semantics` label.
- Data access goes through the repository interfaces — never call Firestore from screens.
- Guest mode is the default until Firebase is configured (`docs/firebase-setup.md`);
  guest data is never uploaded on sign-in.
- Local repositories emit via `Stream.multi` with a microtask hop — in store tests,
  `await Future<void>.delayed(Duration.zero)` after a mutation.
- Never commit keys: not in `.vscode/`, not in `lib/`. `build/web` embeds the Gemini key —
  never share it.

## Session Wrap — Changelog Workflow

After any non-trivial session, run the session-wrap workflow:

1. Scan the session for changes or findings worth preserving.
2. Stage and commit all source changes with a conventional commit message.
3. Create `docs/<topic>.md` if the procedure/finding should be reusable.
4. Update `CHANGELOG.md` (Keep a Changelog format) with what happened.

**Trigger phrases (run without asking):** "wrap up", "commit findings", "save and commit",
"update changelog", "log our changes", "write up what we did", "commit the fix".

## Git Conventions

- Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`
- One logical change per commit
- Push only when user explicitly asks

## Tool Restrictions

Only use the minimum tools needed. Prefer local file tools.

Allowed by default: read, write, search, terminal (when needed), git,
and the `chrome-devtools` MCP server (`mcp__chrome-devtools__*`).
Require explicit request: web-fetch, other MCP servers, external APIs.

### Chrome DevTools MCP

Pre-authorized for this repo — use it without asking when it is the right tool:

- Opening UI/design references the user links (Threads, Instagram, sites that are
  JS-rendered or login-walled, where plain web-fetch returns a shell page).
- Inspecting a running Flutter web build (`flutter run -d chrome`) — console errors,
  network calls, layout, screenshots.

Rules:

- It drives the user's real, logged-in Chrome. Open new tabs; never close, navigate
  away from, or interact with tabs you did not open.
- Read-only by default: navigate, snapshot, screenshot, read console/network.
  Never log in, submit forms, post, click "buy"/"delete", or take any action that
  writes to a third-party account without explicit confirmation.
- Never paste secrets or key material into a page.
- Screenshot/snapshot rather than dumping full page HTML into context.

## Safety

- Never `git push --force` without confirmation
- Never delete files or drop tables without confirmation

## Knowledge Vault

This repo shares the Obsidian collaboration vault at `~/git/obsidian-ai-collab-vault/`.

All routing rules (where to save research, drafts, fixes, memory, deliverables) are defined
**once** in the vault. Read and follow that contract — do not duplicate it here:

→ `~/git/obsidian-ai-collab-vault/_integration/agent-guide.md`

Set `project:` frontmatter to this repo's name on any note you save to the vault.
Confirm each save with one line: `Saved to vault: <relative-path>`.
