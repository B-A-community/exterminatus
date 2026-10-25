# Обновление плагинов: каталог, сравнение версий, скачивание с проверкой,
# установка, откат, окно. Запуск — в два шага (сеть асинхронная):
#   python test/bridge.py test/live_updates.rb     — запускает и ждёт
#   (скрипт сам опрашивает состояние таймерами; итог — в $updates_result)
# Настоящие плагины не переустанавливаются: установка проверяется на примере
# examples/hello_plugin, который после теста удаляется из Plugins.
T = BACommunity::Terminal
U = T::Updater
C = T::Catalog
$updates_result = nil
results = []
ok = ->(name, cond, note = '') { results << [cond ? 'PASS' : 'FAIL', name, note.to_s] }
scratch = ENV['EXT_SCRATCH'] || File.join(Sketchup.temp_dir, 'ext_updates_test')
FileUtils.mkdir_p(scratch)
saved_url = Sketchup.read_default(T::PREFS_KEY, 'catalog_url', '')
U.test_mode = false
saved_pending = Sketchup.read_default(T::PREFS_KEY, 'pending_updates', '{}')
saved_lang = Sketchup.read_default(T::PREFS_KEY, 'install_lang', '')
plugins_dir = File.dirname(Sketchup.extensions.find { |e| e.name == 'Exterminatus' }.extension_path)
root = File.expand_path('../examples/hello_plugin', __dir__)

# ---------- чистые функции ----------
ok.('versions: 1.0 == 1.0.0', C.compare('1.0', '1.0.0').zero?)
ok.('versions: 1.1 > 1.0.9', C.compare('1.1', '1.0.9').positive?)
rel = C.release('tag_name' => 'v1.0', 'published_at' => '2026-09-21T16:17:21Z', 'body' => 'notes',
                'assets' => [{ 'name' => 'pathcopy-advanced-1.0.0-rus.zip', 'browser_download_url' => 'u1', 'size' => 5, 'digest' => 'sha256:ab' },
                             { 'name' => 'pathcopy-advanced-1.0.0-eng.zip', 'browser_download_url' => 'u2', 'size' => 6, 'digest' => nil },
                             { 'name' => 'guide.pdf', 'browser_download_url' => 'u3', 'size' => 1 }])
ok.('release: version from the asset name, languages by suffix',
    rel['version'] == '1.0.0' && rel['assets'].keys.sort == %w[en ru] && rel['assets']['ru']['sha256'] == 'ab', rel)

# Чужое из каталога отбрасывается: другой домен, другой репозиторий, без sha256.
evil = { 'format' => 1, 'plugins' => [
  { 'id' => 'ralncs', 'repo' => 'evil/ralncs', 'extension' => 'Evil', 'releases' => [
    { 'version' => '9.9', 'assets' => {
      'ru' => { 'url' => 'https://evil.example/ralncs.rbz', 'sha256' => 'a' * 64 },
      'en' => { 'url' => 'https://github.com/evil/ralncs/releases/download/v9.9/x.zip', 'sha256' => 'a' * 64 },
      'any' => { 'url' => 'https://github.com/B-A-community/ralncs/releases/download/v9.9/x.zip', 'sha256' => nil } } },
    { 'version' => '1.0', 'assets' => {
      'ru' => { 'url' => 'https://github.com/B-A-community/ralncs/releases/download/v1.0/RALNCS-1.0-rus.zip', 'sha256' => 'b' * 64 } } }] },
  { 'id' => 'stranger', 'repo' => 'evil/stranger', 'releases' => [] }] }
clean = U.send(:sanitize, evil)
r = clean['plugins'].find { |p| p['id'] == 'ralncs' }
ok.('catalog: foreign hosts, repos and missing sha256 are dropped',
    r['repo'] == 'B-A-community/ralncs' && r['extension'] == 'RALNCS' && r['releases'].map { |x| x['version'] } == ['1.0'], r['releases'])
ok.('catalog: plugins outside plugins.json are dropped', clean['plugins'].none? { |p| p['id'] == 'stranger' })
U.catalog_url = 'C:/somewhere/catalog.json'
ok.('local catalog files only in test mode', U.catalog_url == U::CATALOG_URL, U.catalog_url)
U.test_mode = true

# Тестовый каталог: Hello Plugin 1.0 и 1.1 — rbz, собранные из примера.
# Своё имя расширения на каждый запуск: SketchUp помнит зарегистрированные до перезапуска.
ext_name = "Hello Plugin #{Time.now.to_i}"
# И свой файл загрузчика: SketchUp не грузит повторно файл, который уже грузил.
loader_name = "hello_plugin_#{Time.now.to_i}.rb"
build_rbz = lambda do |version|
  path = File.join(scratch, "hello_plugin-#{version}.rbz")
  File.delete(path) if File.exist?(path)
  # rbz — zip; пишем без сжатия (метод 0), версия — в загрузчике.
  files = Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH).select { |f| File.file?(f) }
  entries = files.map do |f|
    name = f.sub("#{root}/", '')
    data = File.binread(f)
    if name == 'hello_plugin.rb'
      name = loader_name
      data = data.sub("ext.version = '1.0.0'", "ext.version = '#{version}'")
                 .sub("SketchupExtension.new('Hello Plugin'", "SketchupExtension.new('#{ext_name}'")
    end
    [name, data]
  end
  out = +''.b
  central = +''.b
  entries.each do |name, data|
    crc = Zlib.crc32(data)
    nb = name.b
    header = [0x04034b50, 20, 0x0800, 0, 0, 0, crc, data.bytesize, data.bytesize, nb.bytesize, 0].pack('VvvvvvVVVvv')
    central << [0x02014b50, 20, 20, 0x0800, 0, 0, 0, crc, data.bytesize, data.bytesize, nb.bytesize, 0, 0, 0, 0, 0, out.bytesize].pack('VvvvvvvVVVvvvvvVV') << nb
    out << header << nb << data
  end
  cd_offset = out.bytesize
  out << central << [0x06054b50, 0, 0, entries.size, entries.size, central.bytesize, cd_offset, 0].pack('VvvvvVVv')
  File.binwrite(path, out)
  path
end
v10 = build_rbz.call('1.0')
v11 = build_rbz.call('1.1')
asset = ->(path) { { 'name' => File.basename(path), 'url' => path, 'size' => File.size(path), 'sha256' => Digest::SHA256.file(path).hexdigest } }
hello = { 'id' => 'hello-plugin', 'name' => 'Hello Plugin', 'repo' => 'B-A-community/hello', 'extension' => ext_name,
          'folder' => 'hello_plugin', 'description' => 'Test',
          'releases' => [{ 'version' => '1.1', 'tag' => 'v1.1', 'date' => '2026-10-25', 'notes' => 'second', 'assets' => { 'any' => asset.(v11) } },
                         { 'version' => '1.0', 'tag' => 'v1.0', 'date' => '2026-10-01', 'notes' => 'first', 'assets' => { 'any' => asset.(v10) } }] }
real = File.join(scratch, 'real_catalog.json')
test_catalog = File.join(scratch, 'test_catalog.json')
broken = File.join(scratch, 'broken_catalog.json')
File.write(broken, JSON.generate(C.build([hello.merge('releases' => [hello['releases'][0].merge('assets' => { 'any' => asset.(v11).merge('sha256' => '0' * 64) })])])))

steps = []
step = ->(&b) { steps << b }
wait_until = nil
run_next = lambda do
  b = steps.shift
  if b.nil?
    # уборка
    Sketchup.write_default(T::PREFS_KEY, 'catalog_url', saved_url)
    Sketchup.write_default(T::PREFS_KEY, 'pending_updates', saved_pending)
    Sketchup.write_default(T::PREFS_KEY, 'install_lang', saved_lang)
    U.test_mode = false
    U.instance_variable_set(:@pending, nil)
    $updates_result = results.map { |r| r.join('  ') } + ["#{results.count { |r| r[0] == 'PASS' }}/#{results.size} passed"]
    next
  end
  b.call
end
# Ждать условия (опрос таймером), потом следующий шаг.
wait_until = lambda do |cond, limit = 60, &after|
  started = Time.now
  timer = UI.start_timer(0.3, true) do
    if cond.call || Time.now - started > limit
      UI.stop_timer(timer)
      after&.call
      run_next.call
    end
  end
end

# 1. Настоящий каталог из релизов GitHub (через API — каталога ещё нет).
step.call do
  U.catalog_url = File.join(scratch, 'no_such_catalog.json')
  U.refresh
  wait_until.(-> { !U.checking? }) do
    rows = U.rows
    by = rows.to_h { |r| [r[:id], r] }
    ok.('API fallback reads our releases', U.error.nil? && by.size == 5, [U.error, by.keys])
    ok.('RAL/NCS has ru and en builds', by['ralncs'] && by['ralncs'][:langs].sort == %w[en ru], by['ralncs'])
    ok.('installed language is read from lang.rb', by['area-counter'] && by['area-counter'][:lang] == 'ru', by['area-counter'])
    ok.('installed equal to release is up to date', by['pathcopy-advanced'] && by['pathcopy-advanced'][:status] == 'current',
        by['pathcopy-advanced']&.slice(:installed, :latest, :status))
    ok.('Exterminatus without releases is unpublished', by['exterminatus'] && by['exterminatus'][:status] == 'unpublished')
    File.write(real, JSON.generate(U.catalog))
  end
end

# 2. Скачать настоящий zip RAL/NCS с GitHub, проверить sha256 и достать .rbz — без установки.
step.call do
  plugin = U.find('ralncs')
  a = plugin['releases'].first['assets']['ru']
  got = nil
  U.send(:get, a['url'], binary: true) { |status, body| got = [status, body] }
  wait_until.(-> { got }, 90) do
    status, body = got
    err = nil
    begin
      U.send(:check, body, a)
      path = U.send(:unpack, body, a, 'ralncs-test')
    rescue StandardError => e
      err = e.message
    end
    ok.('real download: size and sha256 match', status == 200 && err.nil?, [status, body&.bytesize, err])
    ok.('rbz extracted from the release zip', err.nil? && path.to_s.end_with?('.rbz') && File.size(path.to_s) > 1000, path)
    entries = err ? {} : T::Updater::Unzip.entries(File.binread(path))
    ok.('extracted rbz is a plugin', entries.key?('ralncs.rb'), entries.keys.first(3))
  end
end

# 3. Окно по настоящему каталогу.
step.call do
  U.catalog_url = real
  T::UpdatesWindow.show
  wait_until.(-> { !U.checking? }) do
    st = T::UpdatesWindow.state
    ok.('window shows all our plugins', T::UpdatesWindow.visible? && st[:rows].size == 5, st[:rows].map { |r| r[:id] })
  end
end

# 4. Установка, обновление и откат на тестовом плагине.
step.call do
  File.write(test_catalog, JSON.generate(C.build([hello])))
  U.catalog_url = test_catalog
  U.refresh
  wait_until.(-> { !U.checking? }) do
    r = U.rows.find { |x| x[:id] == 'hello-plugin' }
    ok.('not installed → Install', r[:status] == 'missing', r.slice(:status, :latest))
  end
end
step.call do
  # Загрузчик примера защищён @loaded — в этом сеансе его уже грузили.
  if defined?(BACommunity::HelloPlugin) && BACommunity::HelloPlugin.instance_variable_defined?(:@loaded)
    BACommunity::HelloPlugin.remove_instance_variable(:@loaded)
  end
  msg = U.install('hello', version: '1.0')
  ok.('install queued', msg.nil?, msg)
  wait_until.(-> { !U.busy? }) do
    r = U.rows.find { |x| x[:id] == 'hello-plugin' }
    ok.('installed 1.0 loads right away', r[:installed] == '1.0' && r[:status] == 'update' && !r[:pending],
        [r.slice(:installed, :status, :pending, :message), ext_name, Sketchup.extensions.map(&:name).grep(/Hello/),
         Dir.glob(File.join(plugins_dir, 'hello*')).map { |f| File.basename(f) }])
    ok.('files are in Plugins', File.exist?(File.join(plugins_dir, loader_name)))
  end
end
step.call do
  ok.('update_all picks the update', U.update_all == 1)
  wait_until.(-> { !U.busy? }) do
    r = U.rows.find { |x| x[:id] == 'hello-plugin' }
    ok.('update → restart to finish', r[:status] == 'restart' && r[:pending] == '1.1' && U.restart_needed?, r.slice(:status, :pending))
    loader = File.read(File.join(plugins_dir, loader_name))
    ok.('new files are on disk', loader.include?("ext.version = '1.1'"))
    ok.('rollback offers 1.0', r[:previous] == '1.0', r[:previous])
  end
end
step.call do
  U.catalog_url = broken
  U.instance_variable_set(:@pending, {})
  U.refresh
  wait_until.(-> { !U.checking? }) do
    U.install('hello')
  end
end
step.call do
  wait_until.(-> { !U.busy? }) do
    r = U.rows.find { |x| x[:id] == 'hello-plugin' }
    ok.('damaged download is not installed', r[:status] == 'error' && r[:message].to_s.include?('checksum'), r.slice(:status, :message))
  end
end

# уборка тестового плагина
step.call do
  T.unregister('HelloStairs')
  T.unregister('HelloRename')
  FileUtils.rm_f(Dir.glob(File.join(plugins_dir, 'hello_plugin*.rb')))
  FileUtils.rm_rf(File.join(plugins_dir, 'hello_plugin'))
  ok.('test plugin removed from Plugins', Dir.glob(File.join(plugins_dir, 'hello_plugin*')).empty?)
  U.instance_variable_set(:@jobs, {})
  run_next.call
end

run_next.call
'started'
