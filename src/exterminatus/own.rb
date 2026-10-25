# frozen_string_literal: true

module BACommunity
  module Terminal
    # Команды самого терминала: справка, история, макросы, пресеты, проверка
    # плагинов.
    module Builtins
      class << self
        private

        def own(id, aliases, description, params = [], &run)
          spec = { id: id, plugin: PLUGIN_NAME, description: description, aliases: aliases, params: params,
                   keywords: KEYWORDS[id], destructive: DESTRUCTIVE.include?(id) }
          _cmd, err = Registry.add(spec, run, builtin: true)
          warn "Exterminatus: #{err}" if err
        end

        def command_names
          -> { Registry.all.map(&:id).sort }
        end

        def register_own
          own('Commands', %w[Cmds], 'List commands, optionally filtered by plugin or text',
              [{ key: :filter, type: :string, default: '', prompt: false }]) do |args|
            q = args[:filter].to_s.downcase
            list = Registry.all.select do |c|
              q.empty? || c.id.downcase.include?(q) || c.plugin.downcase.include?(q) || c.description.downcase.include?(q)
            end
            next "No commands match #{args[:filter]}" if list.empty?

            list.group_by(&:plugin).sort_by { |plugin, _| plugin == 'SketchUp' ? 'zzz' : plugin.downcase }.map do |plugin, cmds|
              names = cmds.sort_by(&:id).map { |c| c.aliases.empty? ? c.id : "#{c.id} (#{c.aliases.join(', ')})" }
              "#{plugin}: #{names.join(', ')}"
            end.join("\n")
          end

          own('Help', %w[], 'How to use the terminal, or help on one command (Help Move)',
              [{ key: :name, type: :string, default: '', prompt: false, suggest: command_names }]) do |args|
            name = args[:name].to_s.strip
            next general_help if name.empty?

            cmd, _how, similar = Fuzzy.resolve(name)
            next({ ok: false, message: "unknown command #{name}#{similar.any? ? ". Did you mean #{similar.join(', ')}?" : ''}" }) unless cmd

            command_help(cmd)
          end

          own('History', %w[], 'Show recent command lines') do
            list = Session.history.last(20)
            list.empty? ? 'History is empty' : list.join("\n")
          end

          own('ClearLog', %w[Cls], 'Clear the terminal output') do
            Session.clear_log
            nil
          end

          own('CommandBar', %w[], 'Show or hide the command bar') do
            UI.start_timer(0, false) { Window.toggle_bar }
            nil
          end

          own('SelectLast', %w[SelLast], 'Select what the last command created') do
            items = Session.last_created
            next({ ok: false, message: 'nothing created yet' }) if items.empty?

            selection.clear
            selection.add(items)
            "#{selection.size} selected"
          end

          register_library
          register_updates
          own('PluginCheck', %w[], 'Check how plugins are connected to the terminal (for plugin authors)',
              [{ key: :plugin, type: :string, default: '', prompt: false }]) do |args|
            Check.report(args[:plugin].to_s)
          end
        end

        def register_library
          own('Define', %w[], 'Save a command line under a new name: Define Fence "Beam; PathCopy 300"',
              [{ key: :name, type: :string, label: 'Macro name' },
               { key: :text, type: :string, label: 'Command line ($1, $2 for values)' }]) do |args|
            msg, err = Library.define(args[:name], args[:text])
            err ? { ok: false, message: err } : msg
          end

          own('Undefine', %w[], 'Remove a macro',
              [{ key: :name, type: :string, label: 'Macro name', suggest: -> { Library.macros.keys } }]) do |args|
            msg, err = Library.undefine(args[:name])
            err ? { ok: false, message: err } : msg
          end

          own('Macros', %w[], 'List macros') do
            list = Library.macros
            list.empty? ? 'No macros. Define one: Define Fence "Beam; PathCopy 300"' : list.map { |k, v| "#{k} = #{v}" }.join("\n")
          end

          own('PresetSave', %w[], 'Save the current options of a command under a name: PresetSave PathCopy Fence',
              [{ key: :command, type: :string, label: 'Command', suggest: command_names },
               { key: :name, type: :string, label: 'Preset name' }]) do |args|
            cmd = Registry.find(args[:command]) or next({ ok: false, message: "unknown command #{args[:command]}" })

            msg, err = Library.save_preset(cmd, args[:name], Session.remembered(cmd))
            err ? { ok: false, message: err } : msg
          end

          own('PresetDelete', %w[], 'Remove a preset: PresetDelete PathCopy Fence',
              [{ key: :command, type: :string, label: 'Command', suggest: -> { Library.data['presets'].keys } },
               { key: :name, type: :string, label: 'Preset name' }]) do |args|
            cmd = Registry.find(args[:command]) or next({ ok: false, message: "unknown command #{args[:command]}" })

            msg, err = Library.delete_preset(cmd, args[:name])
            err ? { ok: false, message: err } : msg
          end

          own('Presets', %w[], 'List presets, optionally of one command',
              [{ key: :command, type: :string, default: '', prompt: false }]) do |args|
            q = args[:command].to_s
            rows = Library.data['presets'].select { |id, _| q.empty? || id.casecmp?(q) }.flat_map do |id, table|
              cmd = Registry.find(id)
              table.map { |name, values| "#{id} preset=#{name}: #{cmd ? Library.describe(cmd, values) : values}" }
            end
            rows.empty? ? 'No presets. Run a command, then PresetSave <command> <name>' : rows.join("\n")
          end

          own('LibraryExport', %w[], 'Save macros and presets to a file to share',
              [{ key: :file, type: :string, default: '', prompt: false }]) do |args|
            file = args[:file].to_s
            file = UI.savepanel('Save Exterminatus library', '', 'exterminatus_library.json').to_s if file.empty?
            next nil if file.empty?

            Library.export(file)
          end

          own('LibraryImport', %w[], 'Add macros and presets from a file',
              [{ key: :file, type: :string, default: '', prompt: false }]) do |args|
            file = args[:file].to_s
            file = UI.openpanel('Open Exterminatus library', '', 'Library|*.json||').to_s if file.empty?
            next nil if file.empty?

            msg, err = Library.import(file)
            err ? { ok: false, message: err } : msg
          end
        end

        # ---------- обновления плагинов ----------

        def register_updates
          own('PluginUpdates', %w[Updates], 'Open the window to install and update our plugins') do
            UI.start_timer(0, false) { UpdatesWindow.show }
            nil
          end

          own('Plugins', %w[], 'Our plugins: installed version and updates') do
            with_catalog do
              rows = Updater.rows
              lines = rows.map do |r|
                state = { 'update' => "update #{r[:latest]}", 'current' => 'up to date', 'missing' => "not installed (#{r[:latest]})",
                          'newer' => "newer than release #{r[:latest]}", 'restart' => "#{r[:pending]} after restart",
                          'unpublished' => 'no releases', 'busy' => r[:message], 'error' => "error: #{r[:message]}",
                'nolang' => "#{r[:latest]} has no #{r[:lang].to_s.upcase} build",
                'retired' => "retired: #{r[:message]}" }[r[:status]]
                "#{r[:name]}: #{r[:installed] || '—'} — #{state}"
              end
              Session.emit(:result, lines.join("
"))
              Session.emit(:info, "#{Updater.updates.size} updates: PluginUpdate installs them") if Updater.updates.any?
            end
            'Checking GitHub…'
          end

          own('PluginUpdate', %w[], 'Update our plugins: all, or one by name (PluginUpdate pathcopy)',
              [{ key: :name, type: :string, default: '', prompt: false, suggest: -> { Catalog.plugins.map { |p| p['id'] } } }]) do |args|
            name = args[:name].to_s.strip
            with_catalog do
              if name.empty?
                n = Updater.update_all
                Session.emit(:info, n.zero? ? 'All our plugins are up to date' : "Updating #{n} plugins…")
              else
                msg = Updater.install(name)
                Session.emit(msg ? :error : :info, msg || "Updating #{name}…")
              end
            end
            'Checking GitHub…'
          end

          own('PluginInstall', %w[], 'Install one of our plugins: PluginInstall ralncs lang=en',
              [{ key: :name, type: :string, label: 'Plugin', suggest: -> { Catalog.plugins.map { |p| p['id'] } } },
               { key: :lang, type: :option, values: %w[Auto RU EN], default: 'Auto', prompt: false }]) do |args|
            lang = args[:lang] == 'Auto' ? nil : args[:lang].downcase
            with_catalog do
              msg = Updater.install(args[:name], lang: lang)
              Session.emit(msg ? :error : :info, msg || "Installing #{args[:name]}…")
            end
            'Checking GitHub…'
          end

          own('PluginRollback', %w[], 'Go back to the previous release of a plugin',
              [{ key: :name, type: :string, label: 'Plugin', suggest: -> { Catalog.plugins.map { |p| p['id'] } } }]) do |args|
            with_catalog do
              plugin = Updater.find(args[:name])
              prev = plugin && Updater.previous_release(plugin)
              if prev
                msg = Updater.install(plugin['id'], version: prev['version'])
                Session.emit(msg ? :error : :info, msg || "Installing #{plugin['name']} #{prev['version']}…")
              else
                Session.emit(:error, plugin ? "#{plugin['name']}: no earlier release" : "unknown plugin #{args[:name]}")
              end
            end
            'Checking GitHub…'
          end

          own('RestartSketchUp', %w[], 'Restart SketchUp (to load updated plugins)') do
            next({ ok: false, message: 'wait until the plugins finish installing' }) if Updater.busy?

            UI.start_timer(0, false) { Updater.restart }
            nil
          end
        end

        # Свежий каталог, потом блок; ошибка — в вывод терминала.
        def with_catalog(&block)
          Updater.refresh do
            if Updater.error && !Updater.catalog
              Session.emit(:error, Updater.error)
            else
              block.call
            end
          end
        end

        # ---------- справка ----------

        def general_help
          [
            'Type a command name and press Enter: Move, Rectangle, PathCopy. Tab completes, arrows pick.',
            'Arguments in the line: Move 0,0,500   Rectangle 0,0 3000,2000   PathCopy step=1.2m',
            'Chain with ;   Top; ZoomExtents   — what one command creates is selected for the next.',
            'Points: click, or x,y,z  @dx,dy,dz  r<angle  @r<angle, or a distance toward the cursor.',
            'Wrong keyboard layout and small typos are understood: ьщму → Move, Rectnagle → Rectangle.',
            'Enter or Space repeats the last command; Esc cancels.',
            'Help <command> — parameters and examples. Commands — the full list. Macros, Presets — your library.'
          ].join("\n")
        end

        def command_help(cmd)
          lines = ["#{cmd.id}#{cmd.aliases.any? ? " (#{cmd.aliases.join(', ')})" : ''} — #{cmd.plugin}"]
          lines << cmd.description unless cmd.description.empty?
          asked, options = cmd.params.partition(&:prompt?)
          asked.each { |p| lines << "  #{p.label}#{param_details(p)}" }
          options.each { |p| lines << "  option #{p.name}#{param_details(p)}" }
          presets = Library.presets(cmd.id).keys
          lines << "Presets: #{presets.join(', ')}" if presets.any?
          lines << "Examples: #{cmd.examples.join('   ')}" if cmd.examples.any?
          lines << "Words: #{cmd.keywords.join(', ')}" if cmd.keywords.any?
          lines.join("\n")
        end

        def param_details(p)
          bits = [p.type.to_s]
          bits << p.values.join('/') if p.type == :option
          d = p.coerce_default
          bits << "default #{p.format(d)}" unless d.nil? || p.format(d).empty?
          bits << 'only in the command line' if p.optional?
          bits << p.description.to_s if p.description
          " (#{bits.join(', ')})"
        end
      end
    end
  end
end
