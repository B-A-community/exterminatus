# Exterminatus

Общий командный терминал для SketchUp 2024, как командная строка Rhino.
Команды плагинов B&A community и стандартные команды SketchUp вызываются по
имени, а параметры спрашиваются прямо в строке.

Версия 0.1.0 · лицензия [Apache 2.0](LICENSE) · © 2026 B&A community

Создатели: maksarsanjeev — см. [AUTHORS](AUTHORS)

## Как пользоваться

1. Extensions → Exterminatus → **Assign Shortcut…**: выберите клавишу
   (`` ` ``, Ctrl+Space, Alt+Space, Ctrl+`` ` ``, F12). Клавиша заработает после
   перезапуска SketchUp — плагин предложит перезапустить сразу. Можно и
   вручную: Window → Preferences → Shortcuts, поиск «Terminal».
2. Горячая клавиша открывает строку у курсора. Наберите команду, нажмите
   Enter: команда выполнится, строка исчезнет, фокус вернётся в SketchUp. Esc
   закрывает строку.
3. **Command Bar** в том же меню открывает плавающую полосу с выводом. Она
   помнит место и размер. Пока полоса открыта, горячая клавиша ставит фокус в
   неё.

```
ze                         → ZoomExtents
PushPull 20                выдавить выделенные грани на 20 (без числа — инструмент)
Top; ZoomExtents           цепочка команд
MakeComponent name=Door    аргумент по имени
PathCopy 300               аргумент по порядку
Commands architools        список команд плагина
```

| Клавиша | Действие |
|---|---|
| Enter | выполнить; в недобранном имени берётся выделенная подсказка |
| Enter, пробел в пустой строке | повторить последнюю команду или принять значение по умолчанию |
| Tab | дополнить имя |
| ↑ ↓ | подсказки, а без подсказок — история |
| Esc | закрыть подсказки → отменить команду → закрыть строку |

Имена команд только английские. Автодополнение ищет по началу имени, по
заглавным буквам (`pp` → PushPull, `ze` → ZoomExtents), по подстроке и по
синонимам. Синонимы стандартных команд совпадают со стандартными клавишами
SketchUp: `L` — Line, `R` — Rectangle, `P` — PushPull, `M` — Move, `Q` — Rotate,
`S` — Scale, `F` — Offset, `E` — Erase, `B` — Paint, `T` — Tape, `O` — Orbit,
`H` — Pan, `Z` — Zoom.

Команда с параметрами спрашивает их как Rhino:

```
Step <500 mm> ( Mode=Step  Count=10  Align=Yes ):
```

Enter принимает значение по умолчанию. Клик по опции перебирает варианты или
спрашивает значение. Последние значения запоминаются до закрытия SketchUp.

Число, набранное при активном инструменте плагина, уходит этому инструменту,
как ввод в поле Measurements.

## Стандартные команды SketchUp

92 команды, полный список выводит `Commands sketchup`.

| Группа | Команды |
|---|---|
| Рисование | Line, Freehand, Rectangle, RotatedRectangle, Circle, Polygon, Arc, ArcCenter, Pie, Text, Text3D, Dimension, Tape, Protractor, Axes, SectionPlane |
| Инструменты правки | Select, Lasso, Erase, Paint, TagTool, Move, Rotate, Scale, Flip, PushPull, FollowMe, Offset |
| Камера | Orbit, Pan, Zoom, ZoomWindow, ZoomExtents, ZoomSelected, PreviousView, PositionCamera, LookAround, Walk, Top, Bottom, Front, Back, Left, Right, Iso, Perspective, Parallel |
| Стиль | Wireframe, HiddenLine, Shaded, ShadedTextures, Monochrome, ToggleXRay, ToggleBackEdges, ToggleAxes, ToggleGuides, ToggleHidden, ToggleHiddenObjects, ToggleSectionPlanes, ToggleSectionCuts, ToggleShadows, ToggleFog |
| Правка | Undo, Redo, Copy, Cut, Paste, Delete, Hide, Unhide, UnhideAll, SelectAll, SelectNone, InvertSelection, Group, MakeComponent, Explode, MakeUnique, ReverseFaces, DeleteGuides, Purge |
| Сцены | SceneAdd, SceneUpdate, SceneDelete, SceneNext, ScenePrevious |
| Файл | New, Open, Save, Print, RubyConsole, ExtensionManager |
| Терминал | Commands (Help), History, ClearLog (Cls), CommandBar |

Где у SketchUp есть действие (`Sketchup.send_action`), команда вызывает его
и ведёт себя так же, как кнопка. Число набрать в поле Measurements родного
инструмента терминал не может: у Ruby API нет такого вызова. Поэтому команды
с числом выполняются сами, как в Rhino: `PushPull 20`. Остальные команды повторяют пункт меню через
Ruby API, каждая в один шаг отмены.

## Подключение плагинов

Плагин копирует к себе [`terminal_bridge.rb`](src/exterminatus/terminal_bridge.rb)
и регистрирует команды:

```ruby
BACommunity::Terminal.register(id: 'RalFan', plugin: 'RALNCS',
                               description: 'Open the RAL/NCS color fan') { Fan.show }
```

Без терминала плагин работает как раньше. Подробно — с параметрами,
приглашениями из инструментов и чек-листом — в
[docs/PLUGIN_GUIDE.md](docs/PLUGIN_GUIDE.md).

## Установка для разработки

```powershell
.\dev_install.ps1            # SketchUp 2024
.\dev_install.ps1 -Version 2025
```

Проверки в живом SketchUp идут через MCP-мост на :8080:

```bash
python test/bridge.py test/live_session.rb   # исполнитель, параметры, мост: 48 проверок
python test/live_async.py                    # цепочки с send_action, окна: 7 проверок
python test/live_builtins.py                 # стандартные команды: 84 проверки, ~10 минут
```

`test/reload.rb` перечитывает исходники в работающий SketchUp без
перезапуска. `test/ui/harness.html` показывает оба окна в браузере на
настоящем каталоге команд (`python -m http.server` из корня репозитория).

## Структура

```
src/exterminatus.rb               загрузчик расширения
src/exterminatus/
  terminal_bridge.rb              мост для плагинов (копируется как есть)
  api.rb                          публичный API: register, prompt, message…
  registry.rb                     каталог команд, поиск по имени
  params.rb                       типы параметров, разбор ввода
  session.rb                      исполнитель: строка, приглашения, история
  builtins.rb                     стандартные команды SketchUp
  window.rb                       окна: полоса и строка у курсора
  html/                           index.html, terminal.css, terminal.js
design/                           макет и концепция дизайна (Codex)
docs/PLUGIN_GUIDE.md              гайд для плагинов
test/                             живые проверки
```
