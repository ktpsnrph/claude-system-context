---
description: Run a read-only QA pass (functionality, design, responsiveness, security) and save the report to System-Context/Quality-Assurance-Results/
argument-hint: [url-or-focus] [functions|design|responsive|security|all]
---

QA this application WITHOUT changing any code. Arguments from the user: $ARGUMENTS

If a `qa-tester` agent exists in `.claude/agents/`, use it for the testing. If it does not exist, do the testing yourself with the checks below. Do not stop because the agent is missing.

## Scope
- If the arguments contain a URL, test that URL. Otherwise test the app in the current project (read `CLAUDE.md` for the run commands, and start it if needed).
- If the arguments name an area (functions, design, responsive, security), focus on it. If nothing is named, cover all four.
- Only test the URL the user gave or the local app. Never attack, scan or load-test a site you were not given. Use test data only. Never run destructive actions (deleting data, dropping tables, running SQL or migrations against a non-local database).
- Never copy secrets (keys, tokens, passwords, connection strings) into the report or print them.

## Checks
- **functions:** main user flows work end to end, forms validate, errors are handled, no console or server errors, edge cases (empty, very long, special characters).
- **design:** layout, spacing, alignment, consistency, readable text and contrast, broken images, obvious usability problems.
- **responsive:** common phone, tablet and desktop widths; nothing overflows or becomes unusable.
- **security (read-only observation):** missing input validation, exposed secrets or stack traces, missing auth checks on pages, insecure headers or cookies, sensitive data in URLs or logs.

## Report
Write one report with:
1. Header: date, what was tested (URL or project), areas covered, anything you could not test and why.
2. A summary table: number of issues by severity (Critical, High, Medium, Low).
3. Each issue as its own block, with a stable ID (`QA-001`, `QA-002`, ...), severity, area, short title, steps to reproduce, expected vs actual, evidence (screen, message, file and line if known) and a suggested fix. Set `Status: open`.

## Saving the report
1. Get a timestamp, for example `date +%Y-%m-%d_%H%M`. If `date` is not available, use PowerShell `Get-Date -Format yyyy-MM-dd_HHmm`.
2. Create `System-Context/Quality-Assurance-Results/` if it does not exist.
3. Save the report exactly as written to `System-Context/Quality-Assurance-Results/qa-report-<timestamp>.md`.
4. This report is the ONLY file you may create or change. Do not touch source code, config, `.gitignore`, `System-Context/INDEX.md` or any other file, and do not start fixing issues. `/sync-context` will index the report later.

## Reply to the user
A short summary: issues by severity, the top 3 to fix first, the path of the saved report, and the next step: fix issues by asking Claude for them by ID (for example "fix QA-003 from the latest QA report"; after each fix, set that issue's `Status:` line in the report to `fixed`), then run `/sync-context` to log the fixes and index the report.
