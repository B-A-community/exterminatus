# frozen_string_literal: true
#
# Exterminatus bridge, версия 1. Копируется в плагин как есть.
#
# Даёт плагину API терминала BACommunity::Terminal (register, unregister,
# prompt, message, error, run, available?, version) независимо от того,
# установлен ли терминал и в каком порядке SketchUp загрузит расширения. Пока
# терминала нет, register только складывает команды в очередь, unregister
# убирает их оттуда, остальные вызовы возвращают false или nil. Терминал
# при загрузке подменяет эти заглушки настоящими методами и разбирает очередь.
#
# Подробности — docs/PLUGIN_GUIDE.md в репозитории B-A-community/exterminatus.

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
  end
end
