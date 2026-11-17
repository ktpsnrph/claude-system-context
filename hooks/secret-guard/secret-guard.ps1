<#
secret-guard.ps1 - keeps secrets away from Claude Code. Runs on YOUR machine, before Claude sees anything.

Modes:
  tool      (PreToolUse hook)       blocks Claude from reading config files that contain a secret, and from
                                    writing a secret into a file. Claude is told WHERE, never WHAT.
  prompt    (UserPromptSubmit hook) blocks a prompt you typed if it contains a known token format or a
                                    connection string with a password.
  output    (PostToolUse hook)      cannot hide output Claude already got, but warns YOU (and tells Claude not to
                                    repeat it) when a tool's output contained a token or a connection-string password,
                                    so you know to rotate it.
  scan      (pre-commit)            scans the files named on stdin (one per line) or via -Path. Exit 1 if found.
  selftest                          checks the detection rules. Prints PASS/FAIL lines.

Exit code 2 = blocked (Claude Code shows stderr). Secret values are NEVER printed.
Per-project allow list: .claude/secret-guard.allow (one literal value per line; # for comments), for throwaway
values such as a Docker dev password.
#>
param(
  [ValidateSet('tool','prompt','output','scan','selftest')][string]$Mode = 'tool',
  [string[]]$Path
)
$ErrorActionPreference = 'Stop'
$ProjectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }

$Rules = @(
  @{ Label = 'secret-like key with a value';        Rx = '(?i)"[^"]*(password|passwd|pwd|secret|api[-_]?key|access[-_]?key|private[-_]?key|token)[^"]*"\s*:\s*"([^"]+)"' },
  @{ Label = 'password in a connection string';     Rx = '(?i)\b(password|pwd)\s*=\s*([^;"''\s]+)' },
  @{ Label = 'secret in an env-style line';         Rx = '(?i)^\s*(?:-\s*)?(?:export\s+)?[A-Z0-9_]*(PASSWORD|SECRET|TOKEN|API_?KEY|PRIVATE_?KEY)[A-Z0-9_]*\s*=\s*([^\s#]+)' },
  @{ Label = 'secret in a yaml line';               Rx = '(?i)^\s*(?:-\s*)?[\w.-]*(password|secret|token|api[-_]?key)[\w.-]*\s*:\s*([^\s#].*)$' }
)
$Rules += ,@{ Label = 'npm / pip auth token';            Rx = '(?i)(_authToken|_auth)\s*=\s*(\S+)' }
# Token formats recognized in ANY file, prompt or output: AWS, GitHub, Slack, private-key blocks, GitLab,
# Anthropic, OpenAI, Stripe, Google API, npm, Azure storage key.
$TokenRegex  = 'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----' +
               '|glpat-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-(proj-)?[A-Za-z0-9_-]{32,}|[sr]k_live_[A-Za-z0-9]{20,}' +
               '|AIza[0-9A-Za-z_-]{35}|npm_[A-Za-z0-9]{36}|AccountKey=[A-Za-z0-9+/]{40,}={0,2}'
# JWTs: only flagged in config-like files (test code often contains sample JWTs).
$JwtRegex    = 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
# For tool OUTPUT only real connection strings count (a server/host on the same line), or a database URL with
# a password, so ordinary code like `password = GetPassword()` does not raise warnings.
$OutConnRx   = @(
  '(?i)\b(server|host|data source|address)\s*=[^;\r\n]*;[^\r\n]*?\b(password|pwd)\s*=\s*(?<v>[^;"''\s\\]+)',
  '(?i)\b(postgres(ql)?|mysql|mariadb|sqlserver|mongodb(\+srv)?|redis|amqps?)://[^:@/\s]+:(?<v>[^@/\s]+)@'
)
$Placeholder = '(?i)^(\*+|x+|<.*>|\{.*\}|\$\{.*\}|%.*%|changeme|change-me|todo|null|none|redacted|your[-_ ].*|\.\.\.)$'

function Get-AllowList {
  $f = Join-Path $ProjectDir '.claude/secret-guard.allow'
  if (Test-Path -LiteralPath $f) {
    return @(Get-Content -LiteralPath $f | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
  }
  return @()
}

function Test-Real([string]$value, [string[]]$allow) {
  $v = $value.Trim().Trim('"').Trim("'").Trim()
  if ($v.Length -eq 0) { return $false }
  if ($v -match $Placeholder) { return $false }
  if ($v -match '^(\d+|true|false)$') { return $false }
  if ($allow -contains $v) { return $false }
  return $true
}

# Returns a list of descriptions like "line 12 [password in a connection string]". Never returns values.
function Find-Secrets([string]$text, [bool]$full, [string[]]$allow) {
  $hits = @()
  $lines = $text -split "\r?\n"
  for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    if ($line -match '(?i)usersecretsid') { continue }
    if ($line -match $TokenRegex) { $hits += "line $($i + 1) [token or private key]"; continue }
    if (-not $full) { continue }
    if ($line -match $JwtRegex) { $hits += "line $($i + 1) [JWT]"; continue }
    foreach ($r in $Rules) {
      $found = $false
      foreach ($m in [regex]::Matches($line, $r.Rx)) {
        if (Test-Real $m.Groups[2].Value $allow) { $found = $true; break }
      }
      if ($found) { $hits += "line $($i + 1) [$($r.Label)]"; break }
    }
  }
  return $hits
}

function Test-ConfigLike([string]$p) {
  $n = [IO.Path]::GetFileName($p)
  return ($n -match '(?i)^(appsettings.*\.json|launchsettings\.json|secrets\.json|\.env.*|.*\.env|.*\.config|docker-compose.*\.ya?ml|.*\.tfvars|\.npmrc|\.pypirc|credentials.*)$')
}

# Files that exist only to hold secrets: blocked whenever they exist, whatever is inside.
function Test-KeyFile([string]$p) {
  return ([IO.Path]::GetFileName($p) -match '(?i)(\.(pem|pfx|p12|key|ppk|kdbx)$|^(id_(rsa|dsa|ecdsa|ed25519)|\.pgpass|\.netrc|_netrc)$)')
}

# Kinds of secret found in tool output (tokens and connection-string passwords only, to keep noise low).
function Find-OutputSecrets([string]$text, [string[]]$allow) {
  $kinds = @()
  foreach ($m in [regex]::Matches($text, $TokenRegex)) { if (Test-Real $m.Value $allow) { $kinds += 'token or private key'; break } }
  $found = $false
  foreach ($rx in $OutConnRx) {
    foreach ($m in [regex]::Matches($text, $rx)) { if (Test-Real $m.Groups['v'].Value $allow) { $found = $true; break } }
    if ($found) { break }
  }
  if ($found) { $kinds += 'password in a connection string' }
  return $kinds
}

function Test-OneFile([string]$p, [string[]]$allow) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return @() }
  if (Test-KeyFile $p) { return @('key, certificate or password-store file') }
  $item = Get-Item -LiteralPath $p
  if ($item.Length -gt 2MB) { return @() }
  $text = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
  if (-not $text) { return @() }
  return Find-Secrets $text (Test-ConfigLike $p) $allow
}

function Resolve-Candidate([string]$p, [string]$base = $ProjectDir) {
  if ($p -match '^~[\\/]') { return (Join-Path $HOME $p.Substring(2)) }
  if ($p -match '^/([A-Za-z])/(.*)$') { return ($Matches[1] + ':\' + $Matches[2]) }
  if ([IO.Path]::IsPathRooted($p)) { return $p }
  return (Join-Path $base $p)
}

# Words in a shell command, resolved against the folder the command is in at that point (follows cd), so
# `cd other\folder && cat appsettings.json` checks other\folder\appsettings.json, not the project's.
function Get-ShellCandidates([string]$cmd, [string]$base) {
  $out = @()
  foreach ($seg in ($cmd -split '&&|\|\||;|\r?\n|\|')) {
    $s = $seg.Trim()
    if ($s -match '^(?:cd|pushd|chdir|Set-Location|sl)(?:\s+-(?:Literal)?Path)?\s+("[^"]+"|''[^'']+''|\S+)') {
      $t = $Matches[1].Trim('"').Trim("'")
      if ($t -and $t -ne '-') { try { $base = [IO.Path]::GetFullPath((Resolve-Candidate $t $base)) } catch { } }
      continue
    }
    foreach ($m in [regex]::Matches($s, '[^\s"''|<>;&=]+')) { $out += (Resolve-Candidate $m.Value $base) }
  }
  return $out
}

function Block([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

function Read-Stdin { return [Console]::In.ReadToEnd() }

if ($Mode -eq 'selftest') {
  $fail = 0
  function Check([string]$name, [string]$text, [bool]$full, [bool]$expect, [string[]]$allow = @()) {
    $got = (Find-Secrets $text $full $allow).Count -gt 0
    if ($got -eq $expect) { Write-Output "PASS $name" } else { Write-Output "FAIL $name"; $script:fail++ }
  }
  Check 'conn string with password'   ('"Default": "Server=.;Database=x;User Id=sa;Pass' + 'word=Hunter2xyz;"') $true $true
  Check 'conn string blank password'  '"Default": "Server=.;Database=x;User Id=sa;Password=;"'           $true $false
  Check 'json secret value'           '"ApiKey": "abcd1234efgh"'                                         $true $true
  Check 'json blank value'            '"ApiKey": ""'                                                      $true $false
  Check 'numeric token setting'       '"TokenLifetimeMinutes": "60"'                                      $true $false
  Check 'placeholder value'           '"Password": "<set with user-secrets>"'                             $true $false
  Check 'env style'                   'DB_PASSWORD=abc12345'                                              $true $true
  Check 'yaml style'                  '      MSSQL_SA_PASSWORD: Strong_Pass1'                             $true $true
  Check 'allow list'                  'MSSQL_SA_PASSWORD=Dev_Only1'                                       $true $false @('Dev_Only1')
  Check 'aws key anywhere'            ('x = "AKIA' + 'ABCDEFGHIJKLMNOP"')                                        $false $true
  Check 'plain code ignored'          'var password = GetPassword();'                                     $false $false
  Check 'UserSecretsId ignored'       '"UserSecretsId": "6f1c2a3b-aaaa-bbbb-cccc-1234567890ab"'           $true $false
  Check 'gitlab token anywhere'       ('TOKEN = "glpat' + '-AbCdEfGhIjKlMnOpQrSt12"')                            $false $true
  Check 'anthropic key anywhere'      ('key = "sk-ant' + '-api03-AbCdEfGhIjKlMnOpQrSt"')                         $false $true
  Check 'openai key anywhere'         ('k = "sk-proj' + '-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"')               $false $true
  Check 'stripe live key anywhere'    ('k = "sk_live' + '_AbCdEfGhIjKlMnOpQrSt12"')                              $false $true
  Check 'google api key anywhere'     ('k = "AI' + 'zaSyA1234567890abcdefghijklmnopqrstuv"')                     $false $true
  Check 'azure storage key anywhere'  ('Account' + 'Key=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcdefgh==')          $false $true
  Check 'short sk- word ignored'      'var task = "sk-learn-demo";'                                       $false $false
  Check 'jwt in config'               '"Jwt": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.abcdefghij1234"' $true $true
  Check 'jwt in code ignored'         'const t = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.abcdefghij1234"' $false $false
  Check 'npmrc auth token'            '//registry.npmjs.org/:_authToken=abcd1234efgh5678'                 $true $true
  function CheckFile([string]$name, [string]$file, [bool]$expect) {
    $got = (Test-KeyFile $file) -or (Test-ConfigLike $file)
    if ($got -eq $expect) { Write-Output "PASS $name" } else { Write-Output "FAIL $name"; $script:fail++ }
  }
  CheckFile 'ssh key id_ed25519'      'id_ed25519'      $true
  CheckFile 'ssh public key ignored'  'id_ed25519.pub'  $false
  CheckFile '.pgpass'                 '.pgpass'         $true
  CheckFile '.npmrc'                  '.npmrc'          $true
  CheckFile 'credentials.json'        'credentials.json' $true
  CheckFile 'plain source ignored'    'Program.cs'      $false
  function CheckOut([string]$name, [string]$text, [bool]$expect) {
    $got = (@(Find-OutputSecrets $text @())).Count -gt 0
    if ($got -eq $expect) { Write-Output "PASS $name" } else { Write-Output "FAIL $name"; $script:fail++ }
  }
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('sg-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'other') | Out-Null
  Set-Content -LiteralPath (Join-Path $tmp 'other\appsettings.json') -Value ('{"Db":{"Pass' + 'word":"fake12345"}}')
  $c1 = @(Get-ShellCandidates ('cd ' + (Join-Path $tmp 'other') + ' && sed -n 1,30p appsettings.json') $tmp)
  $hit1 = @($c1 | Where-Object { (Test-OneFile $_ @()).Count -gt 0 }).Count -gt 0
  if ($hit1) { Write-Output 'PASS cd then read is checked in the new folder' } else { Write-Output 'FAIL cd then read is checked in the new folder'; $fail++ }
  $c2 = @(Get-ShellCandidates 'cd other && cat appsettings.json' $tmp)
  $hit2 = @($c2 | Where-Object { (Test-OneFile $_ @()).Count -gt 0 }).Count -gt 0
  if ($hit2) { Write-Output 'PASS relative cd then read' } else { Write-Output 'FAIL relative cd then read'; $fail++ }
  Remove-Item -LiteralPath $tmp -Recurse -Force
  CheckOut 'output: conn string in log' ('info: using Server=db;User Id=sa;Pass' + 'word=Hunter2xyz;')     $true
  CheckOut 'output: gitlab token'       ('remote: https://oauth2:glpat' + '-AbCdEfGhIjKlMnOpQrSt12@gitlab') $true
  CheckOut 'output: normal build log'   'Build succeeded. 0 Warning(s) 0 Error(s)'                $false
  CheckOut 'output: blank password'     'Server=db;Password=;'                                    $false
  CheckOut 'output: code not a secret'  'var password = GetPassword();'                          $false
  CheckOut 'output: database url'       ('postgres://app:' + 'Hunter2xyz@localhost:5432/db')     $true
  CheckOut 'prompt: question about tokens' 'token: how does refresh work?'                        $false
  CheckOut 'prompt: file name with secret' 'secret-guard.md: fix the typo'                        $false
  if ($fail -gt 0) { Write-Output "$fail check(s) FAILED"; exit 1 } else { Write-Output 'All checks passed'; exit 0 }
}

try {
  $allow = Get-AllowList

  if ($Mode -eq 'scan') {
    $files = @()
    if ($Path) { $files = @($Path) } else { $files = @((Read-Stdin) -split "\r?\n" | Where-Object { $_.Trim() }) }
    $bad = 0
    foreach ($f in $files) {
      $hits = Test-OneFile (Resolve-Candidate $f) $allow
      if ($hits.Count -gt 0) { $bad++; Write-Output "secret-guard: $f -> $($hits -join ', ')" }
    }
    if ($bad -gt 0) {
      Write-Output 'secret-guard: commit blocked. Move the value to user-secrets or an env var, leave the setting blank, and rotate it if it was ever shared.'
      exit 1
    }
    exit 0
  }

  $raw = Read-Stdin
  if (-not $raw) { exit 0 }
  $j = $raw | ConvertFrom-Json

  if ($Mode -eq 'prompt') {
    # Prompts get the output rules (known tokens, real connection strings). The config-file rules blocked
    # ordinary sentences such as "token: how does refresh work?".
    $hits = @(Find-OutputSecrets ([string]$j.prompt) $allow)
    if ($hits.Count -gt 0) {
      Block 'secret-guard: your message looks like it contains a password, key or token, so it was NOT sent. Remove it and resend. Keep real values in dotnet user-secrets or environment variables. If it was a real secret, rotate it.'
    }
    exit 0
  }

  if ($Mode -eq 'output') {
    # Scan the decoded text of the tool's response (real line breaks, not JSON-escaped). Capped so huge outputs stay fast.
    $parts = New-Object System.Collections.Generic.List[string]
    function Add-Strings($o, [int]$depth) {
      if ($null -eq $o -or $depth -gt 20) { return }
      if ($o -is [string]) { $parts.Add($o); return }
      if ($o -is [System.Management.Automation.PSCustomObject]) { foreach ($p in $o.PSObject.Properties) { Add-Strings $p.Value ($depth + 1) }; return }
      if ($o -is [System.Collections.IEnumerable]) { foreach ($x in $o) { Add-Strings $x ($depth + 1) }; return }
    }
    Add-Strings $j.tool_response 0
    $text = $parts -join "`n"
    if ($text.Length -gt 1MB) { $text = $text.Substring(0, 1MB) }
    $kinds = @(Find-OutputSecrets $text $allow)
    if ($kinds.Count -gt 0) {
      $what = ($kinds -join ' and ')
      $tool = [string]$j.tool_name
      $msg = "secret-guard: WARNING. The output of $tool contained a $what. Claude has already seen it. Treat it as exposed and rotate it (see the rotation checklist in secret-guard.md)."
      $out = @{
        systemMessage      = $msg
        hookSpecificOutput = @{
          hookEventName     = 'PostToolUse'
          additionalContext = "secret-guard: the last tool output contained a $what. Do not repeat, quote, copy or use that value anywhere. Tell the user which command or file exposed it and that they should rotate it."
        }
      }
      Write-Output ($out | ConvertTo-Json -Depth 5 -Compress)
    }
    exit 0
  }

  # Mode = tool
  $tn = [string]$j.tool_name
  $ti = $j.tool_input
  if (-not $ti) { exit 0 }

  # 1) Files Claude is about to read (or search, or touch from the shell)
  $candidates = @()
  foreach ($k in 'file_path', 'notebook_path', 'path') {
    if ($ti.PSObject.Properties[$k] -and $ti.$k) { $candidates += [string]$ti.$k }
  }
  if ($tn -eq 'Grep' -and -not ($ti.PSObject.Properties['path'] -and $ti.path)) { $candidates += $ProjectDir }
  if (($tn -eq 'Bash' -or $tn -eq 'PowerShell') -and $ti.command) {
    $shellBase = if ($j.cwd) { [string]$j.cwd } else { $ProjectDir }
    $candidates += @(Get-ShellCandidates ([string]$ti.command) $shellBase)
  }

  $problems = @()
  foreach ($c in $candidates) {
    $p = Resolve-Candidate $c
    if (Test-Path -LiteralPath $p -PathType Container) {
      if ($tn -eq 'Grep' -or $tn -eq 'Glob') {
        $files = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '[\\/](node_modules|bin|obj|\.git)[\\/]' -and ((Test-ConfigLike $_.Name) -or (Test-KeyFile $_.Name)) } |
          Select-Object -First 200
        foreach ($f in $files) {
          $hits = Test-OneFile $f.FullName $allow
          if ($hits.Count -gt 0) { $problems += "$($f.FullName) -> $($hits -join ', ')" }
        }
      }
      continue
    }
    if ((Test-ConfigLike $p) -or (Test-KeyFile $p)) {
      $hits = Test-OneFile $p $allow
      if ($hits.Count -gt 0) { $problems += "$p -> $($hits -join ', ')" }
    }
  }
  if ($problems.Count -gt 0) {
    Block ("secret-guard: BLOCKED. This file appears to contain a secret: " + ($problems -join '; ') +
      ". Do NOT read, search or print it, and do not ask the user to paste the value. Tell the user to move the value to " +
      "'dotnet user-secrets' (or an environment variable), leave the setting blank, and rotate the secret if it was ever shared.")
  }

  # 2) Content Claude is about to write
  $content = @()
  foreach ($k in 'content', 'new_string') {
    if ($ti.PSObject.Properties[$k] -and $ti.$k) { $content += [string]$ti.$k }
  }
  if ($ti.PSObject.Properties['edits'] -and $ti.edits) {
    foreach ($e in $ti.edits) { if ($e.new_string) { $content += [string]$e.new_string } }
  }
  if ($content.Count -gt 0) {
    $target = if ($ti.PSObject.Properties['file_path']) { [string]$ti.file_path } else { '' }
    $full = if ($target) { Test-ConfigLike $target } else { $false }
    $hits = Find-Secrets ($content -join "`n") $full $allow
    if ($hits.Count -gt 0) {
      Block ("secret-guard: BLOCKED. The content you are writing contains a secret (" + ($hits -join ', ') +
        "). Never write passwords, keys or tokens into files. Leave the setting blank and tell the user to set it with 'dotnet user-secrets' or an environment variable.")
    }
  }
  exit 0
}
catch {
  # Fail open on unexpected errors so a bug never locks you out; the error is shown to you.
  [Console]::Error.WriteLine("secret-guard: internal error, check skipped: $($_.Exception.Message)")
  exit 1
}
