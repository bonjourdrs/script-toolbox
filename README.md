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
compiler included with Windows. Run the build script from PowerShell:

```powershell
.\build.ps1
```

The build script generates `ScriptToolbox.ico` and a PNG preview from
`GenerateIcon.cs`, then embeds the icon into both the executable and its window.
The icon contains 16, 24, 32, 48, 64, 128, and 256 pixel frames.
The built executable is saved as `build/ScriptToolbox.exe`; copy it beside the
launcher to replace the bundled executable. Close the launcher before replacing it.
No separate icon file is required to run the executable.

The source is provided so the bundled executable can be rebuilt and audited locally.

---

_Last updated: 2026-10-18_
