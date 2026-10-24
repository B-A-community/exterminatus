# frozen_string_literal: true

module BACommunity
  module Terminal
    # Ввод кликом в модели, как в Rhino: пока команда спрашивает точку (или
    # параметр с pick:), работает PickTool, а пока просит выделить объекты —
    # SelectTool. Ответить можно и кликом, и с клавиатуры: в терминале или в
    # поле Measurements (onUserText). Enter и Esc в окне модели работают так же,
    # как в терминале.
    module Picker
      class << self
        # Привести инструмент к текущему вопросу Session (param nil — вопроса нет).
        def follow(param, run)
          return stop unless param&.pickable?

          klass = param.selection? ? SelectTool : PickTool
          if @tool.is_a?(klass) && active?(@tool)
            @tool.retarget(param, run)
          else
            @tool = klass.new(param, run)
            Sketchup.active_model.select_tool(@tool)
          end
        end

        def stop
          tool = @tool
          @tool = nil
          Sketchup.active_model.select_tool(nil) if tool && active?(tool)
        end

        # Точка под курсором — для «500» в сторону курсора.
        def cursor
          @tool.respond_to?(:cursor) ? @tool.cursor : nil
        end

        # Инструмент сменил пользователь (пробел, кнопка панели) — команда
        # отменяется, как в Rhino.
        def lost(tool)
          return unless @tool.equal?(tool)

          @tool = nil
          Session.cancel
        end

        private

        def active?(tool)
          tools = Sketchup.active_model.tools
          tools.respond_to?(:active_tool) ? tools.active_tool.equal?(tool) : true
        end
      end

      # Общее для обоих инструментов: клавиатура окна модели идёт в Session.
      module Keys
        def onUserText(text, _view)
          viewport { Session.submit(text) }
        end

        def onReturn(_view)
          viewport { Session.submit('') }
        end

        # 0 — Esc, 2 — Undo: после отмены точки и выделение команды уже не
        # соответствуют модели, поэтому команда отменяется.
        def onCancel(reason, _view)
          viewport { Session.cancel(undo: reason == 2) } if [0, 2].include?(reason)
        end

        def enableVCB?
          true
        end

        def deactivate(view)
          view.invalidate
          Picker.lost(self)
        end

        def resume(view)
          show_status
          view.invalidate
        end

        private

        def viewport
          yield
        rescue StandardError => e
          warn "Exterminatus: #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
          Session.emit(:error, e.message)
        ensure
          Window.settle
        end

        def show_status
          Sketchup.vcb_label = @param.name
          Sketchup.status_text = Session.prompt_line.to_s
        end
      end

      # Точка или значение по точке (pick:). Резиновая нить от base и
      # предпросмотр команды (preview:) рисуются, пока двигается курсор.
      class PickTool
        include Keys

        attr_reader :cursor

        def initialize(param, run)
          @ip = Sketchup::InputPoint.new
          retarget(param, run)
        end

        def retarget(param, run)
          @param = param
          @run = run
          base = Session.resolved(@run)[@param.base] if @param.base
          @base_ip = base ? Sketchup::InputPoint.new(base) : nil
          show_status
          Sketchup.active_model.active_view.invalidate
        end

        def activate
          show_status
        end

        def onMouseMove(_flags, x, y, view)
          @base_ip ? @ip.pick(view, x, y, @base_ip) : @ip.pick(view, x, y)
          @cursor = @ip.valid? ? @ip.position : nil
          view.tooltip = @ip.tooltip
          show_status
          view.invalidate
        end

        def onLButtonDown(flags, x, y, view)
          onMouseMove(flags, x, y, view)
          value = live_value
          return if value.nil?

          viewport { Session.picked(@param, value, face_normal) }
        end

        def draw(view)
          Preview.reset
          base = @base_ip&.position
          if base && @cursor
            view.line_stipple = '-'
            view.line_width = 1
            view.set_color_from_line(base, @cursor)
            view.draw(GL_LINES, base, @cursor)
            Preview.note(base, @cursor)
          end
          Session.preview(@run, @param, live_value, view) if @cursor
          @ip.draw(view) if @ip.valid? && @ip.display?
        end

        def getExtents
          bb = Geom::BoundingBox.new
          bb.add(Sketchup.active_model.bounds)
          Preview.points.each { |p| bb.add(p) }
          bb.add(@cursor) if @cursor
          bb
        end

        private

        def face_normal
          face = @ip.face or return nil
          face.normal.transform(@ip.transformation).normalize
        end

        def live_value
          return nil unless @cursor

          @param.pick(@cursor, Session.resolved(@run))
        rescue StandardError
          nil
        end
      end

      # Выделение для параметра :selection. Клик добавляет объект, Shift —
      # переключает, рамка слева направо — целиком внутри, справа налево —
      # пересечение. Enter или правая кнопка — готово.
      class SelectTool
        include Keys

        DRAG = 4

        def initialize(param, run)
          retarget(param, run)
        end

        def retarget(param, run)
          @param = param
          @run = run
          show_status
        end

        def activate
          show_status
        end

        def onLButtonDown(_flags, x, y, _view)
          @down = [x, y]
          @drag = nil
        end

        def onMouseMove(_flags, x, y, view)
          show_status
          return unless @down

          @drag = [x, y] if @drag || (x - @down[0]).abs > DRAG || (y - @down[1]).abs > DRAG
          view.invalidate if @drag
        end

        def onLButtonUp(flags, x, y, view)
          return unless @down

          ph = view.pick_helper
          picked =
            if @drag
              crossing = x < @down[0]
              ph.window_pick(Geom::Point3d.new(*@down, 0), Geom::Point3d.new(x, y, 0),
                             crossing ? Sketchup::PickHelper::PICK_CROSSING : Sketchup::PickHelper::PICK_INSIDE)
              ph.all_picked
            else
              ph.do_pick(x, y)
              [ph.best_picked].compact
            end
          @down = @drag = nil
          picked = picked.select { |e| @param.kinds.any? { |k| e.is_a?(k) } } unless @param.kinds.empty?
          sel = Sketchup.active_model.selection
          if (flags & CONSTRAIN_MODIFIER_MASK) != 0
            sel.toggle(picked)
          else
            sel.add(picked)
          end
          view.invalidate
        end

        def onRButtonUp(_flags, _x, _y, _view)
          viewport { Session.submit('') }
        end

        # Без контекстного меню: правая кнопка — Enter, как в Rhino.
        def getMenu(_menu, _flags, _x, _y, _view)
          true
        end

        def draw(view)
          return unless @down && @drag

          x0, y0 = @down
          x1, y1 = @drag
          pts = [[x0, y0], [x1, y0], [x1, y1], [x0, y1]].map { |x, y| Geom::Point3d.new(x, y, 0) }
          view.line_width = 1
          view.line_stipple = x1 < x0 ? '-' : ''
          view.drawing_color = Sketchup::Color.new(0, 0, 0)
          view.draw2d(GL_LINE_LOOP, pts)
        end
      end

      # Помощь для preview и учёт точек для getExtents (иначе SketchUp обрежет
      # то, что вне модели). Будущая геометрия (shape) — сплошной тонкой линией
      # цвета рёбер, как у родных инструментов; призрак переносимого (box) —
      # пунктиром.
      module Preview
        COLOR = Sketchup::Color.new(64, 64, 64)

        @points = []

        class << self
          attr_reader :points

          def reset
            @points = []
          end

          def note(*pts)
            @points.concat(pts)
          end

          def lines(view, pts, solid: false)
            return if pts.size < 2

            style(view, solid)
            view.draw(GL_LINES, pts)
            note(*pts)
          end

          def polyline(view, pts, closed: false, solid: false)
            return if pts.size < 2

            style(view, solid)
            view.draw(closed ? GL_LINE_LOOP : GL_LINE_STRIP, pts)
            note(*pts)
          end

          def shape(view, pts, closed: false)
            polyline(view, pts, closed: closed, solid: true)
          end

          # Габарит bounds после преобразования tr.
          def box(view, bounds, tr = IDENTITY)
            return unless bounds.valid?

            c = (0..7).map { |i| bounds.corner(i).transform(tr) }
            edges = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
            lines(view, edges.flat_map { |a, b| [c[a], c[b]] })
          end

          private

          def style(view, solid)
            view.line_width = 1
            view.line_stipple = solid ? '' : '-'
            view.drawing_color = solid ? edge_color : COLOR
          end

          def edge_color
            Sketchup.active_model.rendering_options['ForegroundColor'] || COLOR
          rescue StandardError
            COLOR
          end
        end
      end
    end
  end
end
