# Requires Windows PowerShell 5.1 or PowerShell 7 on Windows.
# This file is started by 脚本工具箱.bat in the same directory.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$appDirectory = $PSScriptRoot
$configPath = Join-Path $appDirectory 'ToolLauncher.tools.json'
$launcherName = '脚本工具箱.bat'

function Get-ToolList {
    if (Test-Path -LiteralPath $configPath) {
        try {
            $saved = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $saved) {
                return @($saved | Where-Object {
                    $_.Path -and (Test-Path -LiteralPath $_.Path -PathType Leaf) -and
                    ([IO.Path]::GetExtension([string]$_.Path) -ieq '.bat')
                } | ForEach-Object {
                    [PSCustomObject]@{
                        Name = if ([string]::IsNullOrWhiteSpace([string]$_.Name)) { [IO.Path]::GetFileNameWithoutExtension([string]$_.Path) } else { [string]$_.Name }
                        Path = [string]$_.Path
                    }
                })
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "工具列表文件无法读取，将重新扫描本目录。`r`n$($_.Exception.Message)",
                '脚本工具箱', 'OK', 'Warning'
            ) | Out-Null
        }
    }

    # First run: list the batch files placed beside this launcher, except the launcher itself.
    return @(Get-ChildItem -LiteralPath $appDirectory -Filter '*.bat' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ine $launcherName } |
        Sort-Object Name |
        ForEach-Object { [PSCustomObject]@{ Name = $_.BaseName; Path = $_.FullName } })
}

function Save-ToolList {
    param([object[]]$Tools)
    try {
        $Tools | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $configPath -Encoding UTF8
        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "无法保存工具列表：`r`n$($_.Exception.Message)",
            '脚本工具箱', 'OK', 'Error'
        ) | Out-Null
        return $false
    }
}

$tools = [System.Collections.ArrayList]::new()
$initialTools = @(Get-ToolList)
if ($initialTools.Count -gt 0) {
    [void]$tools.AddRange([object[]]$initialTools)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = '脚本工具箱'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(760, 510)
$form.MinimumSize = New-Object System.Drawing.Size(620, 390)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$description = New-Object System.Windows.Forms.Label
$description.Text = '选择一个工具后点击“运行”。添加/移除只会修改本工具箱的列表，不会删除原始 .bat 文件。'
$description.Location = New-Object System.Drawing.Point(16, 16)
$description.Size = New-Object System.Drawing.Size(710, 42)
$description.Anchor = 'Top,Left,Right'
$form.Controls.Add($description)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(16, 65)
$list.Size = New-Object System.Drawing.Size(710, 330)
$list.Anchor = 'Top,Bottom,Left,Right'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.GridLines = $true
$list.HideSelection = $false
[void]$list.Columns.Add('工具名称', 220)
[void]$list.Columns.Add('批处理文件路径', 465)
$form.Controls.Add($list)

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = '运行选中工具'
$runButton.Location = New-Object System.Drawing.Point(16, 412)
$runButton.Size = New-Object System.Drawing.Size(135, 34)
$runButton.Anchor = 'Bottom,Left'
$form.Controls.Add($runButton)

$addButton = New-Object System.Windows.Forms.Button
$addButton.Text = '添加 .bat…'
$addButton.Location = New-Object System.Drawing.Point(160, 412)
$addButton.Size = New-Object System.Drawing.Size(110, 34)
$addButton.Anchor = 'Bottom,Left'
$form.Controls.Add($addButton)

$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Text = '从列表移除'
$removeButton.Location = New-Object System.Drawing.Point(279, 412)
$removeButton.Size = New-Object System.Drawing.Size(110, 34)
$removeButton.Anchor = 'Bottom,Left'
$form.Controls.Add($removeButton)

$openFolderButton = New-Object System.Windows.Forms.Button
$openFolderButton.Text = '打开工具文件夹'
$openFolderButton.Location = New-Object System.Drawing.Point(404, 412)
$openFolderButton.Size = New-Object System.Drawing.Size(140, 34)
$openFolderButton.Anchor = 'Bottom,Left'
$form.Controls.Add($openFolderButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = '刷新'
$refreshButton.Location = New-Object System.Drawing.Point(598, 412)
$refreshButton.Size = New-Object System.Drawing.Size(128, 34)
$refreshButton.Anchor = 'Bottom,Right'
$form.Controls.Add($refreshButton)

function Update-List {
    param([string]$SelectPath)
    $list.BeginUpdate()
    $list.Items.Clear()
    foreach ($tool in $tools) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$tool.Name)
        [void]$item.SubItems.Add([string]$tool.Path)
        $item.Tag = $tool
        if ($SelectPath -and ([string]$tool.Path -ieq $SelectPath)) { $item.Selected = $true }
        [void]$list.Items.Add($item)
    }
    $list.EndUpdate()
}

function Get-SelectedTool {
    if ($list.SelectedItems.Count -eq 0) { return $null }
    return $list.SelectedItems[0].Tag
}

function Run-SelectedTool {
    $tool = Get-SelectedTool
    if ($null -eq $tool) {
        [System.Windows.Forms.MessageBox]::Show('请先选择一个工具。', '脚本工具箱', 'OK', 'Information') | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $tool.Path -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("找不到该文件：`r`n$($tool.Path)", '脚本工具箱', 'OK', 'Warning') | Out-Null
        return
    }
    try {
        # A batch file with PAUSE is designed to show its progress/results in
        # a console. Launch that kind normally; keep other tools hidden.
        $batchText = Get-Content -LiteralPath $tool.Path -Raw -ErrorAction Stop
        $requiresConsole = $batchText -match '(?im)^\s*pause\b'
        if ($requiresConsole) {
            Start-Process -FilePath $tool.Path
        }
        else {
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $env:ComSpec
            $startInfo.Arguments = '/d /s /c ""' + $tool.Path + '""'
            $startInfo.WorkingDirectory = [System.IO.Path]::GetDirectoryName($tool.Path)
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            [void][System.Diagnostics.Process]::Start($startInfo)
        }
        $form.Close()
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("无法启动工具：`r`n$($_.Exception.Message)", '脚本工具箱', 'OK', 'Error') | Out-Null
    }
}

function Open-SelectedToolFolder {
    $tool = Get-SelectedTool
    if ($null -eq $tool) {
        [System.Windows.Forms.MessageBox]::Show('请先选择一个工具。', '脚本工具箱', 'OK', 'Information') | Out-Null
        return
    }

    $folder = [System.IO.Path]::GetDirectoryName($tool.Path)
    if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("找不到工具所在文件夹：`r`n$folder", '脚本工具箱', 'OK', 'Warning') | Out-Null
        return
    }

    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $tool.Path)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("无法打开工具文件夹：`r`n$($_.Exception.Message)", '脚本工具箱', 'OK', 'Error') | Out-Null
    }
}

$runButton.Add_Click({ Run-SelectedTool })
$list.Add_DoubleClick({ Run-SelectedTool })
$openFolderButton.Add_Click({ Open-SelectedToolFolder })

$addButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = '选择要添加的批处理文件'
    $dialog.Filter = '批处理文件 (*.bat)|*.bat'
    $dialog.Multiselect = $true
    $dialog.InitialDirectory = $appDirectory
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $lastAdded = $null
    foreach ($path in $dialog.FileNames) {
        $alreadyAdded = @($tools | Where-Object { [string]$_.Path -ieq $path }).Count -gt 0
        if (-not $alreadyAdded) {
            [void]$tools.Add([PSCustomObject]@{ Name = [IO.Path]::GetFileNameWithoutExtension($path); Path = $path })
            $lastAdded = $path
        }
    }
    [void](Save-ToolList -Tools $tools.ToArray())
    Update-List -SelectPath $lastAdded
})

$removeButton.Add_Click({
    $tool = Get-SelectedTool
    if ($null -eq $tool) {
        [System.Windows.Forms.MessageBox]::Show('请先选择要从列表移除的工具。', '脚本工具箱', 'OK', 'Information') | Out-Null
        return
    }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "从工具箱列表移除 [$($tool.Name)] 吗？`r`n不会删除原始 .bat 文件。",
        '确认移除', 'YesNo', 'Question'
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    [void]$tools.Remove($tool)
    if (Save-ToolList -Tools $tools.ToArray()) { Update-List }
})

$refreshButton.Add_Click({
    # Keep the user's manually added entries but discard items whose source file no longer exists.
    $missing = @($tools | Where-Object { -not (Test-Path -LiteralPath $_.Path -PathType Leaf) })
    foreach ($tool in $missing) { [void]$tools.Remove($tool) }
    [void](Save-ToolList -Tools $tools.ToArray())
    Update-List
})

Update-List
[void]$form.ShowDialog()
