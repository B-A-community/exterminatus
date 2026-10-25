# Exterminatus — общий лаунчер плагинов B&A community

> Вставьте этот раздел в `CLAUDE.md` (или `AGENTS.md`) проекта плагина. Он для
> разработчиков и ИИ-агентов, которые работают в проекте.

Этот плагин входит в семейство плагинов **B&A community**. У семейства есть
общий лаунчер **Exterminatus**: [B-A-community/exterminatus](https://github.com/B-A-community/exterminatus).
Это расширение SketchUp, которое:

- **ставит и обновляет наши плагины** из релизов GitHub организации
  B-A-community: окно Extensions → Exterminatus → Plugin Updates, кнопки
  Update / Install / Roll back / Update all;
- **запускает команды по имени из строки терминала**, как в Rhino: команды
  SketchUp и наших плагинов, параметры спрашиваются в строке.

Код в этот плагин для обновлений добавлять **не нужно**. Exterminatus всё
узнаёт сам:

| Что | Откуда берёт |
|---|---|
| установлен ли плагин и какой версии | `SketchupExtension#name` и `#version` в загрузчике |
| язык сборки | `<папка плагина>/lang.rb`, строка `LANG = 'ru'` или `'en'` |
| новые версии | релизы этого репозитория на GitHub |

## Правила, которые нельзя ломать

Эти правила держат обновления. Если нарушить хоть одно, у пользователей
перестанет работать Update.

1. **Имя расширения не меняется.** `SketchupExtension.new('<имя>', …)` — по нему
   Exterminatus находит установленный плагин. Если имя нужно сменить,
   сначала поправьте `src/exterminatus/plugins.json` в репозитории
   Exterminatus.
2. **Папка плагина и `lang.rb` остаются на месте.** В `lang.rb` должна остаться
   строка вида `LANG = 'ru'`: по ней выбирается языковая сборка.
3. **Релиз оформляется так:**
   - версия поднята в загрузчике (`ex.version` / `VERSION`);
   - тег `vX.Y` (например `v1.2`);
   - ассеты `<имя>-<версия>-rus.zip` и `<имя>-<версия>-eng.zip`, внутри
     `.rbz` (PDF-инструкцию рядом можно оставить); можно и сразу
     `<имя>-<версия>-rus.rbz`;
   - версия в имени ассета совпадает с версией в загрузчике (`1.2` и `1.2.0`
     считаются равными);
   - релиз не черновик и не pre-release: такие пропускаются.
4. **Своих проверок обновлений, загрузчиков и «скачать новую версию» в плагин
   не добавлять.** Это делает Exterminatus, и только для репозиториев
   B-A-community: скачивает по HTTPS, сверяет sha256 и ставит штатно, как
   Extension Manager.
5. **Репозиторий должен лежать в организации B-A-community** и быть публичным.
   Релизы из личных аккаунтов и приватных репозиториев лаунчер не видит.

Новый релиз попадает к пользователям сам: каталог пересобирается раз в час,
вручную — Actions → catalog → Run workflow в репозитории Exterminatus.

## Подключить команды плагина к терминалу (по желанию)

Если команды плагина подключены к терминалу, их можно вызывать из строки по
имени. Пункт меню, кнопка панели и команда терминала строятся из одного
описания, а без Exterminatus плагин работает как раньше.

- Пошагово, с готовым заданием для агента: [docs/INTEGRATE.md](https://github.com/B-A-community/exterminatus/blob/main/docs/INTEGRATE.md)
- Справочник API: [docs/PLUGIN_GUIDE.md](https://github.com/B-A-community/exterminatus/blob/main/docs/PLUGIN_GUIDE.md)
- Пример плагина: [examples/hello_plugin](https://github.com/B-A-community/exterminatus/tree/main/examples/hello_plugin)
- Мост, который кладётся в плагин без изменений: [src/exterminatus/terminal_bridge.rb](https://github.com/B-A-community/exterminatus/blob/main/src/exterminatus/terminal_bridge.rb)

Подключение — отдельная задача. Делать её только по просьбе владельца
проекта, сначала показав опись пунктов меню (шаг 1 в INTEGRATE.md).

## Новый плагин в семействе

Чтобы новый плагин появился в лаунчере, его нужно добавить в
[`src/exterminatus/plugins.json`](https://github.com/B-A-community/exterminatus/blob/main/src/exterminatus/plugins.json)
репозитория Exterminatus (поля описаны в
[docs/RELEASES.md](https://github.com/B-A-community/exterminatus/blob/main/docs/RELEASES.md)).
Это делается в проекте Exterminatus, не в проекте плагина.
