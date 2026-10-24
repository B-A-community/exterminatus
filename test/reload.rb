# Перечитать исходники терминала из репозитория в живой SketchUp (без перезапуска).
# Меню и окна не пересоздаются; открытые окна надо закрыть и открыть заново.
src = File.expand_path('../src/exterminatus', __dir__)
%w[constants params registry session window builtins shortcut api].each { |f| load File.join(src, "#{f}.rb") }
# Встроенные команды пересоздаём, чтобы блоки взяли новый код.
T = BACommunity::Terminal
T::Registry.all.select(&:builtin).each { |c| T::Registry.remove(c.id) }
T::Builtins.register_all
T.register_own unless T::Registry.find('Commands')
puts "reloaded #{BACommunity::Terminal::Registry.all.size} commands"
