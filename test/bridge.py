"""Run Ruby in the live SketchUp through the MCP bridge (127.0.0.1:8080).

Usage: python test/bridge.py file.rb      — eval the file's text in SketchUp
       python test/bridge.py -e "code"    — eval inline ASCII code
The bridge wants ASCII-only POST bodies, so files are read by SketchUp itself.
"""
import json, os, sys, urllib.request
sys.stdout.reconfigure(encoding="utf-8")

def run(code):
    req = urllib.request.Request('http://127.0.0.1:8080/ruby/execute',
                                 data=json.dumps({'code': code}, ensure_ascii=True).encode('ascii'),
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read().decode('utf-8'))

if __name__ == '__main__':
    if sys.argv[1] == '-e':
        code = sys.argv[2]
    else:
        path = os.path.abspath(sys.argv[1]).replace(chr(92), '/')
        code = "eval(File.read(%r, encoding: 'utf-8'), TOPLEVEL_BINDING, %r)" % (path, path)
    res = run(code)
    out = res.get('output') or []
    for line in out:
        print(line)
    if 'error' in res:
        print('ERROR:', res['error'])
        for b in res.get('backtrace') or []:
            print('  ', b)
        sys.exit(1)
    print('=>', res.get('result'))
