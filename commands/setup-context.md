---
description: FRESH apps only. Set up a minimal, indexed project context (CLAUDE.md, settings, a few rules) and a short spec for a brand-new app. Refuses to run on an existing repo. No app code.
argument-hint: [what the app does, and the stack if you know it]
---

Set up the project context for a brand-new application, before any feature code exists. Use this command ONLY for a fresh application. The app: $ARGUMENTS

Principles: context is small, indexed, and split by purpose. Every fact lives in exactly one file. Start minimal and grow only when a real need appears.

Constraints: use paths relative to the repo root. Never commit. Never push. Never put secrets (keys, tokens, passwords, connection strings) in any file or output; document HOW secrets are provided, never the values. Ask questions only if the goal or stack is missing or ambiguous: one short batch, then proceed.

## STEP 0 (always first): refuse on an existing repo
Before creating or changing anything, check whether this is a fresh application. It is NOT fresh if ANY of these exist:
- source code: a `src/`, `app/` or `lib/` folder with files, or any code files beyond a trivial hello-world
- project or build files: `*.sln`, `*.csproj`, `package.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle` or similar
- existing context: a `CLAUDE.md`, a `System-Context/` folder or a `.claude/` folder
Ignore these when deciding: `.git`, `README`, `LICENSE`, `.gitignore`, and editor folders like `.vs/` or `.vscode/`.

If the repo is NOT fresh: STOP. Create and change nothing. Reply with the list of what you found, and tell the user this command is for brand-new applications only. For an existing repo they should instead: run `/sync-context` to organize memory (it will create `System-Context/`), then ask Claude for the change directly and run `/sync-context` at the end of each session.

If the repo is fresh:
- If this is not a git repo, run `git init`. Never work on `main`/`master`: create and switch to branch `context-setup`.

## STEP 1: write the spec
Create `System-Context/design/spec.md` (under ~60 lines): goal, target users, must-have features, explicit non-goals, constraints (platform, budget, deadlines), open questions. Mark every assumption you made as "ASSUMPTION".

## STEP 2: create the minimal context
Create only these, and only with real content for THIS app:

```
CLAUDE.md                  overview, stack, exact build/run/test/lint commands, folder map,
                           one-line rules linking to System-Context/rules/. Under ~100 lines.
.claude/settings.json      shared permissions (commit it)
System-Context/rules/      1-2 files to start (e.g. code-style.md, testing.md), each under ~5 KB,
                           written as short checkable statements (do / never do)
.gitignore                 CLAUDE.local.md, .claude/settings.local.json, .env*, plus the stack's usual ignores
```

`settings.json` permissions:
- allow: the build, test, and lint commands for this stack
- deny: reading `.env*`, secrets folders, and anything outside the repo; also deny destructive commands (`rm -rf`, force push, `git push`)
- deny (databases and secrets): `sqlcmd*`, `sqlpackage*`, `psql*`, `mysql*`, `mongosh*`, `dotnet ef database*`, `dotnet user-secrets*`, reading the user-secrets folder (`~/AppData/Roaming/Microsoft/UserSecrets/**`) and any `~/.aws`, `~/.ssh` or similar credential folders. Include only the ones that fit the stack, but always the secrets ones.
- ask (never auto-allow): the commands that run the app or the tests (e.g. `dotnet run*`, `dotnet test*`, `npm run*`, `npm test*`), because they load local secrets and may reach a real database.
- Permissions are the real guardrail. Add a PreToolUse Bash hook only as an extra layer, and only if the app needs one (it must be executable and registered in `settings.json`).

## Database rule (if the app uses a database)
Write `System-Context/rules/database.md` (a few lines, do / never do):
- Claude only ever touches a disposable local Docker database defined in `docker-compose.yml` (a throwaway password, committed). Its connection string lives in `appsettings.Development.json` or the stack's equivalent.
- Never query, migrate or seed any other database. Never run SQL against a real server. If a task needs real data or a real server, stop and ask the user.
- Never read, print or ask for secrets. The user supplies real connection strings themselves (user-secrets, environment variables) outside Claude's reach.
- Create `docker-compose.yml` for the database when the app first needs one, and say in `CLAUDE.md` how to start and reset it.
Add a one-line pointer to this file in `CLAUDE.md`.

## Secrets rule (always)
Write `System-Context/rules/secrets.md` (a few lines, do / never do):
- Never read, print, ask for or write passwords, keys, tokens or connection strings with real credentials. Settings that need one stay blank in committed files (`appsettings.json` etc.); the user sets real values with `dotnet user-secrets` or environment variables.
- If a tool is blocked with "secret-guard", do not work around it: tell the user which file was flagged and ask them to move the value out.
- If the user pastes a secret into the chat, say it must be rotated.
Add a one-line pointer in `CLAUDE.md`.
Also create `.claude/secret-guard.allow` with only a comment line, plus any throwaway values you commit on purpose (e.g. the Docker dev DB password), one per line.
Check whether `~/.claude/hooks/secret-guard.ps1` exists (existence only, do not read it). If it does not, tell the user in Step 3 to install the secret-guard hook (see `hooks/secret-guard/README.md` in the repository these commands came from).

Do NOT create yet: agents, skills, commands, hooks, `.mcp.json`, `api-conventions.md`, or any file that would hold guesses. They are added later, only when a real need shows up (see GROWING THE CONTEXT).

Rules live ONLY in `System-Context/rules/` (never `docs/rules/` or `.claude/rules/`). Create only `System-Context/design/` and `System-Context/rules/` now; do not create `INDEX.md` or `sessions/`: `/sync-context` creates them. If the repo already uses "sync-context" (`System-Context/INDEX.md`, `System-Context/sessions/latest.md`), add `@System-Context/sessions/latest.md` to `CLAUDE.md`, note that `/sync-context` maintains `System-Context/`, and add index lines for the new files (`design/spec.md` and each rule file).

## STEP 3: STOP for approval
Show the user: whether the secret-guard hook is installed, the folder tree you created, one line per rule file, the spec's assumptions, and the stack. Then STOP and wait. Do not write app code. Tell the user to review, commit, then build the app by asking Claude directly from the spec, and run `/sync-context` at the end of each session (the first run creates the index and session notes).

## GROWING THE CONTEXT (applies to all later work)
- A repeated convention becomes a line in an existing file in `System-Context/rules/` or a new rule file there, plus a one-line pointer in `CLAUDE.md`. Never grow `CLAUDE.md` into a long document.
- A repeated workflow becomes a command or skill. A recurring review/audit role becomes an agent.
- A decision future sessions need (why X over Y, a constraint, a gotcha) goes in the single file that covers it, or `System-Context/design/decisions.md`.
