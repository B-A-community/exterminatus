# frozen_string_literal: true

require 'json'

module BACommunity
  module Terminal
    # Ответ на приглашение Terminal.prompt: введённый текст (пустая строка —
    # Enter), имя нажатой опции или отмена по Esc.
    PromptInput = Struct.new(:text, :option, :cancel) do
      def cancel?
        cancel ? true : false
      end

      def option?
        option ? true : false
      end

      def enter?
        !cancel? && !option? && text.to_s.empty?
      end
    end

    # Исполнитель: разбирает строку, спрашивает параметры, запускает команды,
    # ведёт вывод и историю. Окна только показывают его состояние.
    module Session
      Run = Struct.new(:cmd, :args, :ask, :sub, :confirm)
      External = Struct.new(:text, :default, :options, :tool_id, :block)


      # Второй аргумент блока команды.
      module Context
        def self.message(text)
          Session.emit(:result, text)
        end

        def self.error(text)
          Session.emit(:error, text)
        end
      end

      @log ||= []
      @seq ||= 0
      # Перечитывание файла (test/reload.rb) сбрасывает выполнение целиком.
      @queue = []
      @run = nil
      @external = nil
      @executing = false
      @paused = false
      @last_values ||= Hash.new { |h, k| h[k] = {} }
      @last_failed ||= false

      class << self
        attr_reader :seq

        # ---------- ввод ----------

        def submit(line)
          line = line.to_s
          if @run
            answer(line)
          elsif @external
            answer_external(line)
          else
            text = line.strip
            if text.empty?
              repeat_last
            elsif !forward_to_tool(text)
              remember(text)
              emit(:echo, text)
              @last_failed = false
              chain, err = lex(text)
              return emit(:error, err) if err

              @queue = chain
              drain
            end
          end
        end

        # Клик по опции в строке приглашения.
        def option(name)
          if @run
            param = option_params.find { |p| p.name.casecmp?(name.to_s) }
            choose_option(param) if param
          elsif @external
            key = @external.options.keys.find { |k| k.casecmp?(name.to_s) }
            call_external(PromptInput.new(nil, key, false)) if key
          end
        end

        def cancel
          if @run
            emit(:info, "#{@run.cmd.id} cancelled")
            @run = nil
            @queue.clear
            Picker.stop
          elsif @external
            ext = @external
            @external = nil
            @queue.clear
            call_block(ext.block, PromptInput.new(nil, nil, true))
            Sketchup.active_model.select_tool(nil) if ext.tool_id
            emit(:info, 'Cancelled')
          end
        end

        # ---------- API для плагинов ----------

        # Строка из плагина (Terminal.run). Не попадает в историю. Если её
        # вызвали изнутри команды, она выполнится сразу после этой команды,
        # перед остатком цепочки.
        def run_line(line)
          chain, err = lex(line.to_s)
          return emit(:error, err) if err

          if @executing
            @queue.unshift(*chain)
          else
            @queue.concat(chain)
            drain
          end
          Window.sync
        end

        def external_prompt(text, default: nil, options: nil, tool: nil, &block)
          if text.nil?
            @external = nil
            resume
          else
            opts = normalize_options(options)
            tool_id = tool ? Sketchup.active_model.tools.active_tool_id : nil
            @external = External.new(text.to_s, default, opts, tool_id, block)
          end
          Window.sync
          true
        end

        # ToolsObserver: инструмент, к которому привязано приглашение, сменился.
        def tool_changed(tool_id)
          return unless @external&.tool_id && @external.tool_id != tool_id

          @external = nil
          resume
          Window.sync
        end

        # Команду сняли с регистрации — её запомненные значения больше не нужны.
        def forget(id)
          @last_values.delete(id.to_s)
        end

        # Клик в модели ответил на текущий вопрос.
        def picked(param, value)
          return unless @run && current_param.equal?(param)

          @run.args[param.key] = value
          echo_answer(param, param.format(value))
          accept
        end

        # Значения команды с подставленными Auto (центр по выделению и т. п.).
        def resolved(run, args = run.args)
          args = args.dup
          run.cmd.params.each do |p|
            args[p.key] = p.auto_value(args) if args[p.key].nil? && p.auto?
          end
          args
        end

        # Предпросмотр команды, пока курсор отвечает на вопрос param.
        def preview(run, param, value, view)
          return unless run.cmd.preview && @run.equal?(run)

          run.cmd.preview.call(resolved(run, run.args.merge(param.key => value)), view)
        rescue StandardError => e
          warn "Exterminatus: #{run.cmd.id} preview raised #{e.class}: #{e.message}"
        end

        # Приглашение одной строкой — для строки состояния SketchUp.
        def prompt_line
          st = prompt_state or return nil
          line = +"#{st[:command]}: #{st[:text]}"
          line << " <#{st[:default]}>" if st[:default]
          if st[:options].any?
            opts = st[:options].map { |o| o[:value].to_s.empty? ? o[:name] : "#{o[:name]}=#{o[:value]}" }
            line << " ( #{opts.join('  ')} )"
          end
          line
        end

        def busy?
          !@run.nil? || !@external.nil?
        end

        # Терминалу нужен ввод с клавиатуры: параметр команды или приглашение,
        # не привязанное к инструменту (у инструмента ввод — клики в модели).
        def needs_typing?
          !@run.nil? || (!@external.nil? && @external.tool_id.nil?)
        end

        def last_failed?
          @last_failed
        end

        # ---------- вывод ----------

        def emit(kind, text)
          text.to_s.split("\n").each do |part|
            @seq += 1
            @log << { seq: @seq, kind: kind.to_s, text: part }
          end
          @log.shift(@log.size - LOG_LIMIT) if @log.size > LOG_LIMIT
          @last_failed = true if kind == :error
          Window.sync
        end

        def log_after(seq)
          @log.select { |line| line[:seq] > seq }
        end

        def tail(count)
          @log.last(count)
        end

        def clear_log
          @log.clear
          Window.reset_logs
        end

        def history
          @history ||= begin
            JSON.parse(Sketchup.read_default(PREFS_KEY, 'history', '[]').to_s)
          rescue JSON::ParserError
            []
          end
        end

        # Состояние строки приглашения для окна (nil — приглашения нет).
        def prompt_state
          if @run
            param = current_param
            {
              command: @run.cmd.id,
              text: param ? param_prompt(param) : 'Press Enter to run',
              default: param && !param.selection? ? param.format(@run.args[param.key]).then { |s| s.empty? ? nil : s } : nil,
              options: option_params.reject { |p| p == param }.map { |p| { name: p.name, value: p.format(@run.args[p.key]) } },
              values: param&.type == :option ? param.values : (param&.type == :bool ? %w[Yes No] : [])
            }
          elsif @external
            {
              command: nil,
              text: @external.text,
              default: @external.default&.to_s,
              options: @external.options.map { |k, v| { name: k, value: v } },
              values: []
            }
          end
        end

        private

        # ---------- запуск ----------

        def drain
          while @run.nil? && @external.nil? && !@paused && (tokens = @queue.shift)
            start(tokens)
          end
        end

        # Приглашение плагина снято — продолжить цепочку. Если это случилось
        # внутри блока команды, цепочку продолжит сама команда (execute).
        def resume
          return if @queue.empty? || busy? || @executing || @paused

          drain
        end

        def start(tokens)
          tokens = tokens.dup
          name = tokens.shift
          cmd, similar = Registry.resolve(name)
          unless cmd
            hint = similar.any? ? " Did you mean #{similar.join(', ')}?" : ''
            return fail_chain("Unknown command: #{name}.#{hint}")
          end

          args, err = bind(cmd, tokens)
          return fail_chain(err) if err

          defaults = cmd.params.reject { |p| args.key?(p.key) }
          defaults.each { |p| args[p.key] = p.selection? ? p.selected : last_value(cmd, p) }
          # Без аргументов спрашиваем всё, что prompt: true; с аргументами —
          # только то, без чего нельзя. Выделение — только если оно пустое.
          ask = cmd.params.select do |p|
            missing = args[p.key].nil? && !p.auto?
            next false if p.optional?
            next missing if p.selection?

            tokens.empty? ? p.prompt? || missing : defaults.include?(p) && missing
          end
          confirm = tokens.empty? && ask.none? { |p| !p.selection? } &&
                    cmd.params.any? { |p| !p.optional? && !p.selection? && p.wanted?(args) }
          @run = Run.new(cmd, args, ask, nil, confirm)
          advance
        end

        def advance
          @run.ask.shift while @run.ask.any? && !@run.ask.first.wanted?(@run.args)
          if @run.sub || @run.ask.any? || @run.confirm
            Window.sync
            Picker.follow(current_param, @run)
          else
            execute
          end
        end

        def answer(line)
          text = line.strip
          param = current_param

          if text.empty?
            return execute_confirmed if param.nil?
            return take_selection(param) if param.selection?
            return emit(:error, "#{param.name}: value required") if @run.args[param.key].nil? && !param.auto?

            echo_answer(param, param.format(@run.args[param.key]))
            return accept
          end

          opt = option_params.find { |p| p != param && p.name.casecmp?(text) }
          return choose_option(opt) if opt
          return emit(:error, 'Press Enter to run, Esc to cancel, or click an option') if param.nil?

          value, err = param.parse(text, base: point_base(param), cursor: Picker.cursor)
          return emit(:error, err) if err

          @run.args[param.key] = value
          echo_answer(param, param.format(value))
          accept
        end

        def accept
          if @run.sub
            @run.sub = nil
          else
            @run.ask.shift
          end
          advance
        end

        def execute_confirmed
          @run.confirm = false
          advance
        end

        def choose_option(param)
          if param.cyclic?
            @run.args[param.key] = param.next_value(@run.args[param.key])
          else
            @run.sub = param
          end
          Window.sync
          Picker.follow(current_param, @run)
        end

        def execute
          run = @run
          @run = nil
          Picker.stop
          run.cmd.params.each { |p| @last_values[run.cmd.id][p.key] = run.args[p.key] if p.remember? }
          res = invoke(run.cmd, resolved(run))
          report(run.cmd, res)
          # send_action SketchUp выполняет позже, в своём цикле сообщений:
          # остаток цепочки ждёт, иначе «Hide; SelectNone» снимет выделение
          # раньше, чем скроет.
          if res == :deferred && @queue.any?
            @paused = true
            UI.start_timer(0, false) do
              @paused = false
              drain
              Window.sync
            end
          else
            drain
          end
          Window.sync
        end

        def invoke(cmd, args)
          @executing = true
          block = cmd.run
          arity = block.arity
          if block.lambda? && arity >= 0
            block.call(*[args, Context].first(arity))
          else
            block.call(args, Context)
          end
        rescue StandardError, ScriptError => e
          warn "Exterminatus: #{cmd.id} raised #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
          { ok: false, message: e.message }
        ensure
          @executing = false
          @paused = false
        end

        # Результат команды: строка — сообщение; Hash {ok:, message:} — как в
        # Registry.run у ArchiTools; false — отказ без пояснений.
        def report(cmd, res)
          case res
          when String
            emit(:result, res) unless res.empty?
          when Hash
            ok = res.key?(:ok) ? res[:ok] : res.fetch('ok', true)
            msg = res[:message] || res['message']
            if ok == false
              fail_chain("#{cmd.id}: #{msg || 'failed'}")
            elsif msg && !msg.to_s.empty?
              emit(:result, msg)
            end
          when false
            fail_chain("#{cmd.id} failed")
          end
        end

        def fail_chain(message)
          @queue.clear
          emit(:error, message)
        end

        def repeat_last
          last = history.last
          return unless last

          submit(last)
        end

        # Число в строке при активном Ruby-инструменте уходит ему как ввод в
        # поле Measurements (onUserText) — так работают все инструменты плагинов.
        def forward_to_tool(text)
          return false unless text.match?(/\A[-+]?[\d.,\[<(]/)

          model = Sketchup.active_model
          tool = model.tools.respond_to?(:active_tool) ? model.tools.active_tool : nil
          return false unless tool.respond_to?(:onUserText)

          emit(:echo, text)
          tool.onUserText(text, model.active_view)
          true
        rescue StandardError => e
          emit(:error, "Tool input failed: #{e.message}")
          true
        end

        # ---------- внешнее приглашение ----------

        def answer_external(line)
          text = line.strip
          key = @external.options.keys.find { |k| k.casecmp?(text) } unless text.empty?
          emit(:echo, text.empty? ? "#{@external.text}: <Enter>" : "#{@external.text}: #{text}")
          call_external(PromptInput.new(key ? nil : text, key, false))
        end

        def call_external(input)
          call_block(@external.block, input)
          resume
          Window.sync
        end

        def call_block(block, input)
          block&.call(input)
        rescue StandardError, ScriptError => e
          warn "Exterminatus: prompt handler raised #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
          emit(:error, e.message)
        end

        def normalize_options(options)
          case options
          when nil then {}
          when Hash then options.each_with_object({}) { |(k, v), h| h[k.to_s] = v.nil? ? nil : v.to_s }
          else Array(options).each_with_object({}) { |k, h| h[k.to_s] = nil }
          end
        end

        # ---------- разбор строки ----------

        def current_param
          @run.sub || @run.ask.first
        end

        def option_params
          @run.cmd.params.reject { |p| p.prompt? || p.optional? || !p.wanted?(@run.args) }
        end

        def last_value(cmd, param)
          values = @last_values[cmd.id]
          values.key?(param.key) && param.remember? ? values[param.key] : param.coerce_default
        end

        def param_prompt(param)
          param.selection? ? "#{param.label}. Press Enter when done" : param.label
        end

        # Пустой Enter на «Select objects»: взять выделение из модели.
        def take_selection(param)
          items = param.selected
          return emit(:error, 'Nothing selected') unless items

          @run.args[param.key] = items
          echo_answer(param, param.format(items))
          accept
        end

        # Точка, от которой считаются «@…» и число в сторону курсора.
        def point_base(param)
          param.base ? resolved(@run)[param.base] : nil
        end

        def echo_answer(param, text)
          emit(:echo, "#{param.label}: #{text}")
        end

        # Позиционные значения идут по порядку параметров, именованные —
        # Name=value в любом месте.
        # Сначала раскладываем текст по параметрам, потом разбираем в порядке
        # params: «to=@100,0,0 from=0,0,0» знает from, когда считает to.
        def bind(cmd, tokens)
          raw = {}
          positional = []
          tokens.each do |tok|
            if (m = tok.match(/\A([A-Za-z][A-Za-z0-9]*)=(.*)\z/m))
              param = cmd.params.find { |p| p.name.casecmp?(m[1]) }
              return [nil, "#{cmd.id}: unknown parameter #{m[1]}"] unless param

              raw[param] = m[2]
            else
              positional << tok
            end
          end
          free = cmd.params.reject { |p| raw.key?(p) || p.selection? }
          if positional.size > free.size
            return [nil, "#{cmd.id}: takes no arguments"] if cmd.params.empty?

            return [nil, "#{cmd.id}: too many arguments (parameters: #{cmd.params.map(&:name).join(', ')})"]
          end

          positional.each_with_index { |tok, i| raw[free[i]] = tok }
          args = {}
          cmd.params.each do |param|
            next unless raw.key?(param)

            value, err = param.parse(raw[param], base: args[param.base])
            return [nil, err] if err

            args[param.key] = value
          end
          [args, nil]
        end

        # Строка → [[токены команды], ...], nil или [nil, ошибка]. Звенья
        # цепочки — через «;». Строка в кавычках — только двойных и только в
        # начале слова или после «=»: в 3'6" кавычки — футы и дюймы.
        def lex(line)
          chain = [[]]
          tok = nil
          quote = false
          line.each_char do |ch|
            if quote
              if ch == '"'
                quote = false
              else
                tok << ch
              end
            elsif ch == '"' && (tok.nil? || tok.end_with?('='))
              tok ||= +''
              quote = true
            elsif ch == ';' || ch.match?(/\s/)
              chain.last << tok if tok
              tok = nil
              chain << [] if ch == ';'
            else
              (tok ||= +'') << ch
            end
          end
          return [nil, 'Unclosed quote'] if quote

          chain.last << tok if tok
          [chain.reject(&:empty?), nil]
        end

        def remember(text)
          list = history
          list.delete(text)
          list << text
          list.shift(list.size - HISTORY_LIMIT) if list.size > HISTORY_LIMIT
          Sketchup.write_default(PREFS_KEY, 'history', JSON.generate(list))
        end
      end
    end
  end
end
