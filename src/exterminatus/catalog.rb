# frozen_string_literal: true

require 'json'
require 'zlib'
require 'rubygems' # Gem::Version — и в SketchUp, и в GitHub Actions

module BACommunity
  module Terminal
    # Каталог наших плагинов: какие версии вышли и где их скачать. Чистый
    # Ruby без SketchUp: этот же файл собирает catalog.json в GitHub Actions
    # (tools/build_catalog.rb).
    #
    # Плагины находятся сами: любой публичный репозиторий B-A-community, у
    # которого есть релиз 1.0 или новее с плагином SketchUp (.rbz или zip с
    # .rbz внутри). Имя расширения и папка берутся из самого пакета.
    # plugins.json только уточняет: порядок, описания, «hidden» (не
    # показывать) и «retired» (выведен из обращения).
    #
    # Ассеты релиза — «RALNCS-1.0-rus.zip» (внутри .rbz и PDF) или сразу
    # «*.rbz». Язык — по суффиксу -rus/-ru/-eng/-en, без суффикса — для
    # любого языка.
    module Catalog
      FORMAT = 1
      ORG = 'B-A-community'
      KEEP_RELEASES = 5
      # Найденный сам плагин попадает в список с этой версии.
      MIN_DISCOVERED = '1.0'
      # Тема репозитория, которая прячет его из списка.
      IGNORE_TOPIC = 'exterminatus-ignore'
      LANGS = { 'rus' => 'ru', 'ru' => 'ru', 'eng' => 'en', 'en' => 'en' }.freeze
      # Имя папки или id: без «.» и «..», без разделителей пути.
      SAFE_NAME = /\A(?!\.{1,2}\z)[A-Za-z0-9._-]+\z/.freeze
      REPO = %r{\AB-A-community/[A-Za-z0-9._-]+\z}i.freeze
      # Сайт плагинов: у каждого своя страница с описанием и отзывами.
      SITE = 'https://pachka.space/'
      SITE_API = 'https://pachka.space/wp-json/wp/v2/patchka_plugin?per_page=100'
      # Страница или её вкладка (#comments-panel).
      PAGE = %r{\Ahttps://pachka\.space/[A-Za-z0-9/_-]*(?:#[A-Za-z0-9_-]+)?\z}.freeze

      class << self
        # plugins.json целиком: plugins (уточнения и порядок), hidden, retired.
        def config(path = File.join(__dir__, 'plugins.json'))
          raw = JSON.parse(File.read(path, encoding: 'utf-8'))
          { 'plugins' => Array(raw['plugins']), 'hidden' => Array(raw['hidden']).map(&:to_s),
            'retired' => Array(raw['retired']) }
        end

        # Уточнённые плагины (у них уже известны extension и folder).
        def plugins(path = File.join(__dir__, 'plugins.json'))
          config(path)['plugins']
        end

        def hidden?(repo, cfg = config)
          cfg['hidden'].any? { |r| r.casecmp?(repo.to_s) }
        end

        # → причина или nil
        def retired(repo, cfg = config)
          item = cfg['retired'].find { |r| r['repo'].to_s.casecmp?(repo.to_s) }
          item && (item['reason'].to_s.empty? ? 'No longer supported' : item['reason'].to_s)
        end

        # plugin — запись (уточнение или найденный), releases — ответ GitHub
        # /repos/{repo}/releases. min: — отбросить релизы старше этой версии.
        def entry(plugin, releases, min: nil)
          list = Array(releases).reject { |r| r['draft'] || r['prerelease'] }
                                .map { |r| release(r) }.compact
          list = list.reject { |r| compare(r['version'], min).negative? } if min
          list = list.sort_by { |r| version_key(r['version']) }.reverse.first(KEEP_RELEASES)
          plugin.merge('releases' => list)
        end

        def build(entries)
          { 'format' => FORMAT, 'generated' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), 'plugins' => entries }
        end

        # Релиз GitHub → { version, tag, date, notes, assets: { 'ru' => {...} } } или nil.
        def release(gh)
          assets = {}
          versions = []
          Array(gh['assets']).each do |a|
            name = a['name'].to_s
            next unless name.match?(/\.(zip|rbz)\z/i)

            lang = name[/-(rus|ru|eng|en)\.(?:zip|rbz)\z/i, 1]
            key = lang ? LANGS[lang.downcase] : 'any'
            versions << name[/-(\d+(?:\.\d+)+)(?:-|\.)/, 1]
            digest = a['digest'].to_s.sub(/\Asha256:/, '')
            assets[key] = { 'name' => name, 'url' => a['browser_download_url'], 'size' => a['size'],
                            'sha256' => digest.empty? ? nil : digest }
          end
          return nil if assets.empty?

          tag = gh['tag_name'].to_s
          version = versions.compact.first || tag.sub(/\Av/i, '')
          { 'version' => version, 'tag' => tag, 'date' => gh['published_at'].to_s[0, 10],
            'notes' => gh['body'].to_s.strip[0, 2000], 'assets' => assets }
        end

        # Что внутри пакета: { 'extension' => имя в Extension Manager,
        # 'folder' => папка плагина } или nil, если это не плагин SketchUp или
        # определить нельзя (несколько расширений, имя собирается выражением).
        # name — имя ассета (.rbz или .zip, в котором лежит .rbz).
        def inspect_package(data, name)
          files = Unzip.entries(data)
          unless name.to_s.downcase.end_with?('.rbz')
            rbz = files.keys.find { |n| n.downcase.end_with?('.rbz'.b) }
            if rbz
              data = Unzip.read(data, files[rbz])
              files = Unzip.entries(data)
            end
          end
          names = files.keys.map { |n| n.dup.force_encoding('UTF-8').scrub }
          dirs = names.select { |n| n.include?('/') }.map { |n| n.split('/').first }.uniq
          texts = {}
          files.each do |n, e|
            next unless n.end_with?('.rb'.b)

            texts[n.dup.force_encoding('UTF-8').scrub] = Unzip.read(data, e).force_encoding('UTF-8').scrub
          end
          found = texts.filter_map do |path, text|
            next if path.include?('/')

            m = text.match(/SketchupExtension\.new\(\s*(?:(['"])((?:(?!\1).)*)\1|([A-Z][A-Za-z0-9_]*))\s*,\s*([^)\n]*)/m) or next
            loader = File.basename(path, '.rb')
            folder = folder_of(m[4], loader, dirs)
            ext = m[2] ? static(m[2]) : constant(m[3], text, texts.select { |p, _| folder && p.start_with?("#{folder}/") })
            next if ext.to_s.strip.empty? || folder.nil?

            { 'extension' => ext, 'folder' => folder }
          end
          # Два расширения в одном пакете — неоднозначно, такой плагин описывают в plugins.json.
          found.size == 1 ? found.first : nil
        rescue StandardError
          nil
        end

        # Страницы сайта (ответ WordPress API) → { 'ralncs' => 'https://pachka.space/plugins/ral-ncs/' }.
        # Страница сопоставляется с репозиторием по имени без знаков: ral-ncs ↔ ralncs.
        def site_pages(posts)
          Array(posts).each_with_object({}) do |post, map|
            link = post.is_a?(Hash) ? post['link'].to_s : ''
            next unless link.match?(PAGE) && post['status'] == 'publish'

            map[key(post['slug'])] ||= link
          end
        end

        # Страница плагина: явно заданная (page в plugins.json) или найденная по имени репозитория.
        def page_for(plugin, pages)
          given = plugin['page'].to_s
          return given if given.match?(PAGE)

          pages[key(plugin['repo'].to_s.split('/').last)]
        end

        def key(name)
          name.to_s.downcase.gsub(/[^a-z0-9]/, '')
        end

        # Сравнение версий: «1.0» == «1.0.0» < «1.1».
        def compare(a, b)
          version_key(a) <=> version_key(b)
        end

        def version_key(v)
          Gem::Version.new(v.to_s.sub(/\Av/i, '').strip)
        rescue ArgumentError
          Gem::Version.new('0')
        end

        private

        # NAME = 'area counter' в загрузчике или в файлах папки плагина.
        def constant(name, loader, others)
          [loader, *others.values].each do |text|
            m = text.match(/\b#{name}\s*=\s*(['"])((?:(?!\1).)*)\1/) or next
            return static(m[2])
          end
          nil
        end

        # Только постоянная строка: «Tool #{VERSION}» или с экранированием
        # определить без исполнения нельзя — тогда nil.
        def static(text)
          text.include?('#{') || text.include?('\\') ? nil : text
        end

        # Папка плагина: из пути загрузки («ralncs/main», File.join('area_counter',
        # 'main.rb')), иначе по имени загрузчика; обязательно есть в архиве.
        def folder_of(path_arg, loader, dirs)
          literal = path_arg.to_s[/\A\s*(?:File\.join\(\s*)?(['"])([^'"\/\\]+)/, 2]
          candidate = [literal, loader].compact.find { |d| dirs.include?(d) }
          candidate ||= dirs.first if dirs.size == 1
          candidate&.match?(SAFE_NAME) ? candidate : nil
        end
      end

      # Чтение zip без сторонних библиотек: оглавление и распаковка записи.
      module Unzip
        class << self
          # → { имя (байты) => [смещение локального заголовка, метод, сжатый размер] }
          def entries(data)
            data = data.b
            eocd = data.rindex("PK\x05\x06".b) or raise 'not a zip archive'
            count = data[eocd + 10, 2].unpack1('v')
            offset = data[eocd + 16, 4].unpack1('V')
            raise 'zip64 archives are not supported' if count == 0xFFFF || offset == 0xFFFFFFFF

            list = {}
            count.times do
              raise 'broken zip archive' unless data[offset, 4] == "PK\x01\x02".b

              method, = data[offset + 10, 2].unpack('v')
              csize = data[offset + 20, 4].unpack1('V')
              name_len, extra_len, comment_len = data[offset + 28, 6].unpack('vvv')
              local = data[offset + 42, 4].unpack1('V')
              # Имена — байты: кодировка в архиве бывает любая.
              name = data[offset + 46, name_len]
              list[name] = [local, method, csize]
              offset += 46 + name_len + extra_len + comment_len
            end
            list
          end

          def read(data, entry)
            data = data.b
            local, method, csize = entry
            raise 'broken zip archive' unless data[local, 4] == "PK\x03\x04".b

            name_len, extra_len = data[local + 26, 4].unpack('vv')
            raw = data[local + 30 + name_len + extra_len, csize]
            case method
            when 0 then raw
            when 8 then Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)
            else raise "unsupported zip compression #{method}"
            end
          end
        end
      end
    end
  end
end
