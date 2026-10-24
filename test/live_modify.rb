# Команды правки с точками, выражения и пикер. Всё — внутри группы
# EXT_SANDBOX, сдвинутой от начала координат (проверка координат открытой
# группы). Запуск: python test/bridge.py test/live_modify.rb
T = BACommunity::Terminal
S = T::Session
m = Sketchup.active_model
results = []
ok = ->(name, cond, note = '') { results << [cond ? 'PASS' : 'FAIL', name, note.to_s] }
mm = ->(v) { (v.to_f * 25.4).round(3) }
saved_history = S.history.dup

%w[Move Copy Rotate Scale PolarArray Offset PushPull].each { |id| S.forget(id) }
m.select_tool(nil)
m.close_active while m.active_path
sandbox = m.entities.add_group
sandbox.name = 'EXT_SANDBOX'
sandbox.transform!(Geom::Transformation.translation([5000.mm, 0, 0]))
sandbox.entities.add_cpoint(ORIGIN) # пустая группа исчезнет
m.active_path = [sandbox]
raise 'not in sandbox' unless m.active_path&.first&.name == 'EXT_SANDBOX'

ents = m.active_entities
off = 5000.mm # мировые координаты внутри открытой группы
box = lambda do |x = 0|
  grp = ents.add_group
  face = grp.entities.add_face([off + x, 0, 0], [off + x + 1000.mm, 0, 0], [off + x + 1000.mm, 1000.mm, 0], [off + x, 1000.mm, 0])
  face.reverse! if face.normal.z.negative?
  face.pushpull(1000.mm)
  grp
end
run = lambda do |line|
  mark = S.seq
  S.submit(line)
  S.log_after(mark).select { |l| l[:kind] == 'error' }.map { |l| l[:text] }
end
sel = ->(*e) { m.selection.clear; m.selection.add(e.flatten) }

# ---------- разбор значений ----------
P = T::Param
len = P.new(key: :d, type: :length)
ok.('length 1200/4', mm.(len.parse('1200/4').first) == 300.0, len.parse('1200/4').inspect)
ok.('length 1.2m+300', mm.(len.parse('1.2m+300').first) == 1500.0)
ok.('length (100+50)*2', mm.(len.parse('(100+50)*2').first) == 300.0)
ok.('length 1,5 still ok', mm.(len.parse('1,5').first) == 1.5)
ok.('length -500', mm.(len.parse('-500').first) == -500.0)
ok.('length 1/0 error', len.parse('1/0').last.to_s.include?('length expected'))
ok.('length 1/2" is a fraction', mm.(len.parse('1/2"').first) == 12.7, len.parse('1/2"').inspect)
num = P.new(key: :n, type: :number)
ok.('number 1e-3', num.parse('1e-3').first == 0.001, num.parse('1e-3').inspect)
pt = P.new(key: :p, type: :point)
v = pt.parse('100,0,50').first
ok.('point x,y,z', v.to_a.map { |c| mm.(c) } == [100.0, 0.0, 50.0], v.inspect)
v = pt.parse('100,200').first
ok.('point x,y', v.to_a.map { |c| mm.(c) } == [100.0, 200.0, 0.0])
base = Geom::Point3d.new(1000.mm, 0, 0)
v = pt.parse('@0,0,250', base: base).first
ok.('point @relative', v.to_a.map { |c| mm.(c) } == [1000.0, 0.0, 250.0], v.inspect)
v = pt.parse('@1000<90', base: base).first
ok.('point @polar', v.to_a.map { |c| mm.(c) } == [1000.0, 1000.0, 0.0], v.inspect)
v = pt.parse('300', base: base, cursor: Geom::Point3d.new(1000.mm, 50.mm, 0)).first
ok.('point: distance toward cursor', v.to_a.map { |c| mm.(c) } == [1000.0, 300.0, 0.0], v.inspect)
ok.('point: number without cursor -> hint', pt.parse('300', base: base).last.to_s.include?('move the cursor'))
ok.('point @ without base -> error', pt.parse('@1,2,3').last.to_s.include?('no previous point'))
sc = P.new(key: :f, type: :scale)
ok.('scale 2 and 1,1,2', sc.parse('2').first == [2.0, 2.0, 2.0] && sc.parse('1,1,2').first == [1.0, 1.0, 2.0])
ok.('scale 0 error', !sc.parse('0').last.nil?)

# ---------- Move ----------
g = box.call
sel.(g)
errs = run.('Move 0,0,500')
ok.('Move 0,0,500', errs.empty? && mm.(g.bounds.min.z) == 500.0, [errs, mm.(g.bounds.min.z)])
ok.('Move inline asks nothing', !S.busy?)

S.submit('Move')
st = S.prompt_state
ok.('Move asks base point', st && st[:text] == 'Point to move from', st)
ok.('picker is active', m.tools.active_tool.is_a?(T::Picker::PickTool), m.tools.active_tool.class)
S.submit("#{(off / 1.mm).round},0,500")
st = S.prompt_state
ok.('then target point', st && st[:text] == 'Point to move to', st)
S.submit('@0,0,-500')
ok.('Move from/to typed', !S.busy? && mm.(g.bounds.min.z) == 0.0, mm.(g.bounds.min.z))
ok.('picker gone after command', !m.tools.active_tool.is_a?(T::Picker::PickTool), m.tools.active_tool.class)

# Клик в модели: onLButtonDown по экранной точке вершины.
view = m.active_view
view.zoom(g)
S.submit('Move')
tool = m.tools.active_tool
corner = g.bounds.corner(0)
sx, sy = view.screen_coords(corner).to_a
tool.onLButtonDown(0, sx, sy, view)
st = S.prompt_state
ok.('click answers the point', st && st[:text] == 'Point to move to', st)
tool = m.tools.active_tool
target = corner.offset(Z_AXIS, 300.mm)
tool.instance_variable_set(:@cursor, target)
S.submit('200') # 200 в сторону курсора (вверх)
ok.('number toward cursor moves', mm.(g.bounds.min.z) == 200.0, mm.(g.bounds.min.z))

# Предпросмотр: подставной view записывает вызовы.
class FakeView
  attr_reader :calls
  def initialize; @calls = 0; end
  def method_missing(name, *) = (@calls += 1 if name == :draw; nil)
  def respond_to_missing?(*) = true
end
fv = FakeView.new
S.submit('Move')
S.submit('0,0,0')
run_state = S.instance_variable_get(:@run)
S.preview(run_state, run_state.cmd.param(:to), Geom::Point3d.new(0, 0, 100.mm), fv)
ok.('Move preview draws the box', fv.calls == 1, fv.calls)
S.cancel
ok.('Esc cancels and drops picker', !S.busy? && !m.tools.active_tool.is_a?(T::Picker::PickTool))

# Именованные аргументы в любом порядке: to=@… считается от from.
errs = run.("Move to=@0,0,100 from=#{(off / 1.mm).round},0,0")
ok.('named args in any order', errs.empty? && mm.(g.bounds.min.z) == 300.0, [errs, mm.(g.bounds.min.z)])
run.("Move 0,0,-100")

# ---------- выделение ----------
m.selection.clear
S.submit('Move 0,0,100')
st = S.prompt_state
ok.('no selection -> asks to select', st && st[:text].start_with?('Select objects to move'), st)
ok.('select tool is active', m.tools.active_tool.is_a?(T::Picker::SelectTool), m.tools.active_tool.class)
errs = run.('')
ok.('Enter with nothing selected -> error', errs == ['Nothing selected'], errs)
sel.(g)
S.submit('')
ok.('selection then Enter runs', !S.busy? && mm.(g.bounds.min.z) == 300.0, mm.(g.bounds.min.z))

# ---------- Copy ----------
before = ents.grep(Sketchup::Group).size
sel.(g)
errs = run.('Copy 1500,0,0 count=3')
after = ents.grep(Sketchup::Group)
ok.('Copy count=3 makes 3 copies', errs.empty? && after.size == before + 3, [errs, after.size - before])
far = after.map { |x| mm.(x.bounds.max.x) }.max
ok.('copies go 1500 apart', far == mm.(off) + 1000.0 + 4500.0, far)
ents.erase_entities(after - [g])

# Атрибуты экземпляра компонента переходят в копию.
comp = box.call(3000.mm).to_component
comp.set_attribute('ext_test', 'size', 42)
sel.(comp)
run.('Copy 0,2000,0 count=1')
twin = ents.grep(Sketchup::ComponentInstance).find { |x| !x.equal?(comp) }
ok.('Copy keeps instance attributes', twin && twin.get_attribute('ext_test', 'size') == 42)
ents.erase_entities([comp, twin].compact)

# Свободная геометрия копируется и сливается.
f = ents.add_face([off, 3000.mm, 0], [off + 500.mm, 3000.mm, 0], [off + 500.mm, 3500.mm, 0], [off, 3500.mm, 0])
faces_before = ents.grep(Sketchup::Face).size
sel.(f)
errs = run.('Copy 0,1000,0 count=1')
ok.('Copy loose face', errs.empty? && ents.grep(Sketchup::Face).size == faces_before + 1, [errs, ents.grep(Sketchup::Face).size - faces_before])
ents.erase_entities(ents.grep(Sketchup::Face) + ents.grep(Sketchup::Edge))

# Опция набором «Count=3» в ответ на вопрос: вопрос тот же, опция новая.
sel.(g)
S.submit('Copy')
S.submit('Count=3')
st = S.prompt_state
ok.('Name=value at a prompt sets the option', st && st[:text] == 'Point to copy from' &&
    st[:options].find { |o| o[:name] == 'Count' }&.dig(:value) == '3', st)
errs = run.('Count=0')
ok.('Name=value is range-checked', errs.first.to_s.include?('at least'), errs)
S.cancel

# Ждущая команда не глотает другие: имя команды отменяет её и запускается.
sel.(g)
S.submit('Move')
mark = S.seq
S.submit('SelectNone')
texts = S.log_after(mark).map { |l| l[:text] }
ok.('command name replaces a waiting command', !S.busy? && m.selection.empty? && texts.include?('Move cancelled'), texts)
sel.(g)
S.submit('Move')
errs = run.('qwerty')
ok.('garbage at a prompt hints Esc', S.busy? && errs.first.to_s.include?('Esc cancels Move'), errs)
S.cancel

# ---------- Rotate ----------
sel.(g)
c0 = g.bounds.center
errs = run.('Rotate 90')
ok.('Rotate 90 around center', errs.empty? && g.bounds.center.distance(c0) < 0.01, [errs, g.bounds.center, c0])
ok.('Rotate turned the group', (g.transformation.xaxis - Y_AXIS).length.to_f < 1e-6, g.transformation.xaxis)
errs = run.("Rotate 90 center=#{(off / 1.mm).round},0,0 copy=yes")
copies = ents.grep(Sketchup::Group) - [g]
ok.('Rotate copy=yes', errs.empty? && copies.size == 1, [errs, copies.size])
ents.erase_entities(copies)
sel.(g)
S.submit('Rotate')
st = S.prompt_state
ok.('Rotate prompt shows options', st && st[:text] == 'Rotation angle' && st[:options].map { |o| o[:name] } == %w[Center Axis Copy], st)
S.option('Center')
st = S.prompt_state
ok.('Center option asks a point', st && st[:text] == 'Center of rotation' && m.tools.active_tool.is_a?(T::Picker::PickTool), st)
S.submit('')
st = S.prompt_state
ok.('Enter keeps Auto center', st && st[:text] == 'Rotation angle', st)
rs = S.instance_variable_get(:@run)
ang = T::Builtins.send(:angle_at, c0.offset(Y_AXIS, 100), S.resolved(rs))
ok.('angle from cursor', ang == 90.0, ang)
S.option('Copy') # Copy=Yes запомнился с прошлого Rotate — выключить
S.submit('-90')
ok.('Rotate back', (g.transformation.xaxis - X_AXIS).length.to_f < 1e-6, g.transformation.xaxis)

# ---------- Scale ----------
sel.(g)
errs = run.('Scale 2')
ok.('Scale 2', errs.empty? && mm.(g.bounds.width) == 2000.0, [errs, mm.(g.bounds.width)])
errs = run.('Scale 0.5,0.5,0.5')
ok.('Scale back per axis', errs.empty? && mm.(g.bounds.width) == 1000.0, [errs, mm.(g.bounds.width)])

# ---------- PolarArray ----------
sel.(g)
errs = run.("PolarArray #{(off / 1.mm).round},0,0 4")
copies = ents.grep(Sketchup::Group) - [g]
ok.('PolarArray 4 -> 3 copies', errs.empty? && copies.size == 3, [errs, copies.size])
ents.erase_entities(copies)

# ---------- Offset ----------
f = ents.add_face([off, 0, 0], [off + 1000.mm, 0, 0], [off + 1000.mm, 1000.mm, 0], [off, 1000.mm, 0])
ents.erase_entities(g)
sel.(f)
errs = run.('Offset 100')
inner = ents.grep(Sketchup::Face).map { |x| [mm.(x.bounds.width), mm.(x.bounds.height)] }.sort
ok.('Offset 100 inside', errs.empty? && inner.include?([800.0, 800.0]), [errs, inner])
ok.('offset_at sign', T::Builtins.send(:offset_at, Geom::Point3d.new(off + 500.mm, 50.mm, 0), { objects: [f] }).to_mm.round(3) == 50.0)
ents.erase_entities(ents.grep(Sketchup::Face) + ents.grep(Sketchup::Edge))
f = ents.add_face([off, 0, 0], [off + 1000.mm, 0, 0], [off + 1000.mm, 1000.mm, 0], [off, 1000.mm, 0])
sel.(f)
errs = run.('Offset -100')
outer = ents.grep(Sketchup::Edge).map { |e| mm.(e.length) }.max
ok.('Offset -100 outside', errs.empty? && outer == 1200.0, [errs, outer])
errs = run.('Offset 600')
ok.('Offset that collapses -> error', errs.first.to_s.include?('collapses'), errs)
ents.erase_entities(ents.grep(Sketchup::Face) + ents.grep(Sketchup::Edge))

# ---------- PushPull ----------
f = ents.add_face([off, 0, 0], [off + 1000.mm, 0, 0], [off + 1000.mm, 1000.mm, 0], [off, 1000.mm, 0])
sel.(f)
errs = run.('PushPull 20')
ok.('PushPull 20', errs.empty? && mm.(ents.grep(Sketchup::Face).map { |x| x.bounds.depth }.max) == 20.0, errs)
f = ents.grep(Sketchup::Face).max_by { |x| x.bounds.center.z }
sel.(f)
S.submit('PushPull')
st = S.prompt_state
ok.('PushPull asks distance', st && st[:text] == 'Extrusion distance', st)
lift = T::Builtins.send(:lift_at, f.vertices.first.position.offset(f.normal, 30.mm), { objects: [f] })
ok.('distance from cursor', lift.to_mm.round(3) == 30.0, lift.to_mm)
S.cancel

# ---------- уборка ----------
m.selection.clear
m.select_tool(nil)
m.close_active while m.active_path
m.entities.grep(Sketchup::Group).select { |x| x.name == 'EXT_SANDBOX' }.each(&:erase!)
S.history.replace(saved_history)
Sketchup.write_default(T::PREFS_KEY, 'history', JSON.generate(saved_history))

results.each { |r| puts r.join('  ') }
puts "#{results.count { |r| r[0] == 'PASS' }}/#{results.size} passed"
