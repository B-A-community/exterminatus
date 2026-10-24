# frozen_string_literal: true

module BACommunity
  module Terminal
    # Параметр команды: как его спросить, разобрать введённый текст и показать
    # текущее значение. Типы:
    #   :length    — длина в единицах модели («500», «1.2m», «3'6"», «1200/4»), Length
    #   :number    — дробное число, :integer — целое
    #   :angle     — угол в градусах (Float)
    #   :string    — строка как есть
    #   :option    — одно из values; клик по опции перебирает значения по кругу
    #   :bool      — Yes/No; клик переключает
    #   :point     — точка: клик в модели или «x,y,z», «@dx,dy,dz», «r<угол»,
    #                «@r<угол», а с base — просто число (расстояние в сторону курсора)
    #   :vector    — вектор «dx,dy,dz» или «r<угол»
    #   :scale     — множитель «2» или по осям «1,1,2» → [sx, sy, sz]
    #   :selection — объекты, выделенные в модели; берётся текущее выделение,
    #                а если оно пустое, терминал просит выделить и нажать Enter
    # prompt: true — спрашивается по очереди; false — только опцией в строке
    # приглашения (как Mode=Fit у Rhino). optional: true — только из строки
    # команды, никогда не спрашивается и не запоминается: без него команда
    # делает другое (Move 0,0,500 сдвигает сразу, Move без вектора спрашивает точки).
    class Param
      TYPES = %i[length number integer angle string option bool point vector scale selection].freeze
      TRUE_WORDS  = %w[yes y true on 1].freeze
      FALSE_WORDS = %w[no n false off 0].freeze
      AUTO = 'Auto'

      attr_reader :key, :name, :label, :type, :default, :values, :description, :min, :max, :base, :kinds

      def initialize(spec)
        spec = spec.transform_keys(&:to_sym)
        @key  = spec.fetch(:key).to_sym
        @name = (spec[:name] || @key.to_s.split('_').map(&:capitalize).join).to_s
        @label = (spec[:label] || @name).to_s
        @type = (spec[:type] || :string).to_sym
        @values = Array(spec[:values]).map(&:to_s)
        @default = spec[:default]
        @prompt = spec.key?(:prompt) ? spec[:prompt] : true
        @optional = spec[:optional] ? true : false
        @min = spec[:min]
        @max = spec[:max]
        @description = spec[:description]
        @base = spec[:base]&.to_sym
        @auto = spec[:auto]
        @pick = spec[:pick]
        @ask_if = spec[:ask_if]
        @kinds = Array(spec[:kinds])
        @custom = spec[:parse]

        raise ArgumentError, "parameter name must be Latin letters and digits: #{@name.inspect}" unless @name.match?(NAME_PATTERN)
        raise ArgumentError, "#{@name}: unknown type #{@type.inspect}" unless TYPES.include?(@type)
        raise ArgumentError, "#{@name}: type :option needs values" if @type == :option && @values.empty?
        raise ArgumentError, "#{@name}: pick must respond to call" if @pick && !@pick.respond_to?(:call)
        raise ArgumentError, "#{@name}: parse must respond to call" if @custom && !@custom.respond_to?(:call)
      end

      def prompt?
        @prompt && !@optional ? true : false
      end

      def optional?
        @optional
      end

      def selection?
        @type == :selection
      end

      # Значение можно оставить пустым: команда подставит своё (Center=Auto).
      def auto?
        @auto ? true : false
      end

      # Значение по args, когда оно Auto (auto: ->(args) { ... }), иначе nil.
      def auto_value(args)
        @auto.respond_to?(:call) ? @auto.call(args) : nil
      end

      # Ответ можно дать кликом в модели.
      def pickable?
        @type == :point || selection? || !@pick.nil?
      end

      # Значение из точки под курсором (для :point — сама точка).
      def pick(point, args)
        return point if @type == :point

        @pick&.call(point, args)
      end

      # Нужен ли параметр при этих значениях остальных (ask_if: ->(args) { ... }).
      def wanted?(args)
        @ask_if.nil? || @ask_if.call(args) ? true : false
      end

      # Последнее значение запоминается на сеанс. Точки и выделение — нет:
      # они относятся к месту в модели, а не к привычкам пользователя.
      def remember?
        !@optional && !selection? && @type != :point
      end

      # Опции и флаги меняются кликом без ввода значения.
      def cyclic?
        @type == :option || @type == :bool
      end

      # Выделение, подходящее параметру (kinds: [Sketchup::Face]); nil — пусто.
      def selected
        items = Sketchup.active_model.selection.to_a
        items = items.select { |e| @kinds.any? { |k| e.is_a?(k) } } unless @kinds.empty?
        items.empty? ? nil : items
      end

      # Текст → [значение, nil] или [nil, текст ошибки]. ctx: base — точка, от
      # которой считаются «@…» и голое число; cursor — точка под курсором;
      # args — уже известные значения команды (для parse:).
      def parse(text, ctx = {})
        s = text.to_s.strip
        return [nil, nil] if auto? && s.casecmp?(AUTO)

        # Свой разбор (parse: ->(text, args) { value или nil }); nil — обычный.
        if @custom && !s.empty?
          value = @custom.call(s, ctx[:args] || {})
          return [value, nil] unless value.nil?
        end
        return [nil, "#{name}: select objects in the model, then press Enter"] if selection?
        return [nil, "#{name}: value expected"] if s.empty? && @type != :string

        value = case @type
                when :length  then parse_length(s)
                when :number  then Expr.number(s)
                when :integer then integer(Expr.number(s))
                when :angle   then Expr.number(s.delete('°'))
                when :string  then s
                when :option  then parse_option(s)
                when :bool    then parse_bool(s)
                when :point   then return parse_point(s, ctx)
                when :vector  then parse_vector(s)
                when :scale   then parse_scale(s)
                end
        return [nil, "#{name}: #{expected}"] if value.nil?

        check_range(value)
      rescue ArgumentError, TypeError, ZeroDivisionError, FloatDomainError
        [nil, "#{name}: #{expected}"]
      end

      def format(value)
        return (auto? ? AUTO : '') if value.nil?

        case @type
        when :length  then value.to_l.to_s
        when :number  then trim(value.to_f)
        when :angle   then "#{trim(value.to_f)}°"
        when :bool    then value ? 'Yes' : 'No'
        when :point, :vector then value.to_a.map { |c| short_length(c) }.join(', ')
        when :scale   then value.uniq.size == 1 ? trim(value.first) : value.map { |f| trim(f) }.join(', ')
        when :selection then "#{value.size} selected"
        else value.to_s
        end
      end

      # Следующее значение для клика по опции.
      def next_value(value)
        return !value if @type == :bool

        i = @values.index(value.to_s) || -1
        @values[(i + 1) % @values.size]
      end

      # Значение по умолчанию, приведённое к типу (длина из Numeric — в дюймах,
      # как принято в SketchUp).
      def coerce_default
        return nil if @default.nil?
        return @default.to_l if @type == :length && @default.is_a?(Numeric)
        return [@default.to_f] * 3 if @type == :scale && @default.is_a?(Numeric)

        @default
      end

      def to_h
        { key: @key, name: @name, label: @label, type: @type, values: @values, prompt: prompt?,
          optional: optional?, description: @description }
      end

      private

      def expected
        case @type
        when :length  then 'length expected (e.g. 500, 1.2m, 3\'6", 1200/4)'
        when :number  then 'number expected'
        when :integer then 'integer expected'
        when :angle   then 'angle in degrees expected'
        when :option  then "one of #{@values.join(', ')}"
        when :bool    then 'Yes or No'
        when :point   then 'point expected: click, or x,y,z  @dx,dy,dz  r<angle'
        when :vector  then 'vector expected: dx,dy,dz or r<angle'
        when :scale   then 'factor expected: 2 or 1,1,2'
        else 'value expected'
        end
      end

      def parse_length(s)
        inches = Expr.length(s)
        inches&.to_l
      end

      def integer(f)
        return nil if f.nil? || f != f.round

        f.round
      end

      # Точки — в координатах модели. Внутри открытой группы SketchUp 2024 и
      # сам отдаёт и принимает мировые координаты, пересчёт не нужен.
      def parse_point(s, ctx)
        base = ctx[:base]
        rel = s.start_with?('@')
        body = rel ? s[1..] : s
        if !rel && !body.include?(',') && !body.include?('<')
          # Голое число — расстояние от base в сторону курсора, как в поле
          # Measurements у родных инструментов.
          return [nil, "#{name}: #{expected}"] unless base
          return [nil, "#{name}: move the cursor to show the direction, then type the distance"] unless ctx[:cursor]

          dir = ctx[:cursor] - base
          return [nil, "#{name}: move the cursor away from the base point"] unless dir.valid?

          d = Expr.length(body) or return [nil, "#{name}: #{expected}"]
          return [base.offset(dir, d), nil]
        end

        vec = vector_from(body) or return [nil, "#{name}: #{expected}"]
        if rel
          return [nil, "#{name}: no previous point for @"] unless base

          [base.offset(vec), nil]
        else
          [ORIGIN.offset(vec), nil]
        end
      rescue ArgumentError, TypeError, ZeroDivisionError, FloatDomainError
        [nil, "#{name}: #{expected}"]
      end

      def parse_vector(s)
        vector_from(s.delete_prefix('@'))
      end

      # «x,y» / «x,y,z» (дробь — через точку) или «r<угол» в плоскости XY.
      def vector_from(s)
        if (m = s.match(/\A([^<]+)<([^<]+)\z/))
          r = Expr.length(m[1]) or return nil
          a = Expr.number(m[2].delete('°')) or return nil
          return Geom::Vector3d.new(r * Math.cos(a.degrees), r * Math.sin(a.degrees), 0)
        end
        parts = s.split(',', -1)
        return nil unless parts.size.between?(2, 3)

        comps = parts.map { |p| Expr.length(p) }
        return nil if comps.any?(&:nil?)

        comps << 0.0 if comps.size == 2
        Geom::Vector3d.new(*comps)
      end

      def parse_scale(s)
        parts = s.split(',', -1)
        return nil unless [1, 3].include?(parts.size)

        f = parts.map { |p| Expr.number(p) }
        return nil if f.any? { |v| v.nil? || v.zero? }

        f.size == 1 ? f * 3 : f
      end

      def parse_option(s)
        down = s.downcase
        exact = @values.find { |v| v.downcase == down }
        return exact if exact

        hits = @values.select { |v| v.downcase.start_with?(down) }
        hits.size == 1 ? hits.first : nil
      end

      def parse_bool(s)
        down = s.downcase
        return true if TRUE_WORDS.include?(down)
        return false if FALSE_WORDS.include?(down)

        nil
      end

      def check_range(value)
        num = value.is_a?(Numeric) ? value.to_f : nil
        return [value, nil] if num.nil?
        return [nil, "#{name}: must be at least #{format(bound(@min))}"] if @min && num < bound(@min).to_f
        return [nil, "#{name}: must be at most #{format(bound(@max))}"] if @max && num > bound(@max).to_f

        [value, nil]
      end

      def bound(v)
        @type == :length && v.is_a?(Numeric) ? v.to_l : v
      end

      def trim(f)
        f == f.round ? f.round.to_s : f.round(6).to_s
      end

      # Координата без единиц: «500», а не «500 mm».
      def short_length(c)
        c.to_l.to_s.sub(/\s*[a-z]+\z/i, '').sub(/\A~\s*/, '')
      end
    end

    # Арифметика в значениях: «1200/4», «2*300+50», «1.2m-300». Числа без
    # единиц — в единицах модели; длины с единицами («1.2m», «3'6"») SketchUp
    # переводит сам.
    module Expr
      OPS = /[-+*\/()]/.freeze

      class << self
        # Длина в дюймах (Float) или nil.
        def length(text)
          s = text.to_s.strip
          return nil if s.empty?

          return plain_length(s) unless expression?(s)

          # Одна «/» без других операторов — сначала как дробь SketchUp:
          # «1/2"» — полдюйма, а не 1 мм / 2 дюйма.
          if s.match?(%r{\A[^-+*()]*/[^-+*()/]*\z})
            plain = plain_length(s)
            return plain if plain
          end

          unit = '1'.to_l.to_f
          value = evaluate(s) { |op| number?(op) ? op.tr(',', '.').to_f : (plain_length(op) or raise ArgumentError) / unit }
          value&.*(unit)
        end

        def number(text)
          s = text.to_s.strip
          return nil if s.empty?

          plain = Float(s.tr(',', '.'), exception: false) # и «1e-3»
          return plain if plain || !expression?(s)

          evaluate(s) { |op| number?(op) ? op.tr(',', '.').to_f : raise(ArgumentError) }
        end

        private

        # Есть оператор не в начале (знак числа — не выражение).
        def expression?(s)
          s.match?(%r{[*/()]}) || s.match?(/[^-+\s]\s*[-+]/)
        end

        def number?(s)
          s.match?(/\A\d*[.,]?\d+\z/)
        end

        # Десятичный разделитель SketchUp берёт из системы: в русской Windows это
        # запятая, поэтому пробуем обе записи.
        def plain_length(s)
          [s, s.tr('.', ','), s.tr(',', '.')].uniq.each do |variant|
            return variant.to_l.to_f
          rescue ArgumentError
            next
          end
          nil
        end

        # Разбор с приоритетами: сумма → произведение → унарный знак, скобки.
        def evaluate(s, &operand)
          tokens = s.scan(%r{\s*([-+*/()]|[^-+*/()\s]+)}).flatten
          pos = 0
          peek = -> { tokens[pos] }
          take = -> { tokens[pos].tap { pos += 1 } }
          expr = nil
          factor = lambda do
            t = take.call or raise ArgumentError
            case t
            when '-' then -factor.call
            when '+' then factor.call
            when '('
              v = expr.call
              raise ArgumentError unless take.call == ')'

              v
            else
              raise ArgumentError if t.match?(OPS)

              operand.call(t)
            end
          end
          term = lambda do
            v = factor.call
            while %w[* /].include?(peek.call)
              op = take.call
              r = factor.call
              raise ZeroDivisionError if op == '/' && r.zero?

              v = op == '*' ? v * r : v / r
            end
            v
          end
          expr = lambda do
            v = term.call
            v = take.call == '+' ? v + term.call : v - term.call while %w[+ -].include?(peek.call)
            v
          end
          v = expr.call
          raise ArgumentError unless pos == tokens.size

          v
        end
      end
    end
  end
end
