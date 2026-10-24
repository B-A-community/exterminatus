# frozen_string_literal: true

module BACommunity
  module Terminal
    # Параметр команды: как его спросить, разобрать введённый текст и показать
    # текущее значение. Типы:
    #   :length  — длина в единицах модели («500», «1.2m», «3'6"»), значение Length
    #   :number  — дробное число, :integer — целое
    #   :angle   — угол в градусах (Float)
    #   :string  — строка как есть
    #   :option  — одно из values; клик по опции перебирает значения по кругу
    #   :bool    — Yes/No; клик переключает
    # prompt: true — спрашивается по очереди; false — только опцией в строке
    # приглашения (как Mode=Fit у Rhino). optional: true — только из строки
    # команды, никогда не спрашивается и не запоминается: без него команда
    # делает другое (PushPull без числа включает инструмент).
    class Param
      TYPES = %i[length number integer angle string option bool].freeze
      TRUE_WORDS  = %w[yes y true on 1].freeze
      FALSE_WORDS = %w[no n false off 0].freeze

      attr_reader :key, :name, :type, :default, :values, :description, :min, :max

      def initialize(spec)
        spec = spec.transform_keys(&:to_sym)
        @key  = spec.fetch(:key).to_sym
        @name = (spec[:name] || @key.to_s.split('_').map(&:capitalize).join).to_s
        @type = (spec[:type] || :string).to_sym
        @values = Array(spec[:values]).map(&:to_s)
        @default = spec[:default]
        @prompt = spec.key?(:prompt) ? spec[:prompt] : true
        @optional = spec[:optional] ? true : false
        @min = spec[:min]
        @max = spec[:max]
        @description = spec[:description]

        raise ArgumentError, "parameter name must be Latin letters and digits: #{@name.inspect}" unless @name.match?(NAME_PATTERN)
        raise ArgumentError, "#{@name}: unknown type #{@type.inspect}" unless TYPES.include?(@type)
        raise ArgumentError, "#{@name}: type :option needs values" if @type == :option && @values.empty?
      end

      def prompt?
        @prompt && !@optional ? true : false
      end

      def optional?
        @optional
      end

      # Опции и флаги меняются кликом без ввода значения.
      def cyclic?
        @type == :option || @type == :bool
      end

      # Текст → [значение, nil] или [nil, текст ошибки].
      def parse(text)
        s = text.to_s.strip
        return [nil, "#{name}: value expected"] if s.empty? && @type != :string

        value = case @type
                when :length  then parse_length(s)
                when :number  then Float(s.tr(',', '.'))
                when :integer then Integer(s, 10)
                when :angle   then Float(s.delete('°').tr(',', '.'))
                when :string  then s
                when :option  then parse_option(s)
                when :bool    then parse_bool(s)
                end
        return [nil, "#{name}: #{expected}"] if value.nil?

        check_range(value)
      rescue ArgumentError, TypeError
        [nil, "#{name}: #{expected}"]
      end

      def format(value)
        return '' if value.nil?

        case @type
        when :length  then value.to_l.to_s
        when :number  then trim(value.to_f)
        when :angle   then "#{trim(value.to_f)}°"
        when :bool    then value ? 'Yes' : 'No'
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

        @default
      end

      def to_h
        { key: @key, name: @name, type: @type, values: @values, prompt: prompt?, optional: optional?,
          description: @description }
      end

      private

      def expected
        case @type
        when :length  then 'length expected (e.g. 500, 1.2m, 3\'6")'
        when :number  then 'number expected'
        when :integer then 'integer expected'
        when :angle   then 'angle in degrees expected'
        when :option  then "one of #{@values.join(', ')}"
        when :bool    then 'Yes or No'
        else 'value expected'
        end
      end

      # Десятичный разделитель SketchUp берёт из системы: в русской Windows это
      # запятая, поэтому пробуем обе записи.
      def parse_length(s)
        [s, s.tr('.', ','), s.tr(',', '.')].uniq.each do |variant|
          return variant.to_l
        rescue ArgumentError
          next
        end
        nil
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
    end
  end
end
