"""Живая проверка встроенных команд SketchUp через терминал.

send_action выполняется после возврата из вызова моста, поэтому каждое
действие запускаем одним вызовом, а результат читаем следующим. Геометрия
создаётся только внутри группы-песочницы EXT_SANDBOX, перед каждым шагом
проверяется, что мы всё ещё в ней.
Запуск: python test/live_builtins.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bridge import run as bridge  # noqa: E402


def rb(code):
    res = bridge(code)
    if 'error' in res:
        raise RuntimeError(res['error'])
    # Мост отдаёт inspect значения: строка JSON приходит в кавычках.
    out = res.get('result')
    if out in (None, 'nil'):
        return None
    value = json.loads(out)
    return json.loads(value) if isinstance(value, str) else value


def term(line):
    return rb("S=BACommunity::Terminal::Session; f=S.seq; S.submit(%s); "
              "S.log_after(f).select{|l| l[:kind]=='error'}.map{|l| l[:text]}.to_json" % json.dumps(line))


results = []


def ok(name, cond, note=''):
    results.append(('PASS' if cond else 'FAIL', name, str(note)))


TOOLS = {
    'Line': 'SketchTool', 'Freehand': 'FreehandTool', 'Rectangle': 'RectangleTool',
    'RotatedRectangle': None, 'Circle': 'CircleTool', 'Polygon': 'PolyTool',
    'Arc': None, 'ArcCenter': None, 'Pie': None, 'Text': 'TextTool',
    'Dimension': 'DimensionTool', 'Tape': 'MeasureTool', 'Protractor': 'ProtractorTool',
    'Axes': 'SketchCSTool', 'SectionPlane': 'SectionPlaneTool',
    'Lasso': None, 'Erase': 'EraseTool', 'Paint': 'PaintTool', 'TagTool': None, 'Move': 'MoveTool',
    'Rotate': 'RotateTool', 'Scale': 'ScaleTool', 'Flip': None, 'PushPull': 'PushPullTool',
    'FollowMe': 'ExtrudeTool', 'Offset': 'OffsetTool', 'Orbit': 'CameraOrbitTool', 'Pan': 'CameraDollyTool',
    'Zoom': 'CameraZoomTool', 'ZoomWindow': 'CameraZoomWindowTool', 'PositionCamera': 'PositionCameraTool',
    'LookAround': 'CameraPanTool', 'Walk': 'CameraWalkTool',
}
names = {}
for cmd, expected in TOOLS.items():
    rb("Sketchup.active_model.select_tool(nil); nil.to_json")
    errs = term(cmd)
    name = rb("Sketchup.active_model.tools.active_tool_name.to_json")
    names[cmd] = name
    if errs:
        ok(cmd, False, '; '.join(errs))
    elif expected is None:
        ok(cmd, name != 'SelectionTool', name)
    else:
        ok(cmd, name == expected, name)
rb("Sketchup.active_model.select_tool(nil); nil.to_json")
term('Select')

VIEWS = {'Top': [0, 0, -1], 'Bottom': [0, 0, 1], 'Front': [0, 1, 0], 'Back': [0, -1, 0],
         'Left': [1, 0, 0], 'Right': [-1, 0, 0]}
for cmd, d in VIEWS.items():
    errs = term(cmd)
    got = rb("Sketchup.active_model.active_view.camera.direction.to_a.map{|v| v.round(3)}.to_json")
    ok(cmd, not errs and [round(x) for x in got] == d, got)
term('Iso')
got = rb("Sketchup.active_model.active_view.camera.direction.to_a.map{|v| v.round(3)}.to_json")
ok('Iso', all(abs(x) > 0.1 for x in got), got)

# Текстуры — это RenderMode 2 с флагом Texture.
for cmd, mode in {'Wireframe': [0, None], 'HiddenLine': [1, None], 'Shaded': [2, False],
                  'ShadedTextures': [2, True], 'Monochrome': [5, None]}.items():
    errs = term(cmd)
    got = rb("ro=Sketchup.active_model.rendering_options; [ro['RenderMode'], ro['Texture']].to_json")
    ok(cmd, not errs and got[0] == mode[0] and (mode[1] is None or got[1] == mode[1]), got)
term('ShadedTextures')

TOGGLES = {
    'ToggleAxes': "rendering_options['DisplaySketchAxes']",
    'ToggleGuides': "rendering_options['HideConstructionGeometry']",
    'ToggleHidden': "rendering_options['DrawHidden']",
    'ToggleHiddenObjects': "rendering_options['DrawHiddenObjects']",
    'ToggleXRay': "rendering_options['ModelTransparency']",
    'ToggleBackEdges': "rendering_options['DrawBackEdges']",
    'ToggleSectionPlanes': "rendering_options['DisplaySectionPlanes']",
    'ToggleSectionCuts': "rendering_options['DisplaySectionCuts']",
    'ToggleFog': "rendering_options['DisplayFog']",
    'ToggleShadows': "shadow_info['DisplayShadows']",
}
for cmd, key in TOGGLES.items():
    before = rb("Sketchup.active_model.%s.to_json" % key)
    errs = term(cmd)
    after = rb("Sketchup.active_model.%s.to_json" % key)
    term(cmd)
    back = rb("Sketchup.active_model.%s.to_json" % key)
    ok(cmd, not errs and before != after and back == before, '%s -> %s -> %s' % (before, after, back))

for cmd, persp in {'Parallel': False, 'Perspective': True}.items():
    errs = term(cmd)
    ok(cmd, not errs and rb("Sketchup.active_model.active_view.camera.perspective?.to_json") == persp)

rb("""m=Sketchup.active_model; m.select_tool(nil); m.close_active while m.active_path
g=m.entities.add_group; g.name='EXT_SANDBOX'; e=g.entities
f=e.add_face([0,0,0],[1000.mm,0,0],[1000.mm,1000.mm,0],[0,1000.mm,0]); f.pushpull(-500.mm)
e.add_cline([0,0,0],[1,0,0]); m.active_path=[g]; nil.to_json""")


def guard():
    return rb("p=Sketchup.active_model.active_path; (!p.nil? && p.first.name=='EXT_SANDBOX').to_json")


def count(kind):
    return rb("Sketchup.active_model.active_entities.grep(Sketchup::%s).size.to_json" % kind)


def select_all_in_sandbox():
    rb("s=Sketchup.active_model.selection; s.clear; s.add(Sketchup.active_model.active_entities.to_a); nil.to_json")


def first_hidden():
    return rb("Sketchup.active_model.active_entities.grep(Sketchup::ComponentInstance).first.hidden?.to_json")


steps_ok = True
for step in range(1):
    if not guard():
        steps_ok = False
        break
    term('SelectAll')
    n = rb("Sketchup.active_model.selection.size.to_json")
    ok('SelectAll', n > 10, n)
    term('SelectNone')
    ok('SelectNone', rb("Sketchup.active_model.selection.size.to_json") == 0)
    term('InvertSelection')
    ok('InvertSelection', rb("Sketchup.active_model.selection.size.to_json") == n)
    errs = term('ZoomSelected')
    ok('ZoomSelected', not errs, errs)
    errs = term('DeleteGuides')
    ok('DeleteGuides', not errs and count('ConstructionLine') == 0, errs)
    if not guard():
        steps_ok = False
        break
    rb("s=Sketchup.active_model.selection; s.clear; s.add(Sketchup.active_model.active_entities.grep(Sketchup::Face).first); nil.to_json")
    errs = term('ReverseFaces')
    ok('ReverseFaces', not errs, errs)
    select_all_in_sandbox()
    errs = term('Group')
    ok('Group', not errs and count('Group') == 1, errs)
    errs = term('Explode')
    ok('Explode', not errs and count('Group') == 0, errs)
    select_all_in_sandbox()
    errs = term('MakeComponent name=ExtBox')
    dname = rb("Sketchup.active_model.active_entities.grep(Sketchup::ComponentInstance).first&.definition&.name.to_json")
    ok('MakeComponent', not errs and str(dname).startswith('ExtBox'), dname)
    errs = term('MakeUnique')
    ok('MakeUnique', not errs, errs)
    if not guard():
        steps_ok = False
        break
    errs = term('Hide')
    ok('Hide', not errs and first_hidden(), errs)
    errs = term('UnhideAll')
    ok('UnhideAll', not errs and not first_hidden(), errs)
    errs = term('Undo')
    ok('Undo', not errs and first_hidden(), errs)
    errs = term('Redo')
    ok('Redo', not errs and not first_hidden(), errs)
    if not guard():
        steps_ok = False
        break
    select_all_in_sandbox()
    errs = term('Delete')
    ok('Delete', not errs and rb("Sketchup.active_model.active_entities.size.to_json") == 0, errs)
    term('SelectNone')
    errs = term('ZoomSelected')
    ok('ZoomSelected with empty selection -> error', bool(errs), errs)
if not steps_ok:
    ok('sandbox guard', False, 'left the sandbox, stopped')

rb("m=Sketchup.active_model; m.close_active while m.active_path; "
   "g=m.entities.grep(Sketchup::Group).find{|x| x.name=='EXT_SANDBOX'}; g.erase! if g; nil.to_json")
errs = term('Purge')
ok('Purge', not errs, errs)
pages = rb("Sketchup.active_model.pages.size.to_json")
term('SceneAdd')
ok('SceneAdd', rb("Sketchup.active_model.pages.size.to_json") == pages + 1)
errs = term('SceneUpdate')
ok('SceneUpdate', not errs, errs)
errs = term('SceneDelete')
ok('SceneDelete', not errs and rb("Sketchup.active_model.pages.size.to_json") == pages, errs)
for cmd in ['ZoomExtents', 'PreviousView', 'SceneNext', 'ScenePrevious', 'Copy', 'Cut', 'Unhide']:
    errs = term(cmd)
    ok(cmd + ' runs', not errs, errs)
rb("Sketchup.active_model.select_tool(nil); nil.to_json")

for r in results:
    print('  '.join(r))
print('%d/%d passed' % (sum(r[0] == 'PASS' for r in results), len(results)))
