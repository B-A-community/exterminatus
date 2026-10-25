# frozen_string_literal: true

require 'json'
require 'rubygems' # Gem::Version — и в SketchUp, и в GitHub Actions

module BACommunity
  module Terminal
    # Каталог наших плагинов: какие версии вышли и где их скачать. Чистый
    # Ruby без SketchUp: этот же файл собирает catalog.json в GitHub Actions
    # (tools/build_catalog.rb).
    #
    # Релиз плагина на GitHub — ассеты вида «RALNCS-1.0-rus.zip» (внутри .rbz и
    # PDF) или сразу «*.rbz». Язык — по суффиксу -rus/-ru/-eng/-en, без
    # суффикса — для любого языка.
    module Catalog
      FORMAT = 1
      KEEP_RELEASES = 5
      LANGS = { 'rus' => 'ru', 'ru' => 'ru', 'eng' => 'en', 'en' => 'en' }.freeze

      class << self
        # Список наших плагинов из plugins.json.
        def plugins(path = File.join(__dir__, 'plugins.json'))
          JSON.parse(File.read(path, encoding: 'utf-8'))['plugins']
        end

        # plugin — запись plugins.json, releases — ответ GitHub
        # /repos/{repo}/releases (массив). → запись каталога.
        def entry(plugin, releases)
          list = Array(releases).reject { |r| r['draft'] || r['prerelease'] }
                                .map { |r| release(r) }.compact
                                .sort_by { |r| version_key(r['version']) }.reverse
                                .first(KEEP_RELEASES)
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

        # Сравнение версий: «1.0» == «1.0.0» < «1.1».
        def compare(a, b)
          version_key(a) <=> version_key(b)
        end

        def version_key(v)
          Gem::Version.new(v.to_s.sub(/\Av/i, '').strip)
        rescue ArgumentError
          Gem::Version.new('0')
        end
      end
    end
  end
end
