# frozen_string_literal: true

# Собрать catalog.json — какие наши плагины есть, какие версии вышли и где
# их скачать. Запускается в GitHub Actions (.github/workflows/catalog.yml) и
# локально:
#   ruby tools/build_catalog.rb [out.json]
# Токен GITHUB_TOKEN (если есть) снимает лимит GitHub API в 60 запросов в час.
#
# Плагины ищутся по всем публичным репозиториям B-A-community: релиз 1.0+ с
# .rbz (или zip с .rbz) — и пакет внутри регистрирует SketchupExtension.
# plugins.json задаёт порядок и уточнения, hidden и retired.

require 'net/http'
require 'uri'
require 'json'
require_relative '../src/exterminatus/catalog'

C = BACommunity::Terminal::Catalog
out = ARGV[0] || 'catalog.json'

def request(url, json: true, limit: 5)
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  req['Accept'] = json ? 'application/vnd.github+json' : 'application/octet-stream'
  req['User-Agent'] = 'Exterminatus catalog'
  if ENV['GITHUB_TOKEN'].to_s != '' && uri.host == 'api.github.com'
    req['Authorization'] = "Bearer #{ENV['GITHUB_TOKEN']}"
  end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  if res.is_a?(Net::HTTPRedirection) && limit.positive?
    return request(res['location'], json: json, limit: limit - 1)
  end
  return nil if res.code == '404'
  raise "#{url}: HTTP #{res.code} #{res.body.to_s[0, 200]}" unless res.code == '200'

  json ? JSON.parse(res.body) : res.body
end

def api(path)
  request("https://api.github.com#{path}")
end

# Все страницы списка.
def api_all(path)
  list = []
  (1..20).each do |page|
    chunk = api("#{path}#{path.include?('?') ? '&' : '?'}per_page=100&page=#{page}") || []
    list.concat(chunk)
    break if chunk.size < 100
  end
  list
end

cfg = C.config
repos = api_all("/orgs/#{C::ORG}/repos?type=public").to_h { |r| [r['full_name'].downcase, r] }
ignored = ->(meta) { meta && Array(meta['topics']).include?(C::IGNORE_TOPIC) }

# Переименованный репозиторий: старое имя из plugins.json → нынешнее (GitHub
# отвечает редиректом), чтобы не получить две записи одного плагина.
canonical = {}
cfg['plugins'].each do |p|
  meta = repos[p['repo'].downcase] || api("/repos/#{p['repo']}")
  canonical[p['repo'].downcase] = meta ? meta['full_name'] : p['repo']
  repos[meta['full_name'].downcase] ||= meta if meta
end
listed = canonical.values.map(&:downcase)
hidden = cfg['hidden'].map(&:downcase) + repos.values.select { |m| ignored.call(m) }.map { |m| m['full_name'].downcase }

# Выведен из обращения: по plugins.json или потому что репозиторий в архиве.
retire = lambda do |entry, meta|
  reason = C.retired(entry['repo'], cfg) || (meta && meta['archived'] ? 'Repository archived' : nil)
  reason ? entry.merge('status' => 'retired', 'reason' => reason) : entry.merge('status' => 'active')
end

entries = []

# Уточнённые — первыми, в порядке plugins.json.
cfg['plugins'].each do |plugin|
  repo = canonical[plugin['repo'].downcase]
  next if hidden.include?(repo.downcase) || hidden.include?(plugin['repo'].downcase)

  meta = repos[repo.downcase]
  releases = api("/repos/#{repo}/releases?per_page=100") || []
  entry = retire.call(C.entry(plugin.merge('repo' => repo), releases), meta)
  latest = entry['releases'].first
  warn "#{plugin['id']}: #{latest ? "#{latest['version']} (#{latest['assets'].keys.join(', ')})" : 'no releases'}" \
       "#{entry['status'] == 'retired' ? " — retired: #{entry['reason']}" : ''}"
  entries << entry
end

# Найденные сами — по имени.
repos.values.sort_by { |r| r['name'].downcase }.each do |meta|
  repo = meta['full_name']
  next if listed.include?(repo.downcase) || meta['fork'] || hidden.include?(repo.downcase)

  releases = api("/repos/#{repo}/releases?per_page=100") || []
  base = C.entry({ 'repo' => repo }, releases, min: C::MIN_DISCOVERED)
  latest = base['releases'].first or next

  # Первый пакет может оказаться не тем (документация, битый файл): смотрим
  # остальные ассеты, потом прошлые релизы.
  pkg = nil
  base['releases'].first(3).each do |rel|
    rel['assets'].values.each do |asset|
      data = request(asset['url'], json: false)
      pkg = data && C.inspect_package(data, asset['name'])
      break if pkg
    end
    break if pkg
  end
  unless pkg
    warn "#{repo}: #{latest['version']} — SketchUp plugin not recognized (no .rbz, several extensions, " \
         'or a computed name): skipped; describe it in plugins.json if it is a plugin'
    next
  end

  entry = retire.call(base.merge('id' => meta['name'].downcase, 'name' => pkg['extension'],
                                 'extension' => pkg['extension'], 'folder' => pkg['folder'],
                                 'description' => meta['description'].to_s, 'discovered' => true), meta)
  warn "#{entry['id']}: found #{pkg['extension']} #{latest['version']} (#{latest['assets'].keys.join(', ')})"
  entries << entry
end

# Скрытые — и в каталог: клиент не добавит их обратно из своего (старого) plugins.json.
catalog = C.build(entries).merge('hidden' => hidden.uniq.sort)
File.write(out, JSON.pretty_generate(catalog), encoding: 'utf-8')
warn "written #{out}: #{entries.size} plugins"
