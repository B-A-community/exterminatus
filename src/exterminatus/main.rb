# frozen_string_literal: true

module BACommunity
  module Terminal
    %w[terminal_bridge params fuzzy registry session picker window library check
       keywords builtins modify draw native own shortcut catalog updater updates_window api]
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

    unless defined?(@ui_built)
      @ui_built = true

      Builtins.register_all
      Library.register_macros
      drain_queue

      terminal = UI::Command.new('Terminal') { Window.invoke }
      terminal.tooltip = 'Terminal'
      terminal.status_bar_text = 'Type a command. Shortcut: Extensions > Exterminatus > Assign Shortcut…'

      bar = UI::Command.new('Command Bar') { Window.toggle_bar }
      bar.tooltip = 'Command Bar'
      bar.status_bar_text = 'Show or hide the command bar'
      bar.set_validation_proc { Window.visible?(:bar) ? MF_CHECKED : MF_UNCHECKED }

      menu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)
      menu.add_item(terminal)
      menu.add_item(bar)
      menu.add_separator
      menu.add_item('Plugin Updates…') { UpdatesWindow.show }
      menu.add_item('Assign Shortcut…') { Shortcut.show }

      watch(Sketchup.active_model)
      Sketchup.add_observer(AppWatch.new)
      UI.start_timer(2, false) { Shortcut.report_pending }
      # Проверка обновлений не должна мешать терминалу загрузиться.
      begin
        # До 0.3.2 история и обновления лежали в настройках SketchUp и там
        # портились: убрать старые значения, теперь это файлы.
        # Не читаем их: само чтение испорченного значения падает.
        %w[history pending_updates].each { |k| Sketchup.write_default(PREFS_KEY, k, '') }
        Updater.schedule_check
      rescue StandardError, ScriptError => e
        warn "Exterminatus: update check skipped: #{e.class}: #{e.message}"
      end
    end
  end
end
