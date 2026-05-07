# GitHub Proxied Git Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable personal skill that runs GitHub `push`, `pull`, and `fetch` through Clash Verge with repository-local Git proxy config and safe Clash Verge lifecycle cleanup.

**Architecture:** The implementation creates a self-contained skill directory with one `SKILL.md` and one PowerShell runner. The skill document defines when and how to use the capability, while the PowerShell script owns Clash Verge startup detection, repository-local Git proxy configuration, fixed-operation dispatch, push verification, and conditional shutdown.

**Tech Stack:** Markdown, PowerShell, Git for Windows

---

### Task 1: Create The Skill Directory And Initial Skill Document

**Files:**
- Create: `E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\SKILL.md`

- [ ] **Step 1: Write the failing skill skeleton**

Create `E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\SKILL.md` with this minimal failing content:

```md
---
name: github-proxied-git
description: Use when GitHub push, pull, or fetch fails behind a restricted network and needs temporary Clash Verge proxy support with repository-local Git configuration.
---

# GitHub Proxied Git

## Overview

Placeholder overview.
```

- [ ] **Step 2: Verify the skill file exists but is incomplete**

Run:

```powershell
Get-Content -Path 'E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\SKILL.md'
```

Expected:

- The file exists
- It only contains the placeholder overview and does not yet satisfy the spec

- [ ] **Step 3: Replace the failing skeleton with the full skill document**

Update `E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\SKILL.md` to:

```md
---
name: github-proxied-git
description: Use when GitHub push, pull, or fetch fails behind a restricted network, especially with HTTP 302, RPC failed, or remote end hung up unexpectedly, and the operation should run through Clash Verge with repository-local Git proxy settings.
---

# GitHub Proxied Git

## Overview

Run fixed GitHub Git operations through Clash Verge when the current network blocks direct GitHub traffic. This skill starts Clash Verge only when needed, applies repository-local proxy settings, runs a fixed `push`, `pull`, or `fetch` operation, and only closes Clash Verge if this run started it.

## When To Use

Use this skill when:

- `git push`, `git pull`, or `git fetch` against GitHub fails on the current network
- Errors include `HTTP 302`, `RPC failed`, `remote end hung up unexpectedly`, or similar upload-stage disconnects
- GitHub access is known to require Clash Verge on the current machine

Do not use this skill when:

- The remote is not GitHub
- The task requires arbitrary Git command passthrough
- The task needs global Git proxy changes

## Supported Operations

- `push`
- `pull`
- `fetch`

The wrapper only supports these fixed operations. It does not accept an arbitrary Git command string.

## Workflow

1. Confirm the target repository is the current working repository.
2. Run the PowerShell wrapper with one fixed operation.
3. Let the wrapper detect whether Clash Verge is already running.
4. Let the wrapper apply repository-local Git proxy settings for GitHub only.
5. Review the wrapper result, especially the remote verification step after `push`.

## Script Path

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1" -Operation push
```

Swap `push` for `pull` or `fetch` as needed.

## Expected Behavior

- If Clash Verge is not running, the script starts `C:\Program Files\Clash Verge\clash-verge.exe`
- If Clash Verge is already running, the script reuses it and leaves it running afterward
- Git config changes are written with `--local` only
- `push` checks whether the remote branch head matches the local branch head before treating an error as a real failure

## Verification

After a successful `push`, verify with:

```powershell
git rev-parse HEAD
git ls-remote origin HEAD
```

After a successful `fetch` or `pull`, verify with:

```powershell
git status --short --branch
```

## Common Pitfalls

| Problem | Handling |
|---------|----------|
| Clash Verge executable not found | Confirm `C:\Program Files\Clash Verge\clash-verge.exe` exists before running |
| `push` still reports a transport error | Check whether remote and local branch heads already match before retrying |
| Repository has local uncommitted changes | Review `git status --short --branch` before running `pull` |
| The user already had Clash Verge open | Do not close it unless the wrapper started it |
```

- [ ] **Step 4: Verify the full skill document content**

Run:

```powershell
Get-Content -Path 'E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\SKILL.md'
```

Expected:

- The frontmatter uses `name` and `description`
- The document includes fixed operations, script path, verification steps, and lifecycle behavior

- [ ] **Step 5: Commit**

Run:

```bash
git add "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\SKILL.md"
git commit -m "feat: add github proxied git skill doc"
```

### Task 2: Implement The Clash Verge Git Wrapper Script

**Files:**
- Create: `E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1`

- [ ] **Step 1: Write the failing script stub**

Create `E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1` with this failing stub:

```powershell
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('push', 'pull', 'fetch')]
  [string]$Operation
)

throw "Not implemented"
```

- [ ] **Step 2: Run the script to verify it fails intentionally**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1" -Operation fetch
```

Expected:

- FAIL with `Not implemented`

- [ ] **Step 3: Replace the stub with the full implementation**

Update `E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1` to:

```powershell
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('push', 'pull', 'fetch')]
  [string]$Operation,
  [string]$Remote = 'origin',
  [string]$ProxyScheme = 'socks5h',
  [string]$ProxyHost = '127.0.0.1',
  [int]$ProxyPort = 7897,
  [int]$StartupWaitSeconds = 8,
  [int]$MaxCheckRetries = 3,
  [int]$MaxPushRetries = 3
)

$ErrorActionPreference = 'Stop'

$clashPath = 'C:\Program Files\Clash Verge\clash-verge.exe'
$clashStartedByScript = $false
$clashProcess = $null

function Invoke-Git {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GitArgs
  )

  & git @GitArgs
  if ($LASTEXITCODE -ne 0) {
    throw ("git " + ($GitArgs -join ' ') + " failed with exit code " + $LASTEXITCODE)
  }
}

function Test-InGitRepository {
  return (Test-Path -LiteralPath '.git')
}

function Get-CurrentBranch {
  return (& git rev-parse --abbrev-ref HEAD).Trim()
}

function Get-BranchHead {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BranchName
  )

  return (& git rev-parse $BranchName).Trim()
}

function Get-RemoteBranchHead {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteName,
    [Parameter(Mandatory = $true)]
    [string]$BranchName
  )

  $remoteLine = (& git ls-remote $RemoteName "refs/heads/$BranchName").Trim()
  if (-not $remoteLine) {
    return ''
  }

  return ($remoteLine -split "\s+")[0]
}

function Test-RemoteMatchesLocal {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteName,
    [Parameter(Mandatory = $true)]
    [string]$BranchName
  )

  $local = Get-BranchHead -BranchName $BranchName
  $remote = Get-RemoteBranchHead -RemoteName $RemoteName -BranchName $BranchName
  return ($local -and $remote -and ($local -eq $remote))
}

function Test-ClashRunning {
  $process = Get-Process -Name 'clash-verge' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $process) {
    return $null
  }

  return $process
}

function Start-ClashIfNeeded {
  $existing = Test-ClashRunning
  if ($null -ne $existing) {
    return @{
      Started = $false
      Process = $existing
    }
  }

  if (-not (Test-Path -LiteralPath $clashPath)) {
    throw "Clash Verge executable not found at $clashPath"
  }

  $startedProcess = Start-Process -FilePath $clashPath -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds $StartupWaitSeconds

  return @{
    Started = $true
    Process = $startedProcess
  }
}

function Stop-ClashIfStarted {
  param(
    [bool]$Started,
    $Process
  )

  if (-not $Started) {
    return
  }

  if ($null -eq $Process) {
    return
  }

  try {
    if (-not $Process.HasExited) {
      Stop-Process -Id $Process.Id -Force
    }
  } catch {
    Write-Warning ("Failed to stop Clash Verge process " + $Process.Id + ": " + $_.Exception.Message)
  }
}

function Set-RepositoryLocalGitProxyConfig {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Scheme,
    [Parameter(Mandatory = $true)]
    [string]$Host,
    [Parameter(Mandatory = $true)]
    [int]$Port
  )

  $proxyUrl = "${Scheme}://${Host}:$Port"

  Invoke-Git config --local http.sslBackend schannel
  Invoke-Git config --local http.version HTTP/1.1
  Invoke-Git config --local http.expect false
  Invoke-Git config --local http.sslVerify true
  Invoke-Git config --local http.maxRequests 1
  Invoke-Git config --local core.compression 0

  & git config --local --unset-all http.proxy 2>$null
  & git config --local --unset-all https.proxy 2>$null
  & git config --local --unset http.https://github.com.proxy 2>$null

  Invoke-Git config --local http.https://github.com.proxy $proxyUrl
  Invoke-Git config --local http.lowSpeedLimit 0
  Invoke-Git config --local http.postBuffer 524288000
}

function Test-RemoteReachable {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteName,
    [Parameter(Mandatory = $true)]
    [int]$Retries
  )

  for ($attempt = 1; $attempt -le $Retries; $attempt++) {
    & git ls-remote $RemoteName | Out-Null
    if ($LASTEXITCODE -eq 0) {
      return $true
    }

    if ($attempt -lt $Retries) {
      Start-Sleep -Seconds 2
    }
  }

  return $false
}

function Invoke-FixedOperation {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Op,
    [Parameter(Mandatory = $true)]
    [string]$RemoteName,
    [Parameter(Mandatory = $true)]
    [int]$PushRetries
  )

  if ($Op -eq 'fetch') {
    Invoke-Git fetch $RemoteName
    return
  }

  if ($Op -eq 'pull') {
    Invoke-Git pull
    return
  }

  $branch = Get-CurrentBranch
  for ($attempt = 1; $attempt -le $PushRetries; $attempt++) {
    try {
      Invoke-Git push -u $RemoteName $branch
      return
    } catch {
      if (Test-RemoteMatchesLocal -RemoteName $RemoteName -BranchName $branch) {
        Write-Host "[warn] push transport failed but remote already matches local branch head"
        return
      }

      if ($attempt -ge $PushRetries) {
        throw
      }

      Start-Sleep -Seconds 2
    }
  }
}

if (-not (Test-InGitRepository)) {
  throw 'No .git directory found. Run this script from a repository root.'
}

Invoke-Git --version | Out-Null

$clashInfo = Start-ClashIfNeeded
$clashStartedByScript = $clashInfo.Started
$clashProcess = $clashInfo.Process

try {
  Set-RepositoryLocalGitProxyConfig -Scheme $ProxyScheme -Host $ProxyHost -Port $ProxyPort

  if (-not (Test-RemoteReachable -RemoteName $Remote -Retries $MaxCheckRetries)) {
    Write-Warning 'GitHub remote reachability check failed before the main operation. Continuing anyway.'
  }

  Invoke-FixedOperation -Op $Operation -RemoteName $Remote -PushRetries $MaxPushRetries
} finally {
  Stop-ClashIfStarted -Started $clashStartedByScript -Process $clashProcess
}
```

- [ ] **Step 4: Run the script with `fetch` to verify the implementation executes**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1" -Operation fetch
```

Expected:

- PASS without `Not implemented`
- The script either starts Clash Verge or reuses the existing one
- The current repository receives repository-local Git proxy settings

- [ ] **Step 5: Commit**

Run:

```bash
git add "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1"
git commit -m "feat: add clash wrapped github git runner"
```

### Task 3: Verify Push, Lifecycle Cleanup, And Documentation Accuracy

**Files:**
- Modify: `E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\SKILL.md`
- Modify: `E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1`

- [ ] **Step 1: Run a push-path validation with Clash Verge initially closed**

Run:

```powershell
Get-Process -Name clash-verge -ErrorAction SilentlyContinue
powershell -ExecutionPolicy Bypass -File "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1" -Operation push
Get-Process -Name clash-verge -ErrorAction SilentlyContinue
```

Expected:

- Before the run, no `clash-verge` process is required
- During the run, the script can start Clash Verge
- After the run, if the script started Clash Verge, it is no longer running

- [ ] **Step 2: Run a fetch-path validation with Clash Verge initially open**

Run:

```powershell
Start-Process -FilePath 'C:\Program Files\Clash Verge\clash-verge.exe'
Start-Sleep -Seconds 8
$before = (Get-Process -Name clash-verge -ErrorAction SilentlyContinue | Select-Object -First 1).Id
powershell -ExecutionPolicy Bypass -File "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1" -Operation fetch
$after = (Get-Process -Name clash-verge -ErrorAction SilentlyContinue | Select-Object -First 1).Id
"before=$before after=$after"
```

Expected:

- PASS
- `before` and `after` are both populated
- The existing Clash Verge instance remains running after the wrapper completes

- [ ] **Step 3: Adjust the script or skill document only if the verification exposed a mismatch**

If verification reveals a mismatch, update the relevant file inline. The update must be concrete. For example, if the wrapper actually uses remote `origin` only for `fetch` and `push`, make sure the skill document says exactly that:

```md
## Supported Operations

- `push`: runs `git push -u origin <current-branch>`
- `pull`: runs `git pull`
- `fetch`: runs `git fetch origin`
```

- [ ] **Step 4: Run final verification commands**

Run:

```powershell
Get-Content -Path "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\SKILL.md"
Get-Content -Path "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1"
git status --short --branch
```

Expected:

- The skill document matches the actual script behavior
- The script still supports only `push`, `pull`, and `fetch`
- Git status shows only the intended skill-related changes for this task

- [ ] **Step 5: Commit**

Run:

```bash
git add "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\SKILL.md" "E:\source_code\superpowers\foam-daily-notes\notes\skills\github-proxied-git\invoke-github-git-with-clash.ps1"
git commit -m "test: verify github proxied git skill behavior"
```
