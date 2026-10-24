# Копирует плагин в папку Plugins SketchUp для разработки.
# По умолчанию SketchUp 2024; для другой версии:  .\dev_install.ps1 -Version 2025
# После копирования перезапустите SketchUp (или в Ruby-консоли: load 'exterminatus.rb').
param([string]$Version = '2024')
$ErrorActionPreference = "Stop"

$plugins = Join-Path $env:APPDATA "SketchUp\SketchUp $Version\SketchUp\Plugins"
if (-not (Test-Path $plugins)) {
  Write-Error "Не найдена папка плагинов SketchUp ${Version}: $plugins"
}

Copy-Item (Join-Path $PSScriptRoot "src\exterminatus.rb") $plugins -Force
Copy-Item (Join-Path $PSScriptRoot "src\exterminatus") $plugins -Recurse -Force
Write-Host "Установлено в $plugins"
