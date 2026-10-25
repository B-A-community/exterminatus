"""Строка терминала: Backspace мимо поля не уводит страницу «назад» (окно
становилось пустым); закрыть и сразу открыть — строка видна и получает
обновления. Запуск: python test/live_popup_keys.py"""
import sys, time
sys.path.insert(0, r'C:\work\maksar-ruslan\exterminatus\test')
from bridge import run
W = 'BACommunity::Terminal::Window'
def rb(code):
    r = run(code)
    if 'error' in r: raise RuntimeError(r['error'])
    return r.get('result')
res = []
def ok(n, c, note=''): res.append(('PASS' if c else 'FAIL', n, note))
diag = r"""T=BACommunity::Terminal; $diag=nil
unless $diag_hooked == T::Session.method(:option).source_location
  T::Session.singleton_class.alias_method(:option_orig_diag, :option)
  T::Session.define_singleton_method(:option) { |name| name.to_s.start_with?('DIAG') ? ($diag = name) : option_orig_diag(name) }
  $diag_hooked = T::Session.method(:option).source_location
end
T::Window.instance_variable_get(:@dialogs)[:popup]&.execute_script(%q{(function(){ JSCODE })()}); nil"""
def page(js):
    rb(diag.replace('JSCODE', js)); time.sleep(1.5); return rb("$diag.to_s")
rb("%s.close(:popup); %s.open_popup; nil" % (W, W)); time.sleep(2.5)
ok('close + open right away shows the line', rb("%s.visible?(:popup).to_s" % W) == '"true"', rb("%s.visible?(:popup).to_s" % W))
# Фокус на странице (не в поле), Backspace: событие отменено, фокус вернулся в поле.
r = page("document.getElementById('input').blur(); var e=new KeyboardEvent('keydown',{key:'Backspace',bubbles:true,cancelable:true}); document.body.dispatchEvent(e); sketchup.option('DIAG '+e.defaultPrevented+' '+(document.activeElement&&document.activeElement.id)+' '+location.href.slice(-10));")
ok('Backspace outside the field is blocked and focus returns', 'DIAG true input index.html' in r, r)
# В поле Backspace работает как обычно.
r = page("var i=document.getElementById('input'); i.focus(); i.value='Mov'; var e=new KeyboardEvent('keydown',{key:'Backspace',bubbles:true,cancelable:true}); i.dispatchEvent(e); sketchup.option('DIAG '+e.defaultPrevented);")
ok('Backspace inside the field is not blocked', 'DIAG false' in r, r)
rb("%s.sync; nil" % W)
r = page("sketchup.option('DIAG '+(document.querySelector('.terminal')?'ok':'none'));")
ok('new line still gets updates after the old one closed', 'DIAG ok' in r, r)
for x in res: print('  '.join(x))
print('%d/%d passed' % (sum(x[0]=='PASS' for x in res), len(res)))
