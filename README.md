# Script Toolbox

A small Windows desktop launcher for local scripts and utilities.

## Run

On Windows, run `脚本工具箱.bat`. It starts `ScriptToolbox.exe`, which lets you add,
order, rename, launch, and remove entries from a local tool list.

The launcher supports `.bat`, `.py`, and `.exe` tools. Its per-machine list is saved
as `ToolLauncher.tools.json`; that file is intentionally ignored by Git because it
contains absolute paths specific to one computer.

## Included cleanup tool

`清理垃圾.bat` starts `cleanup.ps1`.

```bat
清理垃圾.bat -Preview
```

Use `-Preview` to see the estimated removable space without deleting anything. The
PowerShell script skips Edge and VS Code caches when those applications are running.
Windows Update download-cache cleanup is opt-in and needs an elevated PowerShell:

```powershell
.\cleanup.ps1 -IncludeWindowsUpdateCache
```

## Build the launcher

`ScriptToolbox.exe` is built from `ScriptToolbox.cs` using the .NET Framework C#
compiler included with Windows:

```powershell
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /target:winexe /out:ScriptToolbox.exe /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ScriptToolbox.cs
```

The source is provided so the bundled executable can be rebuilt and audited locally.
