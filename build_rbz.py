"""Собрать dist/exterminatus-<версия>.rbz из src/ (rbz — zip, пути с прямыми слэшами)
и dist/exterminatus-plugin-kit-<версия>.zip — набор для авторов плагинов.

Запуск: python build_rbz.py
"""
import os
import re
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, 'src')
consts = open(os.path.join(SRC, 'exterminatus', 'constants.rb'), encoding='utf-8').read()
version = re.search(r"VERSION\s*=\s*'([^']+)'", consts).group(1)
out = os.path.join(ROOT, 'dist', 'exterminatus-%s.rbz' % version)
os.makedirs(os.path.dirname(out), exist_ok=True)

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for folder, _, files in os.walk(SRC):
        for name in sorted(files):
            path = os.path.join(folder, name)
            z.write(path, os.path.relpath(path, SRC).replace(os.sep, '/'))
    names = z.namelist()

print('%s: %d files, %d KB' % (out, len(names), os.path.getsize(out) // 1024))

# Набор для авторов плагинов: мост, инструкции, пример — всё, что кладут в
# проект своего плагина.
kit = os.path.join(ROOT, 'dist', 'exterminatus-plugin-kit-%s.zip' % version)
with zipfile.ZipFile(kit, 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(SRC, 'exterminatus', 'terminal_bridge.rb'), 'terminal_bridge.rb')
    for doc in ('INTEGRATE.md', 'PLUGIN_GUIDE.md'):
        z.write(os.path.join(ROOT, 'docs', doc), 'docs/' + doc)
    example = os.path.join(ROOT, 'examples')
    for folder, _, files in os.walk(example):
        for name in sorted(files):
            path = os.path.join(folder, name)
            z.write(path, os.path.relpath(path, ROOT).replace(os.sep, '/'))
    kit_names = z.namelist()
print('%s: %d files' % (kit, len(kit_names)))
