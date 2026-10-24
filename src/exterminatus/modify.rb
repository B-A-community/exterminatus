# frozen_string_literal: true

module BACommunity
  module Terminal
    # Команды правки в духе Rhino: строка говорит, что нужно, а ответить можно
    # кликом в модели или числом. Без выделения сначала просят выделить. Всё
    # сразу можно написать и в строке: «Move 0,0,500», «Rotate 90 axis=x»,
    # «Copy 1000,0,0 count=5», «Offset 50», «PushPull 20». Родные инструменты
    # SketchUp остаются на своих клавишах (M, Q, S, F, P в окне модели).
    module Builtins
      AXES = %w[X Y Z].freeze

      class << self
        private

        def register_modify
          no_offset = ->(a) { a[:offset].nil? }
          center = ->(a) { center_of(a[:objects]) }

          add('Move', %w[M], 'Move the selection by a vector or from point to point',
              [objects('Select objects to move'),
               { key: :offset, type: :vector, optional: true },
               { key: :from, type: :point, label: 'Point to move from', ask_if: no_offset },
               { key: :to, type: :point, label: 'Point to move to', base: :from, ask_if: no_offset }],
              preview: ->(a, view) { Picker::Preview.box(view, bounds_of(a[:objects]), shift(a)) if shift(a) }) do |a|
            items = alive(a[:objects])
            operation('Move') { model.active_entities.transform_entities(shift(a), items) }
            "#{plural(items.size, 'object')} moved by #{vector_text(shift(a).origin - ORIGIN)}"
          end

          add('Copy', %w[Co], 'Copy the selection by a vector or from point to point; Count makes a linear array',
              [objects('Select objects to copy'),
               { key: :offset, type: :vector, optional: true },
               { key: :from, type: :point, label: 'Point to copy from', ask_if: no_offset },
               { key: :to, type: :point, label: 'Point to copy to', base: :from, ask_if: no_offset },
               { key: :count, type: :integer, default: 1, min: 1, max: 1000, prompt: false }],
              preview: lambda { |a, view|
                next unless shift(a)

                b = bounds_of(a[:objects])
                steps(a[:count]).each { |i| Picker::Preview.box(view, b, shift(a, i)) }
              }) do |a|
            items = alive(a[:objects])
            operation('Copy') { copy(items, steps(a[:count]).map { |i| shift(a, i) }) }
            "#{plural(a[:count], 'copy', 'copies')} made"
          end

          add('Rotate', %w[Q Ro], 'Rotate the selection around its center or a picked point',
              [objects('Select objects to rotate'),
               { key: :angle, type: :angle, label: 'Rotation angle', default: 90.0, base: :center,
                 pick: ->(pt, a) { angle_at(pt, a) } },
               { key: :center, type: :point, label: 'Center of rotation', prompt: false, auto: center },
               { key: :axis, type: :option, values: AXES, default: 'Z', prompt: false },
               { key: :copy, type: :bool, default: false, prompt: false }],
              preview: ->(a, view) { Picker::Preview.box(view, bounds_of(a[:objects]), turn(a)) if a[:angle] }) do |a|
            items = alive(a[:objects])
            operation('Rotate') { place(items, [turn(a)], a[:copy]) }
            "#{plural(items.size, 'object')} #{a[:copy] ? 'copied' : 'rotated'} by #{trim(a[:angle])}° around #{a[:axis]}"
          end

          add('Scale', %w[S Sc], 'Scale the selection uniformly (2) or per axis (1,1,2)',
              [objects('Select objects to scale'),
               { key: :factor, type: :scale, label: 'Scale factor', default: 2 },
               { key: :center, type: :point, label: 'Scale origin', prompt: false, auto: center },
               { key: :copy, type: :bool, default: false, prompt: false }]) do |a|
            items = alive(a[:objects])
            tr = Geom::Transformation.scaling(a[:center], *a[:factor])
            operation('Scale') { place(items, [tr], a[:copy]) }
            "#{plural(items.size, 'object')} #{a[:copy] ? 'copied' : 'scaled'} by #{a[:factor].uniq.map { |f| trim(f) }.join(', ')}"
          end

          add('PolarArray', %w[ArrayPolar], 'Copy the selection around a center',
              [objects('Select objects to array'),
               { key: :center, type: :point, label: 'Center of polar array' },
               { key: :count, type: :integer, label: 'Number of items', default: 6, min: 2, max: 1000 },
               { key: :angle, type: :angle, label: 'Angle to fill', default: 360.0, prompt: false,
                 min: -360.0, max: 360.0 },
               { key: :axis, type: :option, values: AXES, default: 'Z', prompt: false }],
              preview: lambda { |a, view|
                next unless a[:center]

                b = bounds_of(a[:objects])
                polar(a).each { |tr| Picker::Preview.box(view, b, tr) }
              }) do |a|
            items = alive(a[:objects])
            operation('Polar Array') { copy(items, polar(a)) }
            "#{plural(a[:count] - 1, 'copy', 'copies')} around #{a[:axis]}"
          end

          add('Offset', %w[F Off], 'Offset the outer edges of selected faces (inside is positive)',
              [objects('Select faces to offset', Sketchup::Face),
               { key: :distance, type: :length, label: 'Offset distance', default: 100.mm,
                 pick: ->(pt, a) { offset_at(pt, a) } }],
              preview: lambda { |a, view|
                next unless a[:distance]

                faces(a).each { |f| (pts = offset_loop(f, a[:distance])) && Picker::Preview.polyline(view, pts, closed: true) }
              }) do |a|
            done = operation('Offset') { faces(a).count { |f| offset_face(f, a[:distance]) } }
            next({ ok: false, message: 'the offset collapses the faces' }) if done.zero?

            "#{plural(done, 'face')} offset by #{a[:distance].to_l}"
          end

          add('PushPull', %w[P PP], 'Extrude selected faces by a distance',
              [objects('Select faces to push or pull', Sketchup::Face),
               { key: :distance, type: :length, label: 'Extrusion distance', default: 100.mm,
                 pick: ->(pt, a) { lift_at(pt, a) } }],
              preview: lambda { |a, view|
                next unless a[:distance]

                faces(a).each { |f| extrusion(view, f, a[:distance]) }
              }) do |a|
            items = faces(a)
            operation('Push/Pull') { items.each { |f| f.pushpull(a[:distance]) if f.valid? } }
            "#{plural(items.size, 'face')} pushed #{a[:distance].to_l}"
          end
        end

        def objects(label, *kinds)
          { key: :objects, type: :selection, label: label, kinds: kinds }
        end

        def alive(items)
          Array(items).select(&:valid?)
        end

        def faces(a)
          alive(a[:objects]).grep(Sketchup::Face)
        end

        def bounds_of(items)
          bb = Geom::BoundingBox.new
          alive(items).each { |e| bb.add(e.bounds) }
          bb
        end

        def center_of(items)
          bb = bounds_of(items)
          bb.valid? ? bb.center : nil
        end

        def axis_of(name)
          { 'X' => X_AXIS, 'Y' => Y_AXIS }.fetch(name.to_s, Z_AXIS)
        end

        # ---------- Move, Copy ----------

        # Сдвиг на шаг i (Copy с Count делает шаги 1..Count).
        def shift(a, i = 1)
          vec = a[:offset] || (a[:from] && a[:to] && a[:to] - a[:from])
          return nil unless vec

          Geom::Transformation.translation(Geom::Vector3d.new(vec.x * i, vec.y * i, vec.z * i))
        end

        def steps(count)
          (1..[count.to_i, 1].max).to_a
        end

        # ---------- Rotate, PolarArray ----------

        def turn(a, angle = a[:angle])
          Geom::Transformation.rotation(a[:center], axis_of(a[:axis]), angle.degrees)
        end

        def polar(a)
          count = a[:count]
          fill = a[:angle]
          step = fill.abs >= 360 ? fill / count : fill / (count - 1)
          (1...count).map { |i| turn(a, step * i) }
        end

        # Угол от опорного направления до курсора в плоскости поворота. Около
        # кратных 15° прилипает, как транспортир SketchUp.
        def angle_at(pt, a)
          axis = axis_of(a[:axis])
          v = pt - a[:center]
          v -= Geom::Vector3d.new(axis.x * (v % axis), axis.y * (v % axis), axis.z * (v % axis))
          return nil if v.length < 1e-6

          ref = { 'X' => Y_AXIS, 'Y' => Z_AXIS }.fetch(a[:axis].to_s, X_AXIS)
          deg = Math.atan2((ref * v) % axis, ref % v).radians
          snap = (deg / 15.0).round * 15.0
          (deg - snap).abs < 2 ? snap : deg.round(1)
        end

        # ---------- Offset ----------

        # Контур грани, сдвинутый внутрь на d (минус — наружу), или nil.
        def offset_loop(face, d)
          pts = face.outer_loop.vertices.map(&:position)
          pts = pts.reject.with_index { |p, i| p.on_line?([pts[i - 1], pts[(i + 1) % pts.size]]) }
          return nil if pts.size < 3

          n = face.normal
          lines = pts.each_with_index.map do |p, i|
            dir = pts[(i + 1) % pts.size] - p
            [p.offset(n * dir, d), dir]
          end
          out = lines.each_index.map do |i|
            Geom.intersect_line_line(lines[i - 1], lines[i]) || lines[i][0]
          end
          return nil if d.to_f.positive? && out.each_index.any? { |i| (out[(i + 1) % out.size] - out[i]) % lines[i][1] <= 0 }

          out
        end

        def offset_face(face, d)
          pts = offset_loop(face, d) or return false

          ents = model.active_entities
          if d.to_f.positive?
            # Грань поверх грани делит её, как родной Offset.
            inner = ents.add_face(pts)
            inner.reverse! if inner && inner.normal % face.normal < 0
          else
            ents.add_edges(pts + [pts.first])&.first&.find_faces
          end
          true
        end

        # Расстояние от курсора до края первой грани: внутри — плюс, снаружи — минус.
        def offset_at(pt, a)
          face = faces(a).first or return nil
          p = pt.project_to_plane(face.plane)
          ring = face.outer_loop.vertices.map(&:position)
          d = ring.each_index.map { |i| segment_distance(p, ring[i - 1], ring[i]) }.min
          inside = [Sketchup::Face::PointInside, Sketchup::Face::PointOnFace].include?(face.classify_point(p))
          (inside ? d : -d).to_l
        end

        def segment_distance(p, a, b)
          ab = b - a
          return p.distance(a) if ab.length.zero?

          t = [[(p - a) % ab / (ab % ab), 0.0].max, 1.0].min
          p.distance(a.offset(ab, ab.length * t))
        end

        # ---------- PushPull ----------

        def lift_at(pt, a)
          face = faces(a).first or return nil
          ((pt - face.vertices.first.position) % face.normal).to_l
        end

        def extrusion(view, face, d)
          base = face.outer_loop.vertices.map(&:position)
          top = base.map { |p| p.offset(face.normal, d) }
          Picker::Preview.polyline(view, top, closed: true)
          Picker::Preview.lines(view, base.zip(top).flatten)
        end

        # ---------- копирование ----------

        # Без copy — преобразовать на месте, с copy — сделать копии.
        def place(items, transforms, as_copy)
          return copy(items, transforms) if as_copy

          model.active_entities.transform_entities(transforms.first, items)
        end

        # Группы и компоненты копируются как экземпляры (с материалом, тегом,
        # именем). Свободную геометрию на время оборачиваем в группу: так копии
        # сливаются с окружением, как при копировании инструментом Move.
        def copy(items, transforms)
          ents = model.active_entities
          inst, loose = items.partition { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          transforms.each do |tr|
            inst.each { |e| ents.transform_entities(tr, clone_instance(ents, e)) }
          end
          # Грань без своих рёбер в группу не переносится — берём их тоже.
          loose = loose.grep(Sketchup::Drawingelement)
          loose |= loose.grep(Sketchup::Face).flat_map(&:edges)
          return if loose.empty?

          tmp = ents.add_group(loose)
          transforms.each { |tr| ents.add_instance(tmp.definition, tr * tmp.transformation).explode }
          selection.add(tmp.explode.grep(Sketchup::Drawingelement).select { |e| ents.include?(e) })
        end

        def clone_instance(ents, inst)
          return inst.copy if inst.is_a?(Sketchup::Group)

          c = ents.add_instance(inst.definition, inst.transformation)
          c.material = inst.material
          c.layer = inst.layer
          c.name = inst.name
          c.casts_shadows = inst.casts_shadows?
          c.receives_shadows = inst.receives_shadows?
          # Атрибуты экземпляра: Dynamic Components, данные плагинов.
          inst.attribute_dictionaries&.each do |dict|
            dict.each_pair { |k, v| c.set_attribute(dict.name, k, v) }
          end
          c
        end

        # ---------- текст ----------

        def plural(n, one, many = "#{one}s")
          "#{n} #{n == 1 ? one : many}"
        end

        def trim(f)
          f.to_f == f.to_f.round ? f.to_f.round.to_s : f.to_f.round(3).to_s
        end

        def vector_text(v)
          v.to_a.map { |c| c.to_l.to_s }.join(', ')
        end
      end
    end
  end
end
