# frozen_string_literal: true

module BACommunity
  module Terminal
    # Рисование в духе Rhino: Line, Rectangle, Circle, Arc, ArcCenter, Pie,
    # Polygon. Точки — кликом в модели
    # или вводом; всё сразу можно написать и в строке:
    # «Line 0,0,0 1000,0,0», «Rectangle 0,0,0 3000,2000», «Circle 0,0,0 500».
    # Plane=Auto кладёт фигуру на грань, по которой кликнули первой точкой
    # (углом или центром), иначе — на XY.
    module Builtins
      PLANES = %w[Auto XY XZ YZ].freeze

      class << self
        private

        def register_draw
          # Line идёт дальше от последней точки, пока не нажат Enter или Esc,
          # как инструмент Line у SketchUp.
          add('Line', %w[L], 'Draw edges point to point; Enter finishes',
              [{ key: :start, type: :point, label: 'Start of line' },
               { key: :finish, type: :point, label: 'End of line', base: :start }],
              repeat: ->(a) { { start: a[:finish] } }) do |a|
            next({ ok: false, message: 'the points are the same' }) if a[:start] == a[:finish]

            operation('Line') do
              edge = model.active_entities.add_line(a[:start], a[:finish])
              edge&.find_faces
            end
            nil
          end

          add('Rectangle', %w[R Rect], 'Draw a rectangle by two corners or by size',
              [{ key: :corner, type: :point, label: 'First corner of rectangle' },
               { key: :other, type: :point, label: 'Other corner or size', base: :corner,
                 parse: ->(s, a) { corner_by_size(s, a) } },
               { key: :plane, type: :option, values: PLANES, default: 'Auto', prompt: false }],
              preview: ->(a, view) { (pts = rectangle(a)) && Picker::Preview.shape(view, pts, closed: true) }) do |a|
            pts = rectangle(a) or next({ ok: false, message: 'the rectangle has no area' })

            operation('Rectangle') { model.active_entities.add_face(pts) }
            "Rectangle #{size_text(a)}"
          end

          add('Circle', %w[C], 'Draw a circle by center and radius',
              [{ key: :center, type: :point, label: 'Center of circle' },
               { key: :radius, type: :length, label: 'Radius', base: :center, min: 0.001.mm,
                 pick: ->(pt, a) { radius_at(pt, a) } },
               { key: :segments, type: :integer, default: 24, min: 3, max: 999, prompt: false },
               { key: :plane, type: :option, values: PLANES, default: 'Auto', prompt: false }],
              preview: lambda { |a, view|
                Picker::Preview.shape(view, circle_points(a), closed: true) if a[:radius]&.positive?
              }) do |a|
            operation('Circle') do
              ents = model.active_entities
              ents.add_face(ents.add_circle(a[:center], plane_normal(a, :center), a[:radius], a[:segments]))
            end
            "Circle R#{a[:radius].to_l}"
          end
        end

        # ---------- дуги и многоугольник ----------

        def register_curves
          options = [{ key: :segments, type: :integer, default: 12, min: 2, max: 999, prompt: false },
                     { key: :plane, type: :option, values: PLANES, default: 'Auto', prompt: false }]

          # Как Arc у SketchUp (клавиша A): два конца и стрелка прогиба.
          add('Arc', %w[A], 'Draw an arc by two end points and bulge',
              [{ key: :start, type: :point, label: 'Start of arc' },
               { key: :finish, type: :point, label: 'End of arc', base: :start },
               { key: :bulge, type: :length, label: 'Bulge', pick: ->(pt, a) { bulge_at(pt, a) } },
               *options],
              preview: ->(a, view) { (spec = arc_by_bulge(a)) && Picker::Preview.shape(view, arc_points(spec, a[:segments])) }) do |a|
            spec = arc_by_bulge(a) or next({ ok: false, message: 'the arc needs two different ends and a bulge' })

            operation('Arc') { add_arc(spec, a[:segments]) }
            "Arc R#{spec[3].to_l}"
          end

          center_params = [{ key: :center, type: :point, label: 'Center of arc' },
                           { key: :start, type: :point, label: 'Start of arc', base: :center },
                           { key: :angle, type: :angle, label: 'End point or angle', default: 90.0, min: -360.0, max: 360.0,
                             base: :center, pick: ->(pt, a) { sweep_at(pt, a) }, parse: ->(s, a) { sweep_to(s, a) } },
                           *options]

          add('ArcCenter', %w[AC], 'Draw an arc by center, start point and angle',
              center_params, preview: ->(a, view) { (spec = arc_by_center(a)) && Picker::Preview.shape(view, arc_points(spec, a[:segments])) }) do |a|
            spec = arc_by_center(a) or next({ ok: false, message: 'the arc needs a radius and an angle' })

            operation('Arc') { add_arc(spec, a[:segments]) }
            "Arc R#{spec[3].to_l}, #{trim(a[:angle])}°"
          end

          add('Pie', %w[], 'Draw a pie-shaped face by center, start point and angle',
              center_params, preview: lambda { |a, view|
                next unless (spec = arc_by_center(a))

                Picker::Preview.shape(view, [spec[0], *arc_points(spec, a[:segments])], closed: true)
              }) do |a|
            spec = arc_by_center(a) or next({ ok: false, message: 'the pie needs a radius and an angle' })

            operation('Pie') do
              edges = add_arc(spec, a[:segments])
              ents = model.active_entities
              if spec[4] >= 2 * Math::PI - 1e-9
                ents.add_face(edges) # полный круг — без радиусов
              else
                # Концы — из самой дуги: рёбра могли слиться с чужими и развернуться.
                ring = arc_points(spec, a[:segments])
                [ring.first, ring.last].each { |p| ents.add_line(spec[0], p) }
                edges.first.find_faces
              end
            end
            "Pie R#{spec[3].to_l}, #{trim(a[:angle])}°"
          end

          add('Polygon', %w[Poly], 'Draw a regular polygon by center and corner (or radius)',
              [{ key: :center, type: :point, label: 'Center of polygon' },
               { key: :corner, type: :point, label: 'Corner of polygon or radius', base: :center,
                 parse: ->(s, a, cursor) { corner_by_radius(s, a, cursor) } },
               { key: :sides, type: :integer, default: 6, min: 3, max: 999, prompt: false },
               { key: :mode, type: :option, values: %w[Inscribed Circumscribed], default: 'Inscribed', prompt: false },
               options.last],
              preview: ->(a, view) { (pts = polygon(a)) && Picker::Preview.shape(view, pts, closed: true) }) do |a|
            pts = polygon(a) or next({ ok: false, message: 'the polygon needs a radius' })

            # Контур сразу по вершинам: add_ngon с поворотом после мог бы
            # слиться с чужим контуром и повернуть и его.
            operation('Polygon') do
              ents = model.active_entities
              ents.add_face(ents.add_curve(pts + [pts.first]))
            end
            "Polygon #{a[:sides]} sides"
          end
        end

        # Дуга: [центр, направление на начало, нормаль, радиус, развёртка > 0].
        def add_arc(spec, segments)
          center, x, n, r, sweep = spec
          model.active_entities.add_arc(center, x, n, r, 0, sweep, segments)
        end

        def arc_points(spec, segments)
          center, x, n, r, sweep = spec
          y = n * x
          (0..segments).map do |i|
            t = sweep * i / segments
            center.offset(x, r * Math.cos(t)).offset(y, r * Math.sin(t))
          end
        end

        # Угол от x до v вокруг n, 0…2π.
        def angle_around(x, v, n)
          t = Math.atan2((x * v) % n, x % v)
          t.negative? ? t + 2 * Math::PI : t
        end

        def flat(v, n)
          v - Geom::Vector3d.new(n.x * (v % n), n.y * (v % n), n.z * (v % n))
        end

        # ---------- Arc: концы и прогиб ----------

        # Середина хорды, перпендикуляр к ней в плоскости, половина хорды.
        def chord(a)
          return nil unless a[:start] && a[:finish]

          n = plane_normal(a, :start)
          c = flat(a[:finish] - a[:start], n)
          half = c.length / 2.0
          return nil if half < 1e-6

          [a[:start].offset(c, half), (n * c).normalize, half, c, n]
        end

        def bulge_at(pt, a)
          frame = chord(a) or return nil
          mid, w, = frame
          ((pt - mid) % w).to_l
        end

        def arc_by_bulge(a)
          frame = chord(a) or return nil
          mid, w, half, c, n = frame
          h = a[:bulge].to_f
          return nil if h.abs < 1e-6

          r = (half**2 + h**2) / (2 * h.abs)
          apex = mid.offset(w, h)
          center = apex.offset(w, h.positive? ? -r : r)
          x = (a[:start] - center).normalize
          to = angle_around(x, a[:start].offset(c) - center, n)
          via = angle_around(x, apex - center, n)
          # Дуга идёт через вершину прогиба: если та не по пути, идём в другую сторону.
          via <= to ? [center, x, n, r, to] : [center, x, n.reverse, r, 2 * Math::PI - to]
        end

        # ---------- ArcCenter, Pie: центр, начало, угол ----------

        def arc_by_center(a)
          return nil unless a[:center] && a[:start] && a[:angle]

          n = plane_normal(a, :center)
          v = flat(a[:start] - a[:center], n)
          return nil if v.length < 1e-6 || a[:angle].to_f.abs < 1e-6

          sweep = a[:angle].to_f.degrees
          return nil if sweep.abs >= 2 * Math::PI - 1e-9 && a[:segments].to_i < 3 # круг из двух отрезков

          sweep.negative? ? [a[:center], v.normalize, n.reverse, v.length, -sweep] : [a[:center], v.normalize, n, v.length, sweep]
        end

        # Угол от начала дуги до курсора против часовой стрелки, 0…360; около
        # кратных 15° прилипает.
        def sweep_at(pt, a)
          deg = exact_sweep(pt, a) or return nil
          snap = (deg / 15.0).round * 15.0
          (deg - snap).abs < 2 ? snap : deg.round(1)
        end

        # Угол до точки без прилипания — для введённых координат.
        def exact_sweep(pt, a)
          return nil unless a[:center] && a[:start]

          n = plane_normal(a, :center)
          x = flat(a[:start] - a[:center], n)
          v = flat(pt - a[:center], n)
          return nil if x.length < 1e-6 || v.length < 1e-6

          deg = angle_around(x, v, n).radians
          deg < 1e-6 ? 360.0 : deg
        end

        # «x,y,z» или «@…» на вопрос об угле — конечная точка.
        def sweep_to(s, a)
          return nil unless s.include?(',') || s.include?('<')

          pt, err = Param.new(key: :end, type: :point).parse(s, base: a[:center])
          err ? nil : exact_sweep(pt, a)
        end

        # ---------- Polygon ----------

        # Число — радиус до вершины: в сторону курсора в плоскости
        # многоугольника, а без курсора (из строки) — по оси плоскости.
        def corner_by_radius(s, a, cursor)
          return nil if s.match?(/[,@<]/) || a[:center].nil?

          r = Expr.length(s) or return nil
          n = plane_normal(a, :center)
          dir = cursor ? flat(cursor - a[:center], n) : plane_axes(n).first
          return nil if dir.length < 1e-6

          a[:center].offset(dir, r)
        end

        def polygon(a)
          return nil unless a[:center] && a[:corner]

          n = plane_normal(a, :center)
          d = flat(a[:corner] - a[:center], n)
          return nil if d.length < 1e-6

          k = a[:sides]
          r = d.length
          first = a[:center].offset(d, r)
          # Circumscribed: курсор — середина стороны, вершины дальше и сдвинуты на полшага.
          if a[:mode] == 'Circumscribed'
            first = a[:center].offset(d, r / Math.cos(Math::PI / k))
            first = first.transform(Geom::Transformation.rotation(a[:center], n, Math::PI / k))
          end
          (0...k).map { |i| first.transform(Geom::Transformation.rotation(a[:center], n, 2 * Math::PI * i / k)) }
        end

        # Нормаль плоскости фигуры. Auto — грань под кликом в точке key.
        def plane_normal(a, key)
          case a[:plane]
          when 'XZ' then Y_AXIS
          when 'YZ' then X_AXIS
          when 'XY' then Z_AXIS
          else Session.clicked_normal(key) || Z_AXIS
          end
        end

        # Оси в плоскости: u горизонтальна, если плоскость не горизонтальна.
        def plane_axes(n)
          u = n.parallel?(Z_AXIS) ? X_AXIS.clone : (Z_AXIS * n).normalize
          v = (n * u).normalize
          [u, v]
        end

        # ---------- Rectangle ----------

        def rectangle(a)
          c1 = a[:corner]
          c2 = a[:other]
          return nil unless c1 && c2

          n = plane_normal(a, :corner)
          u, v = plane_axes(n)
          d = c2 - c1
          w = d % u
          h = d % v
          return nil if w.abs < 1e-6 || h.abs < 1e-6

          [c1, c1.offset(u, w), c1.offset(u, w).offset(v, h), c1.offset(v, h)]
        end

        # «3000,2000» — ширина и высота в плоскости прямоугольника, как в поле
        # Measurements у SketchUp. Остальные записи («@…», клик) — как у точки.
        def corner_by_size(s, a)
          parts = s.split(',', -1)
          return nil unless parts.size == 2 && a[:corner] && !s.match?(/[@<]/)

          w = Expr.length(parts[0]) or return nil
          h = Expr.length(parts[1]) or return nil
          u, v = plane_axes(plane_normal(a, :corner))
          a[:corner].offset(u, w).offset(v, h)
        end

        def size_text(a)
          pts = rectangle(a)
          "#{pts[0].distance(pts[1]).to_l} x #{pts[1].distance(pts[2]).to_l}"
        end

        # ---------- Circle ----------

        def radius_at(pt, a)
          n = plane_normal(a, :center)
          v = pt - a[:center]
          v -= Geom::Vector3d.new(n.x * (v % n), n.y * (v % n), n.z * (v % n))
          v.length.positive? ? v.length.to_l : nil
        end

        def circle_points(a)
          u, v = plane_axes(plane_normal(a, :center))
          r = a[:radius]
          (0...a[:segments]).map do |i|
            t = 2 * Math::PI * i / a[:segments]
            a[:center].offset(u, r * Math.cos(t)).offset(v, r * Math.sin(t))
          end
        end
      end
    end
  end
end
