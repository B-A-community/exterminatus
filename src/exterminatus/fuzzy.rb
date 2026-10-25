# frozen_string_literal: true

module BACommunity
  module Terminal
    # Набранное в русской раскладке: «ьщму» — это «move». Клавиши те же,
    # поэтому переводим по клавиатуре ЙЦУКЕН → QWERTY.
    module Layout
      RU = 'йцукенгшщзхъфывапролджэячсмитьбюёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ'
      EN = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>~"

      class << self
        def cyrillic?(text)
          text.to_s.match?(/[а-яё]/i)
        end

        # «"» в русской раскладке — Shift+2, то есть «@» перед числом.
        def to_en(text)
          text.to_s.tr(RU, EN).gsub(/"(?=[-+\d.])/, '@')
        end
      end
    end

    # Догадаться, какую команду имели в виду: раскладка, русское слово из
    # keywords, опечатка. Всё это только если точного имени нет.
    module Fuzzy
      class << self
        # → [Command, как догадались (nil — точное имя), []] или [nil, nil, похожие id]
        def resolve(name)
          cmd, similar = Registry.resolve(name)
          return [cmd, nil, []] if cmd

          query = name.to_s.downcase
          if Layout.cyrillic?(query)
            words = by_keyword(query, exact: true)
            return [words.first, :keyword, []] if words.size == 1

            en = Layout.to_en(query)
            cmd, more = Registry.resolve(en)
            return [cmd, :layout, []] if cmd

            words = by_keyword(query) if words.empty?
            return [words.first, :keyword, []] if words.size == 1

            similar = (words.map(&:id) + more).uniq
            query = en
          end
          typo = by_typo(query)
          return [typo.first, :typo, []] if typo.size == 1 && !typo.first.destructive

          [nil, nil, (similar + typo.map(&:id)).uniq.first(5)]
        end

        # Ближайшие по написанию имена (параметры, опции) — для «Did you mean».
        def closest(word, names)
          q = word.to_s.downcase
          scored = names.map { |n| [n, distance(q, n.to_s.downcase)] }
          best = scored.map(&:last).min
          return [] if best.nil? || best > limit(q)

          scored.select { |_, d| d == best }.map(&:first)
        end

        # Расстояние Дамерау — Левенштейна (перестановка двух букв — одна ошибка).
        def distance(a, b)
          return b.size if a.empty?
          return a.size if b.empty?

          prev2 = nil
          prev = (0..b.size).to_a
          a.each_char.with_index(1) do |ca, i|
            cur = [i]
            b.each_char.with_index(1) do |cb, j|
              cost = ca == cb ? 0 : 1
              v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].min
              v = [v, prev2[j - 2] + 1].min if prev2 && i > 1 && j > 1 && ca == b[j - 2] && a[i - 2] == cb
              cur << v
            end
            prev2 = prev
            prev = cur
          end
          prev.last
        end

        private

        # Русское слово: точно («круг») или началом («перемес» → переместить,
        # «круги» → круг).
        def by_keyword(q, exact: false)
          Registry.all.select do |c|
            Array(c.keywords).any? do |k|
              next k == q if exact

              (q.size >= 3 && k.start_with?(q)) || (k.size >= 4 && q.start_with?(k))
            end
          end
        end

        # Опечатка: одна ошибка в коротком имени, две — в длинном.
        def by_typo(q)
          return [] if q.size < 3

          scored = Registry.all.map do |c|
            [c, c.names.map { |n| n.size < 3 ? 99 : distance(q, n.downcase) }.min]
          end
          best = scored.map(&:last).min
          return [] if best.nil? || best > limit(q)

          scored.select { |_, d| d == best }.map(&:first)
        end

        def limit(q)
          q.size >= 7 ? 2 : 1
        end
      end
    end
  end
end
