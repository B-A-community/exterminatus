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
Line                       точки кликом или вводом, идёт дальше до Enter
Rectangle 0,0,0 3000,2000  прямоугольник по углу и размеру
Circle 0,0,0 500           окружность по центру и радиусу
Arc 0,0,0 1000,0,0 200     дуга по концам и прогибу
ArcCenter 0,0,0 1000,0,0 90  дуга по центру, началу и углу (или конечной точке)
Polygon 0,0,0 500 sides=8  многоугольник по центру и радиусу (или вершине)
Move                       спросит точки: клик в модели или 0,0,0 → @1000,0,0
Move 0,0,500               сдвинуть выделение сразу
Copy 1000,0,0 count=5      пять копий с шагом 1000
Rotate 90 axis=x           повернуть вокруг центра выделения
PushPull 1200/4            выдавить выделенные грани на 300
Top; ZoomExtents           цепочка команд
MakeComponent name=Door    аргумент по имени
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
спрашивает значение; `Count=3` в ответ меняет опцию, не уходя с вопроса.
Будущая геометрия рисуется тонкой сплошной линией, как у родных инструментов,
а переносимые объекты — пунктирным габаритом. Последние значения запоминаются до закрытия SketchUp.

Число, набранное при активном инструменте плагина, уходит этому инструменту,
как ввод в поле Measurements.

### Точки и клики

Если команда спрашивает точку, отвечать можно как удобно:

| Ввод | Смысл |
|---|---|
| клик в модели | точка с привязками SketchUp (концы, середины, оси) |
| `100,0,50` | координаты (дробь — через точку: `0,0,1.5`) |
| `@1000,0,0` | смещение от предыдущей точки |
| `1000<45`, `@1000<45` | расстояние под углом в плоскости XY |
| `500` | 500 в сторону курсора от предыдущей точки |
| `1200/4`, `1.2m-300` | арифметика работает в любом числе и длине |

Набирать можно в терминале или прямо в окне модели — в поле Measurements.
Enter, Esc и правая кнопка в окне модели работают так же, как в терминале.
Если ничего не выделено, команда просит выделить: клик добавляет объект,
Shift — переключает, рамка слева направо берёт целиком попавшее, справа
налево — задетое; Enter или правая кнопка — готово.

Line после каждого отрезка продолжает от последней точки, пока не нажат
Enter или Esc; замкнутый контур становится гранью. У Rectangle второй ответ —
угол или размер `3000,2000` в плоскости прямоугольника. Rectangle и Circle
ложатся на грань, по которой кликнули первой точкой (`Plane=Auto`), а без
грани — на XY; опция `Plane` фиксирует XY, XZ или YZ. Так же ложатся дуги и
многоугольник.

Arc строится как у SketchUp: два конца, потом прогиб (клик или число; минус —
в другую сторону). ArcCenter и Pie: центр, начало, потом угол — клик, число
градусов (минус — по часовой) или конечная точка `x,y,z`. Polygon: центр, потом
вершина кликом или радиус числом; `Sides` — число сторон, `Mode=Circumscribed`
— радиус до середины стороны.

## Стандартные команды SketchUp

94 команды, полный список выводит `Commands sketchup`.

| Группа | Команды |
|---|---|
| Рисование | Freehand, RotatedRectangle, Arc, ArcCenter, Pie, Text, Text3D, Dimension, Tape, Protractor, Axes, SectionPlane |
| Рисование в духе Rhino | Line, Rectangle, Circle, Arc, ArcCenter, Pie, Polygon |
| Правка в духе Rhino | Move, Copy, Rotate, Scale, PolarArray, Offset, PushPull |
| Инструменты правки | Select, Lasso, Erase, Paint, TagTool, Flip, FollowMe |
| Камера | Orbit, Pan, Zoom, ZoomWindow, ZoomExtents, ZoomSelected, PreviousView, PositionCamera, LookAround, Walk, Top, Bottom, Front, Back, Left, Right, Iso, Perspective, Parallel |
| Стиль | Wireframe, HiddenLine, Shaded, ShadedTextures, Monochrome, ToggleXRay, ToggleBackEdges, ToggleAxes, ToggleGuides, ToggleHidden, ToggleHiddenObjects, ToggleSectionPlanes, ToggleSectionCuts, ToggleShadows, ToggleFog |
| Правка | Undo, Redo, CopyToClipboard, Cut, Paste, Delete, Hide, Unhide, UnhideAll, SelectAll, SelectNone, InvertSelection, Group, MakeComponent, Explode, MakeUnique, ReverseFaces, DeleteGuides, Purge |
| Сцены | SceneAdd, SceneUpdate, SceneDelete, SceneNext, ScenePrevious |
| Файл | New, Open, Save, Print, RubyConsole, ExtensionManager |
| Терминал | Commands (Help), History, ClearLog (Cls), CommandBar |

Где у SketchUp есть действие (`Sketchup.send_action`), команда вызывает его
и ведёт себя так же, как кнопка. Передать число родному инструменту терминал
не может: у Ruby API нет такого вызова. Поэтому Line, Rectangle, Circle,
Arc, Polygon, Move, Copy, Rotate, Scale, Offset и PushPull — свои команды в
духе Rhino, каждая в один шаг отмены. Родные инструменты остаются на своих
клавишах в окне модели (L, R, C, A, M, Q, S, F, P).
Остальные команды повторяют пункт меню через Ruby API.

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

## Установка

Window → Extension Manager → Install Extension → `exterminatus-0.1.0.rbz`.
Пакет собирается из `src/`: `python build_rbz.py` → `dist/`.

## Установка для разработки

```powershell
.\dev_install.ps1            # SketchUp 2024
.\dev_install.ps1 -Version 2025
```

Проверки в живом SketchUp идут через MCP-мост на :8080:

```bash
python test/bridge.py test/live_session.rb   # исполнитель, параметры, мост: 48 проверок
python test/bridge.py test/live_modify.rb    # Move…PushPull, точки, пикер: 57 проверок
python test/bridge.py test/live_draw.rb      # рисование: 47 проверок
python test/live_async.py                    # цепочки с send_action, окна: 10 проверок
python test/live_builtins.py                 # стандартные команды: 72 проверки, ~10 минут
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
  modify.rb                       Move, Copy, Rotate, Scale, PolarArray, Offset, PushPull
  draw.rb                         Line, Rectangle, Circle, Arc, ArcCenter, Pie, Polygon
  picker.rb                       ввод кликом: точки, выделение, предпросмотр
  window.rb                       окна: полоса и строка у курсора
  html/                           index.html, terminal.css, terminal.js
design/                           макет и концепция дизайна (Codex)
docs/PLUGIN_GUIDE.md              гайд для плагинов
test/                             живые проверки
```
