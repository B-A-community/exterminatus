# Живые проверки исполнителя терминала без окна (запуск: python test/bridge.py test/live_session.rb).
# Модель не трогает: тестовые команды только записывают аргументы.

T = BACommunity::Terminal
S = T::Session
$checks = []
$got = nil

def check(name)
  ok = yield
  $checks << [ok ? 'PASS' : 'FAIL', name]
rescue StandardError => e
  $checks << ['FAIL', "#{name}: #{e.class}: #{e.message} #{e.backtrace.first}"]
end

def run(line)
  from = S.seq
  S.submit(line)
  S.log_after(from)
end

def errors(lines)
  lines.select { |l| l[:kind] == 'error' }.map { |l| l[:text] }
end

S.cancel while S.busy?
# История пользователя: сохранить и вернуть в конце, чтобы тест её не засорял.
$saved_history = S.history.dup
%w[ExtTest ExtLambda0 ExtFail ExtRaise].each { |id| T.unregister(id) }

T.register(id: 'ExtTest', plugin: 'Test', description: 'test command',
           params: [{ key: :step, type: :length, default: 500.mm },
                    { key: :count, type: :integer, default: 3, prompt: false, min: 1 },
                    { key: :mode, type: :option, values: %w[Fit Step], default: 'Fit', prompt: false }]) do |args|
  $got = args.dup
  "ran #{args[:step].to_mm.round} #{args[:count]} #{args[:mode]}"
end
T.register(id: 'ExtLambda0', plugin: 'Test', &-> { $got = :lambda0; 'zero' })
T.register(id: 'ExtFail', plugin: 'Test') { { ok: false, message: 'nope' } }
T.register(id: 'ExtRaise', plugin: 'Test') { raise 'boom' }

check('reject non-English id') { T.register(id: 'Стена', plugin: 'Test') {} == false }
check('reject lowercase id') { T.register(id: 'wall', plugin: 'Test') {} == false }
check('reject duplicate id') { T.register(id: 'Line', plugin: 'Test') {} == false }

check('builtins present') { %w[Line PushPull ZoomExtents Top Purge Group].all? { |id| T::Registry.find(id) } }
check('alias L -> Line') { T::Registry.resolve('l').first&.id == 'Line' }
check('prefix ZoomExt -> ZoomExtents') { T::Registry.resolve('ZoomExt').first&.id == 'ZoomExtents' }
check('initials pp -> PushPull') { T::Registry.resolve('pp').first&.id == 'PushPull' }
check('ambiguous Zoom* not auto-picked') { T::Registry.resolve('Zoo').first.nil? }

lines = run('Frobnicate')
check('unknown command reports error') { errors(lines).first.to_s.start_with?('Unknown command: Frobnicate') }

lines = run('ExtTest')
st = S.prompt_state
check('prompt for Step with default') { st && st[:text] == 'Step' && st[:default] == T::Param.new(key: :x, type: :length).format(500.mm) }
check('options listed') { st[:options].map { |o| "#{o[:name]}=#{o[:value]}" } == ['Count=3', 'Mode=Fit'] }
lines = run('')
check('Enter takes default and runs') { $got && $got[:step].to_mm.round == 500 && $got[:count] == 3 && !S.busy? }

$got = nil
run('ExtTest 250')
check('inline positional runs at once') { $got && $got[:step].to_mm.round == 250 && !S.busy? }

$got = nil
run('ExtTest step=1m count=5 mode=st')
check('named args, option prefix') { $got && $got[:step].to_mm.round == 1000 && $got[:count] == 5 && $got[:mode] == 'Step' }

$got = nil
run('ExtTest')
S.option('Mode')
check('option click cycles') { S.prompt_state[:options].find { |o| o[:name] == 'Mode' }[:value] == 'Fit' }
S.option('Count')
check('option click opens sub-prompt') { S.prompt_state[:text] == 'Count' }
lines = run('0')
check('min enforced') { errors(lines).any? { |e| e.include?('at least') } && S.prompt_state[:text] == 'Count' }
run('7')
check('back to main prompt') { S.prompt_state[:text] == 'Step' }
run('count')
check('typed option name opens sub-prompt') { S.prompt_state[:text] == 'Count' }
run('8')
run('120')
check('prompt flow result') { $got && $got[:step].to_mm.round == 120 && $got[:count] == 8 && $got[:mode] == 'Fit' }

$got = nil
run('ExtTest step=2m')
check('last values remembered') { $got[:count] == 8 }

run('ExtTest')
S.cancel
check('cancel clears run') { !S.busy? }

lines = run('ExtTest abc')
check('bad value -> error, no run') { errors(lines).any? && !S.busy? }

$got = []
T.unregister('ExtChain')
T.register(id: 'ExtChain', plugin: 'Test', params: [{ key: :n, type: :integer }]) { |a| $got << a[:n]; nil }
run('ExtChain 1; ExtChain 2 ; ExtChain 3')
check('chain runs in order') { $got == [1, 2, 3] }

$got = []
run('ExtChain 1; Frobnicate; ExtChain 3')
check('chain stops at error') { $got == [1] }

$got = []
T.unregister('ExtReq')
T.register(id: 'ExtReq', plugin: 'Test', params: [{ key: :n, type: :integer }]) { |a| $got << a[:n]; nil }
run('ExtReq')
check('required param prompts') { S.prompt_state && S.prompt_state[:text] == 'N' && S.prompt_state[:default].nil? }
lines = run('')
check('Enter without value -> required') { errors(lines).any? { |e| e.include?('required') } && S.busy? }
run('4')
check('required param answered') { $got == [4] }

run('ExtLambda0')
check('zero-arity lambda') { $got == :lambda0 }
lines = run('ExtFail')
check('ok:false -> error') { errors(lines) == ['ExtFail: nope'] }
lines = run('ExtRaise')
check('exception -> error') { errors(lines) == ['ExtRaise: boom'] }

lines = run('ExtLambda0 extra')
check('too many args') { errors(lines).first.to_s.include?('takes no arguments') }

# Внешнее приглашение (уровень 2 для инструментов плагинов)
inputs = []
T.prompt('Pick start point', options: { 'Mode' => 'Fit', 'Undo' => nil }) { |i| inputs << i }
check('external prompt state') { S.prompt_state[:text] == 'Pick start point' && S.prompt_state[:options].size == 2 }
run('undo')
run('')
run('42')
S.option('Mode')
S.cancel
check('external inputs') do
  inputs.map { |i| i.cancel? ? :cancel : (i.option || i.text) } == ['Undo', '', '42', 'Mode', :cancel] && !S.busy?
end

# Числа уходят активному Ruby-инструменту, как в поле Measurements
class ExtTool
  attr_reader :texts
  def initialize; @texts = []; end
  def onUserText(text, _view); @texts << text; end
end
tool = ExtTool.new
Sketchup.active_model.select_tool(tool)
run('1500;300')
check('number forwarded to tool') { tool.texts == ['1500;300'] }
Sketchup.active_model.select_tool(nil)

# Repeat last
$got = []
run('ExtChain 9')
run('')
check('Enter repeats last line') { $got == [9, 9] }

# Ревью Codex: кавычки, вложенный run, продолжение цепочки после приглашения
$got = []
T.unregister('ExtLen')
T.register(id: 'ExtLen', plugin: 'Test', params: [{ key: :len, type: :length }]) { |a| $got << a[:len].to_f.round(3); nil }
run(%q(ExtLen 3'6"))
check('feet and inches survive the lexer') { $got == [42.0] }
T.unregister('ExtStr')
T.register(id: 'ExtStr', plugin: 'Test', params: [{ key: :s, type: :string }]) { |a| $got << a[:s]; nil }
$got = []
run('ExtStr s="Door 900"; ExtStr "a;b"')
check('quoted strings') { $got == ['Door 900', 'a;b'] }
lines = run('ExtStr "open')
check('unclosed quote -> error') { errors(lines) == ['Unclosed quote'] }

$got = []
T.unregister('ExtOuter')
T.register(id: 'ExtOuter', plugin: 'Test') { $got << :outer; T.run('ExtChain 5'); nil }
run('ExtOuter; ExtChain 6')
check('nested run goes before the tail') { $got == [:outer, 5, 6] }
check('nested run not in history') { S.history.last == 'ExtOuter; ExtChain 6' }

$got = []
T.unregister('ExtAsk')
T.register(id: 'ExtAsk', plugin: 'Test') do
  T.prompt('Name') { |i| $got << i.text; T.prompt(nil) }
  nil
end
run('ExtAsk; ExtChain 7')
check('chain waits for plugin prompt') { $got == [] && S.prompt_state[:text] == 'Name' }
run('Bob')
check('chain resumes after prompt') { $got == ['Bob', 7] && !S.busy? }
run('ExtAsk; ExtChain 8')
S.cancel
check('cancel of plugin prompt drops the chain') { $got == ['Bob', 7, nil] && !S.busy? }

# Мост: заглушки копят команды, терминал разбирает очередь
bridge = File.read(File.join(T::PLUGIN_PATH, 'terminal_bridge.rb'), encoding: 'utf-8')
sandbox = Module.new
sandbox.module_eval(bridge.gsub('module BACommunity', 'module Ns'))
stub = sandbox.const_get(:Ns).const_get(:Terminal)
check('stub register queues') { stub.register(id: 'Queued', plugin: 'P') { 1 } == true && stub.instance_variable_get(:@queue).size == 1 }
check('stub other calls return false') { stub.available? == false && stub.prompt('x') == false && stub.message('m') == false && stub.run('Top') == false && stub.version.nil? }
check('stub unregister drops queued command') { stub.unregister('queued') == false && stub.instance_variable_get(:@queue).empty? }
check('real terminal skips stub') do
  before = T.method(:register).source_location
  eval(bridge, TOPLEVEL_BINDING)
  T.method(:register).source_location == before && T.available?
end

%w[ExtTest ExtLambda0 ExtFail ExtRaise ExtChain ExtReq ExtLen ExtStr ExtOuter ExtAsk].each { |id| T.unregister(id) }
S.history.replace($saved_history)
T::Library.write_json('history.json', $saved_history)
fails = $checks.reject { |c| c[0] == 'PASS' }
puts $checks.map { |c| c.join('  ') }
puts "#{$checks.size - fails.size}/#{$checks.size} passed"
nil
