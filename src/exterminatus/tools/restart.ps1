# Перезапуск SketchUp после обновления плагинов. Запускается из Exterminatus
# скрытым процессом: ждёт, пока завершится именно этот процесс SketchUp и его
# помощники CEF, и запускает SketchUp снова.
# Ждёт, только пока лежит флаг-файл с нашим токеном: если выход отменили,
# SketchUp удаляет флаг, и помощник уходит, ничего не запуская. Не дольше
# 10 минут.
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$Flag,
    [Parameter(Mandatory = $true)][string]$Token
)

function Still-Wanted {
    (Test-Path -LiteralPath $Flag) -and ((Get-Content -LiteralPath $Flag -Raw) -eq $Token)
}

$deadline = (Get-Date).AddMinutes(10)
while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
    if (-not (Still-Wanted) -or (Get-Date) -gt $deadline) { exit 0 }
    Start-Sleep -Milliseconds 500
}
if (-not (Still-Wanted)) { exit 0 }
Remove-Item -LiteralPath $Flag -ErrorAction SilentlyContinue

# Помощники CEF этого SketchUp (их родитель — закрытый процесс) ещё могут
# завершаться: SketchUp, запущенный при живых помощниках, падает в libcef.dll.
$folder = Split-Path -Parent $Exe
$until = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $until -and (Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase) })) {
    Start-Sleep -Milliseconds 500
}
Start-Sleep -Seconds 2
Start-Process -FilePath $Exe
