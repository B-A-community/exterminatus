# frozen_string_literal: true

module BACommunity
  module Terminal
    # PluginCheck: как плагины подключены к терминалу. Для авторов плагинов —
    # находит то, что работает, но работает не так, как задумано.
    module Check
      # Длина по умолчанию больше этого числа дюймов скорее всего задана в мм
      # без .mm (500 → 12.7 м).
      SUSPICIOUS_INCHES = 100

      class << self
        def report(filter = '')
          q = filter.to_s.downcase
          cmds = Registry.all.reject { |c| c.builtin || c.plugin == Library::MACRO_PLUGIN }
          cmds = cmds.select { |c| c.plugin.downcase.include?(q) || c.id.downcase.include?(q) } unless q.empty?
          problems = Registry.problems.select { |pr| q.empty? || pr[:plugin].downcase.include?(q) }
          return "No plugin commands#{q.empty? ? '' : " match #{filter}"}. Plugins connect with terminal_bridge.rb (docs/PLUGIN_GUIDE.md)" if cmds.empty? && problems.empty?

          lines = []
          by_plugin = cmds.group_by(&:plugin)
          (by_plugin.keys | problems.map { |pr| pr[:plugin] }).sort_by(&:downcase).each do |plugin|
            list = by_plugin[plugin] || []
            notes = problems.select { |pr| pr[:plugin] == plugin }.map { |pr| "registration: #{pr[:text]}" }.uniq
            list.sort_by(&:id).each { |c| notes.concat(command_notes(c).map { |n| "#{c.id}: #{n}" }) }
            lines << "#{plugin}: #{list.size} commands, #{notes.empty? ? 'OK' : "#{notes.size} notes"}"
            notes.each { |n| lines << "  #{n}" }
          end
          lines.concat(bridge_notes)
          lines.join("\n")
        end

        def command_notes(cmd)
          notes = []
          desc = cmd.description.to_s
          notes << 'no description (it is shown in suggestions)' if desc.strip.empty?
          notes << 'description is not in English' if Layout.cyrillic?(desc)
          notes << "description is long (#{desc.size} chars); one short phrase reads better" if desc.size > 90
          notes << 'no keywords: add Russian words to find it (keywords: "копия массив")' if cmd.keywords.empty?
          cmd.params.each { |p| notes.concat(param_notes(cmd, p)) }
          if cmd.params.any? { |p| p.type == :point } && cmd.preview.nil?
            notes << 'picks points but has no preview: (args, view) — the user sees only the rubber band'
          end
          entry = Kit.spec(cmd.id)
          if entry.nil?
            notes << 'registered with register, not command: menu and toolbar are not built from it'
          elsif !Kit.ui_command(cmd.id)
            notes << 'menu item was not built'
          else
            notes.concat(icon_notes(entry[:spec][:icon]))
          end
          notes
        end

        private

        def param_notes(cmd, p)
          notes = []
          d = p.instance_variable_get(:@default)
          if p.type == :length && d.is_a?(Numeric) && !d.is_a?(Length) && d.to_f.abs > SUSPICIOUS_INCHES
            notes << "#{p.name}: default #{d} means #{d} inches (#{(d.to_f * 25.4 / 1000).round(2)} m); write #{d}.mm"
          end
          if p.prompt? && %i[point selection].include?(p.type) && p.label == p.name
            notes << "#{p.name}: no label — the prompt says just \"#{p.name}\"; label: 'Pick start point'"
          end
          if p.type == :option && p.coerce_default && !p.values.include?(p.coerce_default.to_s)
            notes << "#{p.name}: default #{p.coerce_default.inspect} is not one of #{p.values.join(', ')}"
          end
          if p.base && !cmd.param(p.base)
            notes << "#{p.name}: base #{p.base.inspect} is not a parameter of #{cmd.id}"
          end
          notes
        end

        def icon_notes(icon)
          paths = case icon
                  when nil then []
                  when Hash then icon.values
                  else [icon]
                  end
          paths.map(&:to_s).reject { |f| File.exist?(f) }.map { |f| "icon not found: #{f}" }
        end

        # Копии моста в плагинах: старые версии работают, но без command.
        def bridge_notes
          known = Terminal.instance_variable_get(:@bridges) || {}
          old = $LOADED_FEATURES.select { |f| File.basename(f, '.rb') == 'terminal_bridge' && !known.key?(f) }
          own = File.join(PLUGIN_PATH, 'terminal_bridge.rb')
          old.reject { |f| File.expand_path(f) == File.expand_path(own) }
             .map { |f| "old bridge (version 1): #{f} — copy the new terminal_bridge.rb" }
        end
      end
    end
  end
end
