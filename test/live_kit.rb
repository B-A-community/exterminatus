# Мост v2 (Terminal.command), понимание ввода, макросы, пресеты, результат
# как выделение, новые команды SketchUp. Всё — внутри группы EXT_SANDBOX.
# Запуск: python test/bridge.py test/live_kit.rb
T = BACommunity::Terminal
S = T::Session
L = T::Library
m = Sketchup.active_model
results = []
ok = ->(name, cond, note = '') { results << [cond ? 'PASS' : 'FAIL', name, note.to_s] }
mm = ->(v) { (v.to_f * 25.4).round(3) }
saved_history = S.history.dup
saved_library = L.path
L.path = File.join(Sketchup.temp_dir, "ext_library_test_#{Time.now.to_i}.json")
L.reload

T::Window.close(:bar) # открытая полоса не даёт открыться строке у курсора
m.select_tool(nil)
m.close_active while m.active_path
sandbox = m.entities.add_group
sandbox.name = 'EXT_SANDBOX'
sandbox.transform!(Geom::Transformation.translation([5000.mm, 0, 0]))
sandbox.entities.add_cpoint(ORIGIN)
m.active_path = [sandbox]
raise 'not in sandbox' unless m.active_path&.first&.name == 'EXT_SANDBOX'

ents = m.active_entities
x0 = 5000
run = lambda do |line|
  mark = S.seq
  S.submit(line)
  S.log_after(mark)
end
errors = ->(log) { log.select { |l| l[:kind] == 'error' }.map { |l| l[:text] } }
texts = ->(log) { log.map { |l| l[:text] } }
clear = -> { ents.erase_entities(ents.to_a.reject { |e| e.is_a?(Sketchup::ConstructionPoint) && e.position == ORIGIN }) }
box = lambda do |x, size = 1000|
  base_face = ents.add_face([x.mm, 0, 0], [(x + size).mm, 0, 0], [(x + size).mm, size.mm, 0], [x.mm, size.mm, 0])
  base_face.reverse! if base_face.normal.z.negative?
  base_face.pushpull(size.mm)
  # Без своих переменных: eval в TOPLEVEL_BINDING делит их с прошлым запуском.
  ents.add_group(ents.grep(Sketchup::Face).select { |q| q.bounds.min.x >= x.mm - 0.01 && q.bounds.max.x <= (x + size).mm + 0.01 } +
                 ents.grep(Sketchup::Edge).select { |q| q.bounds.min.x >= x.mm - 0.01 && q.bounds.max.x <= (x + size).mm + 0.01 })
end

# ---------- понимание ввода ----------
F = T::Fuzzy
r = F.resolve('ьщму')
ok.('layout: ьщму → Move', r[0]&.id == 'Move' && r[1] == :layout, [r[0]&.id, r[1]])
r = F.resolve('круг')
ok.('keyword: круг → Circle', r[0]&.id == 'Circle' && r[1] == :keyword, [r[0]&.id, r[1]])
r = F.resolve('переместить')
ok.('keyword word form: переместить → Move', r[0]&.id == 'Move', [r[0]&.id, r[1]])
r = F.resolve('Rectnagle')
ok.('typo: Rectnagle → Rectangle', r[0]&.id == 'Rectangle' && r[1] == :typo, [r[0]&.id, r[1]])
r = F.resolve('Polgon')
ok.('typo: Polgon → Polygon', r[0]&.id == 'Polygon', [r[0]&.id, r[1]])
r = F.resolve('Deleet')
ok.('typo never runs a destructive command', r[0].nil? && r[2].include?('Delete'), r[2])
r = F.resolve('qqqzzz')
ok.('nonsense → nothing', r[0].nil?, r[2])
r = F.resolve('ZE')
ok.('exact alias stays exact', r[0]&.id == 'ZoomExtents' && r[1].nil?, [r[0]&.id, r[1]])
log = run.('Ршыещкн') # History в русской раскладке
ok.('typed in RU layout runs the command', errors.(log).empty? && texts.(log).include?('Ршыещкн → History'), texts.(log).first(3))
log = run.('Histroy')
ok.('typo runs the command with a note', texts.(log).include?('Histroy → History'), texts.(log).first(3))

pt = T::Param.new(key: :p, type: :point)
v, e = pt.parse('500б0б0')
ok.('point typed in RU layout', e.nil? && v && mm.(v.x) == 500.0, [v, e])
ln = T::Param.new(key: :l, type: :length)
v, e = ln.parse('1ю5ь')
ok.('length 1ю5ь → 1.5m', e.nil? && v && mm.(v) == 1500.0, [v, e])
st = T::Param.new(key: :s, type: :string)
v, = st.parse('Окна')
ok.('strings keep Cyrillic', v == 'Окна', v)

clear.call
log = run.("Rectangle #{x0},0,0 1000,500 stpe=1")
ok.('unknown parameter says what exists', errors.(log).first.to_s.include?('Parameters: Corner, Other, Plane'), errors.(log))
log = run.("Rectangle #{x0},0,0 1000,500 здфту=xy") # plane= в RU раскладке
ok.('parameter name in RU layout', errors.(log).empty? && ents.grep(Sketchup::Face).size == 1, errors.(log))
clear.call

# ---------- результат как выделение ----------
m.selection.clear
log = run.("Rectangle #{x0},0,0 1000,500 plane=xy; PushPull 300")
faces = ents.grep(Sketchup::Face)
ok.('chain: Rectangle; PushPull extrudes the new face', errors.(log).empty? && faces.size == 6 &&
    mm.(ents.to_a.map(&:bounds).inject { |a, b| a.add(b) }.depth) == 300.0, [errors.(log), faces.size])
run.('SelectNone')
log = run.('SelectLast')
ok.('SelectLast selects what PushPull made', m.selection.size.positive?, texts.(log))
clear.call

# ---------- макросы ----------
log = run.('Define Lift "Move 0,0,$1"')
ok.('Define makes a command', errors.(log).empty? && T::Registry.find('Lift')&.plugin == 'Macros', texts.(log))
g = box.(x0)
m.selection.clear
m.selection.add(g)
z0 = g.bounds.min.z
log = run.('Lift 250')
ok.('macro with $1 runs', errors.(log).empty? && mm.(g.bounds.min.z - z0) == 250.0, [errors.(log), mm.(g.bounds.min.z - z0)])
log = run.('Define Move "Top"')
ok.('Define refuses a built-in name', errors.(log).first.to_s.include?('already a command'), errors.(log))
log = run.('Define Loop "Loop"')
ok.('Define refuses a macro calling itself', errors.(log).first.to_s.include?('cannot call itself'), errors.(log))
L.define('PingA', 'PingB')
L.define('PingB', 'PingA')
log = run.('PingA')
ok.('indirect macro loop stops', errors.(log).any? { |t| t.include?('Too many') } && !S.busy?, errors.(log).first(2))
L.undefine('PingA')
L.undefine('PingB')
L.define('Hop', 'History')
60.times { T.run('History') }
log = run.('Hop')
ok.('Terminal.run calls do not use up the macro limit', errors.(log).empty?, errors.(log))
L.undefine('Hop')
log = run.('Macros')
ok.('Macros lists', texts.(log).any? { |t| t.start_with?('Lift = ') }, texts.(log))
log = run.('Undefine Lift')
ok.('Undefine removes', T::Registry.find('Lift').nil?, texts.(log))
clear.call

# ---------- пресеты ----------
S.forget('Circle')
run.("Circle #{x0},0,0 300 segments=48 plane=xy")
log = run.('PresetSave Circle Fine')
ok.('PresetSave stores the last options', errors.(log).empty? && L.presets('Circle')['Fine']&.dig('segments') == 48, texts.(log))
run.("Circle #{x0},0,0 300 segments=6")
clear.call
log = run.("Circle #{x0},0,0 300 preset=fine")
edges = ents.grep(Sketchup::Edge).size
ok.('preset= applies', errors.(log).empty? && edges == 48, [errors.(log), edges])
clear.call
log = run.("Circle #{x0},0,0 300 preset=fine segments=8")
ok.('explicit value beats the preset', ents.grep(Sketchup::Edge).size == 8, ents.grep(Sketchup::Edge).size)
clear.call
log = run.("Circle #{x0},0,0 300 preset=nope")
ok.('unknown preset lists the known ones', errors.(log).first.to_s.include?('Presets: Fine'), errors.(log))
S.submit('Circle')
st = S.prompt_state
ok.('Preset shows as an option at the prompt', st[:options].any? { |o| o[:name] == 'Preset' }, st[:options])
S.option('Preset')
ok.('clicking Preset asks the name with choices', S.prompt_state[:text] == 'Preset name' && S.prompt_state[:values] == ['Fine'],
    S.prompt_state)
S.submit('Fine')
ok.('after the preset the original question is back', S.prompt_state[:text] == 'Center of circle', S.prompt_state[:text])
S.cancel
file = File.join(Sketchup.temp_dir, "ext_library_export_#{Time.now.to_i}.json")
L.define('Up', 'Move 0,0,$1')
run.("LibraryExport #{file}")
L.undefine('Up')
L.delete_preset(T::Registry.find('Circle'), 'Fine')
log = run.("LibraryImport #{file}")
ok.('LibraryImport brings macros and presets back', T::Registry.find('Up') && L.presets('Circle').key?('Fine'), texts.(log))
L.undefine('Up')
clear.call

# ---------- Terminal.command (мост v2) ----------
calls = []
cmd = T.command(id: 'ExtKitProbe', plugin: 'EXT Test', description: 'Probe command',
                menu: 'Extensions/EXT Test', menu_text: 'Kit Probe', keywords: 'зонд',
                params: [{ key: :objects, type: :selection, label: 'Select something' },
                         { key: :size, type: :length, default: 100.mm, prompt: false }]) do |a|
  calls << a
  "probe #{a[:objects].size} #{a[:size].to_mm.round}"
end
ok.('command returns a UI::Command', cmd.is_a?(UI::Command), cmd.class)
ok.('command is in the terminal', T::Registry.find('ExtKitProbe')&.plugin == 'EXT Test')
ok.('keywords work for plugin commands', F.resolve('зонд')[0]&.id == 'ExtKitProbe')
g = box.(x0)
m.selection.clear
m.selection.add(g)
mark = S.seq
T::Kit.invoke('ExtKitProbe')
ok.('menu click asks like a typed command (options, Enter)', S.prompt_state&.dig(:text) == 'Press Enter to run', S.prompt_state)
ok.('menu click opens the line for typing', T::Window.visible?(:popup))
S.submit('')
ok.('menu click runs it through the terminal', calls.size == 1 && S.log_after(mark).any? { |l| l[:text] == 'probe 1 100' },
    texts.(S.log_after(mark)))
ok.('menu click goes to history', S.history.last == 'ExtKitProbe', S.history.last)
T::Window.close(:popup)
S.submit('Circle')
T::Kit.invoke('ExtKitProbe')
ok.('menu click cancels the waiting command', S.prompt_state&.dig(:command) == 'ExtKitProbe', S.prompt_state&.dig(:command))
S.cancel
T::Window.close(:popup)
solo = []
T.command(id: 'ExtKitSolo', plugin: 'EXT Test', description: 'Selection only',
          params: [{ key: :objects, type: :selection, label: 'Select something' }]) { |a| solo << a; nil }
T::Kit.send(:standalone, T::Kit.spec('ExtKitSolo'))
ok.('standalone run (no terminal) takes the selection', solo.size == 1 && solo.last[:objects] == [g], solo.size)
T.unregister('ExtKitSolo')
other_calls = []
other = T.command(id: 'ExtKitProbe', plugin: 'EXT Other', description: 'Same name', menu: 'Extensions/EXT Test') { other_calls << 1; nil }
ok.('second plugin with the same id does not steal the terminal command', T::Registry.find('ExtKitProbe').plugin == 'EXT Test')
before_calls = calls.size
other.proc.call
ok.("each plugin's menu item runs its own block", other_calls.size == 1 && calls.size == before_calls, [other_calls.size, calls.size])
check = T::Check.report('EXT')
ok.('PluginCheck reports the plugin', check.include?('EXT Test: 1 commands') && check.include?('name already taken') &&
    check.include?('no preview') == false, check)
T.unregister('ExtKitProbe')
clear.call

# ---------- новые команды SketchUp ----------
g = box.(x0)
h = box.(x0 + 2000)
m.selection.clear
m.selection.add(g)
log = run.('SetTag "EXT Test Tag"')
ok.('SetTag creates the tag', errors.(log).empty? && g.layer.name == 'EXT Test Tag', texts.(log))
log = run.('SetMaterial Red')
ok.('SetMaterial by color name', errors.(log).empty? && g.material&.color&.to_a&.first(3) == [255, 0, 0], texts.(log))
log = run.('SetMaterial #00ff00')
ok.('SetMaterial by hex', g.material&.color&.to_a&.first(3) == [0, 255, 0], texts.(log))
log = run.('SetMaterial none')
ok.('SetMaterial none clears', g.material.nil?, texts.(log))
log = run.('Rename "Box A"')
ok.('Rename', g.name == 'Box A', texts.(log))
log = run.('Info')
ok.('Info describes the selection', texts.(log).any? { |t| t.start_with?('Size: 1000') }, texts.(log))
log = run.('Isolate')
ok.('Isolate hides the rest', h.hidden? && !g.hidden?, [texts.(log), h.valid?, ents.map { |e| [e.class.name, e.hidden?] }])
log = run.('Unisolate')
ok.('Unisolate shows it again', !h.hidden?, texts.(log))

m.selection.clear
m.selection.add(g)
log = run.("Mirror #{x0 + 1500},0,0 #{x0 + 1500},1000,0")
copy = ents.grep(Sketchup::Group).find { |q| q != g && q != h && q.bounds.min.x.to_f > (x0 + 1500).mm.to_f }
ok.('Mirror copies across the line', errors.(log).empty? && copy && mm.(copy.bounds.min.x) == x0 + 2000.0,
    [texts.(log), ents.grep(Sketchup::Group).map { |q| [mm.(q.bounds.min.x), mm.(q.bounds.max.x)] }])
copy&.erase!

if Sketchup.is_pro?
  m.selection.clear
  m.selection.add([g, h])
  log = run.('Union')
  ok.('Union joins two solids', errors.(log).empty? && ents.grep(Sketchup::Group).size == 1,
      [errors.(log), ents.grep(Sketchup::Group).size, [g.valid?, h.valid?]])
  clear.call
  a = box.(x0)
  b = box.(x0 + 500)
  m.selection.clear
  m.selection.add(a)
  S.submit('Subtract')
  ok.('Subtract asks for cutters with a fresh selection', S.prompt_state&.dig(:text).to_s.start_with?('Select the cutting solids') && m.selection.empty?,
      S.prompt_state&.dig(:text))
  m.selection.add(b)
  log = run.('')
  left = ents.grep(Sketchup::Group)
  w = left.map { |q| mm.(q.bounds.width) }.sort
  ok.('Subtract cuts the target and removes the cutter', errors.(log).empty? && w == [500.0], [errors.(log), w])
  clear.call
  a = box.(x0)
  cutter = box.(x0 + 500).to_component
  m.selection.clear
  m.selection.add(a)
  S.submit('Subtract')
  m.selection.add(cutter)
  log = run.('')
  w = ents.grep(Sketchup::Group).map { |q| mm.(q.bounds.width) }
  ok.('Subtract with a component cutter', errors.(log).empty? && w == [500.0] && !cutter.valid?, [errors.(log), w])
  clear.call
  a = box.(x0)
  far = box.(x0 + 3000)
  m.selection.clear
  m.selection.add(a)
  S.submit('Subtract')
  m.selection.add(far)
  log = run.('')
  w = ents.grep(Sketchup::Group).map { |q| mm.(q.bounds.width) }
  ok.('Subtract with a cutter that misses keeps the target (as SketchUp does)', errors.(log).empty? && w == [1000.0], [errors.(log), w])
end
clear.call

log = run.("Guide #{x0},0,0 #{x0 + 100},100,0")
ok.('Guide adds a construction line', ents.grep(Sketchup::ConstructionLine).size == 1, texts.(log))
log = run.("DimLinear #{x0},0,0 #{x0 + 1000},0,0 #{x0 + 1000},300,0")
d = ents.grep(Sketchup::DimensionLinear).first
ok.('DimLinear', d && mm.(d.offset_vector.y) == 300.0, [texts.(log), d&.offset_vector])
log = run.("Label #{x0},0,0 #{x0 + 300},300,0 \"Wall A\"")
ok.('Label', ents.grep(Sketchup::Text).first&.text == 'Wall A', texts.(log))
log = run.("SectionAt #{x0},0,1000 plane=xy")
sp = ents.grep(Sketchup::SectionPlane).first
ok.('SectionAt places a horizontal section', sp && sp.get_plane[2].abs.round(6) == 1.0, [texts.(log), sp&.get_plane])
clear.call

# Sweep: квадрат 100 в YZ, путь — две линии.
prof = ents.add_face([x0.mm, 0, 0], [x0.mm, 100.mm, 0], [x0.mm, 100.mm, 100.mm], [x0.mm, 0, 100.mm])
path = [ents.add_line([x0.mm, 0, 0], [(x0 + 1000).mm, 0, 0]), ents.add_line([(x0 + 1000).mm, 0, 0], [(x0 + 1000).mm, 1000.mm, 0])]
m.selection.clear
m.selection.add(path)
S.submit('Sweep')
ok.('Sweep asks the profile', S.prompt_state&.dig(:text).to_s.start_with?('Select the profile face'), S.prompt_state&.dig(:text))
m.selection.add(prof)
log = run.('')
ok.('Sweep extrudes along the path', errors.(log).empty? && ents.grep(Sketchup::Face).size >= 8, [errors.(log), ents.grep(Sketchup::Face).size])
m.selection.clear
m.selection.add(ents.to_a)
log = run.('Soften 100')
ok.('Soften softens the bends', errors.(log).empty? && ents.grep(Sketchup::Edge).any?(&:soft?), texts.(log))
log = run.('Unsoften')
ok.('Unsoften hardens', ents.grep(Sketchup::Edge).none?(&:soft?), texts.(log))
clear.call

log = run.('Help Rectangle')
ok.('Help shows parameters', texts.(log).any? { |t| t.include?('First corner of rectangle (point') }, texts.(log))
log = run.('Help прямоуг')
ok.('Help understands Russian words', texts.(log).first(2).any? { |t| t.start_with?('Rectangle (R, Rect)') }, texts.(log).first(2))

# ---------- уборка ----------
m.selection.clear
m.select_tool(nil)
m.close_active while m.active_path
m.entities.grep(Sketchup::Group).select { |x| x.name == 'EXT_SANDBOX' }.each(&:erase!)
m.layers.remove(m.layers['EXT Test Tag']) if m.layers['EXT Test Tag']
S.history.replace(saved_history)
T::Library.write_json('history.json', saved_history)
L.path = saved_library
L.reload

results.each { |r| puts r.join('  ') }
puts "#{results.count { |r| r[0] == 'PASS' }}/#{results.size} passed"
