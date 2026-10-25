# frozen_string_literal: true

# Мост — копия src/exterminatus/terminal_bridge.rb без изменений.
Sketchup.require(File.join(__dir__, 'terminal_bridge'))

module BACommunity
  module HelloPlugin
    T = BACommunity::Terminal
    MENU = 'Extensions/Hello Plugin'

    # Сама работа плагина — обычный Ruby, про терминал не знает.
    def self.build_stairs(start, finish, steps, width)
      model = Sketchup.active_model
      run = finish - start
      return { ok: false, message: 'the stairs need some length' } unless run.valid?

      flat = Geom::Vector3d.new(run.x, run.y, 0)
      return { ok: false, message: 'pick the end at a different place in plan' } unless flat.valid?

      side = (flat * Z_AXIS).normalize
      side.length = width
      rise = run.z / steps
      tread = Geom::Vector3d.new(flat.x / steps, flat.y / steps, 0)
      model.start_operation('Stairs', true)
      group = model.active_entities.add_group
      steps.times do |i|
        p = start.offset(tread, tread.length * i).offset(Z_AXIS, rise * i)
        face = group.entities.add_face(p, p.offset(tread), p.offset(tread).offset(side), p.offset(side))
        next unless face

        face.reverse! if face.normal.z.negative?
        face.pushpull(rise.abs > 0 ? rise.abs : 1.mm)
      end
      model.commit_operation
      { message: "#{steps} steps, rise #{rise.to_l}", created: [group] }
    end

    unless defined?(@ui_built)
      @ui_built = true

      # Одно описание: пункт меню, кнопка, команда терминала, справка.
      T.command(
        id: 'HelloStairs', plugin: 'Hello Plugin',
        description: 'Simple stairs between two points',
        keywords: 'лестница ступени',
        examples: ['HelloStairs 0,0,0 3000,0,1500', 'HelloStairs steps=12 width=1200'],
        menu: MENU, menu_text: 'Stairs', toolbar: 'Hello Plugin',
        icon: File.join(__dir__, 'icons', 'stairs.svg'),
        params: [
          { key: :start, type: :point, label: 'Bottom of stairs' },
          { key: :finish, type: :point, label: 'Top of stairs', base: :start },
          { key: :steps, type: :integer, default: 10, min: 2, max: 100, prompt: false },
          { key: :width, type: :length, default: 1000.mm, min: 100.mm, prompt: false }
        ],
        preview: lambda { |a, view|
          next unless a[:start] && a[:finish]

          view.line_stipple = '-'
          view.draw(GL_LINES, a[:start], a[:finish])
          view.line_stipple = ''
        }
      ) do |args|
        HelloPlugin.build_stairs(args[:start], args[:finish], args[:steps], args[:width])
      end

      # Без точек: без терминала спросит Name окном, выделение — из модели.
      T.command(
        id: 'HelloRename', plugin: 'Hello Plugin',
        description: 'Give the selected groups a numbered name',
        keywords: 'нумерация имена',
        menu: MENU, menu_text: 'Number Names', separator: true,
        enabled: -> { !Sketchup.active_model.selection.empty? },
        params: [
          { key: :objects, type: :selection, label: 'Select groups to name', kinds: [Sketchup::Group] },
          { key: :prefix, type: :string, default: 'Room', label: 'Name prefix' }
        ]
      ) do |args|
        model = Sketchup.active_model
        model.start_operation('Number Names', true)
        args[:objects].each_with_index { |g, i| g.name = "#{args[:prefix]} #{i + 1}" }
        model.commit_operation
        "#{args[:objects].size} named #{args[:prefix]} 1…#{args[:objects].size}"
      end
    end
  end
end
