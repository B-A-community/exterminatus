# frozen_string_literal: true
#
# Exterminatus bridge, версия 2. Копируется в плагин как есть.
#
# Даёт плагину API терминала BACommunity::Terminal независимо от того,
# установлен ли терминал и в каком порядке SketchUp загрузит расширения:
#
#   Terminal.command(...) { |args| ... }  — команда целиком: пункт меню, кнопка
#                                          на панели и команда терминала из
#                                          одного описания (версия 2)
#   Terminal.register(...)               — только команда терминала (версия 1)
#   unregister, prompt, message, error, run, available?, version
#
# Пока терминала нет, register только складывает команды в очередь, остальные
# вызовы возвращают false или nil. Терминал при загрузке подменяет заглушки
# настоящими методами и разбирает очередь. Меню и кнопки command строит сразу
# и без терминала: пункт меню тогда запускает команду сам (окном с
# параметрами или блоком fallback:).
#
# В каждом плагине лежит своя копия файла. Код Kit берётся у самой новой из
# загруженных копий, поэтому старая копия в одном плагине не мешает новой в
# другом.
#
# Подробности — docs/PLUGIN_GUIDE.md в репозитории Exterminatus.

module BACommunity
  module Terminal
    unless respond_to?(:register)
      @queue = []

      def self.register(**spec, &run)
        @queue << [spec, run]
        true
      end

      def self.unregister(id)
        @queue.reject! { |spec, _| spec[:id].to_s.casecmp?(id.to_s) }
        false
      end

      def self.available?
        false
      end

      def self.version
        nil
      end

      def self.run(*_args)
        false
      end

      def self.prompt(*_args, **_opts)
        false
      end

      def self.message(*_args)
        false
      end

      def self.error(*_args)
        false
      end
    end

    # Какие копии моста загружены и какой версии — для PluginCheck.
    (@bridges ||= {})[__FILE__] = 2

    if (@kit_version || 0) < 2
      @kit_version = 2

      # Построение меню и панелей и запуск команды без терминала.
      module Kit
        # Ключи command, которые относятся к меню и панели, а не к терминалу.
        # Новая копия моста заменяет константу старой без предупреждения.
        remove_const(:UI_KEYS) if const_defined?(:UI_KEYS, false)
        UI_KEYS = %i[menu menu_text tooltip toolbar icon separator enabled checked fallback].freeze

        @specs ||= {}     # id.downcase => первая запись { spec:, run:, fallback:, file:, ui: }
        @menus ||= {}     # 'Extensions/PathCopy Advanced' => UI::Menu
        @toolbars ||= {}  # имя => UI::Toolbar
        @last ||= {}      # id.downcase => значения окна параметров

        class << self
          # Пункт меню запускает свою запись: если два плагина назвали команду
          # одинаково, у каждого пункта остаётся свой блок.
          def command(spec, run, file)
            spec = spec.transform_keys(&:to_sym)
            id = spec[:id].to_s
            ui = spec.slice(*UI_KEYS)
            entry = { id: id, spec: spec, run: run, fallback: ui[:fallback], file: file }
            # Первый плагин владеет именем; тот же файл, загруженный заново
            # (разработка), заменяет свою запись.
            prev = @specs[id.downcase]
            @specs[id.downcase] = entry if prev.nil? || prev[:file] == file
            Terminal.register(**spec.reject { |k, _| UI_KEYS.include?(k) }, &run)
            entry[:ui] = build(entry, ui)
          end

          def ui_command(id)
            @specs[id.to_s.downcase]&.dig(:ui)
          end

          def spec(id)
            @specs[id.to_s.downcase]
          end

          def specs
            @specs
          end

          # Пункт меню или кнопка: с терминалом — как набранная команда
          # (вопросы в строке и клики в модели), без него — сами.
          def invoke(id)
            entry = @specs[id.to_s.downcase] or return

            run_entry(entry)
          end

          def run_entry(entry)
            id = entry[:id]
            return if Terminal.available? && Terminal.respond_to?(:invoke) && Terminal.invoke(id, entry[:run])

            standalone(entry)
          rescue StandardError => e
            warn "Exterminatus bridge: #{id} raised #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
            UI.messagebox("#{id}: #{e.message}")
          end

          private

          def build(entry, ui)
            id = entry[:id]
            spec = entry[:spec]
            cmd = UI::Command.new(ui[:menu_text] || spaced(id)) { Kit.run_entry(entry) }
            cmd.tooltip = ui[:tooltip] || ui[:menu_text] || spaced(id)
            cmd.status_bar_text = spec[:description].to_s
            small, large = icons(ui[:icon])
            cmd.small_icon = small if small
            cmd.large_icon = large if large
            if ui[:enabled] || ui[:checked]
              cmd.set_validation_proc do
                if ui[:enabled] && !ui[:enabled].call then MF_GRAYED
                elsif ui[:checked] then ui[:checked].call ? MF_CHECKED : MF_UNCHECKED
                else MF_ENABLED
                end
              end
            end
            if ui[:menu]
              menu = menu(ui[:menu])
              menu.add_separator if ui[:separator]
              menu.add_item(cmd)
            end
            toolbar(ui[:toolbar]).add_item(cmd) if ui[:toolbar]
            cmd
          end

          # 'Extensions/PathCopy Advanced/Arrays' (или массив) → подменю.
          def menu(path)
            parts = path.is_a?(Array) ? path.map(&:to_s) : path.to_s.split(%r{\s*[/>]\s*})
            key = parts.join('/')
            @menus[key] ||= if parts.size == 1
                              UI.menu(parts.first)
                            else
                              menu(parts[0..-2]).add_submenu(parts.last)
                            end
          end

          def toolbar(name)
            @toolbars[name.to_s] ||= begin
              tb = UI::Toolbar.new(name.to_s)
              # Показать после того, как плагин добавит все кнопки.
              UI.start_timer(0, false) { tb.get_last_state == TB_NEVER_SHOWN ? tb.show : tb.restore }
              tb
            end
          end

          def icons(icon)
            case icon
            when nil then [nil, nil]
            when Hash then [icon[:small] || icon[:large], icon[:large] || icon[:small]].map { |p| p&.to_s }
            else [icon.to_s, icon.to_s]
            end
          end

          def spaced(id)
            id.to_s.gsub(/(?<=[a-z0-9])(?=[A-Z])/, ' ')
          end

          # ---------- без терминала ----------

          def standalone(entry)
            id = entry[:id]
            return entry[:fallback].call if entry[:fallback]

            args = standalone_args(id, entry[:spec]) or return
            report(id, call_run(entry[:run], args))
          end

          # Значения по умолчанию, выделение из модели, остальное — окном.
          def standalone_args(id, spec)
            params = Array(spec[:params]).map { |p| p.transform_keys(&:to_sym) }
            args = {}
            params.each do |p|
              next unless p[:type].to_s == 'selection'

              items = Sketchup.active_model.selection.to_a
              kinds = Array(p[:kinds])
              items = items.select { |e| kinds.any? { |k| e.is_a?(k) } } unless kinds.empty?
              if items.empty?
                UI.messagebox("#{p[:label] || 'Select objects'}, then run #{spaced(id)} again.")
                return nil
              end
              args[p[:key].to_sym] = items
            end
            points = params.select { |p| %w[point vector].include?(p[:type].to_s) && !p[:optional] && !p[:auto] }
            unless points.empty?
              UI.messagebox("#{spaced(id)} picks points in the model: install Exterminatus to use it.")
              return nil
            end

            asked = params.select { |p| !p[:optional] && !args.key?(p[:key].to_sym) && %w[point vector].none?(p[:type].to_s) }
            last = (@last[id.to_s.downcase] ||= {})
            asked.each { |p| args[p[:key].to_sym] = last.fetch(p[:key].to_sym) { default_of(p) } }
            shown = asked.reject { |p| p[:ask_if] && !p[:ask_if].call(args) }
            return args if shown.empty?

            labels = shown.map { |p| p[:label] || name_of(p) }
            values = shown.map { |p| text_of(p, args[p[:key].to_sym]) }
            lists = shown.map do |p|
              case p[:type].to_s
              when 'option' then Array(p[:values]).join('|')
              when 'bool' then 'Yes|No'
              else ''
              end
            end
            input = UI.inputbox(labels, values, lists, spaced(id)) or return nil

            shown.each_with_index do |p, i|
              value = p[:parse] ? p[:parse].call(input[i].to_s.strip, args) : nil
              value = value_of(p, input[i]) if value.nil?
              err = value.nil? ? 'is not a valid value' : out_of_range(p, value)
              if err
                UI.messagebox("#{labels[i]}: #{input[i].to_s.strip} #{err}")
                return nil
              end
              args[p[:key].to_sym] = last[p[:key].to_sym] = value
            end
            args
          end

          def out_of_range(p, value)
            return nil unless value.is_a?(Numeric)

            min, max = [p[:min], p[:max]].map { |b| p[:type].to_s == 'length' && b.is_a?(Numeric) ? b.to_l : b }
            return "must be at least #{min}" if min && value.to_f < min.to_f
            return "must be at most #{max}" if max && value.to_f > max.to_f

            nil
          end

          def name_of(p)
            (p[:name] || p[:key].to_s.split('_').map(&:capitalize).join).to_s
          end

          def default_of(p)
            d = p[:default]
            p[:type].to_s == 'length' && d.is_a?(Numeric) ? d.to_l : d
          end

          def text_of(p, v)
            case p[:type].to_s
            when 'bool' then v ? 'Yes' : 'No'
            when 'length' then v.nil? ? '' : v.to_l.to_s
            else v.to_s
            end
          end

          def value_of(p, s)
            s = s.to_s.strip
            case p[:type].to_s
            when 'length' then begin
              s.to_l
            rescue ArgumentError
              begin
                s.tr(',', '.').to_l
              rescue ArgumentError
                nil
              end
            end
            when 'number', 'angle' then Float(s.tr(',', '.'), exception: false)
            when 'integer' then Integer(s, exception: false)
            when 'bool' then s == 'Yes'
            when 'option' then Array(p[:values]).map(&:to_s).find { |v| v.casecmp?(s) }
            when 'scale'
              f = s.split(',').map { |x| Float(x.strip, exception: false) }
              f.any? { |v| v.nil? || v.zero? } || ![1, 3].include?(f.size) ? nil : (f.size == 1 ? f * 3 : f)
            else s
            end
          end

          # Вызов как у терминала: (args) или (args, ctx).
          def call_run(run, args)
            if run.lambda? && run.arity >= 0
              run.call(*[args, Context].first(run.arity))
            else
              run.call(args, Context)
            end
          end

          def report(id, res)
            case res
            when String then Sketchup.status_text = res unless res.empty?
            when Hash
              ok = res.key?(:ok) ? res[:ok] : res.fetch('ok', true)
              msg = res[:message] || res['message']
              if ok == false
                UI.messagebox("#{spaced(id)}: #{msg || 'failed'}")
              elsif msg
                Sketchup.status_text = msg.to_s
              end
            when false then UI.messagebox("#{spaced(id)} failed")
            end
          end
        end

        # Второй аргумент блока без терминала: сообщения — в строку состояния.
        module Context
          def self.message(text)
            Sketchup.status_text = text.to_s
          end

          def self.error(text)
            UI.messagebox(text.to_s)
          end
        end
      end

      # Команда целиком из одного описания. Кроме ключей register:
      #   menu:      'Extensions/PathCopy Advanced' — куда положить пункт
      #   menu_text: 'Copy Along Path' — текст пункта (по умолчанию из id)
      #   tooltip:   подсказка кнопки (по умолчанию menu_text)
      #   toolbar:   'PathCopy' — панель, на которую положить кнопку
      #   icon:      путь к .svg/.png или { small:, large: }
      #   separator: true — разделитель перед пунктом
      #   enabled:   -> { ... } — пункт серый, пока вернёт ложь
      #   checked:   -> { ... } — галочка у пункта
      #   fallback:  -> { ... } — что делать без терминала (по умолчанию —
      #              окно с параметрами и выделение из модели)
      # → UI::Command (его можно положить ещё и в контекстное меню).
      def self.command(**spec, &run)
        raise ArgumentError, "#{spec[:id]}: no block given" unless run

        Kit.command(spec, run, caller_locations(1, 1).first&.path)
      end
    end
  end
end
