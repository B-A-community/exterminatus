# frozen_string_literal: true

module BACommunity
  module Terminal
    %w[params registry session window builtins api]
      .each { |file| Sketchup.require(File.join(__dir__, file)) }

    # Приглашение с tool: true снимается, когда пользователь сменил инструмент.
    class ToolWatch < Sketchup::ToolsObserver
      def onActiveToolChanged(_tools, _name, id)
        Session.tool_changed(id)
      end
    end

    class AppWatch < Sketchup::AppObserver
      def onNewModel(model)
        Terminal.watch(model)
      end

      def onOpenModel(model)
        Terminal.watch(model)
      end
    end

    def self.watch(model)
      @tool_watch ||= ToolWatch.new
      model.tools.remove_observer(@tool_watch)
      model.tools.add_observer(@tool_watch)
    end

    # Команды самого терминала.
    def self.register_own
      register(id: 'Commands', plugin: PLUGIN_NAME, aliases: %w[Help],
               description: 'List commands, optionally filtered by plugin or text',
               params: [{ key: :filter, type: :string, default: '', prompt: false }]) do |args|
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

      register(id: 'History', plugin: PLUGIN_NAME, description: 'Show recent command lines') do
        list = Session.history.last(20)
        list.empty? ? 'History is empty' : list.join("\n")
      end

      register(id: 'ClearLog', plugin: PLUGIN_NAME, aliases: %w[Cls], description: 'Clear the terminal output') do
        Session.clear_log
        nil
      end

      register(id: 'CommandBar', plugin: PLUGIN_NAME, description: 'Show or hide the command bar') do
        UI.start_timer(0, false) { Window.toggle_bar }
        nil
      end
    end

    unless defined?(@ui_built)
      @ui_built = true

      Builtins.register_all
      register_own
      drain_queue

      terminal = UI::Command.new('Terminal') { Window.invoke }
      terminal.tooltip = 'Terminal'
      terminal.status_bar_text = 'Type a command. Assign a shortcut in Preferences > Shortcuts.'

      bar = UI::Command.new('Command Bar') { Window.toggle_bar }
      bar.tooltip = 'Command Bar'
      bar.status_bar_text = 'Show or hide the command bar'
      bar.set_validation_proc { Window.visible?(:bar) ? MF_CHECKED : MF_UNCHECKED }

      menu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)
      menu.add_item(terminal)
      menu.add_item(bar)

      watch(Sketchup.active_model)
      Sketchup.add_observer(AppWatch.new)
    end
  end
end
