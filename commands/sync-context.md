---
description: Set up or update "sync-context" (System-Context/INDEX.md, System-Context/*, System-Context/sessions/latest.md, small CLAUDE.md) for the current repo
---

Maintain "sync-context": a small, indexed memory folder named `System-Context/` for the CURRENT repo only. Use paths relative to the repo root. Ask no questions unless something is destructive or ambiguous.

Everything the memory folder writes lives inside `System-Context/` (the INDEX, the topic folders, the rules, the session summaries). Do not create `docs/`, `sessions/` or `.claude/rules/`.

## STEP 0 (always first)
- Run `git fetch`. Read recent commits by others (`git log` on the current and upstream branches). Do not overwrite their work; if a file you would edit changed upstream, merge your changes onto it.
- Never work on `main`/`master`. If on one, create or switch to branch `sync-update` (or `sync-setup` if `System-Context/INDEX.md` does not exist yet).
- Never edit source code. Never commit. Never push. Never copy secrets (keys, tokens, passwords, connection strings, config values) into any file, and do not print them.
- Edit only `System-Context/`, `CLAUDE.md`, the repo-root `.gitignore` (only the lines in STEP 1) and notes files (README/notes-style markdown). Never edit anything under `.claude/` (settings, hooks, agents, skills, commands, rules).
- `System-Context/` is also an Obsidian vault. Outside STEP 1 below, never read, edit, move or index `System-Context/.obsidian/` or `System-Context/_assets/`. `System-Context/_inbox/` is handled only by STEP 1.

## STEP 1: Obsidian housekeeping
Items 1-5 are setup. Run them when `System-Context/INDEX.md` does not exist, or when `System-Context/.obsidian/app.json` or `System-Context/_inbox/` is missing; otherwise skip them. Items 6-8 run on every run. Each item checks first and changes only what is missing or wrong, so a second run changes nothing. List every change in the final report under "Obsidian housekeeping".
1. Folders: make sure `System-Context/_inbox/` and `System-Context/_assets/` exist, each with an empty `.gitkeep`.
2. Obsidian settings: in `System-Context/.obsidian/app.json` (create the folder and file if missing), set these keys and keep every other key as it is:
   `"useMarkdownLinks": true`, `"newLinkFormat": "relative"`, `"alwaysUpdateLinks": true`, `"newFileLocation": "folder"`, `"newFileFolderPath": "_inbox"`, `"attachmentFolderPath": "_assets"`, `"userIgnoreFilters": ["_assets/"]`.
   If Obsidian is open, tell the user that the settings take effect after the vault is reopened.
3. Git ignore: make sure the repo-root `.gitignore` contains these lines (append only the missing ones):
   ```
   System-Context/.obsidian/*
   !System-Context/.obsidian/app.json
   !System-Context/.obsidian/core-plugins.json
   ```
4. Untrack Obsidian's personal files: if `git ls-files System-Context/.obsidian` lists anything other than `app.json` or `core-plugins.json`, run `git rm --cached` on those files only. This stages the removal; do not commit. Never delete the files from disk.
5. Do-not-load list: make sure `CLAUDE.md` has a "Do NOT load" section containing these lines (add only the missing ones; never remove lines the user added):
   - `System-Context/.obsidian/` and `System-Context/_assets/`: Obsidian settings and images, never needed for context
   - `System-Context/_inbox/`: unfiled notes; `/sync-context` files them
   - `System-Context/Quality-Assurance-Results/`: QA reports; read only when re-checking a QA issue
6. Wikilinks: on a first-time setup, scan every `.md` file in `System-Context/` (except `.obsidian/` and `_assets/`); otherwise scan only `_inbox/` and the files changed since the date in the heading of `System-Context/sessions/latest.md` (`git log --since=<that date> --name-only` plus `git status --short`). Convert `[[note]]`, `[[note|text]]` and `[[note#heading]]` to relative markdown links (`[text](relative/path.md)`, `[text](relative/path.md#heading)`). If a wikilink points to a note that does not exist, leave it as it is and list it in the report.
7. Inbox: for each file in `System-Context/_inbox/` (except `.gitkeep`), search `System-Context/INDEX.md` for the file that covers its subject. If one matches, merge the note's facts into that file and delete the inbox file. If none matches, move the note with `git mv` (or a plain move if untracked) into the folder that fits (`design/`, `rules/`, `env/`, `history/` or a topic folder), give it a lowercase-hyphen name, and add its index line. Apply the rules for rules (Mode B step 3): a note that states a rule that is not settled becomes a suggestion in the report, not a rule. If a note contains anything that looks like a secret, do not copy it anywhere: leave the file in `_inbox/` and tell the user to remove the value and rotate it.
8. Old QA folders: if `System-Context/qa-results/` or `System-Context/qa/` exists, move every file in it with `git mv` (or a plain move if untracked) into `System-Context/Quality-Assurance-Results/` (create it if missing), then remove the empty old folder. In `CLAUDE.md` and `System-Context/INDEX.md`, change mentions of the old folder path to `System-Context/Quality-Assurance-Results/`, and fix links in other notes that pointed into the old folder.

Then: if `System-Context/INDEX.md` does NOT exist -> MODE A. If it exists -> MODE B.

## Layout of System-Context/
```
System-Context/
  INDEX.md        one line per file: path, what it holds, keywords
  rules/          rules and conventions that are easy to break (the ONLY home for rules)
  env/            run, build, secrets handling (how, never values), deploy
  design/         design and decisions
  history/        history of fixes (read only when the same symptom comes back)
  sessions/       latest.md plus dated past summaries (YYYY-MM-DD.md)
  <topic>/        any existing topic folder (for example SSO/): keep it, index it, do not move it
  Quality-Assurance-Results/  QA reports from /qa (read only when re-checking a QA issue)
  .obsidian/      Obsidian settings (managed only by STEP 1; never read for context)
  _inbox/         new notes land here; STEP 1 files them on every run
  _assets/        images and attachments (never read for context)
```
Each file stays under ~5 KB. Add a new small file, or a new topic folder, only when nothing existing covers the fact.
If a file would go over ~5 KB: first trim it (move reversed or old decisions to `history/`, rules to `rules/`, and replace facts duplicated from another file with a link to it). If it is still over ~5 KB, split it by sub-topic into a folder named after the file (for example `design/admin-center.md` -> `design/admin-center/overview.md`, `permissions.md`, `audit-log.md`), with `overview.md` as the entry point. Its "Parts:" list has one line per part: link, then that part's keywords. Use `git mv` for the original file and point its index line at `overview.md` (see Index rules). Never split into numbered files (`admin-center-2.md`) or flat prefixed siblings.
Moving a note (filing from `_inbox/`, a split, any `git mv` inside `System-Context/`): Obsidian does not see the move, so fix the links yourself. Rewrite the relative links inside the moved note (to other notes and to `_assets/`) so they resolve from its new location, and update links in other notes that pointed to its old path. List any link you could not resolve in the report.

## Index rules
`System-Context/INDEX.md` has one line per file: path as a plain relative markdown link (not `[[wiki links]]`), what it holds, keywords. Sections: Rules and environment / Design and decisions / History of fixes (read only when the same symptom comes back) / Topics / Session state.
- Every file in `System-Context/` has a line (including `spec.md`, `plan.md`, `decisions.md` if present), and every indexed path exists, except the parts of a split folder below.
- A split folder (one with an `overview.md`) gets exactly one line, pointing to its `overview.md`, carrying the keywords of every part. Its parts get no index line of their own; they are reached through the overview's "Parts:" list, where each part line has its keywords. If older runs left one line per part, merge their keywords into the overview line, delete the part lines, and add any missing keywords to the overview's "Parts:" list.
- `.obsidian/`, `_inbox/` and `_assets/` are never indexed; no line may point into them.
- `Quality-Assurance-Results/` gets exactly one line for the whole folder ("QA reports; read only when re-checking a QA issue").
- `sessions/` gets exactly two lines: one for `latest.md`, one for the dated past summaries ("past session summaries; read only when tracing an old decision"). If older runs left one line per dated file, replace them with that single line.

## MODE A: first-time setup
1. Read `CLAUDE.md`, any notes/README, any existing `docs/` or `System-Context/` content. Split big files by subject into the layout above. Rules found in `docs/rules/` move to `System-Context/rules/` (use `git mv`). If `.claude/rules/` already has files, leave them where they are and list them in the final report as a suggestion. Move content, do not summarize it away; every fact lands in exactly one file. Use `git mv` where it fits. Do not delete files; shrink fully replaced ones to a short pointer to `System-Context/INDEX.md`.
2. Write `System-Context/INDEX.md` following the Index rules.
3. Write `System-Context/sessions/latest.md` from the current notes: `# Last session: YYYY-MM-DD`, then sections Built, Decided, Findings, Open (in order), How things were done.
4. Rewrite `CLAUDE.md` small: keep every existing rule, one line each, pointing to its file in `System-Context/rules/` or the doc that covers it. Add the line `@System-Context/sessions/latest.md` and a "How this project's memory is kept" section: read `System-Context/INDEX.md` first, open only the file whose keywords match, do not read the whole `System-Context/` folder; before saving a fact, search the index, update the file that covers it, else add a small file and an index line. In the same section add this rule: "At the start of a session, if `System-Context/sessions/latest.md` is older than the most recent git commit, tell the user to run `/sync-context` first."
5. Check the index by hand against the Index rules.
6. Finish with: a table of old section -> new file; the "Obsidian housekeeping" changes from STEP 1; anything stale or contradictory that you did not change; a graphify line if the repo has no `graphify-out/` (if the CLI is installed: "run `/graphify .` to build a graph for this repo"; if not: "optional: graphify can turn this repo into a knowledge graph; see its install steps", and never build it here); `git diff --stat` (note untracked files too, via `git status --short`).

## MODE B: end-of-session update
1. Catch-up check: read the date in the heading of `System-Context/sessions/latest.md` and compare it with the commits made since then (`git log --since=<that date> --stat`, current branch and upstream). If there are commits or changes that no session summary covers (a session was skipped), summarize them from the git history and the working tree, and mark them in the new summary as "Recovered from git history, not from the session itself" so the user knows they are less detailed. Never invent details that git does not show.
   Then summarize: rename `System-Context/sessions/latest.md` to `System-Context/sessions/YYYY-MM-DD.md` (date from its heading; add `-2`/`-3` if that name exists), then write a new `latest.md` for THIS session and any recovered work (same headings as Mode A step 3). Keep it short.
2. Docs: for everything that changed this session, find the matching file through `System-Context/INDEX.md` and update it. If no file covers it, add a small file (under ~5 KB) in the right folder and an index line.
3. Rules: add a rule only when it is settled and will rarely change; otherwise list it as a suggestion. Put the rule in the matching file in `System-Context/rules/` (add a small file if none fits) and add only a one-line pointer to it in `CLAUDE.md`. Never write rule text into `CLAUDE.md`. Keep `CLAUDE.md` small. Also check that the "How this project's memory is kept" section in `CLAUDE.md` contains the staleness rule from Mode A step 4; if it is missing, add that one line.
4. Graphify: never build a new graph on your own (the first build reads the whole repo and adds generated files to commit; that is the user's decision). Check two things: does `graphify-out/` exist, and is the CLI installed (`graphify --version` succeeds). Then:
   - Folder exists, CLI installed: update it with `/graphify . --update --no-viz` (never `--cluster-only`, which always rebuilds `graph.html`). Only `graph.json` and `GRAPH_REPORT.md` are needed; if `graphify-out/graph.html` exists, delete it. Tell the user to commit it on its own, apart from the code and the summary.
   - Folder exists, CLI missing: do not update. In the report, warn that the graph is now out of date and give the install steps (`uv tool install graphifyy`, two y's, then `graphify install`).
   - No folder, CLI installed: do not build. Add one line to the report: "graphify is installed but this repo has no graph; run `/graphify .` to build one."
   - Neither: say nothing.
5. Check the index by hand again against the Index rules.
6. Finish with a short summary, any suggested rules, the "Obsidian housekeeping" changes from STEP 1, the graphify result from step 4 (if any), and `git diff --stat` (plus `git status --short` for untracked files).