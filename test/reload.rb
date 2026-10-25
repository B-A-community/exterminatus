# Перечитать исходники терминала из репозитория в живой SketchUp (без перезапуска).
# Меню и окна не пересоздаются; открытые окна надо закрыть и открыть заново.
src = File.expand_path('../src/exterminatus', __dir__)
# Мост переопределяет Kit, только если его версия новее загруженной.
BACommunity::Terminal.instance_variable_set(:@kit_version, 0)
%w[constants terminal_bridge params fuzzy registry session picker window library check
   keywords builtins modify draw native own shortcut catalog updater updates_window api].each { |f| load File.join(src, "#{f}.rb") }
# Встроенные команды пересоздаём, чтобы блоки взяли новый код.
T = BACommunity::Terminal
T::Registry.all.select(&:builtin).each { |c| T::Registry.remove(c.id) }
T::Builtins.register_all
puts "reloaded #{BACommunity::Terminal::Registry.all.size} commands"
