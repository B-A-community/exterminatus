# Line, Rectangle, Circle: ввод, клик, повтор Line, плоскости. Всё — внутри
# группы EXT_SANDBOX, сдвинутой от начала координат.
# Запуск: python test/bridge.py test/live_draw.rb
T = BACommunity::Terminal
S = T::Session
m = Sketchup.active_model
results = []
ok = ->(name, cond, note = '') { results << [cond ? 'PASS' : 'FAIL', name, note.to_s] }
mm = ->(v) { (v.to_f * 25.4).round(3) }
saved_history = S.history.dup
%w[Line Rectangle Circle].each { |id| S.forget(id) }

m.select_tool(nil)
m.close_active while m.active_path
sandbox = m.entities.add_group
sandbox.name = 'EXT_SANDBOX'
sandbox.transform!(Geom::Transformation.translation([5000.mm, 0, 0]))
sandbox.entities.add_cpoint(ORIGIN)
m.active_path = [sandbox]
raise 'not in sandbox' unless m.active_path&.first&.name == 'EXT_SANDBOX'

ents = m.active_entities
x0 = 5000 # мм, мировые координаты внутри открытой группы
run = lambda do |line|
  mark = S.seq
  S.submit(line)
  S.log_after(mark).select { |l| l[:kind] == 'error' }.map { |l| l[:text] }
end
clear = -> { ents.erase_entities(ents.grep(Sketchup::Face) + ents.grep(Sketchup::Edge)) }
prompt = -> { S.prompt_state&.dig(:text) }
dims = ->(f) { [mm.(f.bounds.width), mm.(f.bounds.height), mm.(f.bounds.depth)] }

# ---------- Line ----------
errs = run.("Line #{x0},0,0 #{x0 + 1000},0,0")
ok.('Line inline draws one edge', errs.empty? && ents.grep(Sketchup::Edge).size == 1 && !S.busy?, [errs, ents.grep(Sketchup::Edge).size])
clear.call

S.submit('Line')
ok.('Line asks start', prompt.call == 'Start of line', prompt.call)
ok.('picker active', m.tools.active_tool.is_a?(T::Picker::PickTool))
S.submit("#{x0},0,0")
S.submit('@1000,0,0')
ok.('after a segment asks the next end', prompt.call == 'End of line', prompt.call)
S.submit('@0,1000,0')
S.submit('@-1000,0,0')
S.submit("#{x0},0,0") # замкнули — появилась грань
ok.('closed loop makes a face', ents.grep(Sketchup::Face).size == 1, ents.grep(Sketchup::Face).size)
mark = S.seq
S.submit('')
ok.('Enter finishes quietly', !S.busy? && S.log_after(mark).empty? && !m.tools.active_tool.is_a?(T::Picker::PickTool),
    S.log_after(mark))
clear.call

S.submit('Line')
S.submit("#{x0},0,0")
S.submit('@500,0,0')
S.cancel
ok.('Esc ends Line, keeps the edge', !S.busy? && ents.grep(Sketchup::Edge).size == 1)
clear.call

errs = run.("Line #{x0},0,0 #{x0},0,0")
ok.('same points -> error', errs == ['Line: the points are the same'], errs)

# ---------- Rectangle ----------
errs = run.("Rectangle #{x0},0,0 3000,2000")
f = ents.grep(Sketchup::Face).first
ok.('Rectangle by size', errs.empty? && f && dims.(f) == [3000.0, 2000.0, 0.0], [errs, f && dims.(f)])
clear.call
errs = run.("Rectangle #{x0},0,0 #{x0 + 1000},500,0")
f = ents.grep(Sketchup::Face).first
ok.('Rectangle by two corners', errs.empty? && f && dims.(f) == [1000.0, 500.0, 0.0], [errs, f && dims.(f)])
clear.call
errs = run.("Rectangle #{x0},0,0 3000,2000 plane=xz")
f = ents.grep(Sketchup::Face).first
ok.('Rectangle plane=XZ', errs.empty? && f && dims.(f) == [3000.0, 0.0, 2000.0], [errs, f && dims.(f)])
clear.call
errs = run.("Rectangle #{x0},0,0 #{x0 + 1000},0,0 plane=xy")
ok.('flat rectangle -> error', errs == ['Rectangle: the rectangle has no area'], errs)

S.submit('Rectangle plane=xy') # аргумент есть — но точек нет, спросит
ok.('Rectangle asks the corner', prompt.call == 'First corner of rectangle', prompt.call)
S.submit("#{x0},0,0")
ok.('then other corner or size', prompt.call == 'Other corner or size', prompt.call)
S.submit('@400,300')
f = ents.grep(Sketchup::Face).first
ok.('@ relative corner', f && dims.(f) == [400.0, 300.0, 0.0], f && dims.(f))
clear.call

# Plane=Auto: клик по грани стены кладёт прямоугольник на неё.
wall = ents.add_face([x0.mm, 0, 0], [x0.mm, 0, 1000.mm], [(x0 + 1000).mm, 0, 1000.mm], [(x0 + 1000).mm, 0, 0])
view = m.active_view
view.camera = Sketchup::Camera.new([(x0 + 500).mm, -3000.mm, 500.mm], [(x0 + 500).mm, 0, 500.mm], Z_AXIS)
view.refresh # выбор кликом идёт по отрисованному кадру
S.forget('Rectangle')
S.submit('Rectangle')
tool = m.tools.active_tool
sx, sy = view.screen_coords(Geom::Point3d.new((x0 + 300).mm, 0, 300.mm)).to_a
tool.onLButtonDown(0, sx, sy, view)
corner = S.instance_variable_get(:@run)&.args&.dig(:corner)
ok.('click on the wall gives the corner', corner && mm.(corner.y) == 0.0,
    [corner, view.camera.eye, [sx, sy], tool.class])
S.submit('200,100')
made = ents.grep(Sketchup::Face).reject { |x| x.equal?(wall) || !x.valid? }
small = made.min_by(&:area)
ok.('Plane=Auto follows the wall', small && dims.(small)[1] == 0.0 && mm.(small.area / 25.4) != 0, small && dims.(small))
S.cancel if S.busy?
clear.call

# Оба угла кликом по стене: второй клик не сбивает плоскость первого.
wall = ents.add_face([x0.mm, 0, 0], [x0.mm, 0, 1000.mm], [(x0 + 1000).mm, 0, 1000.mm], [(x0 + 1000).mm, 0, 0])
view.refresh
S.submit('Rectangle')
[[300, 300], [700, 600]].each do |px, pz|
  sx, sy = view.screen_coords(Geom::Point3d.new((x0 + px).mm, 0, pz.mm)).to_a
  m.tools.active_tool.onLButtonDown(0, sx, sy, view)
end
small = ents.grep(Sketchup::Face).reject { |x| x.equal?(wall) || !x.valid? }.min_by(&:area)
near = ->(d, w) { d.zip(w).all? { |x, y| (x - y).abs < 5 } } # клик по экрану — с точностью до пикселя
ok.('two clicks on the wall', !S.busy? && small && near.(dims.(small), [400, 0, 300]), [S.busy?, small && dims.(small)])
S.cancel if S.busy?
clear.call

# Запомненная Plane=XZ действует и на размер «W,H» без Plane в строке.
run.("Rectangle #{x0},0,0 300,200 plane=xz")
clear.call
errs = run.("Rectangle #{x0},0,0 300,200")
f = ents.grep(Sketchup::Face).first
ok.('remembered plane applies to size', errs.empty? && f && dims.(f) == [300.0, 0.0, 200.0], [errs, f && dims.(f)])
clear.call
S.forget('Rectangle')

# Undo во время Line отменяет и остаток цепочки.
S.submit("Line; Circle #{x0},0,0 500")
S.submit("#{x0},0,0")
S.submit('@500,0,0')
m.tools.active_tool.onCancel(2, view)
ok.('Undo in Line drops the chain', !S.busy? && ents.grep(Sketchup::Face).empty?, ents.grep(Sketchup::Face).size)
clear.call

# ---------- Circle ----------
errs = run.("Circle #{x0},0,0 500")
f = ents.grep(Sketchup::Face).first
ok.('Circle inline', errs.empty? && f && dims.(f)[0].round == 1000 && f.edges.size == 24, [errs, f && dims.(f), f&.edges&.size])
clear.call
errs = run.("Circle #{x0},0,0 500 segments=8 plane=yz")
f = ents.grep(Sketchup::Face).first
ok.('Circle segments=8 plane=YZ', errs.empty? && f && f.edges.size == 8 && dims.(f)[0] == 0.0, [errs, f && dims.(f)])
clear.call
S.forget('Circle') # Plane=YZ запомнился, как опция Rhino
S.submit('Circle')
S.submit("#{x0},0,0")
ok.('Circle asks radius', prompt.call == 'Radius', prompt.call)
rs = S.instance_variable_get(:@run)
r = T::Builtins.send(:radius_at, Geom::Point3d.new((x0 + 300).mm, 400.mm, 77.mm), S.resolved(rs))
ok.('radius from cursor ignores height', mm.(r) == 500.0, mm.(r))
S.submit('250*2')
f = ents.grep(Sketchup::Face).first
ok.('typed radius with arithmetic', f && dims.(f)[0].round == 1000, f && dims.(f))
clear.call

# Предпросмотр рисует без ошибок.
class FakeView
  attr_reader :calls
  def initialize; @calls = 0; end
  def method_missing(name, *) = (@calls += 1 if name == :draw; nil)
  def respond_to_missing?(*) = true
end
S.submit('Rectangle')
S.submit("#{x0},0,0")
fv = FakeView.new
rs = S.instance_variable_get(:@run)
S.preview(rs, rs.cmd.param(:other), Geom::Point3d.new((x0 + 100).mm, 100.mm, 0), fv)
S.cancel
S.submit('Circle')
S.submit("#{x0},0,0")
rs = S.instance_variable_get(:@run)
S.preview(rs, rs.cmd.param(:radius), 100.mm, fv)
S.cancel
ok.('previews draw', fv.calls == 2, fv.calls)

# ---------- уборка ----------
m.selection.clear
m.select_tool(nil)
m.close_active while m.active_path
m.entities.grep(Sketchup::Group).select { |x| x.name == 'EXT_SANDBOX' }.each(&:erase!)
S.history.replace(saved_history)
Sketchup.write_default(T::PREFS_KEY, 'history', JSON.generate(saved_history))

results.each { |r| puts r.join('  ') }
puts "#{results.count { |r| r[0] == 'PASS' }}/#{results.size} passed"
