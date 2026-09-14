#requires -Version 5.1
<##
.SYNOPSIS
    安全清理本机常见的临时文件、应用缓存和日志。

.DESCRIPTION
    默认直接清理；-Preview 只统计，不删除。
    已占用、无权限或删除失败的内容会保留，并按实际删除前后的差值统计。
    Windows 更新下载缓存默认不处理；只有以管理员身份运行且传入
    -IncludeWindowsUpdateCache 时才会暂停相关服务、清理并恢复服务。

.EXAMPLE
    .\cleanup.ps1
    .\cleanup.ps1 -Preview
    .\cleanup.ps1 -TempOlderThanDays 7
    .\cleanup.ps1 -IncludeWindowsUpdateCache
##>
[CmdletBinding()]
param(
    [switch]$Preview,

    [ValidateRange(0, 3650)]
    [int]$TempOlderThanDays = 3,

    [switch]$IncludeWindowsUpdateCache
)

$ErrorActionPreference = 'Stop'
$script:FreedBytes = [double]0

function Get-SafeFiles {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }

    # 手工遍历目录，避免递归穿过 junction / symlink 到目录外。
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue($Path)
    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
            else { $item }
        }
    }
}

function Get-SafeDirectories {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }

    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue($Path)
    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $current -Force -Directory -ErrorAction SilentlyContinue)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $item
            $pending.Enqueue($item.FullName)
        }
    }
}

function Get-DirectorySize {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return [double]0 }
    $sum = @(Get-SafeFiles $Path | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [double]0 }
    return [double]$sum
}

function Get-PathsSize {
    param([string[]]$Paths)

    $sum = @($Paths | ForEach-Object { Get-DirectorySize $_ } | Measure-Object -Sum).Sum
    if ($null -eq $sum) { return [double]0 }
    return [double]$sum
}

function Remove-EmptyDirectories {
    param([Parameter(Mandatory)][string]$Path)

    Get-SafeDirectories $Path |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if (-not @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)[0]) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
}

function Remove-DirectoryContents {
    param([string]$Path)

    if ($Preview -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    Get-SafeFiles $Path | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
    Remove-EmptyDirectories $Path
}

function Get-OldTempFilesSize {
    param([string]$Path, [datetime]$OlderThan)

    $sum = @(Get-SafeFiles $Path |
        Where-Object { $_.LastWriteTime -lt $OlderThan } |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [double]0 }
    return [double]$sum
}

function Remove-OldTempFiles {
    param([string]$Path, [datetime]$OlderThan)

    if ($Preview) { return }
    Get-SafeFiles $Path |
        Where-Object { $_.LastWriteTime -lt $OlderThan } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    Remove-EmptyDirectories $Path
}

function Test-ProcessRunning {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Clean-Category {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$SizeBefore,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $before = [double](& $SizeBefore)
    if ($before -le 0) {
        Write-Host ('  {0,-28} 无可清理内容' -f $Name) -ForegroundColor DarkGray
        return
    }

    if ($Preview) {
        $script:FreedBytes += $before
        Write-Host ('  {0,-28} 可释放 {1,8:N1} MB' -f $Name, ($before / 1MB)) -ForegroundColor Cyan
        return
    }

    try {
        & $Action
    }
    catch {
        Write-Host ('  {0,-28} 清理时出现问题：{1}' -f $Name, $_.Exception.Message) -ForegroundColor DarkYellow
    }

    $after = [double](& $SizeBefore)
    $freed = [Math]::Max([double]0, $before - $after)
    $script:FreedBytes += $freed
    Write-Host ('  {0,-28} 已释放 {1,8:N1} MB' -f $Name, ($freed / 1MB)) -ForegroundColor Green
}

function Get-CodexInstallDirectories {
    param([string]$Path, [datetime]$OlderThan)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Path -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like 'codex-runtime-install-*' -and
            $_.LastWriteTime -lt $OlderThan -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        })
}

Write-Host ''
Write-Host ('========== 垃圾清理 {0} ==========' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Yellow
if ($Preview) { Write-Host '[预览模式] 只统计，不删除。结果为理论上可释放的空间。' -ForegroundColor Cyan }

$cutoff = (Get-Date).AddDays(-$TempOlderThanDays)
$tempDir = Join-Path $env:LOCALAPPDATA 'Temp'
Clean-Category "Temp 临时文件(>${TempOlderThanDays}天)" `
    -SizeBefore { Get-OldTempFilesSize $tempDir $cutoff } `
    -Action { Remove-OldTempFiles $tempDir $cutoff }

$pipCache = Join-Path $env:LOCALAPPDATA 'pip'
Clean-Category 'pip 下载缓存' `
    -SizeBefore { Get-DirectorySize $pipCache } `
    -Action { Remove-DirectoryContents $pipCache }

$crashDumps = Join-Path $env:LOCALAPPDATA 'CrashDumps'
Clean-Category '崩溃转储 CrashDumps' `
    -SizeBefore { Get-DirectorySize $crashDumps } `
    -Action { Remove-DirectoryContents $crashDumps }

$codexDir = Join-Path $env:USERPROFILE '.cache\codex-runtimes'
$codexCutoff = (Get-Date).AddDays(-1)
Clean-Category 'Codex 旧安装残留' `
    -SizeBefore { Get-PathsSize @(Get-CodexInstallDirectories $codexDir $codexCutoff | ForEach-Object FullName) } `
    -Action {
        Get-CodexInstallDirectories $codexDir $codexCutoff | ForEach-Object {
            Remove-DirectoryContents $_.FullName
            if (-not @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)[0]) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

$edgeCache = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache'
if (Test-ProcessRunning 'msedge') {
    Write-Host '  Edge 浏览器缓存               Edge 正在运行，已跳过（关闭后再清理）' -ForegroundColor DarkYellow
}
else {
    Clean-Category 'Edge 浏览器缓存' `
        -SizeBefore { Get-DirectorySize $edgeCache } `
        -Action { Remove-DirectoryContents $edgeCache }
}

$codePaths = @(
    (Join-Path $env:APPDATA 'Code\Cache'),
    (Join-Path $env:APPDATA 'Code\CachedData'),
    (Join-Path $env:APPDATA 'Code\logs')
)
if (Test-ProcessRunning 'Code') {
    Write-Host '  VS Code 缓存/日志              VS Code 正在运行，已跳过（关闭后再清理）' -ForegroundColor DarkYellow
}
else {
    Clean-Category 'VS Code 缓存/日志' `
        -SizeBefore { Get-PathsSize $codePaths } `
        -Action { $codePaths | ForEach-Object { Remove-DirectoryContents $_ } }
}

$traeLogs = Join-Path $env:APPDATA 'Trae CN\logs'
Clean-Category 'Trae 日志' `
    -SizeBefore { Get-DirectorySize $traeLogs } `
    -Action { Remove-DirectoryContents $traeLogs }

$inetCache = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache'
Clean-Category 'INetCache 网络缓存' `
    -SizeBefore { Get-DirectorySize $inetCache } `
    -Action { Remove-DirectoryContents $inetCache }

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$wuDownload = Join-Path $env:WINDIR 'SoftwareDistribution\Download'
if ($IncludeWindowsUpdateCache -and -not $isAdmin) {
    Write-Host '  Windows 更新下载缓存          需要以管理员身份运行，已跳过' -ForegroundColor DarkYellow
}
elseif ($IncludeWindowsUpdateCache) {
    Clean-Category 'Windows 更新下载缓存' `
        -SizeBefore { Get-DirectorySize $wuDownload } `
        -Action {
            $restartServices = @()
            foreach ($serviceName in @('bits', 'wuauserv')) {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($null -ne $service -and $service.Status -eq 'Running') {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    $restartServices += $serviceName
                }
            }
            try {
                Remove-DirectoryContents $wuDownload
            }
            finally {
                foreach ($serviceName in $restartServices) {
                    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                }
            }
        }
}
else {
    Write-Host '  Windows 更新下载缓存          未选择清理（加 -IncludeWindowsUpdateCache 启用）' -ForegroundColor DarkGray
}

Write-Host ''
if ($Preview) {
    Write-Host ('预览完成：理论上可释放约 {0:N1} MB' -f ($script:FreedBytes / 1MB)) -ForegroundColor Cyan
}
else {
    Write-Host ('清理完成：实际释放约 {0:N1} MB' -f ($script:FreedBytes / 1MB)) -ForegroundColor Yellow
}
Write-Host '======================================' -ForegroundColor Yellow
