# frozen_string_literal: true

module BACommunity
  module Terminal
    # Команда терминала. run получает (args) или (args, ctx); args — Hash с
    # ключами параметров (Symbol). preview(args, view) рисует результат, пока
    # пользователь выбирает точку в модели.
    # repeat(args) → Hash готовых значений для следующего круга (Line).
    # keywords — русские слова для поиска («переместить сдвиг»), examples —
    # строки для справки (Help PathCopy).
    # destructive — удаляет или необратимо меняет: опечатка такую команду не
    # запускает, только подсказывает.
    Command = Struct.new(:id, :plugin, :description, :aliases, :params, :run, :preview, :repeat, :builtin,
                         :keywords, :examples, :destructive, keyword_init: true) do
      def names
        [id, *aliases]
      end

      def param(key)
        params.find { |p| p.key == key.to_sym }
      end

      def to_h
        { id: id, plugin: plugin, description: description.to_s, aliases: aliases, builtin: builtin,
          keywords: keywords, destructive: destructive ? true : false, params: params.map(&:to_h) }
      end
    end

    # Каталог команд. Имя (id) уникально без учёта регистра и не может
    # совпадать с чужим синонимом; кто зарегистрировался первым, тот и владеет
    # именем. Встроенные команды SketchUp регистрируются раньше всех.
    module Registry
      @commands ||= {} # id.downcase => Command
      @names ||= {} # id/alias.downcase => Command
      @revision ||= 0

      class << self
        attr_reader :revision

        # → [Command, nil] или [nil, причина отказа]
        def add(spec, run, builtin: false)
          spec = spec.transform_keys(&:to_sym)
          id = spec[:id].to_s
          return [nil, "command id must be English CamelCase (e.g. PathCopy): #{id.inspect}"] unless id.match?(ID_PATTERN)
          return [nil, "#{id}: no block given"] unless run.respond_to?(:call)
          %i[preview repeat].each do |k|
            return [nil, "#{id}: #{k} must respond to call"] if spec[k] && !spec[k].respond_to?(:call)
          end

          aliases = Array(spec[:aliases]).map(&:to_s)
          bad = aliases.reject { |a| a.match?(NAME_PATTERN) }
          return [nil, "#{id}: aliases must be Latin letters and digits: #{bad.inspect}"] if bad.any?

          taken = ([id] + aliases).select { |n| @names.key?(n.downcase) }
          return [nil, "#{id}: name already taken by #{taken.map { |n| owner(n) }.join(', ')}"] if taken.include?(id)

          # Занятый синоним просто не достаётся: команда всё равно доступна по id.
          aliases -= taken
          params = Array(spec[:params]).map { |p| p.is_a?(Param) ? p : Param.new(p) }
          dup = params.map { |p| p.name.downcase }.tally.select { |_, n| n > 1 }.keys
          return [nil, "#{id}: duplicate parameter names #{dup.inspect}"] if dup.any?

          keywords = Array(spec[:keywords]).flat_map { |k| k.to_s.downcase.split(/[\s,]+/) }.reject(&:empty?).uniq
          cmd = Command.new(id: id, plugin: (spec[:plugin] || 'Unknown').to_s, description: spec[:description].to_s,
                            aliases: aliases, params: params, run: run, preview: spec[:preview], repeat: spec[:repeat],
                            builtin: builtin, keywords: keywords, examples: Array(spec[:examples]).map(&:to_s),
                            destructive: spec[:destructive] ? true : false)
          @commands[id.downcase] = cmd
          cmd.names.each { |n| @names[n.downcase] = cmd }
          @revision += 1
          [cmd, taken.empty? ? nil : "#{id}: aliases #{taken.join(', ')} already taken, skipped"]
        rescue ArgumentError, KeyError => e
          [nil, "#{spec[:id]}: #{e.message}"]
        end

        # Отказы и предупреждения регистрации — для PluginCheck.
        def problem(plugin, text)
          (@problems ||= []) << { plugin: plugin.to_s, text: text.to_s }
        end

        def problems
          @problems || []
        end

        def remove(id)
          cmd = @commands.delete(id.to_s.downcase) or return false
          cmd.names.each { |n| @names.delete(n.downcase) }
          @revision += 1
          true
        end

        def all
          @commands.values
        end

        def find(name)
          @names[name.to_s.downcase]
        end

        # Имя из строки → [Command, []] или [nil, похожие id]. Кроме точного имени
        # принимает однозначное начало имени и однозначные заглавные буквы
        # (ze → ZoomExtents), как автодополнение в окне.
        def resolve(name)
          down = name.to_s.downcase
          exact = @names[down]
          return [exact, []] if exact

          by_prefix = @names.select { |n, _| n.start_with?(down) }.values.uniq
          return [by_prefix.first, []] if by_prefix.size == 1

          by_initials = all.select { |c| initials(c.id) == down }
          return [by_initials.first, []] if by_initials.size == 1 && by_prefix.empty?

          similar = (by_prefix + by_initials + all.select { |c| c.id.downcase.include?(down) }).uniq
          [nil, similar.first(5).map(&:id)]
        end

        def catalog
          all.sort_by(&:id).map(&:to_h)
        end

        private

        def owner(name)
          cmd = @names[name.downcase]
          "#{cmd.id} (#{cmd.plugin})"
        end

        def initials(id)
          id.scan(/[A-Z0-9]/).join.downcase
        end
      end
    end
  end
end
