# frozen_string_literal: true

require 'json'

module BACommunity
  module Terminal
    # Окно «Plugin Updates»: наши плагины, у каждого кнопка «Update» или
    # «Install», сверху «Update all», снизу — перезапуск SketchUp.
    module UpdatesWindow
      HTML = File.join(PLUGIN_PATH, 'html', 'updates.html')

      class << self
        def show
          if @dialog&.visible?
            @dialog.bring_to_front
          else
            @dialog = create
            @dialog.show
          end
          Updater.refresh unless Updater.checking? || Updater.busy?
        end

        def visible?
          @dialog ? @dialog.visible? : false
        end

        # Состояние для окна (и для тестов).
        def state
          {
            rows: Updater.rows,
            checking: Updater.checking?,
            error: Updater.error,
            checkedAt: Updater.checked_at&.strftime('%H:%M'),
            lang: Updater.install_lang,
            restart: Updater.restart_needed?,
            busy: Updater.busy?,
            updates: Updater.updates.size
          }
        end

        private

        def create
          dialog = UI::HtmlDialog.new(
            dialog_title: 'Plugin Updates',
            preferences_key: "#{PREFS_KEY}_updates",
            scrollable: false,
            resizable: true,
            width: 640,
            height: 460,
            min_width: 460,
            min_height: 240,
            style: UI::HtmlDialog::STYLE_DIALOG
          )
          dialog.set_file(HTML)
          dialog.add_action_callback('ready') { |_c| push }
          dialog.add_action_callback('refresh') { |_c| Updater.refresh }
          dialog.add_action_callback('install') { |_c, id| guarded { Updater.install(id.to_s) } }
          dialog.add_action_callback('rollback') { |_c, id| guarded { rollback(id.to_s) } }
          dialog.add_action_callback('update_all') { |_c| guarded { Updater.update_all } }
          dialog.add_action_callback('lang') { |_c, lang| Updater.install_lang = lang.to_s }
          dialog.add_action_callback('restart') { |_c| guarded { Updater.restart } }
          dialog.add_action_callback('close') { |_c| dialog.close }
          # Ссылки — только на pachka.space, в обычном браузере.
          dialog.add_action_callback('open') { |_c, url| UI.openURL(url.to_s) if url.to_s.match?(Catalog::PAGE) }
          listener = Updater.listen { push }
          dialog.set_on_closed do
            Updater.unlisten(listener)
            @dialog = nil if @dialog.equal?(dialog)
          end
          dialog
        end

        def rollback(id)
          plugin = Updater.find(id) or return
          prev = Updater.previous_release(plugin) or return

          return unless UI.messagebox("Install #{plugin['name']} #{prev['version']} instead of the current version?", MB_YESNO) == IDYES

          Updater.install(id, version: prev['version'])
        end

        def guarded
          msg = yield
          UI.messagebox(msg) if msg.is_a?(String)
        rescue StandardError => e
          warn "Exterminatus updates: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
          UI.messagebox(e.message)
        end

        def push
          return unless @dialog&.visible?

          @dialog.execute_script("U.update(#{JSON.generate(state)})")
        end
      end
    end
  end
end
