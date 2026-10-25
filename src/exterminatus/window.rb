# frozen_string_literal: true

require 'json'

module BACommunity
  module Terminal
    # Два окна над одной Session:
    #   :bar   — плавающая полоса с выводом, помнит место и размер;
    #   :popup — строка у курсора по горячей клавише, закрывается после команды.
    # Когда полоса открыта, горячая клавиша просто ставит в неё фокус.
    module Window
      HTML = File.join(PLUGIN_PATH, 'html', 'index.html')
      POPUP_WIDTH = 460
      POPUP_LOG_LINES = 1
      BAR_LOG_LINES = 200

      @dialogs ||= {}
      @state ||= {} # mode => {seq:, revision:, history:}

      class << self
        # Главная команда (горячая клавиша).
        def invoke
          if visible?(:bar)
            focus(:bar)
          elsif visible?(:popup)
            close(:popup)
          else
            open_popup
          end
        end

        # Команду запустили из меню или кнопкой: если она ждёт ответа с
        # клавиатуры, открыть строку у курсора. Точки и выделение берутся
        # кликом в модели — окно им не нужно (ввод — в поле Measurements).
        def after_invoke
          sync
          open_popup if Session.wants_typing? && !visible?(:bar) && !visible?(:popup)
        end

        def toggle_bar
          visible?(:bar) ? close(:bar) : open_bar
        end

        def open_bar
          close(:popup)
          dialog = (@dialogs[:bar] ||= create(:bar))
          if dialog.visible?
            focus(:bar)
          else
            dialog.show
          end
        end

        def open_popup
          dialog = (@dialogs[:popup] ||= create(:popup))
          x, y = cursor_position
          dialog.set_position(x - 24, y - 16) if x
          dialog.show
        end

        def visible?(mode)
          d = @dialogs[mode]
          d ? d.visible? : false
        end

        # Отправить в открытые окна всё новое: строки вывода, приглашение,
        # каталог команд, если он менялся.
        def sync
          @dialogs.each do |mode, dialog|
            next unless dialog.visible? && @state[mode]

            st = @state[mode]
            data = { prompt: Session.prompt_state, idle: true }
            lines = Session.log_after(st[:seq])
            data[:log] = lines unless lines.empty?
            st[:seq] = Session.seq
            if st[:revision] != Registry.revision
              data[:commands] = Registry.catalog
              st[:revision] = Registry.revision
            end
            if st[:history] != Session.history.size || lines.any?
              data[:history] = Session.history
              st[:history] = Session.history.size
            end
            dialog.execute_script("T.update(#{JSON.generate(data)})")
          end
        end

        def reset_logs
          @dialogs.each do |mode, dialog|
            next unless dialog.visible? && @state[mode]

            @state[mode][:seq] = Session.seq
            dialog.execute_script('T.update({resetLog: true})')
          end
        end

        def close(mode)
          d = @dialogs[mode]
          d.close if d&.visible?
        end

        # Ввод из окна модели (клик, Enter, поле Measurements) закончил
        # команду — popup уходит, как после Enter в нём самом.
        def settle
          sync
          close(:popup) if visible?(:popup) && !Session.needs_typing? && !Session.last_failed?
        end

        private

        def create(mode)
          bar = mode == :bar
          dialog = UI::HtmlDialog.new(
            dialog_title: bar ? PLUGIN_NAME : 'Command',
            preferences_key: "#{PREFS_KEY}_#{mode}",
            scrollable: false,
            resizable: bar,
            width: bar ? 720 : POPUP_WIDTH,
            height: bar ? 140 : 80,
            min_width: 320,
            min_height: bar ? 90 : 40,
            style: UI::HtmlDialog::STYLE_UTILITY
          )
          dialog.set_file(HTML)
          dialog.add_action_callback('ready') { |_ctx| on_ready(mode) }
          dialog.add_action_callback('submit') { |_ctx, line| on_submit(mode, line) }
          dialog.add_action_callback('option') { |_ctx, name| guarded { Session.option(name) } }
          dialog.add_action_callback('cancel') { |_ctx| guarded { Session.cancel } }
          dialog.add_action_callback('dismiss') { |_ctx| dismiss(mode) }
          dialog.add_action_callback('height') { |_ctx, h| resize_popup(h.to_i) if mode == :popup }
          # Закрытое окно SketchUp не открывает заново с теми же колбэками —
          # следующий раз создаём новое.
          dialog.set_on_closed do
            @state.delete(mode)
            @dialogs.delete(mode) if @dialogs[mode].equal?(dialog)
          end
          dialog
        end

        def on_ready(mode)
          dialog = @dialogs[mode]
          @state[mode] = { seq: Session.seq, revision: Registry.revision, history: Session.history.size }
          data = {
            mode: mode.to_s,
            commands: Registry.catalog,
            history: Session.history,
            log: Session.tail(mode == :bar ? BAR_LOG_LINES : 0),
            prompt: Session.prompt_state
          }
          dialog.execute_script("T.init(#{JSON.generate(data)})")
        end

        def on_submit(mode, line)
          guarded { Session.submit(line) }
          # Popup уходит, когда команде больше нечего спрашивать и она не
          # упала, — ошибка остаётся видна до Esc.
          if mode == :popup
            if !Session.needs_typing? && !Session.last_failed?
              close(:popup)
              Sketchup.focus
            end
          elsif !Session.busy?
            Sketchup.focus
          end
        end

        def dismiss(mode)
          close(:popup) if mode == :popup
          Sketchup.focus
        end

        def focus(mode)
          d = @dialogs[mode]
          return unless d

          d.bring_to_front
          d.execute_script('T.focus()')
        end

        def guarded
          yield
        rescue StandardError => e
          warn "Exterminatus: #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
          Session.emit(:error, e.message)
        ensure
          sync
        end

        def resize_popup(height)
          d = @dialogs[:popup]
          return unless d && height.positive?

          d.set_content_size(POPUP_WIDTH, [[height, 40].max, 360].min)
        end

        # Курсор в экранных координатах (только Windows; на Mac окно встанет
        # туда, где было в прошлый раз).
        def cursor_position
          return nil unless Sketchup.platform == :platform_win

          user32
          buf = "\0" * 8
          return nil if @get_cursor_pos.call(buf).zero?

          buf.unpack('l2')
        rescue StandardError, LoadError
          nil
        end

        def user32
          return if @get_cursor_pos

          require 'fiddle'
          lib = Fiddle.dlopen('user32')
          @get_cursor_pos = Fiddle::Function.new(lib['GetCursorPos'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        end
      end
    end
  end
end
