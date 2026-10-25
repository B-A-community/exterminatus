# frozen_string_literal: true

# Собрать catalog.json — какие версии наших плагинов вышли и где их скачать.
# Запускается в GitHub Actions (.github/workflows/catalog.yml) и локально:
#   ruby tools/build_catalog.rb [out.json]
# Токен GITHUB_TOKEN (если есть) снимает лимит GitHub API в 60 запросов в час.

require 'net/http'
require 'uri'
require 'json'
require_relative '../src/exterminatus/catalog'

C = BACommunity::Terminal::Catalog
out = ARGV[0] || 'catalog.json'

def get_json(path)
  uri = URI("https://api.github.com#{path}")
  req = Net::HTTP::Get.new(uri)
  req['Accept'] = 'application/vnd.github+json'
  req['User-Agent'] = 'Exterminatus catalog'
  req['Authorization'] = "Bearer #{ENV['GITHUB_TOKEN']}" if ENV['GITHUB_TOKEN'].to_s != ''
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  return nil if res.code == '404' # репозитория ещё нет — плагин просто без релизов
  raise "#{path}: HTTP #{res.code} #{res.body[0, 200]}" unless res.code == '200'

  JSON.parse(res.body)
end

entries = C.plugins.map do |plugin|
  releases = get_json("/repos/#{plugin['repo']}/releases?per_page=20") || []
  entry = C.entry(plugin, releases)
  latest = entry['releases'].first
  warn "#{plugin['id']}: #{latest ? "#{latest['version']} (#{latest['assets'].keys.join(', ')})" : 'no releases'}"
  entry
end
File.write(out, JSON.pretty_generate(C.build(entries)), encoding: 'utf-8')
warn "written #{out}"
