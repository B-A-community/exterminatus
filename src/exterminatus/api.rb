# frozen_string_literal: true

module BACommunity
  # Публичный API терминала. Заглушки из terminal_bridge.rb заменяются этими
  # методами; всё, что плагины успели зарегистрировать до загрузки терминала,
  # разбирается из очереди @queue.
  module Terminal
    class << self
      # Зарегистрировать команду.
      #   id:          'PathCopy' — английский CamelCase, уникальный
      #   plugin:      'PathCopy Advanced' — подпись в подсказках
      #   description: 'Copy groups along a path'
      #   aliases:     ['PC'] — необязательно
      #   params:      [{ key: :step, type: :length, default: 500.mm }, ...]
      # Блок получает (args) или (args, ctx) и возвращает строку-сообщение,
      # { ok:, message: } или false. → true, если команда принята.
      def register(**spec, &run)
        cmd, err = Registry.add(spec, run)
        warn "Exterminatus: #{err}" if err
        Window.sync if cmd
        cmd ? true : false
      end

      def unregister(id)
        cmd = Registry.find(id)
        Session.forget(cmd.id) if cmd
        Registry.remove(id).tap { Window.sync }
      end

      def available?
        true
      end

      def version
        VERSION
      end

      # Приглашение в строке терминала, пока работает инструмент плагина:
      #   Terminal.prompt('Pick start point', options: { 'Mode' => 'Fit' }, tool: true) do |input|
      #     input.text / input.option / input.cancel? / input.enter?
      #   end
      # tool: true — приглашение уйдёт само, когда инструмент сменится.
      # Terminal.prompt(nil) — убрать приглашение.
      def prompt(text = nil, default: nil, options: nil, tool: false, &block)
        Session.external_prompt(text, default: default, options: options, tool: tool, &block)
      end

      def message(text)
        Session.emit(:result, text)
        true
      end

      def error(text)
        Session.emit(:error, text)
        true
      end

      # Выполнить строку так, будто её ввели в терминале.
      # Из блока команды строка выполнится сразу после этой команды.
      def run(line)
        Session.run_line(line)
        true
      end

      private

      def drain_queue
        queue = @queue || []
        @queue = []
        queue.each { |spec, run| register(**spec, &run) }
      end
    end
  end
end
