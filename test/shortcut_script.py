"""Проверка tools/assign_shortcut.ps1 на копии SharedPreferences.json —
без SketchUp: exe указывает на несуществующий файл, ждать нечего.
Запуск: python test/shortcut_script.py"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, 'src', 'exterminatus', 'tools', 'assign_shortcut.ps1')
PREFS = os.path.expandvars(r'%APPDATA%\SketchUp\SketchUp 2024\SketchUp\SharedPreferences.json')
CMD = 'Extensions/Exterminatus/Terminal'
results = []


def ok(name, cond, note=''):
    results.append(('PASS' if cond else 'FAIL', name, str(note)))


def entries(path):
    s = json.load(open(path, encoding='utf-8-sig'))['Windows Only']['Settings']
    return [s['Shortcut_%d' % i] for i in range(1, int(s['Num_Shortcuts']) + 1)], s


def run(prefs, entry):
    job = os.path.join(os.path.dirname(prefs), 'job-%d.json' % time.time_ns())
    json.dump({'prefs': prefs, 'exe': r'C:\nonexistent\SketchUp.exe', 'command': CMD,
               'entry': entry, 'restart': False, 'created': int(time.time())}, open(job, 'w', encoding='utf-8'))
    subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT, '-Job', job], check=False)
    return open(job[:-5] + '.log', encoding='utf-8').read()


tmp = tempfile.mkdtemp()
prefs = os.path.join(tmp, 'SharedPreferences.json')
shutil.copy(PREFS, prefs)
before, _ = entries(prefs)
original = json.load(open(prefs, encoding='utf-8-sig'))

log = run(prefs, '0 0 0 `')
after, settings = entries(prefs)
ok('script finished', log.strip().endswith('done'), log.strip().splitlines()[-1])
ok('one entry for the terminal', [e for e in after if e.endswith(CMD)] == ['0 0 0 ` ' + CMD], [e for e in after if CMD in e])
ok('no other command keeps `', [e for e in after if e.startswith('0 0 0 ` ')] == ['0 0 0 ` ' + CMD])
ok('numbering contiguous', set(k for k in settings if k.startswith('Shortcut_')) == set('Shortcut_%d' % i for i in range(1, len(after) + 1)))
ok('backup written', os.path.exists(prefs + '.exterminatus.bak'))
data = json.load(open(prefs, encoding='utf-8-sig'))
del data['Windows Only']['Settings']
o = dict(original)
o['Windows Only'] = dict(original['Windows Only'])
del o['Windows Only']['Settings']
ok('rest of the file unchanged', data == o)

log = run(prefs, '0 0 1 Space')  # занято Lasso — должно его снять
after, _ = entries(prefs)
ok('reassign replaces old key', [e for e in after if e.endswith(CMD)] == ['0 0 1 Space ' + CMD])
ok('conflicting command unbound', not any(e.startswith('0 0 1 Space ') and not e.endswith(CMD) for e in after))

log = run(prefs, '')
after, _ = entries(prefs)
ok('remove shortcut', not any(e.endswith(CMD) for e in after))

shutil.rmtree(tmp)
for r in results:
    print('  '.join(r))
print('%d/%d passed' % (sum(r[0] == 'PASS' for r in results), len(results)))
sys.exit(0 if all(r[0] == 'PASS' for r in results) else 1)
