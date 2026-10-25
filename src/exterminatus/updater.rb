# frozen_string_literal: true

require 'json'
require 'digest'
require 'zlib'
require 'fileutils'

module BACommunity
  module Terminal
    # Установка и обновление наших плагинов из релизов GitHub (B-A-community).
    #
    # Каталог — catalog.json, его собирает GitHub Actions (tools/build_catalog.rb).
    # Пока каталога нет, Exterminatus сам читает релизы репозиториев из
    # plugins.json через GitHub API. В сами плагины ничего добавлять не нужно:
    # установленная версия — из Extension Manager, язык сборки — из
    # <папка плагина>/lang.rb (LANG = 'ru').
    #
    # Всё сетевое — асинхронно (Sketchup::Http): SketchUp не замирает.
    module Updater
      CATALOG_URL = 'https://raw.githubusercontent.com/B-A-community/exterminatus/catalog/catalog.json'
      API = 'https://api.github.com'
      CHECK_EVERY = 24 * 3600
      TIMEOUT = 120

      @listeners ||= []
      @requests ||= []
      @jobs = {}   # id => { state: :queued | :downloading | :installing | :done | :failed, message: }
      @queue = []

      class << self
        attr_reader :catalog, :error, :checked_at
        # Тесты: разрешить локальные файлы и плагины вне plugins.json. Только в
        # памяти — настройками это не включить.
        attr_accessor :test_mode

        # ---------- каталог ----------

        def catalog_url
          url = Sketchup.read_default(PREFS_KEY, 'catalog_url', '').to_s
          return CATALOG_URL if url.empty? || (!test_mode && !url.start_with?('https://'))

          url
        end

        def catalog_url=(url)
          Sketchup.write_default(PREFS_KEY, 'catalog_url', url.to_s)
        end

        def checking?
          @checking ? true : false
        end

        # Перечитать каталог; блок — когда готово (ошибка — в error).
        def refresh(&done)
          (@waiting ||= []) << done if done
          return if @checking

          @checking = true
          @error = nil
          changed
          get(catalog_url, json: true) do |status, body|
            if status == 200 && (data = parse_catalog(body))
              Library.write_json('catalog_cache.json', data)
              finish_refresh(sanitize(data), nil)
            else
              from_api
            end
          end
        end

        # Каталога нет (ещё не опубликован или GitHub недоступен) — релизы
        # каждого плагина напрямую из GitHub API.
        def from_api
          plugins = Catalog.plugins
          entries = {}
          failed = []
          # Основа — то, что уже знали (каталог или его кэш): найденные сами
          # плагины и статусы retired не теряются, API только обновляет версии.
          known = @catalog || (cached = parse_catalog(JSON.generate(Library.read_json('catalog_cache.json', nil)))) && sanitize(cached)
          before = (known ? known['plugins'] : []).to_h { |p| [p['repo'].to_s.downcase, p] }
          plugins.each do |plugin|
            get("#{API}/repos/#{plugin['repo']}/releases?per_page=20", json: true, api: true) do |status, body|
              releases = status == 200 ? (JSON.parse(body) rescue nil) : nil
              releases = [] if status == 404 # репозитория ещё нет
              old = before[plugin['repo'].downcase]
              if releases.is_a?(Array)
                fresh = Catalog.entry(plugin, releases)
                entries[plugin['id']] = old ? old.merge('releases' => fresh['releases']) : fresh
              else
                # Не ответил — оставить то, что знали, и сказать об этом.
                failed << "#{plugin['name']} (#{status.zero? ? 'no answer' : "HTTP #{status}"})"
                entries[plugin['id']] = old || plugin.merge('releases' => [])
              end
              if entries.size == plugins.size
                if failed.size == plugins.size && known.nil?
                  finish_refresh(nil, "GitHub is not reachable: #{failed.first}")
                else
                  ours = plugins.map { |p| p['repo'].downcase }
                  rest = before.reject { |repo, _| ours.include?(repo) }.values
                  err = if failed.size == plugins.size then "GitHub is not reachable: showing the last known list"
                        elsif failed.any? then "Could not check #{failed.join(', ')}"
                        end
                  data = Catalog.build(plugins.map { |p| entries[p['id']] } + rest)
                  data['hidden'] = known['hidden'] if known
                  finish_refresh(sanitize(data), err)
                end
              end
            end
          end
        end

        # ---------- что установлено ----------

        # Строки для окна и терминала.
        def rows
          return [] unless @catalog

          @catalog['plugins'].map { |p| row(p) }.reject { |r| r[:status] == 'retired' && r[:installed].nil? }
        end

        def row(plugin)
          inst = installed(plugin)
          latest = plugin['releases'].first
          job = @jobs[plugin['id']]
          pending = pending_versions[plugin['id']]
          status = if job && %i[queued downloading installing].include?(job[:state]) then 'busy'
                   elsif job && job[:state] == :failed then 'error'
                   elsif pending then 'restart'
                   elsif plugin['status'] == 'retired' then 'retired'
                   elsif latest.nil? then 'unpublished'
                   elsif inst.nil? then 'missing'
                   else
                     cmp = Catalog.compare(inst[:version], latest['version'])
                     # Новая версия вышла без сборки на языке установленной — не
                     # меняем язык молча.
                     if cmp.negative? && !asset_for(latest, inst[:lang]) then 'nolang'
                     else { -1 => 'update', 0 => 'current', 1 => 'newer' }[cmp]
                     end
                   end
          {
            id: plugin['id'], name: plugin['name'], description: plugin['description'].to_s,
            installed: inst && inst[:version], lang: inst && inst[:lang],
            latest: latest && latest['version'], date: latest && latest['date'], notes: latest && latest['notes'],
            langs: latest ? latest['assets'].keys : [],
            previous: previous_release(plugin)&.dig('version'),
            status: status, message: (job && job[:message]) || (status == 'retired' ? plugin['reason'] : nil), pending: pending
          }
        end

        def installed(plugin)
          ext = Sketchup.extensions.find { |e| e.name.to_s.casecmp?(plugin['extension'].to_s) }
          # Файлы удалили руками — расширение числится до перезапуска, но его нет.
          return nil unless ext && File.exist?(ext.extension_path.to_s)

          { version: ext.version.to_s, lang: lang_of(plugin, ext) }
        end

        def find(name)
          return nil unless @catalog

          q = name.to_s.downcase.strip
          list = @catalog['plugins']
          list.find { |p| p['id'] == q || p['name'].downcase == q } ||
            list.find { |p| p['id'].start_with?(q) || p['name'].downcase.start_with?(q) }
        end

        # Язык для установки нового плагина: как у уже установленных наших,
        # иначе по языку SketchUp. Можно задать (install_lang).
        def install_lang
          chosen = Sketchup.read_default(PREFS_KEY, 'install_lang', '').to_s
          return chosen unless chosen.empty?

          langs = (@catalog ? @catalog['plugins'] : []).map { |p| installed(p)&.dig(:lang) }.compact
          return langs.tally.max_by { |_, n| n }.first if langs.any?

          Sketchup.get_locale.to_s.downcase.start_with?('ru') ? 'ru' : 'en'
        end

        def install_lang=(lang)
          Sketchup.write_default(PREFS_KEY, 'install_lang', lang.to_s)
          changed
        end

        def updates
          rows.select { |r| r[:status] == 'update' }
        end

        # ---------- установка ----------

        # Поставить последнюю (или указанную) версию. version: — откат.
        def install(id, version: nil, lang: nil)
          plugin = find(id) or return "unknown plugin #{id}"
          return "#{plugin['name']} is retired: #{plugin['reason']}" if plugin['status'] == 'retired'
          return "#{plugin['name']} is already in the queue" if @jobs[plugin['id']] && %i[queued downloading installing].include?(@jobs[plugin['id']][:state])

          release = version ? plugin['releases'].find { |r| Catalog.compare(r['version'], version).zero? } : plugin['releases'].first
          return "#{plugin['name']} #{version || ''} is not published".squeeze(' ') unless release

          inst = installed(plugin)
          lang ||= inst&.dig(:lang) || install_lang
          asset = asset_for(release, lang) or return "#{plugin['name']} #{release['version']} has no #{lang.to_s.upcase} build"

          @jobs[plugin['id']] = { state: :queued, message: 'Waiting' }
          @queue << [plugin, release, asset]
          changed
          step
          nil
        end

        def update_all
          list = updates
          list.each { |r| install(r[:id]) }
          list.size
        end

        # Релиз до того, что стоит на диске (поставленное, но не загруженное
        # тоже считается) — для отката.
        def previous_release(plugin)
          current = pending_versions[plugin['id']] || installed(plugin)&.dig(:version)
          return nil unless current

          plugin['releases'].find { |r| Catalog.compare(r['version'], current).negative? }
        end

        def busy?
          !@current.nil? || !@queue.empty? || @jobs.values.any? { |j| %i[queued downloading installing].include?(j[:state]) }
        end

        # Сборка на языке lang (или без языка). nil — такой нет.
        def asset_for(release, lang)
          assets = release['assets']
          return assets['any'] if lang.nil? && assets['any']
          return assets.values.first if lang.nil? && assets.size == 1

          assets[lang.to_s] || assets['any']
        end

        # Поставленное, но ещё не загруженное: id => версия. Пишется в файл —
        # окно помнит о перезапуске и после закрытия.
        def pending_versions
          @pending ||= begin
            data = Library.read_json('pending_updates.json', {})
            data.is_a?(Hash) ? data : {}
          end
        end

        def restart_needed?
          !pending_versions.empty?
        end

        # После запуска: что уже загрузилось в новой версии — больше не ждёт.
        def settle_pending
          plugins = Catalog.plugins
          pending_versions.delete_if do |id, version|
            plugin = plugins.find { |p| p['id'] == id }
            inst = plugin && installed(plugin)
            inst.nil? || Catalog.compare(inst[:version], version) >= 0
          end
          save_pending
        end

        # Перезапустить SketchUp: скрытый PowerShell ждёт, пока SketchUp
        # закроется (сохранить ли модели, SketchUp спросит сам), и запускает его.
        #
        # Помощник ждёт именно этот процесс и только пока лежит флаг-файл. Если
        # выход отменили (Cancel в вопросе о сохранении), SketchUp жив и снимает
        # флаг — помощник уходит, ничего не запуская.
        def restart
          return 'Wait until the plugins finish installing' if busy?
          return UI.messagebox('Restart SketchUp yourself to finish the update.') unless Sketchup.platform == :platform_win

          flag = File.join(data_dir, 'restart.flag')
          FileUtils.mkdir_p(data_dir)
          token = "#{Process.pid}-#{Time.now.to_f}"
          File.write(flag, token)
          script = File.join(PLUGIN_PATH, 'tools', 'restart.ps1')
          Shortcut.run_hidden('powershell.exe', %(-NoProfile -ExecutionPolicy Bypass -File "#{script}" ) +
                                                %(-Exe "#{Shortcut.exe_path}" -ProcessId #{Process.pid} -Flag "#{flag}" -Token "#{token}"))
          Sketchup.quit
          # Сюда доходим, только если выход отменили.
          UI.start_timer(1, false) { File.delete(flag) if File.exist?(flag) && File.read(flag) == token }
          nil
        end

        # ---------- проверка при запуске ----------

        def schedule_check
          settle_pending
          return if Sketchup.read_default(PREFS_KEY, 'auto_check', true) == false

          last = Sketchup.read_default(PREFS_KEY, 'last_check', 0).to_i
          return if Time.now.to_i - last < CHECK_EVERY

          UI.start_timer(20, false) do
            refresh do
              next if @error

              Sketchup.write_default(PREFS_KEY, 'last_check', Time.now.to_i)
              list = updates
              next if list.empty?

              text = "Plugin updates: #{list.map { |r| "#{r[:name]} #{r[:latest]}" }.join(', ')} — Extensions > #{PLUGIN_NAME} > Plugin Updates"
              Session.emit(:info, text)
              Sketchup.status_text = text
            end
          end
        end

        # Окно и терминал подписываются на изменения.
        def listen(&block)
          @listeners << block
          block
        end

        def unlisten(block)
          @listeners.delete(block)
        end

        private

        def finish_refresh(data, err)
          @checking = false
          @catalog = data if data
          @error = err
          @checked_at = Time.now if data
          waiting = @waiting || []
          @waiting = []
          changed
          waiting.each do |cb|
            cb.call
          rescue StandardError => e
            warn "Exterminatus updater: #{e.class}: #{e.message}"
          end
        end

        HEX64 = /\A\h{64}\z/.freeze

        # Каталог приходит из сети: оставляем только наши плагины (plugins.json,
        # оттуда же repo, имя расширения и папка) и только ассеты из релизов их
        # репозиториев на GitHub с sha256. Остальное отбрасывается.
        # Список плагинов — из каталога (его собирает GitHub Actions в нашем
        # репозитории): так новые плагины появляются без обновления
        # Exterminatus. Доверяем только репозиториям B-A-community, ассетам из
        # их релизов по HTTPS с sha256 и безопасным именам папок. Свой
        # plugins.json уточняет: порядок, имена, описания, hidden и retired.
        def sanitize(data)
          cfg = Catalog.config
          # Скрытые и по своему plugins.json, и по каталогу (он новее).
          cfg = cfg.merge('hidden' => cfg['hidden'] + Array(data['hidden']).map(&:to_s))
          local = cfg['plugins'].to_h { |p| [p['repo'].downcase, p] }
          # id своих плагинов закреплены за их репозиториями.
          reserved = cfg['plugins'].to_h { |p| [p['id'].to_s.downcase, p['repo'].downcase] }
          seen_repo = {}
          seen_id = {}
          list = Array(data['plugins']).filter_map do |p|
            next unless p.is_a?(Hash)

            repo = p['repo'].to_s
            next unless test_mode || repo.match?(Catalog::REPO)
            next if Catalog.hidden?(repo, cfg) || seen_repo[repo.downcase]

            entry = clean_entry(p.merge(local[repo.downcase] || {}))
            next unless entry
            next if seen_id[entry['id']]
            next if reserved[entry['id']] && reserved[entry['id']] != repo.downcase

            reason = Catalog.retired(repo, cfg)
            entry = entry.merge('status' => 'retired', 'reason' => reason) if reason
            seen_repo[repo.downcase] = true
            seen_id[entry['id']] = true
            entry
          end
          # Наш плагин, которого нет в каталоге (ещё нет релиза), — без версий.
          cfg['plugins'].each do |p|
            next if seen_repo[p['repo'].downcase] || seen_id[p['id'].to_s.downcase] || Catalog.hidden?(p['repo'], cfg)

            list << clean_entry(p.merge('releases' => []))
          end
          data.merge('plugins' => order(list.compact, cfg))
        end

        def clean_entry(p)
          id = p['id'].to_s.downcase
          folder = p['folder'].to_s
          ext = p['extension'].to_s
          return nil unless id.match?(Catalog::SAFE_NAME) && folder.match?(Catalog::SAFE_NAME) && !ext.strip.empty?

          { 'id' => id, 'name' => (p['name'].to_s.strip.empty? ? ext : p['name'].to_s), 'repo' => p['repo'].to_s,
            'extension' => ext, 'folder' => folder, 'description' => p['description'].to_s[0, 200],
            'status' => p['status'] == 'retired' ? 'retired' : 'active', 'reason' => p['reason'].to_s[0, 300],
            'releases' => clean_releases(p, p['releases']) }
        end

        # Сначала — в порядке plugins.json, потом найденные сами, по имени.
        def order(list, cfg)
          rank = cfg['plugins'].each_with_index.to_h { |p, i| [p['repo'].downcase, i] }
          list.sort_by { |e| [rank.fetch(e['repo'].downcase, rank.size), e['name'].downcase] }
        end

        def clean_releases(plugin, releases)
          prefix = "https://github.com/#{plugin['repo']}/releases/download/".downcase
          Array(releases).select { |r| r.is_a?(Hash) && r['assets'].is_a?(Hash) }.map do |r|
            assets = r['assets'].select do |_lang, a|
              next false unless a.is_a?(Hash) && a['url'].is_a?(String)
              next true if test_mode

              a['url'].downcase.start_with?(prefix) && a['sha256'].to_s.match?(HEX64)
            end
            r.merge('version' => r['version'].to_s, 'assets' => assets)
          end.reject { |r| r['assets'].empty? || r['version'].empty? }
             .sort_by { |r| Catalog.version_key(r['version']) }.reverse
        end

        def parse_catalog(body)
          data = JSON.parse(body.to_s)
          data.is_a?(Hash) && data['format'] == Catalog::FORMAT && data['plugins'].is_a?(Array) ? data : nil
        rescue JSON::ParserError
          nil
        end

        def changed
          @listeners.each do |l|
            l.call
          rescue StandardError => e
            warn "Exterminatus updater listener: #{e.class}: #{e.message}"
          end
        end

        # Следующее из очереди: скачать → проверить → распаковать → установить.
        def step
          return if @current || @queue.empty?

          @current = @queue.shift
          plugin, release, asset = @current
          job = @jobs[plugin['id']]
          job[:state] = :downloading
          job[:message] = "Downloading #{release['version']}…"
          changed
          get(asset['url'], binary: true) do |status, body|
            begin
              raise "download failed (HTTP #{status})" unless status == 200 && body

              check(body, asset)
              job[:state] = :installing
              job[:message] = 'Installing…'
              changed
              archive = unpack(body, asset, "#{plugin['id']}-#{release['version']}")
              was = installed(plugin)
              raise 'SketchUp did not install the package' unless Sketchup.install_from_archive(archive, false)

              job[:state] = :done
              job[:message] = nil
              if was
                # Старая версия уже в памяти: новая загрузится после перезапуска.
                pending_versions[plugin['id']] = release['version']
                save_pending
                Session.emit(:result, "#{plugin['name']} #{release['version']} installed — restart SketchUp to load it")
              else
                Session.emit(:result, "#{plugin['name']} #{release['version']} installed")
              end
            rescue Interrupt
              job[:state] = :failed
              job[:message] = 'Cancelled'
            # install_from_archive бросает и Exception, а загрузка плагина —
            # LoadError/SyntaxError: очередь не должна застрять ни на чём.
            rescue Exception => e # rubocop:disable Lint/RescueException
              raise if e.is_a?(SystemExit) || e.is_a?(NoMemoryError)

              job[:state] = :failed
              job[:message] = e.message
              Session.emit(:error, "#{plugin['name']}: #{e.message}")
            ensure
              @current = nil
            end
            changed
            step
          end
        end

        def check(body, asset)
          size = asset['size'].to_i
          raise "downloaded #{body.bytesize} bytes, expected #{size}" if size.positive? && body.bytesize != size
          if asset['sha256'].to_s.empty?
            return if test_mode

            raise 'no checksum for this file in the catalog'
          end

          got = Digest::SHA256.hexdigest(body)
          raise 'checksum does not match: the file was damaged or replaced' unless got.casecmp?(asset['sha256'])
        end

        # Ассет — .rbz или .zip, внутри которого лежит .rbz (с PDF-инструкцией).
        # → путь к архиву для install_from_archive.
        # Файлы сохраняются под своими именами (id-версия), имена из архива и
        # каталога в путь не попадают.
        def unpack(body, asset, base)
          dir = File.join(data_dir, 'downloads')
          FileUtils.mkdir_p(dir)
          safe = base.gsub(/[^A-Za-z0-9._-]/, '_')
          return write(File.join(dir, "#{safe}.rbz"), body) if asset['name'].to_s.downcase.end_with?('.rbz')

          entries = Unzip.entries(body)
          rbz = entries.keys.find { |n| n.downcase.end_with?('.rbz'.b) && !n.include?('/'.b) } ||
                entries.keys.find { |n| n.downcase.end_with?('.rbz'.b) }
          return write(File.join(dir, "#{safe}.rbz"), Unzip.read(body, entries[rbz])) if rbz
          # Сам архив — плагин (загрузчик .rb в корне).
          if entries.keys.any? { |n| n.end_with?('.rb'.b) && !n.include?('/'.b) }
            return write(File.join(dir, "#{safe}.zip"), body)
          end

          raise "#{asset['name']} has no .rbz inside"
        end

        def write(path, data)
          File.binwrite(path, data)
          path
        end

        def data_dir
          Library.data_dir
        end

        def save_pending
          Library.write_json('pending_updates.json', pending_versions)
        end

        def lang_of(plugin, ext)
          dir = File.join(File.dirname(ext.extension_path.to_s), plugin['folder'].to_s)
          file = File.join(dir, 'lang.rb')
          return nil unless File.exist?(file)

          File.read(file, encoding: 'utf-8')[/LANG\s*=\s*'([a-z]{2})'/, 1]
        rescue SystemCallError
          nil
        end

        # GET: url или локальный путь (тесты, свой каталог). Блок — (код, тело).
        # Без ответа за TIMEOUT секунд — (0, nil).
        def get(url, json: false, binary: false, api: false, &cb)
          unless url.match?(%r{\Ahttps://}i)
            raise ArgumentError, "only https downloads are allowed: #{url}" unless test_mode

            path = url.sub(%r{\Afile:///?}i, '')
            UI.start_timer(0, false) do
              if File.exist?(path)
                cb.call(200, binary ? File.binread(path) : File.read(path, encoding: 'utf-8'))
              else
                cb.call(404, nil)
              end
            end
            return
          end

          req = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
          headers = { 'User-Agent' => "Exterminatus/#{VERSION}" }
          headers['Accept'] = 'application/vnd.github+json' if api
          req.headers = headers
          done = false
          @requests << req
          finish = lambda do |status, body|
            next if done

            done = true
            @requests.delete(req)
            body = body&.dup&.force_encoding(binary ? Encoding::BINARY : Encoding::UTF_8)
            cb.call(status, body)
          end
          req.start { |_r, res| finish.call(res.status_code.to_i, res.body) }
          UI.start_timer(TIMEOUT, false) do
            next if done

            req.cancel if req.respond_to?(:cancel)
            finish.call(0, nil)
          end
        rescue StandardError => e
          warn "Exterminatus updater: #{url}: #{e.message}"
          UI.start_timer(0, false) { cb.call(0, nil) }
        end
      end

      # Распаковка zip — в catalog.rb (нужна и сборщику каталога).
      Unzip = Catalog::Unzip
    end
  end
end
