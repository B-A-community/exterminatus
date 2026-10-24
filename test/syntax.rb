# Проверка синтаксиса всех .rb плагина без загрузки.
root = File.expand_path('../src', __dir__)
bad = Dir.glob(File.join(root, '**', '*.rb')).map do |f|
  RubyVM::InstructionSequence.compile_file(f)
  nil
rescue SyntaxError => e
  "#{f}: #{e.message}"
end.compact
puts bad.empty? ? 'syntax ok' : bad
