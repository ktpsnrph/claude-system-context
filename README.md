# claude-system-context

**Project memory for [Claude Code](https://claude.com/claude-code) that lives in your repo, stays small, and you can read.**

Slash commands and safety hooks that give every project a `System-Context/` folder: an index, a few small topic files, and a note of what happened last session. Claude reads the index, opens only the file it needs, and picks up where you left off. You review every change in `git diff`, like code.

```
your-repo/
  CLAUDE.md                     short: commands, folder map, one-line pointers
  System-Context/
    INDEX.md                    one line per file: path, what it holds, keywords
    sessions/latest.md          what was built, decided, found and left open last time
    rules/                      conventions that are easy to break
    design/                     spec, plan, decisions and why
    env/                        how to run, build, deploy (how secrets are provided, never the values)
    history/                    past fixes, read only when the same bug comes back
    Quality-Assurance-Results/  reports from /qa
```

## Why use it

Claude Code starts each session knowing nothing about your project except what you load into it. The usual fixes run into trouble over time:

- **One big `CLAUDE.md`** is loaded in full on every request. It grows, goes stale, and buries the rule that mattered under a hundred that didn't.
- **Re-explaining every session** costs time, and the decision you made last Tuesday (and why) is lost.
- **Hidden memory** you can't easily read or correct means you don't know what Claude "remembers", and your teammates can't see it.

claude-system-context fixes this with a few plain rules:

| | What you get |
|---|---|
| **Small and indexed** | `CLAUDE.md` stays short. Everything else sits in files under ~5 KB, listed in `INDEX.md` with keywords. Claude reads the index and opens one matching file, not the whole folder. |
| **Every fact in one place** | Before saving a fact, Claude searches the index and updates the file that covers it. No duplicates drifting apart. Large files are trimmed or split by topic. |
| **Continuity between sessions** | `/sync-context` at the end of a session writes `sessions/latest.md` (Built, Decided, Findings, Open). The next session loads it automatically. |
| **Survives skipped sessions** | Forgot to sync? The next run reads the git history since the last summary and fills the gap, clearly marked "Recovered from git history". |
| **In git, reviewed like code** | It's plain markdown in your repo. You see every change in a diff, fix what's wrong, and teammates get the same memory on `git pull`. |
| **Team-aware** | It runs `git fetch` first and merges onto teammates' changes instead of overwriting them. |
| **You stay in control** | No command commits, pushes, or edits source code. They work on a branch, never `main`, and stop for your review. |
| **Safe by default** | New projects get `settings.json` deny rules for `.env*`, secrets folders, `git push` and production databases. Two optional hooks keep secrets and other repos away from Claude. |
| **Works in Obsidian** | `System-Context/` is also an Obsidian vault. Drop a note in `_inbox/` and the next sync files it in the right place. |
| **Nothing to run** | Just markdown prompts and (optionally) two PowerShell scripts. No server, database, API key or package to install. |

## How it compares

These tools solve different problems and can be used together. Check each tool's own docs for current details.

| | `/init` (built into Claude Code) | Claude Code auto memory | Auto-capture plugins (e.g. claude-mem) | **claude-system-context** |
|---|---|---|---|---|
| What it does | Scans the codebase once and writes a `CLAUDE.md` | Claude saves notes it thinks are worth keeping | Records sessions automatically and injects summaries into later sessions | Keeps an indexed, topic-split memory and a session log, updated when you run `/sync-context` |
| Where it lives | `CLAUDE.md` in the repo | Your user profile, per machine | A local store outside the repo | `System-Context/` in the repo |
| Kept up to date | No, it's a one-time snapshot | As Claude decides | Automatically | Each time you run `/sync-context` |
| Shared with your team | Yes, via git | No | No | Yes, via git |
| Reviewable | Yes | You can open the files | Through the tool | Yes, every change is a git diff |
| Loaded per request | The whole file | An index plus what's relevant | Summaries the tool selects | `CLAUDE.md` + last session; one topic file when needed |
| Extra software | None | None | Yes (the plugin and its services) | None |

**Already ran `/init`?** Keep it. The first `/sync-context` on an existing repo reads your `CLAUDE.md`, moves each part into the right `System-Context/` file, and shrinks `CLAUDE.md` to pointers. Nothing is summarized away: every fact lands in exactly one file.

**The trade-off:** memory updates when you run `/sync-context`, not on every action. That's on purpose. Nothing gets saved that you didn't see in a diff.

## What's inside

| Folder | Contents |
|---|---|
| [`commands/`](commands) | Slash commands: `/setup-context`, `/sync-context`, `/qa` |
| [`hooks/secret-guard/`](hooks/secret-guard) | Keeps passwords, keys and tokens away from Claude, and warns you when one slips through |
| [`hooks/repo-fence/`](hooks/repo-fence) | Keeps Claude inside the current repo plus what you explicitly share |

### The commands

| Command | When to use it | Edits source code? |
|---|---|---|
| `/setup-context <app description>` | **Brand-new apps only.** Writes a short spec (`System-Context/design/spec.md`) and a minimal context: `CLAUDE.md`, `.claude/settings.json` with safe permissions, and one or two rules. Then it stops for your review. It refuses to run on a repo that already has code or context. | No |
| `/sync-context` | **End of every session**, or once to organize an existing repo. Maintains `System-Context/` and a small `CLAUDE.md`. | No (memory files only) |
| `/qa [url-or-focus] [functions\|design\|responsive\|security\|all]` | After building. A read-only QA pass that saves a report with numbered issues (`QA-001`, ...) so you can say "fix QA-003". | No (the report only) |

None of them commit, push, or copy secrets into files.

## Requirements

- Claude Code and `git`. The commands work on any OS.
- The hooks are PowerShell and **Windows only** (tested on Windows 11). They are optional.
- The examples lean towards .NET (`dotnet user-secrets`, `appsettings.json`). The ideas carry over to any stack.
- Optional: [Obsidian](https://obsidian.md) to browse `System-Context/`, and graphify, which `/sync-context` can refresh if you already use it. Neither is included or needed.

## Quick start

```bash
git clone https://github.com/Ok4jjj/claude-system-context.git
cd claude-system-context
```

**Install the commands** directly in `~/.claude/commands/`. Copy them flat, not in a subfolder: the commands refer to each other by name, and a subfolder renames them to `/<folder>:sync-context`.

```bash
mkdir -p ~/.claude/commands && cp commands/*.md ~/.claude/commands/
```

```powershell
New-Item -ItemType Directory -Force $env:USERPROFILE\.claude\commands | Out-Null
Copy-Item commands\*.md $env:USERPROFILE\.claude\commands\
```

Restart Claude Code and type `/` to check they appear. To install for one repo only, use `<repo>/.claude/commands/` instead.

**Install the hooks (optional, Windows)** once per machine. Follow [secret-guard](hooks/secret-guard/README.md) and [repo-fence](hooks/repo-fence/README.md). Each guide has a self-test; run it before relying on the hook. They are scripts that run on your machine, so read them first.

## Typical workflow

**Existing repo**

1. `/sync-context` to organize what's there into `System-Context/`. Review `git diff`, then commit.
2. Check that `CLAUDE.md` has the exact build, run and test commands.
3. Ask Claude for changes as usual.
4. `/sync-context` at the end of each session. Review and commit.

**Brand-new app**

1. `/setup-context a habit tracker with Next.js and Postgres`
2. Review the spec and context. Commit.
3. Ask Claude to plan the build from the spec into `System-Context/design/plan.md`. Build one task at a time.
4. `/qa` when a feature works, then fix issues by ID.
5. `/sync-context` at the end of each session. Review and commit.

If you forget step 4/5, Claude reminds you: `CLAUDE.md` tells it to flag when `sessions/latest.md` is older than the last commit.

## Design rules

- Context is designed before feature code, and kept small and indexed.
- Every fact lives in exactly one file.
- Rules live only in `System-Context/rules/`. `CLAUDE.md` holds one-line pointers, never rule text.
- Everything in `System-Context/` is listed in `INDEX.md`. Claude reads only the file that matches the task.
- `settings.json` permissions are the real guardrail. Hooks are an extra layer.
- Grow the context only on real need: agents, skills, commands, hooks and `.mcp.json` come later, not up front.

## Troubleshooting

| Problem | Fix |
|---|---|
| Command not in the `/` list | The file must be directly in `~/.claude/commands/` and named exactly (not `sync-context.md.txt`). Restart Claude Code. |
| It shows up as `/<folder>:sync-context` | The file is in a subfolder. Move it up one level. |
| Not sure what got loaded | Run `/help` inside Claude Code. |
| Command loads but behaves oddly | Line 1 must be `---`, then `description:`, then a closing `---`. |

## Status and limits

- This is a personal setup shared as-is, with no support promised. Issues and pull requests are welcome.
- The commands are instructions to Claude, not code. Claude follows them well, but review the diff before you commit.
- The hooks are pattern-based safety nets, not sandboxes. Each guide lists what they miss. Treat any secret that reached Claude as exposed and rotate it.

Claude Code is a product of Anthropic. This project is independent and not affiliated with Anthropic.

## License

[MIT](LICENSE)
