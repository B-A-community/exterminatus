# Пример плагина examples/hello_plugin в живом SketchUp: меню, команда
# терминала, цепочка с передачей созданного, справка, PluginCheck.
# Меню «Extensions → Hello Plugin» и панель остаются до перезапуска SketchUp.
# Запуск: python test/bridge.py test/live_example.rb
T = BACommunity::Terminal
S = T::Session
m = Sketchup.active_model
results = []
ok = ->(name, cond, note = '') { results << [cond ? 'PASS' : 'FAIL', name, note.to_s] }
saved_history = S.history.dup
root = File.expand_path('../examples/hello_plugin', __dir__)
same = File.read(File.join(root, 'hello_plugin', 'terminal_bridge.rb')) ==
       File.read(File.expand_path('../src/exterminatus/terminal_bridge.rb', __dir__))
ok.('example carries the current bridge', same)
unless T::Registry.find('HelloStairs')
  # Тест обновлений мог поставить и снять пример: его защита @ui_built осталась.
  hp = defined?(BACommunity::HelloPlugin) && BACommunity::HelloPlugin
  hp.remove_instance_variable(:@ui_built) if hp && hp.instance_variable_defined?(:@ui_built)
  load File.join(root, 'hello_plugin', 'main.rb')
end

ok.('commands registered', T::Registry.find('HelloStairs') && T::Registry.find('HelloRename'))
ok.('menu items built', T::Kit.ui_command('HelloStairs').is_a?(UI::Command) && T::Kit.ui_command('HelloRename').is_a?(UI::Command))
ok.('found by a Russian word', T::Fuzzy.resolve('лестница')[0]&.id == 'HelloStairs')

m.select_tool(nil)
m.close_active while m.active_path
sandbox = m.entities.add_group
sandbox.name = 'EXT_SANDBOX'
sandbox.entities.add_cpoint(ORIGIN)
m.active_path = [sandbox]
ents = m.active_entities

mark = S.seq
S.submit('HelloStairs 20000,0,0 23000,0,1500 steps=10; HelloRename prefix=Flight')
log = S.log_after(mark).map { |l| l[:text] }
g = ents.grep(Sketchup::Group).first
ok.('chain: stairs built and passed to the next command', g && g.name == 'Flight 1' && !S.busy?, log)
ok.('stairs size', g && (g.bounds.height.to_mm.round == 1000) && (g.bounds.depth.to_mm.round == 1500),
    g && [g.bounds.width, g.bounds.height, g.bounds.depth].map { |v| v.to_mm.round })

mark = S.seq
S.submit('Help HelloStairs')
help = S.log_after(mark).map { |l| l[:text] }
ok.('Help shows examples', help.any? { |t| t.start_with?('Examples: HelloStairs 0,0,0') }, help)

check = T::Check.report('Hello Plugin')
ok.('PluginCheck is clean', check.start_with?('Hello Plugin: 2 commands, OK'), check)

# ---------- уборка ----------
m.selection.clear
m.select_tool(nil)
m.close_active while m.active_path
m.entities.grep(Sketchup::Group).select { |x| x.name == 'EXT_SANDBOX' }.each(&:erase!)
S.history.replace(saved_history)
T::Library.write_json('history.json', saved_history)

results.each { |r| puts r.join('  ') }
puts "#{results.count { |r| r[0] == 'PASS' }}/#{results.size} passed"
