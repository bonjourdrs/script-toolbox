$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The .NET Framework C# compiler was not found.' }

# Keep all build intermediates in the build directory.
$buildDir = Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
$iconGenerator = Join-Path $buildDir 'GenerateIcon.exe'
& $compiler /nologo /target:exe /reference:System.Drawing.dll "/out:$iconGenerator" (Join-Path $PSScriptRoot 'GenerateIcon.cs')
if ($LASTEXITCODE -ne 0) { throw 'Icon generator compilation failed.' }
$iconPath = Join-Path $PSScriptRoot 'ScriptToolbox.ico'
& $iconGenerator $iconPath
if ($LASTEXITCODE -ne 0) { throw 'Icon generation failed.' }
$outputPath = Join-Path $buildDir 'ScriptToolbox.exe'
& $compiler /nologo /target:winexe /optimize+ /codepage:65001 /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/win32icon:$iconPath" "/resource:$iconPath,ScriptToolbox.Icon" "/out:$outputPath" (Join-Path $PSScriptRoot 'ScriptToolbox.cs')
if ($LASTEXITCODE -ne 0) { throw 'Toolbox compilation failed.' }
Write-Host "Built: $outputPath"
