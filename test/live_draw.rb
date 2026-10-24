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
%w[Line Rectangle Circle Arc ArcCenter Pie Polygon].each { |id| S.forget(id) }

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

# ---------- Arc: концы и прогиб ----------
arc = -> { ents.grep(Sketchup::Edge).map(&:curve).compact.uniq.first }
pts = -> { ents.grep(Sketchup::Edge).flat_map(&:vertices).uniq.map(&:position) }
errs = run.("Arc #{x0},0,0 #{x0 + 1000},0,0 200")
c = arc.call
ok.('Arc by bulge: radius', errs.empty? && c.is_a?(Sketchup::ArcCurve) && mm.(c.radius) == 725.0, [errs, c && mm.(c.radius)])
ok.('Arc bulges to +Y', mm.(pts.call.map(&:y).max).round == 200 && mm.(pts.call.map(&:y).min).round == 0, pts.call.map { |q| mm.(q.y) }.minmax)
clear.call
run.("Arc #{x0},0,0 #{x0 + 1000},0,0 -200")
ok.('negative bulge goes to -Y', mm.(pts.call.map(&:y).min).round == -200, pts.call.map { |q| mm.(q.y) }.minmax)
clear.call
run.("Arc #{x0},0,0 #{x0 + 1000},0,0 800")
ok.('bulge over half chord: arc > 180', mm.(pts.call.map(&:y).max).round == 800, pts.call.map { |q| mm.(q.y) }.minmax)
clear.call
S.submit('Arc')
S.submit("#{x0},0,0")
S.submit("#{x0 + 1000},0,0")
ok.('Arc asks bulge', prompt.call == 'Bulge', prompt.call)
rs = S.instance_variable_get(:@run)
b = T::Builtins.send(:bulge_at, Geom::Point3d.new((x0 + 300).mm, 150.mm, 40.mm), S.resolved(rs))
ok.('bulge from cursor', mm.(b) == 150.0, mm.(b))
S.submit('150')
ok.('typed bulge draws', arc.call && !S.busy?)
clear.call

# ---------- ArcCenter, Pie ----------
errs = run.("ArcCenter #{x0},0,0 #{x0 + 1000},0,0 90")
c = arc.call
ends = c && [c.first_edge.start.position, c.last_edge.end.position].map { |q| q.to_a.map { |v| mm.(v).round } }
ok.('ArcCenter 90', errs.empty? && c && mm.(c.radius) == 1000.0 && ends.include?([x0, 1000, 0]), [errs, ends])
clear.call
run.("ArcCenter #{x0},0,0 #{x0 + 1000},0,0 -90")
ok.('ArcCenter -90 goes clockwise', mm.(pts.call.map(&:y).min).round == -1000 && mm.(pts.call.map(&:y).max).round == 0)
clear.call
errs = run.("ArcCenter #{x0},0,0 #{x0 + 1000},0,0 #{x0},-1000,0")
ok.('end point instead of angle: 270', errs.empty? && mm.(pts.call.map(&:x).min).round == x0 - 1000, [errs, pts.call.map { |q| mm.(q.x) }.minmax])
clear.call
S.submit('ArcCenter')
S.submit("#{x0},0,0")
S.submit("#{x0 + 1000},0,0")
rs = S.instance_variable_get(:@run)
ang = T::Builtins.send(:sweep_at, Geom::Point3d.new(x0.mm, 700.mm, 0), S.resolved(rs))
ok.('angle from cursor', ang == 90.0, ang)
S.cancel
errs = run.("Pie #{x0},0,0 #{x0 + 1000},0,0 90")
f = ents.grep(Sketchup::Face).first
area = f && (f.area * 25.4 * 25.4 / 1e6).round(2) # м²
ok.('Pie makes a quarter face', errs.empty? && f && (area - Math::PI / 4).abs < 0.01, [errs, area])
clear.call

# ---------- Polygon ----------
errs = run.("Polygon #{x0},0,0 500")
f = ents.grep(Sketchup::Face).first
corner = f && f.vertices.map { |v| v.position.to_a.map { |q| mm.(q).round } }.include?([x0 + 500, 0, 0])
ok.('Polygon by radius', errs.empty? && f && f.edges.size == 6 && corner, [errs, f&.edges&.size, corner])
clear.call
errs = run.("Polygon #{x0},0,0 #{x0 + 500},0,0 sides=4 mode=circumscribed")
f = ents.grep(Sketchup::Face).first
ok.('Polygon circumscribed square', errs.empty? && f && f.edges.size == 4 && dims.(f).map(&:round) == [1000, 1000, 0], [errs, f && dims.(f)])
clear.call
S.forget('Polygon')
errs = run.("Polygon #{x0},0,0 #{x0},500,0")
f = ents.grep(Sketchup::Face).first
corner = f && f.vertices.map { |v| v.position.to_a.map { |q| mm.(q).round } }.include?([x0, 500, 0])
ok.('Polygon corner follows the point', errs.empty? && corner, errs)
clear.call

# Замечания Codex: точный конец без прилипания, концы Pie, радиус при курсоре вне плоскости.
errs = run.("ArcCenter #{x0},0,0 #{x0 + 1000},0,0 #{x0 + 1000},10,0 plane=xy")
ok.('typed end point is not snapped', errs.empty? && arc.call, errs)
clear.call
ents.add_line([(x0).mm, 100.mm, 0], [(x0 + 100).mm, 0, 0])
errs = run.("Pie #{x0},0,0 #{x0 + 100},0,0 180 segments=2 plane=xy")
ok.('Pie closes over an existing edge', errs.empty? && ents.grep(Sketchup::Face).any?, errs)
clear.call
errs = run.("Pie #{x0},0,0 #{x0 + 1000},0,0 360 segments=2")
ok.('full Pie from two segments -> error', errs.first.to_s.include?('Pie'), errs)
S.forget('Pie')
errs = run.("Pie #{x0},0,0 #{x0 + 1000},0,0 360 segments=12")
ok.('full Pie is a disc', errs.empty? && ents.grep(Sketchup::Face).size == 1, [errs, ents.grep(Sketchup::Face).size])
clear.call
S.forget('Polygon')
pp = T::Builtins.send(:corner_by_radius, '1000', { center: Geom::Point3d.new(x0.mm, 0, 0), plane: 'XY' },
                      Geom::Point3d.new((x0 + 1000).mm, 0, 1000.mm))
ok.('typed radius toward an off-plane cursor', pp && mm.(pp.x) == x0 + 1000.0 && mm.(pp.z) == 0.0, pp)
f0 = ents.add_face(ents.add_ngon(Geom::Point3d.new(x0.mm, 0, 0), Z_AXIS, 500.mm, 4))
before = f0.vertices.map { |v| v.position.to_a.map { |q| mm.(q).round } }.sort
run.("Polygon #{x0},0,0 #{x0 + 354},354,0 sides=4")
now = ents.grep(Sketchup::Edge).flat_map(&:vertices).uniq.map { |v| v.position.to_a.map { |q| mm.(q).round } }
ok.('Polygon does not rotate existing edges', (before - now).empty?, before - now)
clear.call

# ---------- уборка ----------
m.selection.clear
m.select_tool(nil)
m.close_active while m.active_path
m.entities.grep(Sketchup::Group).select { |x| x.name == 'EXT_SANDBOX' }.each(&:erase!)
S.history.replace(saved_history)
Sketchup.write_default(T::PREFS_KEY, 'history', JSON.generate(saved_history))

results.each { |r| puts r.join('  ') }
puts "#{results.count { |r| r[0] == 'PASS' }}/#{results.size} passed"
