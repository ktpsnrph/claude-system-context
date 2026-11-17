# repo-fence

Keeps Claude Code inside the repository you are working on, plus whatever you explicitly share.

**Why it exists.** Folder names in a prompt are not an invitation to explore. After `@`-mentioning a few folders of an older repo, Claude went on to read the rest of that repo on its own: controllers, middleware, even `appsettings.json`. repo-fence makes "current repo plus what I share" a rule that is checked before every file tool and shell command, on your machine.

It is a `PreToolUse` and `UserPromptSubmit` hook written in PowerShell. Windows only.

## What is allowed and blocked

| Always allowed | Allowed when you share it | Blocked |
|---|---|---|
| The current project folder | A file or folder you `@`-mention, or write as a full path in a prompt (`@"C:\Work\old\SharedLib/"`, `C:\Work\old\x.cs`). Only that path, for that session only. | Everything else: other repos, the parent folder (`ls ..`), similarly named repos, `cd` into another repo and reading there |
| The temp folder, `~/.claude` (skills, hooks, this project's memory), Windows and Program Files (tools), `~/.nuget`, `~/.dotnet`, npm | Folders listed in `~/.claude/repo-fence.allow` (permanent; one full path per line, `#` for comments) | Other projects' session transcripts in `~/.claude/projects/` |
| | Searching past sessions, when the prompt mentions "past/previous/earlier session", "conversation" or "transcript" | Searching past sessions otherwise |
| Reading the guard's own files with the Read tool | Changing them, when you name the path in a prompt (that session only) | Writing to the guard's own files, or naming them in a shell command: `~/.claude/hooks/`, `~/.claude/settings.json`, `~/.claude/settings.local.json`, `~/.claude/repo-fence.allow`, and the per-session lists in `%TEMP%\claude-repo-fence\`. Without this, one write would switch the fence off. |

When something is blocked, Claude is told that the path is outside the project and was not shared, not to try another way, and to ask you to share it.

## Install

Once per machine; it then applies to every project.

1. Copy `repo-fence.ps1` to `C:\Users\<me>\.claude\hooks\repo-fence.ps1` (create the `hooks` folder).
2. Merge both hooks into `C:\Users\<me>\.claude\settings.json`, next to any existing ones:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob|Bash|PowerShell|mcp__ccd_session_mgmt__search_session_transcripts|mcp__ccd_session_mgmt__export_transcript",
        "hooks": [
          { "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/.claude/hooks/repo-fence.ps1\" -Mode tool" }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/.claude/hooks/repo-fence.ps1\" -Mode prompt" }
        ]
      }
    ]
  }
}
```

If `$HOME` does not resolve in your setup, use the full path, for example `C:/Users/<me>/.claude/hooks/repo-fence.ps1`.

3. Start a new Claude Code session. Hooks load at session start.

**Updating.** Copy the new `repo-fence.ps1` over the old one yourself. Claude is blocked from writing to `~/.claude/hooks/` and `~/.claude/settings.json` unless you name that path in the prompt.

## Test it

1. Run the self-test from the repo copy. Every line should say `PASS`:
   `powershell -NoProfile -ExecutionPolicy Bypass -File hooks\repo-fence\repo-fence.ps1 -Mode selftest`
2. In a new session, ask Claude to run `ls ..`. It should be blocked with `repo-fence: BLOCKED`.
3. `@`-mention a folder of another repo and ask about it. Reading that folder should work; reading a sibling folder should be blocked.

**Status (2026-11-16).** The self-test passes (46 checks, including the checks for the guard's own files). In live sessions, `ls ..` and a command naming `~/.claude/repo-fence.allow` were blocked. I also replayed five recorded sessions of one project (1,189 tool calls): 53 were blocked, nearly all reads of an older repo outside the folders I had shared, plus one search of a whole drive and one false alarm (see Limits). Normal work inside the repo was not blocked.

## Sharing more

- **One session:** `@`-mention it, or write the full path in the prompt ("also look at C:\Work\old\SiblingLib").
- **Always:** add the full path to `~/.claude/repo-fence.allow`.
- **Reset a session's shares:** delete `%TEMP%\claude-repo-fence\`. Shares also end with the session.

## Limits

- **Pattern matching, not a sandbox.** It reads paths out of the command text. It does not see paths built at runtime: variables (`$p`, `$f`), `$(...)`, paths inside a script file Claude runs, or a program that opens files on its own. A determined workaround gets through; the block message tells Claude not to try.
- **Relative names are checked by shape.** After a `cd`, words that look like files or folders (`src/x.cs`, `Program.cs`, `.`, `*.json`) are checked. A file name without an extension and without a slash (`Makefile`, `LICENSE`) is not.
- **A `cd` into the parent of a shared folder is allowed**, so shared folders can be reached by relative name. Listing or reading anything else in that parent is blocked.
- **Guard files are protected by name.** A command that names only a parent folder (`rm -r ~/.claude`) or builds the path from a variable is not caught. Running the installed script's self-test from Claude's shell is blocked too, because the command names `~/.claude/hooks/`; run it from the repo copy, or yourself.
- **False alarms.** A path-like piece of text inside a complicated quoted `sed` or `perl` expression can be read as a real path (one case in 1,189 replayed calls). Claude sees the block and can rewrite the command.
- **Not covered.** Web and MCP tools other than the session-transcript search (a browser can still open `file:///`). Subagents' tool calls are covered only if Claude Code runs hooks for them, which it normally does.
- **Shares come from the prompt text.** A path that appears only in an attached image, or that Claude finds on its own, does not count as shared.
- **It fails open.** If the script crashes, the check is skipped and `repo-fence: internal error` is shown.
- **Speed.** One extra PowerShell start per tool call and per prompt, typically a few hundred milliseconds.
