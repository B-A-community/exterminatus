# frozen_string_literal: true

module BACommunity
  module Terminal
    # Ещё команды SketchUp в духе Rhino: строка говорит, что нужно, ответ —
    # кликом или вводом. Теги, материалы, изоляция, направляющие, размеры,
    # выноски, сечения, ведение (FollowMe), сглаживание, зеркало, твёрдые тела.
    module Builtins
      ISOLATE_DICT = 'BACommunity_Exterminatus'
      SolidFailed = Class.new(StandardError)

      class << self
        private

        def register_native
          register_properties
          register_annotation
          register_shape
        end

        # ---------- свойства выделения ----------

        def register_properties
          add('SetTag', %w[], 'Put the selection on a tag (a new tag is created)',
              [objects('Select objects to tag'),
               { key: :tag, type: :string, label: 'Tag name', suggest: -> { model.layers.map { |l| tag_name(l) } } }]) do |a|
            items = alive(a[:objects]).select { |e| e.respond_to?(:layer=) }
            name = a[:tag].to_s.strip
            next({ ok: false, message: 'tag name is empty' }) if name.empty?

            layer = model.layers.find { |l| tag_name(l).casecmp?(name) || l.name.casecmp?(name) }
            fresh = layer.nil?
            operation('Set Tag') do
              layer ||= model.layers.add(name)
              items.each { |e| e.layer = layer }
            end
            "#{plural(items.size, 'object')} on #{tag_name(layer)}#{fresh ? ' (new tag)' : ''}"
          end

          add('SetMaterial', %w[Mat], 'Paint the selection with a material (or a color name, #rrggbb, None)',
              [objects('Select objects to paint'),
               { key: :material, type: :string, label: 'Material',
                 suggest: -> { model.materials.map(&:display_name) + ['None'] } }]) do |a|
            items = alive(a[:objects]).select { |e| e.respond_to?(:material=) }
            mat, err = material_for(a[:material].to_s.strip)
            next({ ok: false, message: err }) if err

            operation('Paint') do
              mat = model.materials.add(mat[:name]).tap { |m| m.color = mat[:color] } if mat.is_a?(Hash)
              items.each { |e| e.material = mat }
            end
            "#{plural(items.size, 'object')} painted #{mat ? mat.display_name : 'with the default material'}"
          end

          add('Rename', %w[], 'Name the selected groups and components',
              [objects('Select groups or components', Sketchup::Group, Sketchup::ComponentInstance),
               { key: :name, type: :string, label: 'New name' }]) do |a|
            items = alive(a[:objects])
            operation('Rename') { items.each { |e| e.name = a[:name].to_s } }
            "#{plural(items.size, 'object')} named #{a[:name]}"
          end

          add('Info', %w[What], 'Describe the selection: types, size, tags, materials, area') { info_text }

          add('Isolate', %w[], 'Hide everything except the selection (Unisolate brings it back)',
              [objects('Select objects to keep visible')]) do |a|
            keep = alive(a[:objects])
            others = model.active_entities.select do |e|
              e.is_a?(Sketchup::Drawingelement) && !keep.include?(e) && e.respond_to?(:hidden=) && !e.hidden?
            end
            next 'Nothing else to hide' if others.empty?

            operation('Isolate') do
              others.each { |e| e.hidden = true }
              ids = Array(model.get_attribute(ISOLATE_DICT, 'isolated', [])) | others.map(&:persistent_id)
              model.set_attribute(ISOLATE_DICT, 'isolated', ids)
            end
            "#{plural(others.size, 'object')} hidden; Unisolate shows them again"
          end

          add('Unisolate', %w[], 'Show what Isolate has hidden') do
            ids = Array(model.get_attribute(ISOLATE_DICT, 'isolated', []))
            next 'Nothing isolated' if ids.empty?

            items = Array(model.find_entity_by_persistent_id(ids)).compact.select(&:valid?)
            operation('Unisolate') do
              items.each { |e| e.hidden = false if e.respond_to?(:hidden=) }
              model.delete_attribute(ISOLATE_DICT, 'isolated')
            end
            "#{plural(items.size, 'object')} shown"
          end
        end

        def tag_name(layer)
          layer.respond_to?(:display_name) ? layer.display_name : layer.name
        end

        # → [Sketchup::Material | { name:, color: } | nil (без материала), nil] или [nil, ошибка]
        def material_for(name)
          return [nil, 'material name is empty'] if name.empty?
          return [nil, nil] if %w[none default].include?(name.downcase)

          found = model.materials.find { |m| m.display_name.casecmp?(name) || m.name.casecmp?(name) }
          return [found, nil] if found

          if name.match?(/\A#?\h{6}\z/)
            hex = name.delete('#')
            return [{ name: "##{hex.downcase}", color: Sketchup::Color.new(*hex.scan(/../).map(&:hex)) }, nil]
          end
          color = Sketchup::Color.names.find { |c| c.casecmp?(name) }
          return [{ name: color, color: Sketchup::Color.new(color) }, nil] if color

          [nil, "no material #{name} in the model (a color name like Red or #ff8800 makes a new one)"]
        end

        def info_text
          items = selection.to_a
          if items.empty?
            ents = model.active_entities
            return "Nothing selected. In this context: #{ents.size} entities, #{ents.grep(Sketchup::Face).size} faces, " \
                   "#{ents.count { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }} groups and components"
          end

          kinds = items.group_by { |e| e.class.name.split('::').last }.map { |k, v| plural(v.size, k.gsub(/(?<=[a-z])(?=[A-Z])/, ' ').downcase) }
          bb = bounds_of(items)
          lines = ["#{items.size} selected: #{kinds.join(', ')}"]
          lines << "Size: #{bb.width.to_l} x #{bb.height.to_l} x #{bb.depth.to_l}" if bb.valid?
          tags = items.map { |e| e.respond_to?(:layer) ? tag_name(e.layer) : nil }.compact.uniq
          lines << "Tags: #{tags.first(5).join(', ')}#{tags.size > 5 ? '…' : ''}" if tags.any?
          mats = items.map { |e| e.respond_to?(:material) ? e.material&.display_name : nil }.compact.uniq
          lines << "Materials: #{mats.first(5).join(', ')}#{mats.size > 5 ? '…' : ''}" if mats.any?
          inst = items.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          names = inst.map { |e| e.name.to_s.empty? ? e.definition.name : e.name }.uniq
          lines << "Names: #{names.first(5).join(', ')}#{names.size > 5 ? '…' : ''}" if names.any?
          faces = items.grep(Sketchup::Face)
          lines << "Face area: #{Sketchup.format_area(faces.sum(&:area))}" if faces.any?
          edges = items.grep(Sketchup::Edge)
          lines << "Edge length: #{edges.sum(&:length).to_l}" if edges.any?
          lines.join("\n")
        end

        # ---------- направляющие, размеры, выноски, сечения ----------

        def register_annotation
          add('Guide', %w[], 'Draw an infinite guide line through two points',
              [{ key: :start, type: :point, label: 'First point of guide' },
               { key: :finish, type: :point, label: 'Second point of guide (direction)', base: :start }],
              preview: ->(a, view) { guide_preview(view, a) }) do |a|
            next({ ok: false, message: 'the points are the same' }) if a[:start] == a[:finish]

            operation('Guide') { model.active_entities.add_cline(a[:start], a[:finish] - a[:start]) }
            'Guide added'
          end

          add('GuidePoint', %w[], 'Place guide points; Enter finishes',
              [{ key: :point, type: :point, label: 'Guide point' }],
              repeat: ->(_a) { {} }) do |a|
            operation('Guide Point') { model.active_entities.add_cpoint(a[:point]) }
            nil
          end

          add('DimLinear', %w[DimL], 'Dimension between two points',
              [{ key: :start, type: :point, label: 'First point to dimension' },
               { key: :finish, type: :point, label: 'Second point', base: :start },
               { key: :position, type: :point, label: 'Dimension line position', base: :finish }],
              preview: lambda { |a, view|
                off = dim_offset(a) or next

                Picker::Preview.polyline(view, [a[:start], a[:start].offset(off), a[:finish].offset(off), a[:finish]], solid: true)
              }) do |a|
            next({ ok: false, message: 'the points are the same' }) if a[:start] == a[:finish]

            off = dim_offset(a) || Geom::Vector3d.new(0, 0, 0)
            operation('Dimension') { model.active_entities.add_dimension_linear(a[:start], a[:finish], off) }
            "Dimension #{a[:start].distance(a[:finish]).to_l}"
          end

          add('Label', %w[Leader], 'Text with a leader: point, text position, text',
              [{ key: :point, type: :point, label: 'Point to label' },
               { key: :position, type: :point, label: 'Text position', base: :point },
               { key: :text, type: :string, label: 'Text' }],
              preview: ->(a, view) { Picker::Preview.lines(view, [a[:point], a[:position]], solid: true) if a[:position] }) do |a|
            text = a[:text].to_s
            next({ ok: false, message: 'the text is empty' }) if text.strip.empty?

            operation('Text') { model.active_entities.add_text(text, a[:point], a[:position] - a[:point]) }
            nil
          end

          add('SectionAt', %w[SecAt], 'Place an active section plane through a point (on the clicked face or by Plane)',
              [{ key: :point, type: :point, label: 'Point on the section plane' },
               { key: :plane, type: :option, values: PLANES, default: 'Auto', prompt: false },
               { key: :flip, type: :bool, default: false, prompt: false }]) do |a|
            n = plane_normal(a, :point)
            n = n.reverse if a[:flip]
            plane = operation('Section Plane') do
              sp = model.active_entities.add_section_plane([a[:point], n])
              sp.activate if sp.respond_to?(:activate)
              sp
            end
            next({ ok: false, message: 'cannot place a section plane here' }) unless plane

            "Section plane facing #{n.to_a.map { |c| trim(c) }.join(', ')}"
          end
        end

        def guide_preview(view, a)
          return unless a[:finish] && a[:start] != a[:finish]

          dir = a[:finish] - a[:start]
          far = view.camera.eye.distance(a[:start]) * 4 + 1000
          view.line_stipple = '-'
          view.drawing_color = 'gray'
          view.draw(GL_LINES, a[:start].offset(dir, -far), a[:start].offset(dir, far))
          view.line_stipple = ''
        end

        # Сдвиг размерной линии: перпендикулярная к размеру часть (позиция − конец).
        def dim_offset(a)
          return nil unless a[:start] && a[:finish] && a[:position]

          dir = a[:finish] - a[:start]
          return nil unless dir.valid?

          v = a[:position] - a[:finish]
          along = dir.normalize
          k = v % along
          v - Geom::Vector3d.new(along.x * k, along.y * k, along.z * k)
        end

        # ---------- форма: ведение, сглаживание, зеркало, твёрдые тела ----------

        def register_shape
          add('Sweep', %w[], 'Extrude a profile face along path edges (Follow Me)',
              [{ key: :path, type: :selection, label: 'Select path edges', kinds: [Sketchup::Edge] },
               { key: :profile, type: :selection, label: 'Select the profile face', kinds: [Sketchup::Face] }]) do |a|
            face = alive(a[:profile]).first
            path = alive(a[:path]) - face.edges
            next({ ok: false, message: 'select path edges that are not the edges of the profile' }) if path.empty?

            done = operation('Follow Me') { face.followme(path) }
            next({ ok: false, message: 'Follow Me failed: the path must be connected edges' }) unless done

            "Swept along #{plural(path.size, 'edge')}"
          end

          add('Soften', %w[], 'Soften and smooth edges between faces meeting at less than Angle',
              [objects('Select edges or faces to soften'),
               { key: :angle, type: :angle, label: 'Angle between faces', default: 20.0, min: 0.0, max: 180.0 },
               { key: :smooth, type: :bool, default: true, prompt: false }]) do |a|
            edges = soft_candidates(a[:objects]).select do |e|
              f1, f2 = e.faces
              e.faces.size == 2 && f1.normal.angle_between(f2.normal).radians.round(6) <= a[:angle]
            end
            operation('Soften Edges') do
              edges.each do |e|
                e.soft = true
                e.smooth = a[:smooth]
              end
            end
            "#{plural(edges.size, 'edge')} softened"
          end

          add('Unsoften', %w[], 'Make the selected edges hard again',
              [objects('Select edges or faces')]) do |a|
            edges = soft_candidates(a[:objects]).select { |e| e.soft? || e.smooth? }
            operation('Unsoften Edges') do
              edges.each do |e|
                e.soft = false
                e.smooth = false
              end
            end
            "#{plural(edges.size, 'edge')} made hard"
          end

          add('Mirror', %w[Mi], 'Mirror the selection across a vertical plane through two points',
              [objects('Select objects to mirror'),
               { key: :start, type: :point, label: 'Start of mirror line' },
               { key: :finish, type: :point, label: 'End of mirror line', base: :start },
               { key: :copy, type: :bool, default: true, prompt: false }],
              preview: lambda { |a, view|
                (tr = mirror(a)) && Picker::Preview.box(view, bounds_of(a[:objects]), tr)
              }) do |a|
            tr = mirror(a) or next({ ok: false, message: 'the mirror line must not be vertical or zero' })

            items = alive(a[:objects])
            operation('Mirror') { place(items, [tr], a[:copy]) }
            "#{plural(items.size, 'object')} #{a[:copy] ? 'mirrored as copies' : 'mirrored'}"
          end

          solids = [Sketchup::Group, Sketchup::ComponentInstance]
          add('Union', %w[], 'Join solid groups into one (SketchUp Pro)',
              [{ key: :objects, type: :selection, label: 'Select solids to join', kinds: solids }]) do |a|
            solid_fold(alive(a[:objects]), 'Union') { |acc, other| acc.union(other) }
          end

          add('OuterShell', %w[], 'Outer shell of solid groups (SketchUp Pro)',
              [{ key: :objects, type: :selection, label: 'Select solids', kinds: solids }]) do |a|
            solid_fold(alive(a[:objects]), 'Outer Shell') { |acc, other| acc.outer_shell(other) }
          end

          add('SolidIntersect', %w[], 'Keep only the common part of solids (SketchUp Pro)',
              [{ key: :objects, type: :selection, label: 'Select solids', kinds: solids }]) do |a|
            solid_fold(alive(a[:objects]), 'Intersect') { |acc, other| acc.intersect(other) }
          end

          add('Subtract', %w[], 'Cut solids out of other solids (SketchUp Pro)',
              [{ key: :objects, type: :selection, label: 'Select solids to cut from', kinds: solids },
               { key: :cutters, type: :selection, label: 'Select the cutting solids', kinds: solids, preselect: false },
               { key: :keep, type: :bool, default: false, prompt: false }]) do |a|
            targets = alive(a[:objects])
            cutters = alive(a[:cutters]) - targets
            next({ ok: false, message: 'the cutting solids must be other objects' }) if cutters.empty?
            next({ ok: false, message: 'solid tools need SketchUp Pro' }) unless Sketchup.is_pro?
            next({ ok: false, message: 'only solids can be cut: close all holes first' }) unless (targets + cutters).all?(&:manifold?)

            made = solid_operation('Subtract') do
              ents = model.active_entities
              targets.map do |t|
                cutters.reduce(t) do |acc, c|
                  # c.subtract(acc) даёт acc − c и съедает оба: режем копией.
                  clone_instance(ents, c).subtract(acc) or raise SolidFailed, 'Subtract failed'
                end
              end.tap { ents.erase_entities(cutters) unless a[:keep] }
            end
            next made if made.is_a?(Hash)

            { message: "#{plural(made.size, 'solid')} cut", created: made }
          end
        end

        # Твёрдое тело не получилось — откатить всю операцию, а не оставить
        # половину результата.
        def solid_operation(name, &block)
          operation(name, &block)
        rescue SolidFailed => e
          { ok: false, message: "#{e.message}: the solids may touch only at an edge or not overlap" }
        end

        def soft_candidates(items)
          items = alive(items)
          (items.grep(Sketchup::Edge) + items.grep(Sketchup::Face).flat_map(&:edges)).uniq
        end

        # Отражение относительно вертикальной плоскости через линию start–finish.
        def mirror(a)
          return nil unless a[:start] && a[:finish]

          dir = a[:finish] - a[:start]
          return nil unless dir.valid?

          n = dir * Z_AXIS
          return nil unless n.valid?

          n.normalize!
          d = 2 * (a[:start].to_a.zip(n.to_a).sum { |p, c| p * c })
          m = [[1 - 2 * n.x * n.x, -2 * n.x * n.y, -2 * n.x * n.z],
               [-2 * n.y * n.x, 1 - 2 * n.y * n.y, -2 * n.y * n.z],
               [-2 * n.z * n.x, -2 * n.z * n.y, 1 - 2 * n.z * n.z]]
          Geom::Transformation.new([m[0][0], m[1][0], m[2][0], 0,
                                    m[0][1], m[1][1], m[2][1], 0,
                                    m[0][2], m[1][2], m[2][2], 0,
                                    d * n.x, d * n.y, d * n.z, 1])
        end

        # Union и др.: попарно слева направо, результат — один объект.
        def solid_fold(items, name)
          return { ok: false, message: 'select at least two solids' } if items.size < 2
          return { ok: false, message: 'solid tools need SketchUp Pro' } unless Sketchup.is_pro?
          return { ok: false, message: 'only solids can be joined: close all holes first' } unless items.all?(&:manifold?)

          result = solid_operation(name) do
            items.drop(1).reduce(items.first) { |acc, other| yield(acc, other) or raise SolidFailed, "#{name} failed" }
          end
          return result if result.is_a?(Hash)

          selection.clear
          selection.add(result)
          { message: "#{name}: #{plural(items.size, 'solid')} → 1", created: [result] }
        end
      end
    end
  end
end
