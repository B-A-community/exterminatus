"""Проверки, которым нужен цикл сообщений SketchUp между вызовами моста:
цепочка с отложенным send_action и повторное открытие окон.
Запуск: python test/live_async.py"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bridge import run as bridge  # noqa: E402


def rb(code):
    res = bridge(code)
    if 'error' in res:
        raise RuntimeError(res['error'])
    out = res.get('result')
    if out in (None, 'nil'):
        return None
    value = json.loads(out)
    return json.loads(value) if isinstance(value, str) else value


results = []


def ok(name, cond, note=''):
    results.append(('PASS' if cond else 'FAIL', name, str(note)))


# 1. Hide; SelectNone — Hide идёт через send_action и должен успеть до SelectNone.
rb("""m=Sketchup.active_model; m.select_tool(nil); m.close_active while m.active_path
g=m.entities.add_group; g.name='EXT_SANDBOX'
box=g.entities.add_group; box.entities.add_face([0,0,0],[100,0,0],[100,100,0],[0,100,0])
m.active_path=[g]; m.selection.clear; m.selection.add(box); nil.to_json""")
in_sandbox = rb("p=Sketchup.active_model.active_path; (!p.nil? && p.first.name=='EXT_SANDBOX').to_json")
if in_sandbox:
    rb("BACommunity::Terminal::Session.submit('Hide; SelectNone'); nil.to_json")
    time.sleep(1)
    state = rb("m=Sketchup.active_model; [m.active_entities.grep(Sketchup::Group).first.hidden?, m.selection.size].to_json")
    ok('Hide; SelectNone keeps order', state == [True, 0], state)
else:
    ok('sandbox guard', False)
rb("m=Sketchup.active_model; m.close_active while m.active_path; "
   "g=m.entities.grep(Sketchup::Group).find{|x| x.name=='EXT_SANDBOX'}; g.erase! if g; nil.to_json")

# Цепочка ждёт отложенное действие: ExtMode видит стиль, включённый перед ним.
rb("""T=BACommunity::Terminal; T.unregister('ExtMode'); $modes=[]
T.register(id: 'ExtMode', plugin: 'Test') { $modes << Sketchup.active_model.rendering_options['RenderMode']; nil }
Sketchup.active_model.rendering_options['RenderMode']=0
T::Session.submit('Monochrome; ExtMode; HiddenLine; ExtMode'); nil.to_json""")
time.sleep(1.5)
modes = rb("m=$modes; BACommunity::Terminal.unregister('ExtMode'); Sketchup.send_action('renderTextures:'); m.to_json")
ok('chain waits for send_action', modes == [5, 1], modes)

# 2. Окно открывается повторно и снова получает колбэки (ready → @state).
W = "BACommunity::Terminal::Window"
for mode, opener in (('popup', 'open_popup'), ('bar', 'open_bar')):
    for attempt in (1, 2):
        rb("%s.%s; nil.to_json" % (W, opener))
        time.sleep(1.5)
        ready = rb("%s.instance_variable_get(:@state).key?(:%s).to_json" % (W, mode))
        ok('%s opens with callbacks (#%d)' % (mode, attempt), ready)
        rb("%s.close(:%s); nil.to_json" % (W, mode))
        time.sleep(0.5)

# 3. Команда, набранная в окне, доходит до Ruby (submit) и popup закрывается.
rb("%s.open_popup; nil.to_json" % W)
time.sleep(1.5)
rb("%s.instance_variable_get(:@dialogs)[:popup].execute_script("
   "\"var i=document.getElementById('input'); i.value='Iso'; "
   "i.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter'}));\"); nil.to_json" % W)
time.sleep(1.5)
state = rb("[BACommunity::Terminal::Session.history.last, %s.visible?(:popup)].to_json" % W)
ok('popup submit reaches Ruby and closes', state == ['Iso', False], state)

for r in results:
    print('  '.join(r))
print('%d/%d passed' % (sum(r[0] == 'PASS' for r in results), len(results)))
