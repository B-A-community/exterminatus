# frozen_string_literal: true
#
# Пример плагина B&A community, подключённого к Exterminatus. Загрузчик —
# как у любого расширения SketchUp; всё про терминал — в hello_plugin/main.rb.

require 'sketchup.rb'
require 'extensions.rb'

module BACommunity
  module HelloPlugin
    unless defined?(@loaded)
      @loaded = true
      ext = SketchupExtension.new('Hello Plugin', File.join(__dir__, 'hello_plugin', 'main.rb'))
      ext.version = '1.0.0'
      ext.creator = 'B&A community'
      ext.description = 'Example: one command description gives a menu item, a toolbar button and a terminal command.'
      Sketchup.register_extension(ext, true)
    end
  end
end
