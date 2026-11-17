<#
repo-fence.ps1 - keeps Claude Code inside the current repo plus what you shared. Runs on YOUR machine.

Modes:
  prompt    (UserPromptSubmit hook) remembers the absolute paths you mention or @-mention in a prompt, for this
                                    session only. Only those exact files/folders are opened up, not their neighbours.
  tool      (PreToolUse hook)       blocks file tools and shell commands that touch a path outside the project and
                                    outside what you shared. Also blocks searching past session transcripts unless
                                    you asked about past sessions.
  selftest                          checks the rules. Prints PASS/FAIL lines.

Exit code 2 = blocked (Claude Code shows the message to Claude).
Always allowed: the project, the temp folder, ~/.claude (except other projects' transcripts), Windows and
Program Files (tools), ~/.nuget, ~/.dotnet, npm.
Read-only unless shared: the guard's own files (~/.claude/hooks, settings.json, settings.local.json,
repo-fence.allow, the per-session lists).
Permanent extra folders: ~/.claude/repo-fence.allow (one absolute path per line; # for comments).
Per-session list: %TEMP%\claude-repo-fence\<session id>.allow
#>
param(
  [ValidateSet('prompt','tool','selftest')][string]$Mode = 'tool'
)
$ErrorActionPreference = 'Stop'
$StateDir = Join-Path ([IO.Path]::GetTempPath()) 'claude-repo-fence'
$Sep = [char[]]@('\', '/')
$SessionsFlag = '?sessions'

# Turns a path as written in a command or prompt into a full Windows path. Returns $null for URLs and junk.
function ConvertTo-FullPath([string]$p, [string]$base) {
  if (-not $p) { return $null }
  $p = $p.Trim().Trim('"').Trim("'")
  if (-not $p -or $p -match '://') { return $null }
  if ($p -match '^/([A-Za-z])/(.*)$') { $p = $Matches[1] + ':\' + $Matches[2] }
  elseif ($p -match '^~$') { $p = $HOME }
  elseif ($p -match '^~[\\/](.*)$') { $p = $HOME + '\' + $Matches[1] }
  # A wildcard: check the folder it searches in.
  $i = $p.IndexOfAny([char[]]@('*', '?'))
  if ($i -ge 0) {
    $p = $p.Substring(0, $i)
    $k = $p.LastIndexOfAny($Sep)
    $p = if ($k -ge 0) { $p.Substring(0, $k + 1) } else { '' }
    if (-not $p) { $p = '.' }
  }
  if (-not [IO.Path]::IsPathRooted($p)) { $p = $base.TrimEnd($Sep) + '\' + $p }
  try {
    $full = [IO.Path]::GetFullPath($p)
    if ($full.Length -gt 3) { $full = $full.TrimEnd($Sep) }
    return $full
  } catch { return $null }
}

function Test-Inside([string]$p, [string]$root) {
  if (-not $p -or -not $root) { return $false }
  $a = $p.TrimEnd($Sep).ToLowerInvariant()
  $b = $root.TrimEnd($Sep).ToLowerInvariant()
  return ($a -eq $b) -or $a.StartsWith($b + '\')
}

# Claude Code's folder name for a project under ~/.claude/projects (C:\Work\app -> C--Work-app).
function Get-ProjectKey([string]$proj) { return ($proj.TrimEnd($Sep) -replace '[:\\/ .]', '-') }

function Get-SessionFile([string]$sid) {
  if (-not $sid) { return $null }
  return (Join-Path $StateDir (($sid -replace '[^\w-]', '') + '.allow'))
}

function Read-ListFile([string]$f) {
  if (-not $f -or -not (Test-Path -LiteralPath $f)) { return @() }
  return @(Get-Content -LiteralPath $f | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Get-BuiltinRoots([string]$proj) {
  $r = @($proj, [IO.Path]::GetTempPath(), (Join-Path $HOME '.claude'), (Join-Path $HOME '.nuget'), (Join-Path $HOME '.dotnet'))
  foreach ($v in @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432)) { if ($v) { $r += $v } }
  if ($env:LOCALAPPDATA) { $r += (Join-Path $env:LOCALAPPDATA 'Programs') }
  if ($env:APPDATA) { $r += (Join-Path $env:APPDATA 'npm') }
  return @($r | Where-Object { $_ })
}

function Get-SharedRoots([string]$sid) {
  $lines = @(Read-ListFile (Join-Path $HOME '.claude\repo-fence.allow')) + @(Read-ListFile (Get-SessionFile $sid))
  return @($lines | Where-Object { [IO.Path]::IsPathRooted($_) })
}

# The fence's own switches. Writing to them, or naming them in a shell command, needs a share like any outside
# path; otherwise one write would open everything.
function Get-ProtectedRoots {
  $c = Join-Path $HOME '.claude'
  return @($StateDir, (Join-Path $c 'repo-fence.allow'), (Join-Path $c 'hooks'), (Join-Path $c 'settings.json'), (Join-Path $c 'settings.local.json'))
}

function Test-Allowed([string]$p, [string]$proj, [string[]]$shared, [string[]]$builtin, [bool]$write = $false) {
  foreach ($r in $shared) { if (Test-Inside $p $r) { return $true } }
  if ($write) { foreach ($r in (Get-ProtectedRoots)) { if (Test-Inside $p $r) { return $false } } }
  # Other projects' session transcripts and memory are past work, not this repo.
  $projects = Join-Path $HOME '.claude\projects'
  if (Test-Inside $p $projects) { return (Test-Inside $p (Join-Path $projects (Get-ProjectKey $proj))) }
  foreach ($r in $builtin) { if (Test-Inside $p $r) { return $true } }
  return $false
}

# Splits a command into its parts (&&, ||, ;, |, new line) without splitting inside quotes.
function Split-Command([string]$cmd) {
  $q = New-Object System.Collections.Generic.List[string]
  $mark = [string][char]1
  $masked = [regex]::Replace($cmd, '"[^"]*"|''[^'']*''', [System.Text.RegularExpressions.MatchEvaluator]{
    param($m) $q.Add($m.Value); return ($mark + ($q.Count - 1) + $mark) })
  $parts = @()
  foreach ($seg in ($masked -split '&&|\|\||;|\r?\n|\|')) {
    $parts += [regex]::Replace($seg, [regex]::Escape($mark) + '(\d+)' + [regex]::Escape($mark), [System.Text.RegularExpressions.MatchEvaluator]{
      param($m) return $q[[int]$m.Groups[1].Value] })
  }
  return $parts
}

# Every path a shell command touches, resolved against the folder it is in at that point (follows cd).
# Returns objects: Path, IsCd (a cd target), Base (the folder the command was in).
function Get-ShellPaths([string]$cmd, [string]$base) {
  $out = @()
  # Heredoc bodies and PowerShell here-strings are file CONTENT, not paths being touched.
  $cmd = [regex]::Replace($cmd, "(?ms)(<<-?\s*['""]?(\w+)['""]?[^\n]*)\n.*?^\s*\2\s*$", '$1')
  $cmd = [regex]::Replace($cmd, "(?s)@'.*?'@|@"".*?""@", ' ')
  foreach ($seg in (Split-Command $cmd)) {
    $s = $seg.Trim()
    if (-not $s) { continue }
    if ($s -match '^(?:cd|pushd|chdir|Set-Location|sl)(?:\s+-(?:Literal)?Path)?\s+("[^"]+"|''[^'']+''|\S+)') {
      $t = $Matches[1]
      if ($t -ne '-') {
        $full = ConvertTo-FullPath $t $base
        if ($full) { $out += [pscustomobject]@{ Path = $full; IsCd = $true }; $base = $full }
      }
      continue
    }
    if ($s -match '^(?:cd|pushd|chdir|Set-Location|sl)$') { continue }
    $found = @()
    # Absolute paths, quoted or not, and ../ paths.
    foreach ($m in [regex]::Matches($s, '"([A-Za-z]:[\\/][^"]*|/[A-Za-z]/[^"]*|~[\\/][^"]*)"|''([A-Za-z]:[\\/][^'']*|/[A-Za-z]/[^'']*|~[\\/][^'']*)''')) {
      $found += ($m.Groups[1].Value + $m.Groups[2].Value)
    }
    $unquoted = [regex]::Replace($s, '"[^"]*"|''[^'']*''', ' ')
    foreach ($m in [regex]::Matches($unquoted, '(?<![\w:/\\.$-])([A-Za-z]:[\\/][^\s|<>;&(){}]*|/[A-Za-z]/[^\s|<>;&(){}]*|~[\\/][^\s|<>;&(){}]*|~(?=\s|$))')) {
      $found += $m.Groups[1].Value
    }
    # ../ only as a word of its own, so git ranges (main..HEAD, @{u}..HEAD, a...b) are not read as the parent folder.
    foreach ($m in [regex]::Matches($unquoted, '(?<![^\s=<>(])(\.\.(?:[\\/][^\s|<>;&(){}]*)?)(?=[\s;|&)<>]|$)')) {
      $found += $m.Groups[1].Value
    }
    # Relative names (src/x.cs, Program.cs, ., *.json). Inside the project they are always fine; they matter
    # after a cd to somewhere else.
    foreach ($m in [regex]::Matches($unquoted, '[^\s|<>;&(){}=,]+')) {
      $w = $m.Value
      if ($w -match '^[-$/%@+:~\\]' -or $w -match ':' -or $w.StartsWith('..')) { continue }
      if ($w -eq '.' -or $w -match '[\\/]' -or $w -match '^\*' -or $w -match '^[\w.-]+\.[A-Za-z]\w{0,7}$') { $found += $w }
    }
    # A listing or search command that names no path works on the folder it is in (`ls`, `git log`, `dir`).
    if ($found.Count -eq 0 -and $s -match '^(ls|ll|dir|gci|Get-ChildItem|find|tree|du|git|rg|fd|grep\s.*-\w*[rR])\b') { $found += '.' }
    foreach ($f in $found) {
      $full = ConvertTo-FullPath $f $base
      if ($full) { $out += [pscustomobject]@{ Path = $full; IsCd = $false } }
    }
  }
  return $out
}

# Paths in a shell command that are off limits. A cd into a parent folder of something shared is fine on its
# own; whatever is then read there is checked by name.
function Get-CommandViolations([string]$cmd, [string]$base, [string]$proj, [string[]]$shared, [string[]]$builtin) {
  $bad = @()
  foreach ($x in @(Get-ShellPaths $cmd $base)) {
    if (Test-Allowed $x.Path $proj $shared $builtin $true) { continue }
    if ($x.IsCd -and @($shared | Where-Object { Test-Inside $_ $x.Path }).Count -gt 0) { continue }
    $bad += $x.Path
  }
  return @($bad | Select-Object -Unique)
}

# Absolute paths the user wrote in a prompt (including @"..." mentions).
function Get-PromptPaths([string]$text, [string]$base) {
  $raw = @()
  foreach ($m in [regex]::Matches($text, '"([A-Za-z]:[\\/][^"]+)"')) { $raw += $m.Groups[1].Value }
  $rest = [regex]::Replace($text, '"[^"]*"', ' ')
  foreach ($m in [regex]::Matches($rest, '(?<![\w])([A-Za-z]:[\\/][^\s"''<>|`*?]+|/[A-Za-z]/[^\s"''<>|`*?]+|~[\\/][^\s"''<>|`*?]+)')) { $raw += $m.Groups[1].Value }
  $out = @()
  foreach ($r in $raw) {
    $r = $r.TrimEnd('.', ',', ';', ':', ')', ']', '!', '?')
    $full = ConvertTo-FullPath $r $base
    if ($full) { $out += $full }
  }
  return $out
}

function Block([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

if ($Mode -eq 'selftest') {
  $fail = 0
  $proj = 'C:\Work\app'
  $shared = @('C:\Work\old\SharedLib')
  $builtin = Get-BuiltinRoots $proj
  function CheckPath([string]$name, [string]$p, [bool]$expect) {
    $got = Test-Allowed $p $proj $shared $builtin
    if ($got -eq $expect) { Write-Output "PASS $name" } else { Write-Output "FAIL $name"; $script:fail++ }
  }
  function CheckCmd([string]$name, [string]$cmd, [bool]$expect) {
    $bad = @(Get-CommandViolations $cmd $proj $proj $shared $builtin)
    $got = $bad.Count -eq 0
    if ($got -eq $expect) { Write-Output "PASS $name" } else { Write-Output "FAIL $name (outside: $($bad -join ', '))"; $script:fail++ }
  }
  CheckPath 'project file'                 'C:\Work\app\src\a.cs'                     $true
  CheckPath 'other repo blocked'           'C:\Work\old\OtherApi\x.cs'          $false
  CheckPath 'shared folder allowed'        'C:\Work\old\SharedLib\Domain\x.cs'       $true
  CheckPath 'sibling of shared blocked'    'C:\Work\old\SiblingLib\x.cs'      $false
  CheckPath 'parent folder blocked'        'C:\Work'                                  $false
  CheckPath 'similar name blocked'         'C:\Work\app-v1\x.cs'                      $false
  CheckPath 'temp allowed'                 (Join-Path ([IO.Path]::GetTempPath()) 'x') $true
  CheckPath 'other transcripts blocked'    "$HOME\.claude\projects\C--Work-old\a.jsonl" $false
  CheckPath 'own project memory allowed'   "$HOME\.claude\projects\C--Work-app\memory\m.md" $true
  CheckPath 'skills allowed'               "$HOME\.claude\skills\x\SKILL.md"          $true
  CheckCmd  'cd outside then read'         'cd /c/Work/old/OtherApi && sed -n 1,30p appsettings.json' $false
  CheckCmd  'cd inside, ../ stays inside'  'cd src && cat ../README.md'               $true
  CheckCmd  'relative ../ outside'         'cat ../old/x.cs'                          $false
  CheckCmd  'list parent folder'           'ls ..'                                    $false
  CheckCmd  'cd .. then list'              'cd .. && ls'                              $false
  CheckCmd  'absolute path outside'        'cat C:\Work\old\OtherApi\Program.cs' $false
  CheckCmd  'quoted path outside'          'Get-Content "C:\Work\old\OtherApi\Program.cs"' $false
  CheckCmd  'wildcard outside'             'cat C:/Work/old/*.json'                   $false
  CheckCmd  'shared folder via cd'         'cd "C:\Work\old\SharedLib" && ls'        $true
  CheckCmd  'url ignored'                  'curl https://example.com/c/x'             $true
  CheckCmd  'cmd switches ignored'         'cmd /c dir /s'                            $true
  CheckCmd  'sed expression ignored'       "sed -i 's/a/b/' src/x.cs"                 $true
  CheckCmd  'heredoc body ignored'         "cat > a.txt <<'EOF'`nlog to C:\Logs\x`nEOF" $true
  CheckCmd  'tool in Program Files ok'     '"C:\Program Files\nodejs\node.exe" -v'    $true
  CheckCmd  'cd parent of shared, read shared' 'cd /c/Work/old && cat SharedLib/Domain/x.cs' $true
  CheckCmd  'cd parent of shared, list all'    'cd /c/Work/old && find . -name x'          $false
  CheckCmd  'cd parent of shared, read other'  'cd /c/Work/old && cat OtherApi/Program.cs' $false
  CheckCmd  'cd parent of shared, file there'  'cd /c/Work/old && sed -n 1,30p appsettings.json' $false
  CheckCmd  'semicolon inside quotes'      "sed -i '0,/^using /s//using X;\nusing /' src/a.cs" $true
  CheckCmd  'dev null ignored'             'ls src 2>/dev/null'                        $true
  CheckCmd  'line continuation ignored'    "cat src/a.cs \`n  src/b.cs"                $true
  CheckCmd  'loop in parent, shared files' 'cd /c/Work/old && for f in SharedLib/a.cs SharedLib/b.cs; do echo "== $f"; cat "$f"; done' $true
  CheckCmd  'git in parent folder'         'cd /c/Work/old && git log --oneline'      $false
  CheckCmd  'git range @{u}..HEAD ok'      'git log --oneline @{u}..HEAD'             $true
  CheckCmd  'git range a...b ok'           'git diff main...HEAD; git log HEAD~3..HEAD' $true
  CheckCmd  'redirect to parent blocked'   'echo x >../x.txt'                         $false
  CheckCmd  'project relative names ok'    'cat src/Program.cs README.md; find . -name "*.cs"' $true
  function CheckWrite([string]$name, [string]$p, [bool]$expect) {
    $got = Test-Allowed $p $proj $shared $builtin $true
    if ($got -eq $expect) { Write-Output "PASS $name" } else { Write-Output "FAIL $name"; $script:fail++ }
  }
  CheckPath  'read settings.json allowed'   "$HOME\.claude\settings.json"              $true
  CheckWrite 'write settings.json blocked'  "$HOME\.claude\settings.json"              $false
  CheckWrite 'write a skill allowed'        "$HOME\.claude\skills\x\SKILL.md"          $true
  CheckCmd   'guard allow list via shell'   'echo x >> ~/.claude/repo-fence.allow'     $false
  CheckCmd   'guard hooks via shell'        'cp repo-fence.ps1 ~/.claude/hooks/repo-fence.ps1' $false
  CheckCmd   'guard session list via shell' ('echo x >> "' + (Join-Path $StateDir 'abc.allow') + '"') $false
  CheckCmd   'skills via shell still ok'    'ls ~/.claude/skills'                      $true
  $pp = @(Get-PromptPaths '@"C:\Work\old\SharedLib/" @C:\Work\old\OtherLib\Domain\x.cs, please port' 'C:\Work\app')
  if (($pp -contains 'C:\Work\old\SharedLib') -and ($pp -contains 'C:\Work\old\OtherLib\Domain\x.cs')) { Write-Output 'PASS prompt mentions recorded' } else { Write-Output "FAIL prompt mentions recorded ($($pp -join ', '))"; $fail++ }
  $pu = @(Get-PromptPaths 'see https://example.com/c/x and the readme' 'C:\Work\app')
  if ($pu.Count -eq 0) { Write-Output 'PASS urls in prompt ignored' } else { Write-Output "FAIL urls in prompt ignored ($($pu -join ', '))"; $fail++ }
  if ($fail -gt 0) { Write-Output "$fail check(s) FAILED"; exit 1 } else { Write-Output 'All checks passed'; exit 0 }
}

try {
  $raw = [Console]::In.ReadToEnd()
  if (-not $raw) { exit 0 }
  $j = $raw | ConvertFrom-Json
  $sid = [string]$j.session_id
  $proj = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } elseif ($j.cwd) { [string]$j.cwd } else { (Get-Location).Path }
  $proj = [IO.Path]::GetFullPath($proj).TrimEnd($Sep)
  $cwd = if ($j.cwd) { [string]$j.cwd } else { $proj }

  if ($Mode -eq 'prompt') {
    # Never blocks a prompt and prints nothing (stdout would be added to Claude's context).
    $text = [string]$j.prompt
    $add = @(Get-PromptPaths $text $cwd)
    if ($text -match '(?i)\b(past|previous|earlier|last|other|old)\s+(session|conversation|chat)s?\b|\btranscripts?\b') { $add += $SessionsFlag }
    $f = Get-SessionFile $sid
    if ($f -and $add.Count -gt 0) {
      New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
      $have = @(Read-ListFile $f)
      $new = @($add | Where-Object { $have -notcontains $_ } | Select-Object -Unique)
      if ($new.Count -gt 0) { Add-Content -LiteralPath $f -Value $new -Encoding UTF8 }
    }
    exit 0
  }

  # Mode = tool
  $tn = [string]$j.tool_name
  $ti = $j.tool_input

  if ($tn -match 'search_session_transcripts|export_transcript') {
    if (@(Read-ListFile (Get-SessionFile $sid)) -contains $SessionsFlag) { exit 0 }
    Block ('repo-fence: BLOCKED. Searching past sessions was not asked for. Work only from the current repo (' + $proj +
      ') and what the user shared in this session. If earlier sessions would help, ask the user first.')
  }
  if (-not $ti) { exit 0 }

  $paths = @()
  foreach ($k in 'file_path', 'notebook_path', 'path') {
    if ($ti.PSObject.Properties[$k] -and $ti.$k) { $full = ConvertTo-FullPath ([string]$ti.$k) $cwd; if ($full) { $paths += $full } }
  }
  if ($tn -eq 'Glob' -and $ti.pattern -and ([IO.Path]::IsPathRooted([string]$ti.pattern) -or [string]$ti.pattern -match '^(/[A-Za-z]/|~[\\/]|\.\.)')) {
    $full = ConvertTo-FullPath ([string]$ti.pattern) $cwd; if ($full) { $paths += $full }
  }
  $shared = Get-SharedRoots $sid
  $builtin = Get-BuiltinRoots $proj
  $write = $tn -match '^(Edit|Write|MultiEdit|NotebookEdit)$'
  $outside = @($paths | Where-Object { -not (Test-Allowed $_ $proj $shared $builtin $write) })
  if (($tn -eq 'Bash' -or $tn -eq 'PowerShell') -and $ti.command) { $outside += @(Get-CommandViolations ([string]$ti.command) $cwd $proj $shared $builtin) }
  $outside = @($outside | Select-Object -Unique)
  if ($outside.Count -gt 0) {
    Block ('repo-fence: BLOCKED. ' + ($outside -join ', ') + ' is outside this project (' + $proj + '), or is one of the guard''s own files, and was not shared in this session. ' +
      'Do not try another way to reach it, and do not go looking for similar or older repos. Work from the current repo. ' +
      'If you really need it, ask the user to share it (they can @-mention or name the path).')
  }
  exit 0
}
catch {
  # Fail open on unexpected errors so a bug never locks you out; the error is shown.
  [Console]::Error.WriteLine("repo-fence: internal error, check skipped: $($_.Exception.Message)")
  exit 1
}
