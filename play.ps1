param([switch]$Offline, [switch]$Fresh)
$ErrorActionPreference = 'Stop'
$engine = Get-Command godot -ErrorAction SilentlyContinue
if ($engine) { $enginePath = $engine.Source } else {
    $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $enginePath = Get-ChildItem $packageRoot -Filter 'GodotEngine.GodotEngine_*' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem $_.FullName -Filter 'Godot*_win64.exe' } |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $enginePath) { throw 'Godot 4 is required. Install it or add godot to PATH.' }
$gameArgs = @('--path', $PSScriptRoot, '--')
if ($Offline) { $gameArgs += '--offline' }
if ($Fresh) { $gameArgs += '--fresh' }
& $enginePath @gameArgs
