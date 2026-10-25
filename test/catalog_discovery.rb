# frozen_string_literal: true

# Определение плагина по пакету — на настоящих релизах наших плагинов: имя
# расширения и папка, найденные в .rbz, должны совпасть с plugins.json.
# Запуск вне SketchUp: ruby test/catalog_discovery.rb (нужен интернет;
# GITHUB_TOKEN — по желанию).

require 'net/http'
require 'json'
require_relative '../src/exterminatus/catalog'

C = BACommunity::Terminal::Catalog

def fetch(url, json: true, limit: 5)
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  req['User-Agent'] = 'Exterminatus test'
  req['Authorization'] = "Bearer #{ENV['GITHUB_TOKEN']}" if ENV['GITHUB_TOKEN'].to_s != '' && uri.host == 'api.github.com'
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  return fetch(res['location'], json: json, limit: limit - 1) if res.is_a?(Net::HTTPRedirection) && limit.positive?
  return nil unless res.code == '200'

  json ? JSON.parse(res.body) : res.body
end

results = []
ok = ->(name, cond, note = '') { results << [cond ? 'PASS' : 'FAIL', name, note.to_s] }

C.plugins.each do |plugin|
  releases = fetch("https://api.github.com/repos/#{plugin['repo']}/releases?per_page=5") || []
  latest = C.entry(plugin, releases)['releases'].first
  next ok.("#{plugin['id']}: has a release", false, 'none') unless latest

  latest['assets'].each do |lang, asset|
    data = fetch(asset['url'], json: false)
    pkg = data && C.inspect_package(data, asset['name'])
    ok.("#{plugin['id']} #{latest['version']} #{lang}: extension and folder from the package",
        pkg == { 'extension' => plugin['extension'], 'folder' => plugin['folder'] }, pkg.inspect)
  end
end

# Синтетические пакеты: zip без сжатия из пар [имя, текст].
make_zip = lambda do |files|
  zip = +''.b
  central = +''.b
  files.each do |name, body|
    body = body.b
    nb = name.b
    crc = Zlib.crc32(body)
    local = [0x04034b50, 20, 0, 0, 0, 0, crc, body.bytesize, body.bytesize, nb.bytesize, 0].pack('VvvvvvVVVvv')
    central << [0x02014b50, 20, 20, 0, 0, 0, 0, crc, body.bytesize, body.bytesize, nb.bytesize, 0, 0, 0, 0, 0, zip.bytesize].pack('VvvvvvvVVVvvvvvVV') << nb
    zip << local << nb << body
  end
  cd = zip.bytesize
  zip << central << [0x06054b50, 0, 0, files.size, files.size, central.bytesize, cd, 0].pack('VvvvvVVv')
end
pkg = ->(files) { C.inspect_package(make_zip.(files), 'x-1.0.rbz') }

ok.('a zip without a SketchUp plugin is not a plugin', C.inspect_package(make_zip.([['readme.txt', 'hello']]), 'notes-1.0.zip').nil?)
ok.('loader name differs from the folder: folder from the load path',
    pkg.([['loader.rb', "ex = SketchupExtension.new('Tool', 'actual/main')"], ['actual/main.rb', '']]) ==
      { 'extension' => 'Tool', 'folder' => 'actual' })
ok.('constant with .freeze in the plugin folder',
    pkg.([['tool.rb', "SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_PATH, 'main.rb'))"],
          ['tool/constants.rb', "PLUGIN_NAME = 'Tool Pro'.freeze"]]) == { 'extension' => 'Tool Pro', 'folder' => 'tool' })
ok.('a computed name is not guessed', pkg.([['tool.rb', 'SketchupExtension.new("Tool #{VERSION}", "tool/main")'], ['tool/main.rb', '']]).nil?)
ok.('two extensions in one package are refused',
    pkg.([['a.rb', "SketchupExtension.new('A', 'a/main')"], ['a/main.rb', ''],
          ['b.rb', "SketchupExtension.new('B', 'b/main')"], ['b/main.rb', '']]).nil?)
ok.('a folder named .. is refused', pkg.([['x.rb', "SketchupExtension.new('X', '../main')"]]).nil?)
ok.('Cyrillic name', pkg.([['tool.rb', "SketchupExtension.new('Инсоляция', 'tool/main')"], ['tool/main.rb', '']]) ==
    { 'extension' => 'Инсоляция', 'folder' => 'tool' })

cfg = { 'plugins' => [], 'hidden' => ['B-A-community/old-tool'],
        'retired' => [{ 'repo' => 'B-A-community/legacy', 'reason' => 'Replaced by PathCopy Advanced' }] }
ok.('hidden list', C.hidden?('b-a-community/OLD-tool', cfg) && !C.hidden?('B-A-community/legacy', cfg))
ok.('retired list gives the reason', C.retired('B-A-community/legacy', cfg) == 'Replaced by PathCopy Advanced')
early = C.entry({ 'repo' => 'B-A-community/x' },
                [{ 'tag_name' => 'v0.9', 'assets' => [{ 'name' => 'x-0.9.rbz', 'browser_download_url' => 'u' }] },
                 { 'tag_name' => 'v1.0', 'assets' => [{ 'name' => 'x-1.0.rbz', 'browser_download_url' => 'u' }] }],
                min: C::MIN_DISCOVERED)
ok.('found plugins list only releases from 1.0', early['releases'].map { |r| r['version'] } == ['1.0'], early['releases'])

results.each { |r| puts r.join('  ') }
puts "#{results.count { |r| r[0] == 'PASS' }}/#{results.size} passed"
