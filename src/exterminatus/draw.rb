# frozen_string_literal: true

module BACommunity
  module Terminal
    # Рисование в духе Rhino: Line, Rectangle, Circle. Точки — кликом в модели
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
              preview: ->(a, view) { (pts = rectangle(a)) && Picker::Preview.polyline(view, pts, closed: true) }) do |a|
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
                Picker::Preview.polyline(view, circle_points(a), closed: true) if a[:radius]&.positive?
              }) do |a|
            operation('Circle') do
              ents = model.active_entities
              ents.add_face(ents.add_circle(a[:center], plane_normal(a, :center), a[:radius], a[:segments]))
            end
            "Circle R#{a[:radius].to_l}"
          end
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
