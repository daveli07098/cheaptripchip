# Claude Code Instructions

## Project Context

[Describe the project, tech stack, and any important conventions here.]

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
