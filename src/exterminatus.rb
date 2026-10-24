# frozen_string_literal: true
#
# Exterminatus — загрузчик / манифест расширения.
#
# Общий командный терминал для SketchUp, как командная строка Rhino: команды
# плагинов B&A community и стандартные команды SketchUp вызываются по имени,
# параметры спрашиваются в строке. Плагины подключаются через
# terminal_bridge.rb (см. docs/PLUGIN_GUIDE.md) и без терминала работают как раньше.

require 'sketchup.rb'
require 'extensions.rb'

module BACommunity
  module Terminal
    ROOT_PATH   = File.dirname(File.expand_path(__FILE__)).freeze
    PLUGIN_PATH = File.join(ROOT_PATH, 'exterminatus').freeze
  end
end

require File.join(BACommunity::Terminal::PLUGIN_PATH, 'constants')

module BACommunity
  module Terminal
    unless defined?(@loaded)
      @loaded = true

      extension = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_PATH, 'main.rb'))
      extension.version     = VERSION
      extension.creator     = 'B&A community'
      extension.copyright   = '2026 B&A community'
      extension.description = 'Command line for SketchUp: run SketchUp and B&A plugin commands by name, ' \
                              'with Rhino-style prompts for parameters.'

      Sketchup.register_extension(extension, true)
    end
  end
end
