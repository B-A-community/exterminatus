"""Собрать dist/exterminatus-<версия>.rbz из src/ (rbz — zip, пути с прямыми слэшами).

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
