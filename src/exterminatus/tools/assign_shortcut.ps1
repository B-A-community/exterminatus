# Назначение горячей клавиши SketchUp (Windows). Запускается из Exterminatus
# скрытым процессом: ждёт, пока закроются все окна этой версии SketchUp (при
# выходе SketchUp перезаписывает свои настройки), правит раздел
# "Windows Only" > "Settings" в SharedPreferences.json и, если просили,
# запускает SketchUp заново.
#
# Задание — JSON-файл:
#   prefs    путь к SharedPreferences.json
#   exe      путь к SketchUp.exe
#   command  что назначаем: путь меню (Extensions/Exterminatus/Terminal) или действие
#   entry    "Ctrl Alt Shift Клавиша", например "0 0 0 `"; пусто — снять клавишу
#   restart  запустить SketchUp после правки
#   created  время создания задания (Unix, с); перезапуск — только в течение 3 минут
# Журнал пишется рядом с заданием (.log).
param([Parameter(Mandatory = $true)][string]$Job)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$log = [System.IO.Path]::ChangeExtension($Job, '.log')

function Write-Log([string]$Message) {
    [System.IO.File]::AppendAllText($log, ('{0:s} {1}{2}' -f (Get-Date), $Message, [Environment]::NewLine), $utf8)
}

try {
    $task = [System.IO.File]::ReadAllText($Job, $utf8) | ConvertFrom-Json
    # Ждём не только SketchUp.exe, но и его вспомогательные процессы из той же
    # папки (sketchup_webhelper — CEF): SketchUp, запущенный при живых
    # помощниках, падает в libcef.dll.
    $folder = Split-Path -Parent $task.exe
    Write-Log "waiting for processes from $folder to exit"
    while (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase) }) {
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 2

    Add-Type -AssemblyName System.Web.Extensions
    $json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $json.MaxJsonLength = [int]::MaxValue

    $text = [System.IO.File]::ReadAllText($task.prefs, $utf8)
    $data = $json.DeserializeObject($text)
    if (-not $data.ContainsKey('Windows Only')) { $data['Windows Only'] = New-Object 'System.Collections.Generic.Dictionary[string,object]' }
    $win = $data['Windows Only']
    if (-not $win.ContainsKey('Settings')) { $win['Settings'] = New-Object 'System.Collections.Generic.Dictionary[string,object]' }
    $settings = $win['Settings']

    # Записи: "Ctrl Alt Shift Клавиша Команда"; команда может содержать пробелы.
    $count = 0
    if ($settings.ContainsKey('Num_Shortcuts')) { $count = [int]$settings['Num_Shortcuts'] }
    $entries = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -le $count; $i++) {
        $key = "Shortcut_$i"
        if ($settings.ContainsKey($key)) { $entries.Add([string]$settings[$key]) }
    }

    $combo = [string]$task.entry
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($e in $entries) {
        $parts = $e.Split(' ', 5)
        if ($parts.Count -lt 5) { $kept.Add($e); continue }
        $sameCommand = $parts[4] -eq $task.command
        $sameCombo = $combo -and (($parts[0..3] -join ' ') -eq $combo)
        if ($sameCommand -or $sameCombo) { Write-Log "removed: $e" } else { $kept.Add($e) }
    }
    if ($combo) {
        $kept.Add("$combo $($task.command)")
        Write-Log "added: $combo $($task.command)"
    }

    foreach ($key in @($settings.Keys)) {
        if ($key -like 'Shortcut_*') { [void]$settings.Remove($key) }
    }
    for ($i = 0; $i -lt $kept.Count; $i++) { $settings["Shortcut_$($i + 1)"] = $kept[$i] }
    $settings['Num_Shortcuts'] = $kept.Count

    $out = $json.Serialize($data)
    [void]$json.DeserializeObject($out) # не записываем то, что сами не можем прочитать
    Copy-Item $task.prefs "$($task.prefs).exterminatus.bak" -Force
    $tmp = "$($task.prefs).exterminatus.tmp"
    [System.IO.File]::WriteAllText($tmp, $out, $utf8)
    Move-Item $tmp $task.prefs -Force
    Write-Log "saved $($kept.Count) shortcuts"

    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$task.created
    if ($task.restart -and $age -lt 180) {
        Start-Process -FilePath $task.exe
        Write-Log 'SketchUp restarted'
    }
    Write-Log 'done'
} catch {
    Write-Log "error: $($_.Exception.Message)"
    exit 1
}
