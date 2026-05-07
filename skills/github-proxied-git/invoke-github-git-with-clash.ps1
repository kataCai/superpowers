param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('push', 'pull', 'fetch')]
  [string]$Operation,

  [string]$Remote = 'origin'
)

$ErrorActionPreference = 'Stop'
$script:ClashVergePath = 'C:\Program Files\Clash Verge\clash-verge.exe'
$script:ClashVergeProxyHost = '127.0.0.1'
$script:ClashVergeProxyPort = 7897
$script:StartedClashVerge = $false
$script:ClashVergeInstallDir = Split-Path -Parent $script:ClashVergePath
$script:ExistingClashVergeProcessIds = @()
$script:StartedClashVergeProcessIds = @()
$script:InternetSettingsRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

<#
.SYNOPSIS
  执行 Git 命令并把非零退出码转换为可捕获的异常。

.DESCRIPTION
  该包装器只服务于仓库级代理脚本，因此这里统一处理 Git 进程退出码，
  避免上层逻辑漏判命令失败或在失败路径上跳过清理。

.PARAMETER GitArgs
  传给 git.exe 的完整参数列表。

.OUTPUTS
  无直接返回值；成功时仅保证 Git 命令完成，失败时抛出异常。
#>
function Invoke-Git {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GitArgs
  )

  & git @GitArgs
  if ($LASTEXITCODE -ne 0) {
    throw ("git " + ($GitArgs -join ' ') + " 失败 (exit $LASTEXITCODE)")
  }
}

<#
.SYNOPSIS
  获取当前仓库根目录。

.DESCRIPTION
  通过 git rev-parse 判断脚本是否运行在有效仓库中，并拿到仓库根目录。
  这样即使脚本从子目录启动，也能正确应用 --local 配置。

.OUTPUTS
  仓库根目录的绝对路径。
#>
function Get-RepositoryRoot {
  $root = (& git rev-parse --show-toplevel).Trim()
  if (-not $root) {
    throw '未能定位当前 Git 仓库根目录。'
  }
  return $root
}

<#
.SYNOPSIS
  获取当前机器上与 Clash Verge 安装目录关联的进程集合。

.DESCRIPTION
  Clash Verge 的桌面启动器与实际常驻进程名称可能不同，例如实际代理进程
  可能表现为 `verge-mihomo.exe`。因此这里不能只按单一进程名判断，而要
  结合安装目录和已知进程名过滤，避免把“已运行”误判成“未运行”。

.OUTPUTS
  进程对象数组。若没有匹配进程，则返回空数组。
#>
function Get-ClashVergeProcesses {
  $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
      try {
        $pathMatches = $false
        if ($_.Path) {
          $pathMatches = $_.Path.StartsWith($script:ClashVergeInstallDir, [System.StringComparison]::OrdinalIgnoreCase)
        }

        return $pathMatches -or ($_.ProcessName -in @('clash-verge', 'verge-mihomo'))
      } catch {
        return $false
      }
    })

  return $processes
}

<#
.SYNOPSIS
  判断 Clash Verge 是否已经在运行。

.DESCRIPTION
  只检查进程存在与否，不主动终止既有进程。这样可以确保：
  1. 已经打开 Clash Verge 的用户会话不受影响；
  2. 脚本只清理自己启动的实例。

.OUTPUTS
  布尔值，表示 Clash Verge 是否已运行。
#>
function Test-ClashVergeRunning {
  return [bool](Get-ClashVergeProcesses)
}

<#
.SYNOPSIS
  确保 Clash Verge 处于运行状态。

.DESCRIPTION
  如果当前已经存在 Clash Verge 进程，则直接复用；否则按固定路径启动。
  启动时使用 Hidden，避免脚本触发额外的交互窗口，并保存 Start-Process
  返回的进程对象，便于后续只关闭本脚本启动的那个实例。

.OUTPUTS
  无直接返回值；通过脚本级状态标记是否由本脚本启动。
#>
function Ensure-ClashVergeRunning {
  $existingProcesses = @(Get-ClashVergeProcesses)
  if ($existingProcesses.Count -gt 0) {
    $script:ExistingClashVergeProcessIds = @($existingProcesses | Select-Object -ExpandProperty Id)
    Write-Host '[状态] 检测到已有 Clash Verge 进程，复用现有实例。' -ForegroundColor Cyan
    return
  }

  if (-not (Test-Path -LiteralPath $script:ClashVergePath)) {
    throw "未找到 Clash Verge 可执行文件：$script:ClashVergePath"
  }

  Write-Host '[状态] 未检测到 Clash Verge，按固定路径启动。' -ForegroundColor Cyan
  $script:ExistingClashVergeProcessIds = @()
  Start-Process -FilePath $script:ClashVergePath -WindowStyle Hidden | Out-Null

  for ($i = 0; $i -lt 20; $i++) {
    if (Test-ClashVergeRunning) {
      $script:StartedClashVerge = $true
      Write-Host '[状态] Clash Verge 已启动。' -ForegroundColor Cyan
      return
    }
    Start-Sleep -Milliseconds 250
  }

  throw '已尝试启动 Clash Verge，但在等待窗口内未观察到进程。'
}

<#
.SYNOPSIS
  等待 Clash Verge 的本地代理端口可用。

.DESCRIPTION
  Clash Verge 进程出现并不代表代理端口已经可连通。脚本如果过早执行 git，
  仍可能在第一次握手时失败。因此这里补一个端口就绪等待，保证后续仓库级
  Git 配置真正能被使用。

.PARAMETER Host
  代理监听地址，固定为本机回环地址。

.PARAMETER Port
  代理监听端口，固定为 Clash Verge 约定端口。

.PARAMETER TimeoutSeconds
  最长等待秒数。

.OUTPUTS
  无直接返回值；超时则抛出异常。
#>
function Wait-ForClashVergeProxy {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProxyHost,

    [Parameter(Mandatory = $true)]
    [int]$ProxyPort,

    [int]$TimeoutSeconds = 20
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $connection = Test-NetConnection -ComputerName $ProxyHost -Port $ProxyPort -WarningAction SilentlyContinue
    if ($connection.TcpTestSucceeded) {
      Write-Host ("[状态] Clash Verge 代理端口 {0}:{1} 已就绪。" -f $ProxyHost, $ProxyPort) -ForegroundColor Cyan
      return
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  throw ("Clash Verge 已启动，但代理端口 {0}:{1} 在 {2} 秒内未就绪。" -f $ProxyHost, $ProxyPort, $TimeoutSeconds)
}

<#
.SYNOPSIS
  记录由本脚本新拉起的 Clash Verge 进程 ID。

.DESCRIPTION
  Clash Verge 启动器可能派生出真正的代理子进程，因此不能只依赖
  `Start-Process` 的返回对象。这里在代理端口就绪后，再用“当前进程集合”
  减去“脚本启动前已存在的集合”，只记录本轮新出现的进程 ID，用于精确清理。

.OUTPUTS
  无直接返回值；结果写入脚本级进程 ID 集合。
#>
function Save-StartedClashVergeProcessIds {
  if (-not $script:StartedClashVerge) {
    return
  }

  $currentProcesses = @(Get-ClashVergeProcesses)
  $script:StartedClashVergeProcessIds = @(
    $currentProcesses |
      Where-Object { $script:ExistingClashVergeProcessIds -notcontains $_.Id } |
      Select-Object -ExpandProperty Id
  )
}

<#
.SYNOPSIS
  只清理由本脚本启动的 Clash Verge。

.DESCRIPTION
  失败路径和成功路径都必须执行这里的清理逻辑，但前提是脚本真的启动过
  Clash Verge。这里只按保存的进程对象 PID 收尾，避免误杀用户原本打开的
  其他代理进程，也避免扫描同名进程时影响到非本脚本启动的实例。
  如果代理端口等待阶段提前失败，可能还没来得及显式记录新进程 ID，因此
  这里会再用“当前进程集合 - 启动前进程集合”兜底一次，避免留下本次启动的
  Clash Verge 进程。

.OUTPUTS
  无直接返回值。
#>
function Stop-StartedClashVerge {
  if (-not $script:StartedClashVerge) {
    return
  }

  if ($script:StartedClashVergeProcessIds.Count -eq 0) {
    $script:StartedClashVergeProcessIds = @(
      @(Get-ClashVergeProcesses) |
        Where-Object { $script:ExistingClashVergeProcessIds -notcontains $_.Id } |
        Select-Object -ExpandProperty Id
    )
  }

  if ($script:StartedClashVergeProcessIds.Count -eq 0) {
    return
  }

  foreach ($processId in $script:StartedClashVergeProcessIds) {
    try {
      $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
      if ($null -eq $process) {
        continue
      }

      Stop-Process -Id $processId -Force -ErrorAction Stop
    } catch {
      Write-Host ("[警告] 关闭 Clash Verge 失败，进程 ID：{0}" -f $processId) -ForegroundColor Yellow
    }
  }
}

<#
.SYNOPSIS
  强制关闭当前用户的 Windows 系统代理。

.DESCRIPTION
  当前 skill 的使用场景要求在脚本退出后完全关闭系统代理，而不是恢复到
  脚本启动前的状态。因此这里会无条件关闭 `ProxyEnable`，并清空
  `ProxyServer`、`AutoConfigURL`、`ProxyOverride`，并关闭自动检测；
  同时广播 Internet 设置变更，确保 Windows 设置页和依赖系统代理的应用
  尽快感知到关闭结果。

.OUTPUTS
  无直接返回值。
#>
function Disable-WindowsSystemProxy {
  Set-ItemProperty -Path $script:InternetSettingsRegistryPath -Name ProxyEnable -Value 0
  Set-ItemProperty -Path $script:InternetSettingsRegistryPath -Name ProxyServer -Value ''
  Set-ItemProperty -Path $script:InternetSettingsRegistryPath -Name AutoConfigURL -Value ''
  Set-ItemProperty -Path $script:InternetSettingsRegistryPath -Name ProxyOverride -Value ''
  Set-ItemProperty -Path $script:InternetSettingsRegistryPath -Name AutoDetect -Value 0

  Add-Type -Namespace WinInet -Name NativeMethods -MemberDefinition @'
    [System.Runtime.InteropServices.DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(System.IntPtr hInternet, int dwOption, System.IntPtr lpBuffer, int dwBufferLength);
'@

  $internetOptionSettingsChanged = 39
  $internetOptionRefresh = 37
  $settingsChanged = [WinInet.NativeMethods]::InternetSetOption([System.IntPtr]::Zero, $internetOptionSettingsChanged, [System.IntPtr]::Zero, 0)
  $refresh = [WinInet.NativeMethods]::InternetSetOption([System.IntPtr]::Zero, $internetOptionRefresh, [System.IntPtr]::Zero, 0)
  if (-not $settingsChanged -or -not $refresh) {
    Write-Host '[警告] 系统代理注册表已更新，但 WinInet 刷新返回失败，个别应用可能需要重新读取设置。' -ForegroundColor Yellow
  }
}

<#
.SYNOPSIS
  清理并重新写入仓库级 Git 代理配置。

.DESCRIPTION
  只使用 --local 写入当前仓库的配置，避免污染全局 Git 环境。先清掉可能
  遗留的代理字段，再写入 GitHub 专用代理，保证重复执行时结果稳定。

.PARAMETER ProxyUrl
  只作用于 github.com 的代理地址。

.OUTPUTS
  无直接返回值。
#>
function Set-RepositoryGitProxy {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProxyUrl
  )

  Invoke-Git config --local http.sslBackend schannel
  Invoke-Git config --local http.version HTTP/1.1
  Invoke-Git config --local http.expect false
  Invoke-Git config --local http.sslVerify true
  Invoke-Git config --local http.maxRequests 1
  Invoke-Git config --local core.compression 0
  Invoke-Git config --local http.lowSpeedLimit 0
  Invoke-Git config --local http.postBuffer 524288000

  # 先清理旧代理，避免多次执行时残留的配置互相干扰。
  & git config --local --unset-all http.proxy 2>$null
  & git config --local --unset-all https.proxy 2>$null
  & git config --local --unset-all http.https://github.com.proxy 2>$null

  Invoke-Git config --local "http.https://github.com.proxy" $ProxyUrl
}

<#
.SYNOPSIS
  获取当前分支名。

.DESCRIPTION
  该结果只用于固定的 push 行为。若仓库处于 detached HEAD 状态，脚本无法
  安全推断推送目标分支，应明确失败而不是猜测。

.OUTPUTS
  当前分支名。
#>
function Get-CurrentBranchName {
  $branch = (& git branch --show-current).Trim()
  if (-not $branch) {
    throw '当前仓库处于 detached HEAD 状态，无法执行固定的 push。'
  }
  return $branch
}

<#
.SYNOPSIS
  获取本地分支或 HEAD 的提交哈希。

.DESCRIPTION
  该结果用于 push 失败后的收尾判断，判断远端是否实际上已经与本地一致。

.PARAMETER RefName
  需要解析的 git 引用名称。

.OUTPUTS
  提交哈希字符串。
#>
function Get-BranchHead {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RefName
  )

  return (& git rev-parse $RefName).Trim()
}

<#
.SYNOPSIS
  获取远端分支头提交哈希。

.DESCRIPTION
  push 过程中如果网络中断但远端实际上已更新到本地提交，脚本需要把该
  情况视为成功。这里直接读取 refs/heads/<branch>，只比较分支头，不比较
  其他远端引用。远端返回结果按空白分隔解析，避免把整行文本当作哈希。

.PARAMETER RemoteName
  远端名称，默认 origin。

.PARAMETER BranchName
  远端分支名。

.OUTPUTS
  若远端分支存在则返回提交哈希，否则返回空字符串。
#>
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
  return ($remoteLine -split '\s+')[0]
}

<#
.SYNOPSIS
  判断远端分支头是否已经与本地一致。

.DESCRIPTION
  仅用于 push 的容错路径。如果本地与远端提交一致，即使 push 报出传输
  异常，也按成功处理，避免把“已成功写入但连接中断”误判成失败。

.PARAMETER RemoteName
  远端名称，默认 origin。

.PARAMETER BranchName
  分支名。

.OUTPUTS
  布尔值，表示远端分支头是否与本地一致。
#>
function Test-RemoteMatchesLocal {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteName,
    [Parameter(Mandatory = $true)]
    [string]$BranchName
  )

  $local = Get-BranchHead -RefName 'HEAD'
  $remote = Get-RemoteBranchHead -RemoteName $RemoteName -BranchName $BranchName
  return ($local -and $remote -and ($local -eq $remote))
}

try {
  $repoRoot = Get-RepositoryRoot
  Set-Location -LiteralPath $repoRoot

  Ensure-ClashVergeRunning

  Wait-ForClashVergeProxy -ProxyHost $script:ClashVergeProxyHost -ProxyPort $script:ClashVergeProxyPort
  Save-StartedClashVergeProcessIds

  $proxyUrl = ('socks5h://{0}:{1}' -f $script:ClashVergeProxyHost, $script:ClashVergeProxyPort)
  Set-RepositoryGitProxy -ProxyUrl $proxyUrl

  $branch = $null
  if ($Operation -eq 'push') {
    $branch = Get-CurrentBranchName
  }

  switch ($Operation) {
    'fetch' {
      Write-Host ("[执行] git fetch {0}" -f $Remote) -ForegroundColor Cyan
      Invoke-Git fetch $Remote
      Write-Host '[完成] fetch 执行成功。' -ForegroundColor Green
    }
    'pull' {
      Write-Host '[执行] git pull' -ForegroundColor Cyan
      Invoke-Git pull
      Write-Host '[完成] pull 执行成功。' -ForegroundColor Green
    }
    'push' {
      Write-Host ("[执行] git push {0} {1}" -f $Remote, $branch) -ForegroundColor Cyan
      $pushSucceeded = $false
      try {
        Invoke-Git push $Remote $branch
        $pushSucceeded = $true
      } catch {
        if (Test-RemoteMatchesLocal -RemoteName $Remote -BranchName $branch) {
          # 失败但远端分支头已经等于本地 HEAD 时，说明网络侧完成了实际写入。
          Write-Host '[提示] push 报错但远端头已与本地一致，按成功处理。' -ForegroundColor Yellow
          $pushSucceeded = $true
        } else {
          throw
        }
      }

      if (-not $pushSucceeded) {
        throw 'push 未成功。'
      }

      $local = Get-BranchHead -RefName 'HEAD'
      $remoteHead = Get-RemoteBranchHead -RemoteName $Remote -BranchName $branch
      if ($local -and $remoteHead -and ($local -eq $remoteHead)) {
        Write-Host ("[成功] 本地与远端哈希一致：{0}" -f $local) -ForegroundColor Green
      } else {
        Write-Host ("[警告] push 后哈希不一致：local={0} remote={1}" -f $local, $remoteHead) -ForegroundColor Yellow
      }
    }
  }
} finally {
  Stop-StartedClashVerge
  Disable-WindowsSystemProxy
}
