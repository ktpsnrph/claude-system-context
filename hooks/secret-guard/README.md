# secret-guard: keep passwords away from Claude Code

Claude cannot "forget" a secret it has read, and anything it reads goes to Anthropic. So this guard runs on **your machine, before Claude sees anything**. It never prints the secret itself.

Requires Windows and PowerShell. The examples use .NET tooling (`dotnet user-secrets`, `appsettings.json`); substitute your stack's equivalent (environment variables, a vault) where it differs.

| Where | What it does |
|---|---|
| Before Claude reads/searches a config file (`appsettings*.json`, `.env*`, `*.config`, docker-compose, key files) | Blocks it if the file has a non-blank password/key/token. Claude is told which file and line, never the value, and is told to ask you to move it to `dotnet user-secrets`. |
| Before Claude writes or edits a file | Blocks it if the new content contains a secret. |
| When you submit a prompt | Blocks the message if it contains a known token format or a connection string with a password. It is not sent. |
| After a tool runs (Bash, PowerShell, Read, Grep, web, MCP) | Cannot hide the output, but **warns you** if it contained a token or a database password, and tells Claude not to repeat it. Your cue to rotate. |
| Deny rules in `settings.json` | Claude Code itself refuses commands that print secrets (`printenv`, `env`, `dotnet user-secrets list`, `Get-ChildItem env:`) and reads of `~/.ssh`, `~/.aws`, `~/.azure` and the user-secrets folder. |
| When you `git commit` (optional) | Blocks the commit if a staged file has a secret. |

## Install once (works for every project)

1. Copy `secret-guard.ps1` to `C:\Users\<me>\.claude\hooks\secret-guard.ps1` (create the `hooks` folder).
2. Add this to `C:\Users\<me>\.claude\settings.json` (merge into an existing `"hooks"` block if you have one):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob|Bash|PowerShell",
        "hooks": [
          { "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/.claude/hooks/secret-guard.ps1\" -Mode tool" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|PowerShell|Read|Grep|WebFetch|mcp__.*",
        "hooks": [
          { "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/.claude/hooks/secret-guard.ps1\" -Mode output" }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$HOME/.claude/hooks/secret-guard.ps1\" -Mode prompt" }
        ]
      }
    ]
  },
  "permissions": {
    "deny": [
      "Bash(printenv)", "Bash(printenv:*)", "Bash(env)", "Bash(set)",
      "Bash(dotnet user-secrets list:*)",
      "PowerShell(Get-ChildItem env:*)", "PowerShell(dir env:*)", "PowerShell(ls env:*)", "PowerShell(gci env:*)",
      "PowerShell(dotnet user-secrets list:*)",
      "Read(~/.ssh/**)", "Read(~/AppData/Roaming/Microsoft/UserSecrets/**)", "Read(~/.aws/**)", "Read(~/.azure/**)"
    ]
  }
}
```
If `$HOME` does not resolve in your setup, use the full path (`C:/Users/<me>/.claude/hooks/secret-guard.ps1`). Merge into existing `"hooks"` and `"permissions"` blocks rather than replacing them.

3. Restart Claude Code and run `/hooks` to confirm all three hooks are listed.

## Test it (do this once on each machine)

**Status (2026-11-17), Windows 11.**
- The self-test passes (38 checks: token formats, secret file names, prompt and output checks).
- Verified in a live Claude Code session: step 2 (a config file holding a fake password was blocked on read) and step 4 (printing a fake connection string raised the warning and the "do not repeat it" instruction to Claude).
- Verified only with a simulated hook call, not typed into the app: step 3 (a prompt containing a fake connection string exits with code 2).
- Reading this repository's own guides and scripts raised no false warnings.

1. Self-test: `powershell -NoProfile -ExecutionPolicy Bypass -File $HOME\.claude\hooks\secret-guard.ps1 -Mode selftest`. Every line should say `PASS`.
2. Real test: in a scratch folder create `appsettings.json` containing `{"Db":{"Password":"fake12345"}}`, start Claude Code there and ask it to read the file. It should be blocked with a "secret-guard: BLOCKED" message.
3. Type a fake connection string as a prompt: `Password=fake12345;` with `Server=db;` in front of it on the same line. It should be blocked and not sent. (Written apart here so reading this guide raises no warning.)
4. Ask Claude to run `echo "Server=db;Pass""word=fake12345;"` (the split word keeps the prompt check from blocking your message; the shell prints it joined). You should see a "secret-guard: WARNING" message after it runs.

If step 2 is not blocked: run `claude --debug`, check that the command path resolves (some setups need `%USERPROFILE%` or a full path instead of `$HOME`), and that PowerShell can run the script.

## Allow list (throwaway values)

A Docker dev database password that you commit on purpose would be flagged. Put it, one literal value per line, in `.claude/secret-guard.allow` in that project (lines starting with `#` are comments). `/setup-context` creates this file.

## Optional: block commits too

Create `.githooks/pre-commit` in the project (no extension), then run `git config core.hooksPath .githooks` once:

```sh
#!/bin/sh
git diff --cached --name-only --diff-filter=ACM | powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/hooks/secret-guard.ps1" -Mode scan
```

For deeper history scanning, add gitleaks as well. It is a separate tool.

## Limits

- It checks config-like files, secret-only files and known token formats (AWS, GitHub, GitLab, Slack, Anthropic, OpenAI, Stripe, Google, npm, Azure storage, private keys). A secret in an unusual file or format can still slip through.
- If a secret reaches Claude any other way (pasted from a screenshot, printed in terminal output), treat it as exposed and **rotate it**. For terminal output it now warns you; for screenshots and attachments it cannot.
- On an unexpected error the guard skips the check and shows you the error instead of locking you out.

The details below spell these out.

### What it does NOT do: commit and push
secret-guard never looks at `git push`, and it does not decide whether Claude may commit. It only blocks a git command when the command itself names a config file that holds a secret (for example `git add appsettings.json`), or when the optional pre-commit hook finds a secret in a staged file.

If Claude could commit but not push, the cause is something else. Check in this order:
1. **Permissions.** `/setup-context` writes `git push` into the `deny` list of the project's `.claude/settings.json` on purpose. Claude cannot push there; push yourself. Remove the deny line only if you really want Claude to push.
2. **The bundled commands.** `/setup-context`, `/sync-context` and `/qa` all say "never commit, never push". Inside those commands Claude refuses by design.
3. **Claude Code's own rules.** Depending on the permission mode, Claude Code asks or refuses before outward-facing actions like a push, even if you asked in chat.
4. **Credentials.** Claude's shell cannot answer a login prompt. If your git host needs a password, token or SSH passphrase, the push fails or hangs. Run `git push` yourself once in a terminal so Git Credential Manager stores the login.
The error text tells you which: "denied" / "permission" = 1-3, "Authentication failed" / "could not read Username" = 4.

### Which files it checks
- **Config-like names:** `appsettings*.json`, `launchSettings.json`, `secrets.json`, `.env*`, `*.env`, `*.config`, `docker-compose*.yml`, `*.tfvars`, `.npmrc`, `.pypirc`, `credentials*`. These get the full checks (password/secret/token/api key with a value, `Password=` in connection strings, npm `_authToken`, JWTs).
- **Secret-only files, blocked whatever is inside:** `*.pem`, `*.pfx`, `*.p12`, `*.key`, `*.ppk`, `*.kdbx`, SSH keys `id_rsa`, `id_dsa`, `id_ecdsa`, `id_ed25519` (not the `.pub` files), `.pgpass`, `.netrc`. Paths starting with `~/` are understood. SSH keys with a custom name (`id_work`, `gitlab_key`) are **not** caught by name; the `Read(~/.ssh/**)` deny rule covers them.
- **Every other file** (`config.json`, `settings.py`, `*.ps1`, source code) is checked only for known token formats: AWS (`AKIA...`), GitHub (`ghp_`, `github_pat_`), GitLab (`glpat-`), Slack (`xox...`), Anthropic (`sk-ant-`), OpenAI (`sk-`, 32+ characters), Stripe live keys (`sk_live_`, `rk_live_`), Google API (`AIza...`), npm (`npm_`), Azure storage (`AccountKey=`), and private-key blocks. A plain `password = "abc"` in those files passes.
- **Formats it still does not know:** JWTs outside config files (left out on purpose, test code is full of them), Azure AD client secrets, database passwords in unusual formats, and any custom or company token format.
- Files over 2 MB are skipped.

### Which actions it sees
- **Tools covered:** Read, Edit, Write, MultiEdit, NotebookEdit, Grep, Glob, Bash, PowerShell. PowerShell was added on 2026-11-16: an older install needs `|PowerShell` added to its `matcher` and the new `secret-guard.ps1` copied over, or `Get-Content appsettings.json` through the PowerShell tool is not checked.
- **Not covered: MCP tools** (browser, Figma, etc.).
- **Bash and PowerShell commands:** it only checks words in the command that are literally a file path. These slip through:
  - wildcards: `cat appsettings*.json`
  - (fixed 2026-11-16) `cd other/folder && cat appsettings.json` is now checked in the folder the command `cd`s into. A `cd` hidden in a variable or script is still not followed.
  - indirect reads: a script that reads the file, `$(...)`, variables, `git show HEAD:appsettings.json`
  - secrets that are not in files: `printenv`, `env`, `dotnet user-secrets list`. The deny rules above now stop the common forms, but not variants (`cmd /c set`, `[Environment]::GetEnvironmentVariables()`, `echo $DB_PASSWORD`).
- **Output is checked, but only after the fact.** If a command prints a secret (app logs, `docker compose config`, an error message with a connection string), Claude has already seen it; the warning only tells you so you can rotate. It looks for known token formats and real connection strings (`Server=<host>;Password=<value>;` or `postgres://user:<value>@host`), not for every possible secret, so a plain `password: abc` in a log is not flagged.

### Your prompts
- Only the text you type is checked, with the same rules as tool output: known token formats, and connection strings that have a server/host and a password (or a database URL with a password). A secret inside an attached image, screenshot or pasted file is not.
- Changed 2026-11-16: the config-file rules are no longer used on prompts. They blocked ordinary sentences (`token: how does refresh work?`, `secret-guard.md: fix the typo`, pasted code like `password = GetPassword()`).
- So a bare `password=abc` or `my db pass is hunter2` passes. Don't type passwords into prompts.

### When it fails
- **It fails open.** If the script crashes (PowerShell missing, bad JSON, a bug), the check is skipped and you see `secret-guard: internal error`. Nothing is blocked.
- **Placeholders and the allow list:** values like `changeme`, `***`, `<your-key>`, `${VAR}`, numbers and `true/false` are ignored on purpose, and so is anything in `.claude/secret-guard.allow`. A real secret that looks like a placeholder, or a value you allowed and later reused for real, passes.
- **Speed:** PowerShell starts on every covered tool call, before and (for the output check) after, which adds a short delay (often a few hundred ms) each time.
- **Windows only.** See "Test it" above for what has been verified in a live session.

### What actually protects you
1. `settings.json` deny rules (user level above, plus `/setup-context` per project): the real wall. Claude Code enforces them itself.
2. Keeping secrets outside the repo (`dotnet user-secrets`, environment variables), so there is nothing to find.
3. secret-guard: catches the common mistakes on top, and warns you when one got through.
4. Rotating any secret that reached Claude anyway.

## Leave less to find
The guard can only miss what exists. The fewer real secrets there are on disk and the less they can do, the less a miss costs.
- **Never in the repo:** connection strings and keys go in `dotnet user-secrets` (or environment variables). Config files keep the setting with a blank value.
- **Dev values are throwaway:** the local Docker database uses a disposable password (in `.claude/secret-guard.allow`), never one reused anywhere real.
- **Short-lived and narrow tokens:** give GitLab, cloud and API tokens an expiry date and only the scopes they need (for example GitLab `read_repository` instead of `api`). A leaked narrow token does little damage.
- **No production secrets on the dev machine** if it can be avoided. Production values live in the deploy system (CI variables, a vault), not on disk.

## Rotation checklist
When a "BLOCKED" message was too late, or a "WARNING" appears: rotate first, investigate after. Rotating means creating a new value, switching the app to it, then revoking the old one.

| Secret | Where to revoke and replace |
|---|---|
| GitLab token (`glpat-`) | GitLab > avatar > Preferences > Access tokens > Revoke, then create a new one. Project/group tokens: Settings > Access tokens. Update Git Credential Manager (Windows Credential Manager > `git:https://gitlab...`). |
| GitHub token (`ghp_`, `github_pat_`) | GitHub > Settings > Developer settings > Personal access tokens > Delete, then create a new one. |
| SQL Server / Postgres / MySQL password | Change it on the server (`ALTER LOGIN ... WITH PASSWORD` / `ALTER USER ... PASSWORD`), then update `dotnet user-secrets set "ConnectionStrings:Default" "..."` (and the deploy system). |
| Local Docker dev database | Change the password in `docker-compose.yml` and `.claude/secret-guard.allow`, then `docker compose down -v` and up again. Low risk if it was never reused. |
| Anthropic / OpenAI API key | Console > API keys > delete the key, create a new one, update user-secrets or the env var. |
| AWS access key (`AKIA`) | IAM > Users > Security credentials > create a new key, switch to it, then deactivate and delete the old one. Check CloudTrail for use you don't recognize. |
| Azure storage key / connection string | Storage account > Access keys > Rotate key (rotate the one you don't use first, switch, then rotate the other). |
| Stripe live key | Dashboard > Developers > API keys > Roll key. |
| SSH private key | `ssh-keygen -t ed25519` for a new key, add the new `.pub` to GitLab/GitHub/servers, remove the old public key everywhere. |

Afterwards: check the service's logs for use of the old value between the leak and the revoke, and if it was ever committed, rotation is the fix. Rewriting git history does not help once it was pushed.
