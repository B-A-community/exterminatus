# Подключение плагина к терминалу Exterminatus

Гайд для авторов плагинов B&A community. После подключения команды плагина
вызываются из терминала по имени, как в командной строке Rhino. Без
терминала плагин работает как раньше: ни одна строка кода не обязана знать,
установлен ли он.

Версия API: 1 (Exterminatus 0.1).

## 1. Скопировать мост

Скопируйте [`src/exterminatus/terminal_bridge.rb`](../src/exterminatus/terminal_bridge.rb)
в папку плагина **как есть**, например в `src/<plugin>/terminal_bridge.rb`, и
подключите его до регистрации команд:

```ruby
Sketchup.require(File.join(__dir__, 'terminal_bridge'))
```

Мост определяет `BACommunity::Terminal.register` и остальные методы API.
Если терминал не установлен или SketchUp загрузит его позже плагина, команды
копятся в очереди, и терминал разберёт её при загрузке. Порядок загрузки
расширений значения не имеет. Если терминал загружен раньше, мост ничего не
делает.

Файл не правьте: он одинаковый во всех плагинах, а новые версии моста
совместимы со старыми.

## 2. Зарегистрировать команды

Регистрируйте в `main.rb` рядом с меню, один раз (внутри той же защиты
`unless defined?(@ui_built)`):

```ruby
BACommunity::Terminal.register(
  id: 'SliceSections',                 # имя команды
  plugin: 'Section Slicer',            # подпись в подсказках
  description: 'Horizontal sections of the selected group by levels',
  aliases: %w[Slice]                   # необязательно
) do |args|
  SectionSlicer.run_slice              # тот же код, что у пункта меню
end
```

Правила имён:

- `id` — английский CamelCase, только латиница и цифры, с заглавной буквы:
  `PathCopy`, `RoofHip`, `RalFan`. Кириллица, пробелы и подчёркивания не
  принимаются. Это сделано специально: имена одинаковы в русской и
  английской сборке плагина.
- Имя глобально уникально. Встроенные команды SketchUp (`Line`, `Move`,
  `Offset`, `Group`…) уже заняты. Если имя занято, `register` вернёт `false` и
  напишет причину в Ruby-консоль. Синоним, который уже занят, просто
  пропускается.
- Имя называет действие, а не плагин: `PathCopy`, а не `PathCopyAdvancedTool`.
  Общую приставку стоит давать, только если без неё имя неоднозначно: в
  ArchiTools `Fillet` хорошо, а `Wall` лучше назвать `WallByLines`.
- `description` — одна короткая фраза по-английски, видна в подсказке.

## 3. Что возвращает блок

| Возврат | Что видит пользователь |
|---|---|
| `String` | строка результата в выводе |
| `{ ok: true, message: '...' }` | строка результата |
| `{ ok: false, message: '...' }` | ошибка `Id: message`, цепочка команд останавливается |
| `false` | ошибка `Id failed` |
| `nil`, `true` и всё остальное | ничего, только эхо команды |

Формат `{ ok:, message: }` совпадает с `Registry.run` в ArchiTools: его можно
вернуть как есть. Исключение из блока не роняет терминал: пользователь видит
текст ошибки, а backtrace уходит в Ruby-консоль.

Блок вызывается из окна терминала. Шаг отмены (`start_operation` /
`commit_operation`) делает сама команда, как и при вызове из меню.

## 4. Уровень 1: команда без параметров

Команда, которая открывает окно, включает инструмент или работает с
последними параметрами, подключается одной регистрацией, как в примере выше.
Этого достаточно для большинства пунктов меню:

```ruby
T = BACommunity::Terminal
T.register(id: 'RalFan', plugin: 'RALNCS', description: 'Open the RAL/NCS color fan') { Fan.show }
T.register(id: 'Bezier', plugin: 'Monsieur Bezier', description: 'Draw a Bezier curve') do
  Sketchup.active_model.select_tool(BezierTool.new)
end
```

Если команда включает Ruby-инструмент, число, набранное в терминале, уйдёт
этому инструменту в `onUserText`, как ввод в поле Measurements. Ничего
дописывать не нужно.

## 5. Уровень 2: параметры в строке, как в Rhino

Параметры описываются в `params`. Терминал сам спрашивает их по очереди,
показывает значение по умолчанию, разбирает ввод и запоминает последние
значения на время сеанса SketchUp.

```ruby
BACommunity::Terminal.register(
  id: 'PathCopy', plugin: 'PathCopy Advanced',
  description: 'Copy the selected object along the selected path',
  params: [
    { key: :step,  type: :length,  default: 500.mm, min: 1.mm },
    { key: :mode,  type: :option,  values: %w[Step Count Fit], default: 'Step', prompt: false },
    { key: :count, type: :integer, default: 10, min: 1, prompt: false },
    { key: :align, type: :bool,    default: true, prompt: false }
  ]
) do |args|
  PathCopyAdvanced.run(step: args[:step], mode: args[:mode], count: args[:count], align: args[:align])
end
```

В терминале это выглядит так:

```
PathCopy
Step <500 mm> ( Mode=Step  Count=10  Align=Yes ):
```

- Enter (или пробел в пустой строке) принимает значение по умолчанию.
- Клик по `Mode` перебирает варианты по кругу, по `Align` переключает Yes/No.
  Клик по `Count` спрашивает число и возвращает к `Step`. Имя опции можно и
  набрать.
- Esc отменяет команду.
- Можно сразу в строке: `PathCopy 300`, `PathCopy step=1.2m mode=fit`.
  Позиционные значения идут по порядку `params`, именованные пишутся как
  `Name=value`. Если в строке есть аргументы, остальные параметры берутся по
  умолчанию без вопросов. Спрашиваются только обязательные, у которых нет
  `default`.
- Можно составить цепочку: `Top; ZoomExtents; PathCopy 300`.

Поля параметра:

| Поле | Значение |
|---|---|
| `key` | ключ в `args` (Symbol), обязателен |
| `name` | имя в строке; по умолчанию `key` в CamelCase (`:step_size` → `StepSize`). Только латиница |
| `label` | текст приглашения, если он длиннее имени: `'Point to move from'`. По умолчанию — `name` |
| `type` | `:length`, `:number`, `:integer`, `:angle` (градусы), `:string`, `:option`, `:bool`, `:point`, `:vector`, `:scale`, `:selection` — см. раздел 6 |
| `default` | значение по умолчанию. Для `:length` число считается в дюймах, как везде в SketchUp: пишите `500.mm` |
| `values` | варианты для `:option`, латиницей |
| `prompt` | `true` (по умолчанию) — спрашивать по очереди; `false` — только опцией в скобках |
| `optional` | `true` — значение только из строки команды: не спрашивается и не запоминается, без него в `args` будет `nil`. Так команда без аргумента может делать другое: `PushPull` включает инструмент, `PushPull 20` выдавливает выделенные грани |
| `min`, `max` | границы для чисел и длин |
| `ask_if` | `->(args) { ... }` — спрашивать и показывать параметр, только когда вернёт истину: `ask_if: ->(a) { a[:mode] == 'Count' }` |
| `description` | подсказка (пока не показывается, задел на справку) |

`:length` понимает единицы модели и любые записи SketchUp: `500`, `1.2m`,
`3'6"`, `1,5` и `1.5`. Числа и длины понимают арифметику: `1200/4`,
`2*300+50`, `1.2m-300`. Плагину ничего делать не нужно — в `args` придёт
готовое значение.

Строку с пробелами берите в двойные кавычки: `MakeComponent name="Door 900"`.
Кавычка открывает строку только в начале значения или после `=`, поэтому
`3'6"` остаётся длиной.

## 6. Уровень 2: точки и клики в модели

Параметр, на который удобнее ответить кликом, терминал спрашивает как Rhino:
пока висит вопрос, работает его собственный инструмент с привязками SketchUp,
а ответить можно и кликом, и с клавиатуры — в терминале или в поле
Measurements. Писать свой инструмент для этого не нужно.

```ruby
BACommunity::Terminal.register(
  id: 'Beam', plugin: 'ArchiTools', description: 'Draw a beam between two points',
  params: [
    { key: :start,  type: :point,  label: 'Start of beam' },
    { key: :finish, type: :point,  label: 'End of beam', base: :start },
    { key: :height, type: :length, default: 300.mm, prompt: false }
  ],
  preview: ->(args, view) { view.draw(GL_LINES, args[:start], args[:finish]) if args[:finish] }
) do |args|
  ArchiTools::Beam.build(args[:start], args[:finish], args[:height])
end
```

```
Beam
Start of beam ( Height=300 ):            ← клик или 0,0,0
End of beam ( Height=300 ):              ← клик, @6000,0,0 или 6000 в сторону курсора
```

| Тип | Значение в `args` | Как ответить |
|---|---|---|
| `:point` | `Geom::Point3d` | клик; `x,y,z`; `@dx,dy,dz` и `@r<угол` от точки `base`; `r<угол` от начала координат; число — расстояние от `base` в сторону курсора |
| `:vector` | `Geom::Vector3d` | `dx,dy,dz` или `r<угол` (обычно с `optional: true`: `Move 0,0,500`) |
| `:scale` | `[sx, sy, sz]` | `2` или `1,1,2` |
| `:selection` | массив выделенных объектов | берётся текущее выделение; если оно пустое, терминал просит выделить и нажать Enter |

Поля для них:

| Поле | Значение |
|---|---|
| `base` | ключ точки, от которой считаются `@…` и голое число; от неё же тянется резиновая нить и работают привязки по осям |
| `auto` | значение можно оставить пустым: в строке видно `Center=Auto`, Enter его принимает. `auto: ->(args) { ... }` вычисляет его — команда получит готовую точку |
| `pick` | `->(point, args) { value }` — ответ кликом и для не-точек: угол, расстояние. `point` — точка под курсором |
| `kinds` | для `:selection`: какие объекты брать, `kinds: [Sketchup::Face]` |

У команды есть `preview: ->(args, view) { ... }`: рисует результат, пока
пользователь водит курсором. В `args` уже стоит значение под курсором.
Рисуйте в координатах модели, тонко и пунктиром — так рисует терминал сам.

- Точки — в координатах модели. Внутри открытой группы SketchUp сам отдаёт и
  принимает мировые координаты, пересчитывать ничего не нужно.
- Точки и выделение не запоминаются между вызовами, остальное запоминается
  (как опции Rhino: `Copy=Yes` останется до перезапуска SketchUp).
- Пока висит вопрос, Esc в окне модели отменяет команду, Enter и правая
  кнопка — как Enter в терминале. Смена инструмента тоже отменяет команду.
- Так устроены встроенные Move, Copy, Rotate, Scale, PolarArray, Offset и
  PushPull — их код в [`src/exterminatus/modify.rb`](../src/exterminatus/modify.rb)
  можно брать за образец.

## 7. Уровень 2: приглашения из своего инструмента

Это путь для плагина, у которого уже есть свой инструмент с шагами.
Если инструмент по шагам просит кликнуть в модели, он может писать шаг в
строку терминала, как Rhino («Pick start point»), и принимать опции:

```ruby
class MyTool
  def activate
    step_prompt
  end

  def step_prompt
    BACommunity::Terminal.prompt('Pick start point',
                                 options: { 'Mode' => @mode, 'Undo' => nil },
                                 tool: true) do |input|
      if input.option == 'Mode'
        @mode = @mode == 'Fit' ? 'Step' : 'Fit'
        step_prompt                      # обновить приглашение
      elsif input.option == 'Undo'
        undo_last_point
      elsif input.cancel?                # Esc в терминале
        reset
      elsif !input.enter?
        onUserText(input.text, Sketchup.active_model.active_view)
      end
    end
    Sketchup.status_text = 'Pick start point'  # строка состояния — как раньше
  end

  def deactivate(view)
    BACommunity::Terminal.prompt(nil)
  end
end
```

- `options:` — Hash «имя → показываемое значение» (`nil` — без значения) или
  массив имён.
- `tool: true` — приглашение исчезнет само, когда пользователь сменит
  инструмент. По Esc в терминале инструмент тоже снимается.
- `input.text` — введённая строка, `input.option` — имя опции,
  `input.enter?` — пустой Enter, `input.cancel?` — Esc.
- Без терминала `prompt` возвращает `false` и ничего не делает, поэтому
  `status_text` по-прежнему нужен.

## 8. Остальной API

| Метод | Что делает |
|---|---|
| `Terminal.available?` | `true`, если терминал установлен и загружен |
| `Terminal.message(text)` / `Terminal.error(text)` | строка в выводе терминала |
| `Terminal.run('Top; ZoomExtents')` | выполнить строку команд; в историю не попадает. Вызов из блока команды выполнится сразу после неё, перед остатком цепочки |
| `Terminal.unregister('Id')` | снять команду (для разработки); без терминала убирает её из очереди |
| `Terminal.version` | версия терминала |

Второй аргумент блока `ctx` даёт `ctx.message` / `ctx.error` для
промежуточных сообщений длинной команды.

## 9. Проверка

1. Установите терминал и свой плагин, перезапустите SketchUp.
2. Extensions → Exterminatus → Terminal (назначьте горячую клавишу в
   Preferences → Shortcuts, например `` ` `` или `Ctrl+Space`).
3. `Commands <имя плагина>` покажет зарегистрированные команды.
4. Проверьте каждую команду из терминала и тот же пункт меню без терминала.
   Удалите или отключите Exterminatus и убедитесь, что плагин работает как
   раньше.

## Чек-лист для плагина

- [ ] `terminal_bridge.rb` скопирован без изменений и подключён до `register`
- [ ] каждый пункт меню и каждая кнопка панели инструментов имеют команду
- [ ] имена — английский CamelCase, не конфликтуют со встроенными (`Commands` покажет все)
- [ ] у команд с параметрами — `params`, у второстепенных параметров `prompt: false`
- [ ] команды, которым нужны точки или выделение, спрашивают их параметрами `:point` и `:selection`, а не своим окном
- [ ] блок возвращает `{ ok:, message: }` или строку; отказ объясняет причину
- [ ] инструменты по кликам пишут шаги через `Terminal.prompt(..., tool: true)` и снимают их в `deactivate`
- [ ] плагин проверен без терминала
- [ ] в README плагина — раздел «Терминал» со списком команд, в CHANGELOG — запись патч-версией
