# frozen_string_literal: true

require 'json'

module BACommunity
  module Terminal
    # Пункт меню «Assign Shortcut…»: назначить горячую клавишу терминалу без
    # похода в Preferences → Shortcuts.
    #
    # Ruby API назначать клавиши не умеет. SketchUp 2024 (Windows) хранит их в
    # SharedPreferences.json → "Windows Only" → "Settings" строками
    # "Ctrl Alt Shift Клавиша Команда" («0 0 0 ` Extensions/Exterminatus/Terminal»),
    # читает файл при запуске и перезаписывает при выходе. Поэтому правит его
    # скрытый PowerShell (tools/assign_shortcut.ps1) после закрытия SketchUp,
    # а клавиша начинает работать со следующего запуска.
    module Shortcut
      # Подпись в списке → [Ctrl, Alt, Shift, клавиша как в файле настроек]
      PRESETS = {
        '` (backquote)' => [0, 0, 0, '`'],
        'Ctrl+Space'    => [1, 0, 0, 'Space'],
        'Alt+Space'     => [0, 1, 0, 'Space'],
        'Ctrl+`'        => [1, 0, 0, '`'],
        'F12'           => [0, 0, 0, 'F12']
      }.freeze
      REMOVE = 'No shortcut'
      TITLE = 'Terminal Shortcut'

      class << self
        def show
          return mac_hint unless Sketchup.platform == :platform_win
          return UI.messagebox("Settings file not found:\n#{prefs_path}") unless File.exist?(prefs_path)

          current = bindings(command_path)
          choice = UI.inputbox(['Key'], [PRESETS.keys.first], [(PRESETS.keys + [REMOVE]).join('|')],
                               current.empty? ? TITLE : "#{TITLE} (now: #{current.join(', ')})")
          return unless choice

          label = choice.first
          flags = PRESETS[label]
          return if flags.nil? && current.empty?
          return unless confirm_conflict(flags)

          restart = UI.messagebox("#{flags ? "#{display(flags)} will open the terminal" : 'The terminal shortcut will be removed'} " \
                                  "after SketchUp restarts.\n\nRestart SketchUp now?", MB_YESNO) == IDYES
          schedule(flags, restart)
          Sketchup.quit if restart
        end

        # При загрузке: если в прошлый раз назначали клавишу, сказать, получилось ли.
        def report_pending
          job = Sketchup.read_default(PREFS_KEY, 'shortcut_job', '').to_s
          return if job.empty?

          Sketchup.write_default(PREFS_KEY, 'shortcut_job', '')
          log = job.sub(/\.json\z/, '.log')
          text = File.exist?(log) ? File.read(log, encoding: 'utf-8') : ''
          if text.lines.last.to_s.strip.end_with?(' done')
            now = bindings(command_path)
            Sketchup.status_text = now.empty? ? 'Terminal shortcut removed' : "Terminal shortcut: #{now.join(', ')}"
          else
            UI.messagebox("The terminal shortcut was not applied.\nLog: #{log}")
          end
        end

        def command_path
          "Extensions/#{PLUGIN_NAME}/Terminal"
        end

        private

        def schedule(flags, restart)
          dir = File.join(ENV['TEMP'] || Sketchup.temp_dir, 'Exterminatus')
          Dir.mkdir(dir) unless Dir.exist?(dir)
          # Прямые слэши: write_default съедает обратные.
          job = File.join(dir, "shortcut-#{Time.now.to_i}.json").tr('\\', '/')
          File.write(job, JSON.generate(
            prefs: prefs_path,
            exe: exe_path,
            command: command_path,
            entry: flags ? flags.join(' ') : '',
            restart: restart,
            created: Time.now.to_i
          ), encoding: 'utf-8')
          Sketchup.write_default(PREFS_KEY, 'shortcut_job', job)
          script = File.join(PLUGIN_PATH, 'tools', 'assign_shortcut.ps1')
          run_hidden('powershell.exe', %(-NoProfile -ExecutionPolicy Bypass -File "#{script}" -Job "#{job}"))
          Sketchup.status_text = 'Terminal shortcut will be applied when SketchUp closes' unless restart
        end

        # Клавиша уже занята другой командой — спросить.
        def confirm_conflict(flags)
          return true unless flags

          taken = bindings_by_key(display(flags)).reject { |cmd| cmd == command_path }
          return true if taken.empty?

          UI.messagebox("#{display(flags)} is assigned to #{taken.join(', ')}.\nReassign it to the terminal?",
                        MB_YESNO) == IDYES
        end

        def display(flags)
          ctrl, alt, shift, key = flags
          [('Ctrl' if ctrl == 1), ('Alt' if alt == 1), ('Shift' if shift == 1), key].compact.join('+')
        end

        # Sketchup.get_shortcuts: "Ctrl+Space\tExtensions/Exterminatus/Command Bar"
        def bindings(command)
          Sketchup.get_shortcuts.map { |s| s.split("\t", 2) }.select { |_, cmd| cmd == command }.map(&:first)
        end

        def bindings_by_key(key)
          Sketchup.get_shortcuts.map { |s| s.split("\t", 2) }.select { |k, _| k == key }.map(&:last)
        end

        def prefs_path
          year = 2000 + Sketchup.version.to_i
          File.join(ENV['APPDATA'].to_s, 'SketchUp', "SketchUp #{year}", 'SketchUp', 'SharedPreferences.json')
        end

        # Путь к SketchUp.exe этого процесса (GetModuleFileNameW).
        def exe_path
          require 'fiddle'
          kernel = Fiddle.dlopen('kernel32')
          get = Fiddle::Function.new(kernel['GetModuleFileNameW'],
                                     [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          buf = "\0".b * 2048
          len = get.call(nil, buf, 1024)
          buf[0, len * 2].force_encoding('UTF-16LE').encode('UTF-8')
        end

        # ShellExecuteW с SW_HIDE: без мелькающего окна консоли.
        def run_hidden(file, params)
          require 'fiddle'
          shell = Fiddle.dlopen('shell32')
          exec = Fiddle::Function.new(shell['ShellExecuteW'],
                                      [Fiddle::TYPE_VOIDP] * 5 + [Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP)
          wide = ->(s) { "#{s}\0".encode('UTF-16LE') }
          exec.call(nil, wide.call('open'), wide.call(file), wide.call(params), nil, 0)
        end

        # Нужны и обновлению плагинов (перезапуск SketchUp).
        public :exe_path, :run_hidden

        def mac_hint
          UI.messagebox('On macOS assign the shortcut in SketchUp → Settings → Shortcuts: ' \
                        "search for \"Terminal\" under Extensions → #{PLUGIN_NAME}.")
        end
      end
    end
  end
end
