# Релизы наших плагинов и обновление из Exterminatus

Exterminatus ставит и обновляет плагины B&A community прямо из SketchUp:
Extensions → Exterminatus → **Plugin Updates…** или команды в терминале.
Чужие плагины он не трогает: в списке только то, что записано в
[`src/exterminatus/plugins.json`](../src/exterminatus/plugins.json), и только
из репозиториев организации **B-A-community** на GitHub.

В код плагинов ничего добавлять не нужно. Exterminatus берёт:

- установленную версию — из Extension Manager (`SketchupExtension#version`);
- язык сборки — из `<папка плагина>/lang.rb` (`LANG = 'ru'`);
- новые версии — из релизов GitHub.

## Как выпустить новую версию плагина

Так же, как сейчас:

1. Поднимите версию в загрузчике плагина (`ex.version` / `VERSION`).
2. Соберите пакеты, как обычно: `build.ps1` или `tools/build_rbz.ps1`.
3. Создайте релиз на GitHub в репозитории `B-A-community/<плагин>`:
   - тег `vX.Y` (например `v1.2`);
   - ассеты по образцу `<имя>-<версия>-rus.zip` и `<имя>-<версия>-eng.zip`.

   Внутри zip лежит `.rbz` (PDF рядом можно оставить). Можно прикладывать и
   сам `.rbz` с теми же суффиксами: `<имя>-<версия>-rus.rbz`.
4. Всё. В течение часа релиз попадает в каталог, и у пользователей
   Exterminatus появляется кнопка «Update».

Правила, от которых зависит обновление:

| Что | Почему |
|---|---|
| Версия в имени ассета (`-1.2-`) совпадает с версией в загрузчике | Exterminatus сравнивает их; `1.2` и `1.2.0` считаются равными |
| Суффикс языка `-rus` / `-eng` (или `-ru` / `-en`) | у пользователя ставится та же языковая сборка, что уже стоит |
| Релиз не черновик и не pre-release | черновики и пре-релизы пропускаются |
| Имя расширения (`SketchupExtension.new('RALNCS', …)`) не меняется | по нему Exterminatus находит установленный плагин |

Плохой релиз откатывается одной кнопкой «Roll back to …» в окне. Можно и
командой `PluginRollback <плагин>`: она ставит предыдущий релиз с GitHub.

## Как добавить плагин в список

Добавьте запись в [`src/exterminatus/plugins.json`](../src/exterminatus/plugins.json):

```json
{ "id": "section-slicer", "name": "Section Slicer", "repo": "B-A-community/section-slicer",
  "extension": "Section Slicer", "folder": "section_slicer", "description": "Horizontal sections by levels" }
```

| Поле | Значение |
|---|---|
| `id` | имя для команд (`PluginUpdate section-slicer`) |
| `name` | подпись в окне |
| `repo` | репозиторий, только `B-A-community/…` |
| `extension` | имя расширения, как в Extension Manager |
| `folder` | папка плагина в Plugins (там `lang.rb`) |
| `description` | одна короткая фраза |

После пуша в `main` Action пересоберёт каталог. Пользователи увидят плагин
после следующей проверки. Новый `plugins.json` нужен и самому Exterminatus: он
выходит со следующей версией терминала, а терминал обновляется так же, как
остальные плагины.

## Каталог и GitHub Actions

[`.github/workflows/catalog.yml`](../.github/workflows/catalog.yml) в
репозитории Exterminatus:

- раз в час, по кнопке и при изменении `plugins.json` запускает
  [`tools/build_catalog.rb`](../tools/build_catalog.rb);
- скрипт читает релизы всех репозиториев из `plugins.json`;
- кладёт `catalog.json` в ветку `catalog`.

Exterminatus читает каталог по адресу
`https://raw.githubusercontent.com/B-A-community/exterminatus/catalog/catalog.json`:
один запрос вместо пяти и без лимита GitHub API.

Если каталог недоступен (репозиторий ещё не опубликован, ветки нет), то
Exterminatus сам спрашивает релизы через GitHub API. Без токена GitHub даёт 60
запросов в час с одного IP. Этого хватает, пока пользователей немного, но для
офиса за одним адресом нужен каталог.

Собрать каталог локально:

```bash
ruby tools/build_catalog.rb catalog.json
```

С токеном лимит API выше: `GITHUB_TOKEN=$(gh auth token) ruby tools/build_catalog.rb catalog.json`.

Свой каталог для проверки (например, локальный файл) задаётся в Ruby-консоли:
`BACommunity::Terminal::Updater.catalog_url = 'C:/path/catalog.json'`. Пустая
строка возвращает адрес по умолчанию.

## Что видит пользователь

- **Окно Plugin Updates.** У каждого нашего плагина видны установленная
  версия и язык, последняя версия и дата, что нового. Кнопки:
  - **Update** — есть новая версия;
  - **Install** — плагин не установлен; язык выбирается переключателем RU/EN
    вверху;
  - **Roll back to …** — вернуть предыдущий релиз;
  - **Update all** — обновить всё сразу.
- **Перезапуск.** Обновлённый плагин уже загружен в память, поэтому новая
  версия начинает работать после перезапуска SketchUp. Внизу окна появляется
  кнопка **Restart SketchUp**: SketchUp закрывается (спросив про несохранённые
  модели) и запускается снова. Новый плагин, которого не было, работает сразу.
- **Проверка раз в сутки.** Через 20 секунд после запуска SketchUp
  Exterminatus тихо проверяет обновления. Если они есть, он пишет строку в
  терминал и в строку состояния.
- **Команды в терминале:**
  - `Plugins` — список наших плагинов с версиями;
  - `PluginUpdate` / `PluginUpdate pathcopy` — обновить все или один;
  - `PluginInstall ralncs lang=en` — установить;
  - `PluginRollback ralncs` — откатить;
  - `PluginUpdates` — открыть окно;
  - `RestartSketchUp` — перезапустить SketchUp.

## Безопасность

- Скачивается только то, что указано в каталоге наших репозиториев, только по
  HTTPS с GitHub.
- Каждый файл сверяется с размером и sha256, которые GitHub считает сам при
  загрузке ассета. Не совпало — плагин не ставится.
- Ставит пакет штатный `Sketchup.install_from_archive`, как Extension Manager.
- Выпускать релизы могут участники B-A-community. Значит, их GitHub-аккаунты
  должны быть защищены двухфакторной аутентификацией.
- Если у пользователя в SketchUp включена политика «Identified Extensions
  Only», неподписанный плагин не загрузится. Такие релизы надо подписывать в
  Extension Warehouse, либо держать политику «Unrestricted».
