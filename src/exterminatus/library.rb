# frozen_string_literal: true

require 'json'
require 'fileutils'

module BACommunity
  module Terminal
    # Макросы (Define Fence "Beam; PathCopy 300") и пресеты команд
    # (PathCopy preset=Забор). Хранятся в одном файле library.json, его можно
    # выгрузить и отдать коллеге (LibraryExport / LibraryImport).
    module Library
      MACRO_PLUGIN = 'Macros'
      PLACEHOLDER = /\$(\d)/.freeze

      class << self
        attr_writer :path

        def path
          @path ||= begin
            base = Sketchup.platform == :platform_win ? ENV['APPDATA'].to_s : File.join(Dir.home, 'Library', 'Application Support')
            File.join(base, 'BACommunity', 'Exterminatus', 'library.json')
          end
        end

        def data
          @data ||= read(path) || { 'macros' => {}, 'presets' => {} }
        end

        # Перечитать файл (после смены path в тестах).
        def reload
          Registry.all.select { |c| c.plugin == MACRO_PLUGIN }.each { |c| Registry.remove(c.id) }
          @data = nil
          register_macros
        end

        # ---------- макросы ----------

        def macros
          data['macros']
        end

        # → [сообщение, nil] или [nil, ошибка]
        def define(name, text)
          name = name.to_s.strip
          name = name[0].upcase + name[1..] unless name.empty?
          return [nil, "macro name must be Latin letters and digits, e.g. Fence: #{name.inspect}"] unless name.match?(ID_PATTERN)
          return [nil, 'macro text is empty'] if text.to_s.strip.empty?

          existing = Registry.find(name)
          if existing && existing.plugin != MACRO_PLUGIN
            return [nil, "#{name} is already a command (#{existing.plugin}); choose another name"]
          end

          first = text.to_s.split(/[\s;]/).reject(&:empty?).first.to_s
          return [nil, "#{name} cannot call itself"] if first.casecmp?(name)

          Registry.remove(existing.id) if existing
          macros.delete_if { |k, _| k.casecmp?(name) }
          macros[name] = text.to_s.strip
          save
          register_macro(name, macros[name])
          ["#{name} = #{macros[name]}", nil]
        end

        def undefine(name)
          key = macros.keys.find { |k| k.casecmp?(name.to_s) } or return [nil, "no macro #{name}"]

          macros.delete(key)
          save
          Registry.remove(key)
          ["#{key} removed", nil]
        end

        def register_macros
          macros.each { |name, text| register_macro(name, text) }
        end

        # ---------- пресеты ----------

        def presets(cmd_id)
          data['presets'].find { |k, _| k.casecmp?(cmd_id.to_s) }&.last || {}
        end

        # Запомненные значения команды под именем.
        def save_preset(cmd, name, values)
          name = name.to_s.strip
          return [nil, 'preset name is empty'] if name.empty?

          stored = {}
          cmd.params.each do |p|
            next unless p.remember? && values.key?(p.key)

            stored[p.key.to_s] = encode(p, values[p.key])
          end
          return [nil, "#{cmd.id} has no parameters to save"] if stored.empty?

          table = (data['presets'][cmd.id] ||= {})
          table.delete_if { |k, _| k.casecmp?(name) }
          table[name] = stored
          save
          ["#{cmd.id} preset #{name}: #{describe(cmd, stored)}", nil]
        end

        def delete_preset(cmd, name)
          table = data['presets'][cmd.id] || {}
          key = table.keys.find { |k| k.casecmp?(name.to_s) } or return [nil, "#{cmd.id} has no preset #{name}"]

          table.delete(key)
          data['presets'].delete(cmd.id) if table.empty?
          save
          ["#{cmd.id} preset #{key} removed", nil]
        end

        # → [{ key => значение }, nil] или [nil, ошибка]
        def preset_values(cmd, name)
          table = presets(cmd.id)
          key = table.keys.find { |k| k.casecmp?(name.to_s.strip) }
          unless key
            known = table.keys
            hint = known.any? ? " Presets: #{known.join(', ')}" : " Save one with PresetSave #{cmd.id} <name>"
            return [nil, "#{cmd.id} has no preset #{name}.#{hint}"]
          end

          values = {}
          table[key].each do |k, v|
            p = cmd.param(k) or next
            values[p.key] = decode(p, v)
          end
          [values, nil]
        end

        def describe(cmd, stored)
          stored.map do |k, v|
            p = cmd.param(k)
            p ? "#{p.name}=#{p.format(decode(p, v))}" : "#{k}=#{v}"
          end.join(' ')
        end

        # ---------- файл ----------

        def export(file)
          FileUtils.mkdir_p(File.dirname(file))
          File.write(file, JSON.pretty_generate(data), encoding: 'utf-8')
          "Library saved to #{file}: #{macros.size} macros, #{preset_count(data)} presets"
        end

        # Чужие макросы и пресеты добавляются; с тем же именем — заменяются.
        def import(file)
          incoming = read(file) or return [nil, "cannot read #{file}"]

          skipped = []
          incoming['macros'].each do |name, text|
            _msg, err = define(name, text)
            skipped << "#{name} (#{err})" if err
          end
          incoming['presets'].each do |cmd_id, table|
            mine = (data['presets'][cmd_id] ||= {})
            table.each { |name, values| mine[name] = values }
          end
          save
          msg = "Imported #{incoming['macros'].size - skipped.size} macros, #{preset_count(incoming)} presets"
          msg += "; skipped: #{skipped.join(', ')}" if skipped.any?
          [msg, nil]
        end

        private

        def register_macro(name, text)
          count = text.scan(PLACEHOLDER).flatten.map(&:to_i).max.to_i
          params = (1..count).map { |i| { key: :"a#{i}", name: "A#{i}", label: "Value $#{i}", type: :string } }
          spec = { id: name, plugin: MACRO_PLUGIN, description: text, params: params }
          run = lambda do |args|
            line = text.gsub(PLACEHOLDER) { args[:"a#{Regexp.last_match(1)}"].to_s }
            Session.run_line(line)
            nil
          end
          _cmd, err = Registry.add(spec, run)
          warn "Exterminatus: macro #{err}" if err
        end

        def read(file)
          return nil unless File.exist?(file)

          raw = JSON.parse(File.read(file, encoding: 'utf-8'))
          return nil unless raw.is_a?(Hash)

          { 'macros' => raw['macros'].is_a?(Hash) ? raw['macros'] : {},
            'presets' => raw['presets'].is_a?(Hash) ? raw['presets'] : {} }
        rescue JSON::ParserError, SystemCallError
          nil
        end

        def save
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, JSON.pretty_generate(data), encoding: 'utf-8')
        rescue SystemCallError => e
          Session.emit(:error, "cannot save #{path}: #{e.message}")
        end

        def preset_count(d)
          d['presets'].values.sum(&:size)
        end

        # Длины — в дюймах, векторы — тремя числами.
        def encode(param, v)
          case param.type
          when :length, :number, :angle then v.to_f
          when :integer then v.to_i
          when :bool then v ? true : false
          when :vector, :point then v.to_a.map(&:to_f)
          when :scale then Array(v).map(&:to_f)
          else v.to_s
          end
        end

        def decode(param, v)
          case param.type
          when :length then v.to_f.to_l
          when :vector then Geom::Vector3d.new(*v)
          when :point then Geom::Point3d.new(*v)
          else v
          end
        end
      end
    end
  end
end
