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

Only use the minimum tools needed. Do not invoke browser, web-fetch, MCP server tools,
or external API calls unless the user explicitly asks. Prefer local file tools.

Allowed by default: read, write, search, terminal (when needed), git.
Require explicit request: browser, web-fetch, MCP, external APIs.

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
