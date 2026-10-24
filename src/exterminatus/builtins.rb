# frozen_string_literal: true

module BACommunity
  module Terminal
    # Стандартные команды SketchUp. Где у SketchUp есть действие
    # (Sketchup.send_action), вызываем его — так команда ведёт себя ровно как
    # кнопка. Где действия нет, повторяем пункт меню через Ruby API в одном шаге
    # отмены. Синонимы — стандартные клавиши SketchUp (L, R, P, M…).
    module Builtins
      PLUGIN = 'SketchUp'

      # id, синонимы, описание, действие
      ACTIONS = [
        # Рисование
        ['Freehand',         %w[],         'Draw freehand curves',                         'selectFreehandTool:'],
        ['RotatedRectangle', %w[Rect3],    'Draw a rectangle at any angle by 3 points',    'selectRectangle3PointTool:'],
        ['Polygon',          %w[Poly],     'Draw regular polygons',                        'selectPolygonTool:'],
        ['Arc',              %w[A],        'Draw an arc by endpoints and bulge',           'selectArcTool:'],
        ['ArcCenter',        %w[],         'Draw an arc by center, radius and end point',  'selectArc3PointTool:'],
        ['Pie',              %w[],         'Draw a pie-shaped face',                       'selectArc3PointPieTool:'],
        ['Text',             %w[],         'Insert text with a leader',                    'selectTextTool:'],
        ['Text3D',           %w[],         'Insert 3D text',                               'select3dTextTool:'],
        ['Dimension',        %w[Dim],      'Create linear dimensions',                     'selectDimensionTool:'],
        ['Tape',             %w[T Measure], 'Measure distances, create guides',            'selectMeasureTool:'],
        ['Protractor',       %w[],         'Measure angles, create angled guides',         'selectProtractorTool:'],
        ['Axes',             %w[],         'Move or reorient the drawing axes',            'selectAxisTool:'],
        ['SectionPlane',     %w[Section],  'Place a section plane',                        'selectSectionPlaneTool:'],
        # Правка
        ['Select',           %w[Sel],      'Selection tool',                               'selectSelectionTool:'],
        ['Lasso',            %w[],         'Lasso selection tool',                         'selectLassoSelectionTool:'],
        ['Erase',            %w[E],        'Erase, hide, soften or smooth edges',          'selectEraseTool:'],
        ['Paint',            %w[B],        'Paint bucket',                                 'selectPaintTool:'],
        ['TagTool',          %w[],         'Apply tags to entities by clicking',           'selectTagTool:'],
        ['Flip',             %w[],         'Flip or mirror selected entities',             'selectFlipTool:'],
        ['FollowMe',         %w[],         'Extrude a face along a path',                  'selectExtrudeTool:'],
        # Камера
        ['Orbit',            %w[O],        'Orbit the camera',                             'selectOrbitTool:'],
        ['Pan',              %w[H],        'Pan the camera',                               'selectDollyTool:'],
        ['Zoom',             %w[Z],        'Zoom the camera',                              'selectZoomTool:'],
        ['ZoomWindow',       %w[ZW],       'Zoom to a window',                             'selectZoomWindowTool:'],
        ['ZoomExtents',      %w[ZE],       'Zoom to the whole model',                      'viewZoomExtents:'],
        ['PreviousView',     %w[],         'Return to the previous camera view',           'viewUndo:'],
        ['PositionCamera',   %w[],         'Place the camera at eye height',               'selectPositionCameraTool:'],
        ['LookAround',       %w[],         'Look around from a fixed point',               'selectTurnTool:'],
        ['Walk',             %w[],         'Walk through the model',                       'selectWalkTool:'],
        ['Top',              %w[],         'Standard view: top',                           'viewTop:'],
        ['Bottom',           %w[],         'Standard view: bottom',                        'viewBottom:'],
        ['Front',            %w[],         'Standard view: front',                         'viewFront:'],
        ['Back',             %w[],         'Standard view: back',                          'viewBack:'],
        ['Left',             %w[],         'Standard view: left',                          'viewLeft:'],
        ['Right',            %w[],         'Standard view: right',                         'viewRight:'],
        ['Iso',              %w[],         'Standard view: isometric',                     'viewIso:'],
        # Стиль
        ['Wireframe',        %w[],         'Face style: wireframe',                        'renderWireframe:'],
        ['HiddenLine',       %w[],         'Face style: hidden line',                      'renderHiddenLine:'],
        ['Shaded',           %w[],         'Face style: shaded',                           'renderShaded:'],
        ['ShadedTextures',   %w[Textured], 'Face style: shaded with textures',             'renderTextures:'],
        ['Monochrome',       %w[],         'Face style: monochrome',                       'renderMonochrome:'],
        ['ToggleAxes',       %w[],         'Show or hide model axes',                      'viewShowAxes:'],
        ['ToggleGuides',     %w[],         'Show or hide guides',                          'viewShowGuides:'],
        ['ToggleHidden',     %w[],         'Show or hide hidden geometry',                 'viewShowHiddenGeometry:'],
        ['ToggleHiddenObjects', %w[],      'Show or hide hidden groups and components',    'viewShowHiddenObjects:'],
        # Правка
        ['Undo',             %w[],         'Undo',                                         'editUndo:'],
        ['Redo',             %w[],         'Redo',                                         'editRedo:'],
        ['CopyToClipboard',  %w[CopyClip], 'Copy selection to the clipboard',              'copy:'],
        ['Cut',              %w[],         'Cut selection',                                'cut:'],
        ['Paste',            %w[],         'Paste with the Move tool',                     'paste:'],
        # Сцены
        ['SceneAdd',         %w[],         'Add a scene',                                  'pageAdd:'],
        ['SceneNext',        %w[],         'Go to the next scene',                         'pageNext:'],
        ['ScenePrevious',    %w[ScenePrev], 'Go to the previous scene',                    'pagePrevious:'],
        # Файл и окна
        ['New',              %w[],         'New model',                                    'newDocument:'],
        ['Open',             %w[],         'Open a model',                                 'openDocument:'],
        ['Save',             %w[],         'Save the model',                               'saveDocument:'],
        ['Print',            %w[],         'Print the model',                              'printDocument:'],
        ['RubyConsole',      %w[],         'Show the Ruby console',                        'showRubyPanel:'],
        ['ExtensionManager', %w[],         'Open the Extension Manager',                   'showExtensionManager:']
      ].freeze

      class << self
        def register_all
          ACTIONS.each do |id, aliases, description, action|
            add(id, aliases, description) { send_action(id, action) }
          end
          register_ruby
          register_modify
          register_draw
        end

        private

        def add(id, aliases, description, params = [], preview: nil, repeat: nil, &run)
          spec = { id: id, plugin: PLUGIN, description: description, aliases: aliases, params: params,
                   preview: preview, repeat: repeat }
          _cmd, err = Registry.add(spec, run, builtin: true)
          warn "Exterminatus: #{err}" if err
        end

        def send_action(id, action)
          return { ok: false, message: 'not available in this SketchUp version' } unless Sketchup.send_action(action)

          :deferred
        end

        def model
          Sketchup.active_model
        end

        def selection
          model.selection
        end

        # Шаг отмены с подписью команды; ошибка откатывает шаг целиком.
        def operation(name)
          model.start_operation(name, true)
          res = yield
          model.commit_operation
          res
        rescue StandardError
          model.abort_operation
          raise
        end

        def need_selection(kind = Sketchup::Drawingelement)
          items = selection.grep(kind)
          return items unless items.empty?

          nil
        end

        def instances
          selection.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        end

        def toggle_rendering(key, label)
          ro = model.rendering_options
          ro[key] = !ro[key]
          "#{label} #{ro[key] ? 'on' : 'off'}"
        end

        def set_projection(perspective)
          model.active_view.camera.perspective = perspective
          nil
        end

        # ---------- команды через Ruby API ----------

        def register_ruby
          add('ZoomSelected', %w[ZS], 'Zoom to the selection') do
            next({ ok: false, message: "select something first" }) if selection.empty?

            model.active_view.zoom(selection)
            nil
          end

          add('Perspective', %w[], 'Camera: perspective projection') { set_projection(true) }
          add('Parallel', %w[Ortho], 'Camera: parallel projection') { set_projection(false) }

          add('ToggleXRay', %w[XRay], 'X-ray face style on or off') { toggle_rendering('ModelTransparency', 'X-ray') }
          add('ToggleBackEdges', %w[], 'Back edges on or off') { toggle_rendering('DrawBackEdges', 'Back edges') }
          add('ToggleSectionPlanes', %w[], 'Show or hide section planes') do
            toggle_rendering('DisplaySectionPlanes', 'Section planes')
          end
          add('ToggleSectionCuts', %w[], 'Show or hide section cuts') do
            toggle_rendering('DisplaySectionCuts', 'Section cuts')
          end
          add('ToggleFog', %w[Fog], 'Fog on or off') { toggle_rendering('DisplayFog', 'Fog') }
          add('ToggleShadows', %w[Shadows], 'Shadows on or off') do
            info = model.shadow_info
            info['DisplayShadows'] = !info['DisplayShadows']
            "Shadows #{info['DisplayShadows'] ? 'on' : 'off'}"
          end

          # pageDelete: в SketchUp 2024 молча ничего не делает; обновление сцены
          # тоже через API, чтобы ответить, какая сцена обновлена.
          add('SceneUpdate', %w[], 'Update the current scene') do
            page = model.pages.selected_page or next({ ok: false, message: 'no current scene' })

            page.update
            "#{page.name} updated"
          end
          add('SceneDelete', %w[], 'Delete the current scene') do
            page = model.pages.selected_page or next({ ok: false, message: 'no current scene' })

            name = page.name
            model.pages.erase(page)
            "#{name} deleted"
          end

          add('SelectAll', %w[], 'Select everything in the current context') do
            selection.add(model.active_entities.to_a)
            "#{selection.size} selected"
          end
          add('SelectNone', %w[Deselect], 'Clear the selection') do
            selection.clear
            nil
          end
          add('InvertSelection', %w[], 'Invert the selection in the current context') do
            selection.toggle(model.active_entities.to_a)
            "#{selection.size} selected"
          end

          # Правка выделения — синхронно, чтобы цепочка «Hide; SelectNone»
          # шла по порядку (send_action SketchUp выполняет позже).
          add('Delete', %w[Del], 'Delete selection') do
            items = selection.to_a
            next({ ok: false, message: 'select something first' }) if items.empty?

            operation('Erase') { model.active_entities.erase_entities(items) }
            nil
          end
          add('Hide', %w[], 'Hide selection') do
            items = selection.select { |e| e.respond_to?(:hidden=) }
            next({ ok: false, message: 'select something first' }) if items.empty?

            operation('Hide') { items.each { |e| e.hidden = true } }
            nil
          end
          add('Unhide', %w[], 'Unhide selected hidden entities') do
            items = selection.select { |e| e.respond_to?(:hidden?) && e.hidden? }
            next 'Nothing hidden in the selection' if items.empty?

            operation('Unhide') { items.each { |e| e.hidden = false } }
            nil
          end

          add('UnhideAll', %w[], 'Unhide everything in the current context') do
            hidden = model.active_entities.select { |e| e.respond_to?(:hidden?) && e.hidden? }
            next 'Nothing hidden' if hidden.empty?

            operation('Unhide All') { hidden.each { |e| e.hidden = false } }
            "#{hidden.size} unhidden"
          end

          add('Group', %w[], 'Make a group from the selection') do
            items = need_selection or next({ ok: false, message: 'select geometry first' })

            group = operation('Make Group') { model.active_entities.add_group(items) }
            selection.clear
            selection.add(group)
            nil
          end

          add('MakeComponent', %w[], 'Make a component from the selection',
              [{ key: :name, type: :string, default: 'Component', description: 'Definition name' }]) do |args|
            items = need_selection or next({ ok: false, message: 'select geometry first' })

            instance = operation('Make Component') do
              group = model.active_entities.add_group(items)
              inst = group.to_component
              inst.definition.name = model.definitions.unique_name(args[:name].to_s.empty? ? 'Component' : args[:name])
              inst
            end
            selection.clear
            selection.add(instance)
            "Component #{instance.definition.name}"
          end

          add('Explode', %w[], 'Explode selected groups and components') do
            items = instances
            next({ ok: false, message: 'select groups or components' }) if items.empty?

            operation('Explode') { items.each(&:explode) }
            "#{items.size} exploded"
          end

          add('MakeUnique', %w[], 'Make selected components unique') do
            items = selection.grep(Sketchup::ComponentInstance)
            next({ ok: false, message: 'select components' }) if items.empty?

            operation('Make Unique') { items.each(&:make_unique) }
            "#{items.size} made unique"
          end

          add('ReverseFaces', %w[], 'Reverse selected faces') do
            faces = selection.grep(Sketchup::Face)
            next({ ok: false, message: 'select faces' }) if faces.empty?

            operation('Reverse Faces') { faces.each(&:reverse!) }
            "#{faces.size} reversed"
          end


          add('DeleteGuides', %w[], 'Delete all guides in the current context') do
            guides = model.active_entities.select { |e| e.is_a?(Sketchup::ConstructionLine) || e.is_a?(Sketchup::ConstructionPoint) }
            next 'No guides' if guides.empty?

            operation('Delete Guides') { model.active_entities.erase_entities(guides) }
            "#{guides.size} guides deleted"
          end

          add('Purge', %w[], 'Purge unused components, materials, tags and styles') do
            before = counts
            operation('Purge Unused') do
              model.definitions.purge_unused
              model.materials.purge_unused
              model.layers.purge_unused
              model.styles.purge_unused
            end
            after = counts
            parts = before.map { |k, v| "#{v - after[k]} #{k}" }
            "Purged: #{parts.join(', ')}"
          end
        end

        def counts
          { 'components' => model.definitions.count { |d| !d.image? && !d.group? },
            'materials' => model.materials.count,
            'tags' => model.layers.count,
            'styles' => model.styles.count }
        end
      end
    end
  end
end
