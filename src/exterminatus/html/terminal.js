// Exterminatus — окно терминала (HtmlDialog, CEF 112).
// Состояние живёт в Ruby (Session): строка ввода отправляется целиком,
// Ruby отвечает T.update({log, prompt, ...}). Здесь — только автодополнение,
// история стрелками и отрисовка. Весь видимый текст — английский.
(function () {
  'use strict';

  var S = {
    mode: 'bar',
    commands: [],
    history: [],
    usage: {},
    hpos: -1,
    draft: '',
    prompt: null,
    items: [],
    itemsKind: 'commands', // 'values' — варианты ответа на вопрос, 'commands' — имена команд
    active: 0,
    navigated: false,
    lastHeight: 0,
    pinned: false
  };
  var el = {};

  function call(name) {
    var args = Array.prototype.slice.call(arguments, 1);
    if (window.sketchup && typeof window.sketchup[name] === 'function') {
      window.sketchup[name].apply(window.sketchup, args);
    }
  }

  // ---------- подбор команд ----------

  function initials(id) {
    return (id.match(/[A-Z0-9]/g) || []).join('').toLowerCase();
  }

  // Русская раскладка → латинская по клавишам: «ьщму» → «move».
  var RU = 'йцукенгшщзхъфывапролджэячсмитьбюё';
  var EN = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`";
  function toLatin(text) {
    var out = '';
    for (var i = 0; i < text.length; i++) {
      var ch = text[i], low = ch.toLowerCase(), at = RU.indexOf(low);
      out += at < 0 ? ch : (ch === low ? EN[at] : EN[at].toUpperCase());
    }
    return out;
  }

  function cyrillic(text) {
    return /[а-яё]/i.test(text);
  }

  // Дамерау — Левенштейн: перестановка двух букв — одна ошибка.
  function distance(a, b) {
    var prev2 = null, prev = [], i, j;
    for (j = 0; j <= b.length; j++) prev.push(j);
    for (i = 1; i <= a.length; i++) {
      var cur = [i];
      for (j = 1; j <= b.length; j++) {
        var v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
        if (prev2 && i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
        cur.push(v);
      }
      prev2 = prev;
      prev = cur;
    }
    return prev[b.length];
  }

  // Лучшее из: как набрано, в латинской раскладке, русское слово, опечатка.
  function fuzzyScore(cmd, q) {
    var best = score(cmd, q);
    if (cyrillic(q)) {
      var en = score(cmd, toLatin(q));
      if (en && (!best || en.score - 5 > best.score)) best = { score: en.score - 5, marks: en.marks };
      var kw = keywordScore(cmd, q);
      if (kw && (!best || kw.score > best.score)) best = kw;
      q = toLatin(q);
    }
    if (!best && q.length >= 3) {
      var limit = q.length >= 7 ? 2 : 1, d = 99;
      [cmd.id].concat(cmd.aliases).forEach(function (n) {
        if (n.length >= 3) d = Math.min(d, distance(q, n.toLowerCase()));
      });
      // Опечатку в команде, которая удаляет, Enter не исправляет сам.
      if (d <= limit) best = { score: 400 - d * 50 - cmd.id.length, marks: [], unsafe: !!cmd.destructive };
    }
    return best;
  }

  function keywordScore(cmd, q) {
    var words = cmd.keywords || [], i;
    for (i = 0; i < words.length; i++) {
      var k = words[i];
      if (k === q) return { score: 900, marks: [], note: k };
      if ((q.length >= 3 && k.indexOf(q) === 0) || (k.length >= 4 && q.indexOf(k) === 0)) {
        return { score: 600 - k.length, marks: [], note: k };
      }
    }
    return null;
  }

  // → {score, marks: [индексы символов id]} или null
  function score(cmd, q) {
    var id = cmd.id, low = id.toLowerCase(), i, j;
    if (low === q) return { score: 1000, marks: range(0, q.length) };
    for (i = 0; i < cmd.aliases.length; i++) {
      if (cmd.aliases[i].toLowerCase() === q) return { score: 950, marks: [] };
    }
    if (low.indexOf(q) === 0) return { score: 800 - low.length, marks: range(0, q.length) };
    var ini = initials(id);
    if (ini.indexOf(q) === 0) {
      var caps = [];
      for (i = 0; i < id.length && caps.length < q.length; i++) {
        if (/[A-Z0-9]/.test(id[i])) caps.push(i);
      }
      return { score: 700 - low.length, marks: caps };
    }
    for (i = 0; i < cmd.aliases.length; i++) {
      if (cmd.aliases[i].toLowerCase().indexOf(q) === 0) return { score: 650 - low.length, marks: [] };
    }
    var at = low.indexOf(q);
    if (at > 0) return { score: 500 - at - low.length, marks: range(at, at + q.length) };
    var marks = [];
    for (i = 0, j = 0; i < low.length && j < q.length; i++) {
      if (low[i] === q[j]) { marks.push(i); j++; }
    }
    if (j === q.length && q.length > 1) return { score: 200 - low.length, marks: marks };
    return null;
  }

  function range(a, b) {
    var r = [];
    for (var i = a; i < b; i++) r.push(i);
    return r;
  }

  // Текущий набираемый токен: имя команды в последнем звене цепочки «a; b».
  function commandToken(value) {
    var seg = value.slice(value.lastIndexOf(';') + 1);
    var lead = seg.match(/^\s*/)[0].length;
    var rest = seg.slice(lead);
    if (/\s/.test(rest)) return null; // имя уже набрано, дальше аргументы
    return { start: value.length - rest.length, text: rest };
  }

  // Пока команда ждёт точку или число, буквы — это имя другой команды
  // (Ruby отменит ждущую и запустит новую). Кроме имён опций вопроса.
  function commandsAllowed(value) {
    var p = S.prompt;
    if (!p) return true;
    if (!p.command || p.free_text || (p.values && p.values.length)) return false;
    var q = value.trim().toLowerCase();
    if (!/^[a-zа-яё]/.test(q)) return false;
    if (cyrillic(q)) q = toLatin(q);
    return !(p.options || []).some(function (o) { return o.name.toLowerCase().indexOf(q) === 0; });
  }

  function suggestions() {
    var value = el.input.value;
    S.itemsKind = 'commands';
    if (S.prompt && !commandsAllowed(value)) {
      var vals = S.prompt.values || [];
      if (!vals.length) return [];
      S.itemsKind = 'values';
      var qv = value.trim().toLowerCase();
      return vals.filter(function (v) { return v.toLowerCase().indexOf(qv) === 0; })
        .map(function (v) { return { id: v, value: v, plugin: '', desc: '', marks: range(0, qv.length) }; });
    }
    var tok = commandToken(value);
    if (!tok || !tok.text) return [];
    var q = tok.text.toLowerCase();
    var out = [];
    S.commands.forEach(function (cmd) {
      var m = fuzzyScore(cmd, q);
      if (m) {
        out.push({ id: cmd.id, value: cmd.id, plugin: cmd.plugin, desc: cmd.description, note: m.note, unsafe: m.unsafe,
                   marks: m.marks, score: m.score + Math.min(S.usage[cmd.id.toLowerCase()] || 0, 20) * 5 });
      }
    });
    out.sort(function (a, b) { return b.score - a.score || (a.id < b.id ? -1 : 1); });
    return out.slice(0, 8);
  }

  function isExactName(text) {
    var q = text.toLowerCase();
    return S.commands.some(function (c) {
      return c.id.toLowerCase() === q || c.aliases.some(function (a) { return a.toLowerCase() === q; });
    });
  }

  // ---------- отрисовка ----------

  function renderSuggest() {
    S.items = suggestions();
    if (S.active >= S.items.length) S.active = 0;
    var box = el.suggest;
    box.textContent = '';
    if (!S.items.length) {
      box.classList.add('is-hidden');
      el.input.setAttribute('aria-expanded', 'false');
      el.input.removeAttribute('aria-activedescendant');
      fit();
      return;
    }
    S.items.forEach(function (item, i) {
      var row = document.createElement('div');
      row.className = 'sg' + (i === S.active ? ' sg--active' : '');
      row.id = 'sg-' + i;
      row.setAttribute('role', 'option');
      row.setAttribute('aria-selected', i === S.active ? 'true' : 'false');
      var id = marked('sg__id', item.id, item.marks);
      // Русское слово, по которому нашлась команда: «Circle  круг».
      if (item.note) id.appendChild(span('sg__note', item.note));
      row.appendChild(id);
      row.appendChild(span('sg__plugin', item.plugin));
      if (item.desc) row.appendChild(span('sg__desc', item.desc));
      row.addEventListener('mousedown', function (e) {
        e.preventDefault();
        S.active = i;
        pick(true);
      });
      box.appendChild(row);
    });
    box.classList.remove('is-hidden');
    el.input.setAttribute('aria-expanded', 'true');
    el.input.setAttribute('aria-activedescendant', 'sg-' + S.active);
    var act = box.children[S.active];
    if (act) act.scrollIntoView({ block: 'nearest' });
    fit();
  }

  function span(cls, text) {
    var s = document.createElement('span');
    s.className = cls;
    s.textContent = text || '';
    return s;
  }

  function marked(cls, text, marks) {
    var s = document.createElement('span');
    s.className = cls;
    var set = {};
    (marks || []).forEach(function (i) { set[i] = true; });
    var buf = '', inMark = false;
    function flush() {
      if (!buf) return;
      if (inMark) {
        var m = document.createElement('mark');
        m.textContent = buf;
        s.appendChild(m);
      } else {
        s.appendChild(document.createTextNode(buf));
      }
      buf = '';
    }
    for (var i = 0; i < text.length; i++) {
      var want = !!set[i];
      if (want !== inMark) { flush(); inMark = want; }
      buf += text[i];
    }
    flush();
    return s;
  }

  function renderPrompt() {
    var p = S.prompt;
    var box = el.prompt;
    if (!p) {
      box.classList.add('is-hidden');
      el.input.placeholder = 'Command';
      el.input.setAttribute('aria-label', 'Command');
      el.hint.classList.toggle('is-hidden', !S.history.length);
      fit();
      return;
    }
    box.querySelector('.prompt__text').textContent = p.text;
    box.querySelector('.prompt__default').textContent = p.default ? '<' + p.default + '>' : '';
    var opts = box.querySelector('.prompt__options');
    opts.textContent = '';
    if (p.options && p.options.length) {
      opts.appendChild(document.createTextNode('( '));
      p.options.forEach(function (o, i) {
        if (i) opts.appendChild(document.createTextNode('  '));
        var s = document.createElement('span');
        s.className = 'opt';
        s.setAttribute('data-opt', o.name);
        s.setAttribute('role', 'button');
        s.setAttribute('tabindex', '0');
        s.appendChild(span('opt__name', o.name));
        if (o.value !== null && o.value !== undefined && o.value !== '') s.appendChild(span('opt__value', '=' + o.value));
        s.addEventListener('mousedown', function (e) {
          e.preventDefault();
          call('option', o.name);
        });
        s.addEventListener('keydown', function (e) {
          if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); call('option', o.name); }
        });
        opts.appendChild(s);
      });
      opts.appendChild(document.createTextNode(' )'));
    }
    opts.appendChild(document.createTextNode(':'));
    box.classList.remove('is-hidden');
    el.input.placeholder = '';
    el.input.setAttribute('aria-label', p.text);
    el.hint.classList.add('is-hidden');
    fit();
  }

  function appendLog(lines, replace) {
    if (replace) el.log.textContent = '';
    (lines || []).forEach(function (line) {
      var d = document.createElement('div');
      d.className = 'line line--' + line.kind;
      d.textContent = line.kind === 'error' && line.text.indexOf('Error') !== 0 ? 'Error: ' + line.text : line.text;
      el.log.appendChild(d);
    });
    while (el.log.children.length > 300) el.log.removeChild(el.log.firstChild);
    el.log.scrollTop = el.log.scrollHeight;
    if (S.mode === 'popup') document.body.classList.toggle('has-result', el.log.children.length > 0);
    fit();
  }

  // Высоту popup подгоняем под содержимое (Ruby меняет размер окна).
  function fit() {
    if (S.mode !== 'popup') return;
    // Окно ещё маленькое, flex уже сжал список — меряем части по отдельности.
    var h = 2 + 2 + document.querySelector('.command').offsetHeight;
    [el.suggest, el.log].forEach(function (box) {
      if (getComputedStyle(box).display === 'none') return;
      var cap = parseFloat(getComputedStyle(box).maxHeight);
      h += Math.min(box.scrollHeight, isNaN(cap) ? Infinity : cap) + 1;
    });
    h = Math.ceil(h);
    if (h !== S.lastHeight) {
      S.lastHeight = h;
      call('height', h);
    }
  }

  // ---------- ввод ----------

  function pick(submitNow) {
    var item = S.items[S.active];
    if (!item) return false;
    if (S.itemsKind === 'values') {
      el.input.value = item.value;
    } else {
      var tok = commandToken(el.input.value);
      if (!tok) return false;
      el.input.value = el.input.value.slice(0, tok.start) + item.value + (submitNow ? '' : ' ');
    }
    if (submitNow) {
      submit();
    } else {
      renderSuggest();
    }
    return true;
  }

  function submit() {
    var value = el.input.value;
    // Enter берёт подсказку, выбранную стрелками, а без выбора — первую,
    // если имя команды недобрано.
    var item = S.items[S.active];
    if (item && S.itemsKind === 'values') {
      if (S.navigated) value = item.value;
    } else if (item) {
      var tok = commandToken(value);
      if (tok && tok.text && (S.navigated || (!isExactName(tok.text) && !item.unsafe))) {
        value = value.slice(0, tok.start) + item.value;
      }
    }
    S.navigated = false;
    if (value.trim()) {
      var name = (value.trim().split(/\s+/)[0] || '').toLowerCase();
      S.usage[name] = (S.usage[name] || 0) + 1;
    }
    el.input.value = '';
    S.hpos = -1;
    S.items = [];
    renderSuggest();
    document.body.classList.add('is-busy');
    document.querySelector('.terminal').setAttribute('aria-busy', 'true');
    call('submit', value);
  }

  function spaceSubmits(value) {
    if (!value) return true;
    if ((value.match(/"/g) || []).length % 2) return false; // внутри кавычек
    var p = S.prompt;
    return !(p && p.free_text);
  }

  function renderPin() {
    if (!el.pin) return;
    el.pin.setAttribute('aria-pressed', S.pinned ? 'true' : 'false');
    var t = S.pinned ? 'Unpin: close the command line after a command' : 'Keep the command line open';
    el.pin.title = t;
    el.pin.setAttribute('aria-label', t);
  }

  function historyStep(dir) {
    var list = S.history;
    if (!list.length) return;
    if (S.hpos === -1) {
      if (dir > 0) return;
      S.draft = el.input.value;
      S.hpos = list.length;
    }
    S.hpos += dir;
    if (S.hpos < 0) S.hpos = 0;
    if (S.hpos >= list.length) {
      S.hpos = -1;
      el.input.value = S.draft;
    } else {
      el.input.value = list[S.hpos];
    }
    var end = el.input.value.length;
    el.input.setSelectionRange(end, end);
  }

  function onKey(e) {
    var open = S.items.length > 0;
    switch (e.key) {
      case 'Enter':
        e.preventDefault();
        submit();
        break;
      case 'Tab':
        // Без подсказок Tab остаётся переходом фокуса (к опциям приглашения).
        if (open && !e.shiftKey) {
          e.preventDefault();
          pick(false);
        }
        break;
      case 'ArrowDown':
        e.preventDefault();
        if (open) { S.active = (S.active + 1) % S.items.length; S.navigated = true; renderSuggest(); } else if (!S.prompt) historyStep(1);
        break;
      case 'ArrowUp':
        e.preventDefault();
        if (open) { S.active = (S.active - 1 + S.items.length) % S.items.length; S.navigated = true; renderSuggest(); } else if (!S.prompt) historyStep(-1);
        break;
      case 'Escape':
        e.preventDefault();
        if (open && el.input.value) {
          S.items = [];
          el.suggest.classList.add('is-hidden');
          el.input.value = '';
          renderSuggest();
        } else if (S.prompt) {
          call('cancel');
        } else {
          call('dismiss');
        }
        break;
      case ' ':
        // Как в Rhino: пробел — это Enter (команда, ответ, повтор последней).
        // Shift+пробел — обычный пробел, для аргументов в строке
        // («Move 0,0,500»); в кавычках и в текстовых ответах — тоже пробел.
        if (!e.shiftKey && spaceSubmits(el.input.value)) {
          e.preventDefault();
          submit();
        }
        break;
      default:
        break;
    }
  }

  // ---------- API для Ruby ----------

  window.T = {
    init: function (data) {
      S.mode = data.mode;
      document.body.className = 'mode-' + data.mode;
      S.commands = data.commands || [];
      S.history = data.history || [];
      S.history.forEach(function (line) {
        var name = (line.split(/\s+/)[0] || '').toLowerCase();
        S.usage[name] = (S.usage[name] || 0) + 1;
      });
      appendLog(data.log, true);
      S.prompt = data.prompt || null;
      S.pinned = !!data.pinned;
      renderPin();
      renderPrompt();
      T.focus();
    },

    update: function (data) {
      if (data.commands) S.commands = data.commands;
      if ('pinned' in data) { S.pinned = !!data.pinned; renderPin(); }
      if (data.history) S.history = data.history;
      if (data.resetLog) appendLog([], true);
      if (data.log) appendLog(data.log, false);
      if ('prompt' in data) {
        S.prompt = data.prompt || null;
        renderPrompt();
        renderSuggest();
      }
      if (data.idle) {
        document.body.classList.remove('is-busy');
        document.querySelector('.terminal').setAttribute('aria-busy', 'false');
      }
    },

    focus: function () {
      window.focus();
      el.input.focus();
    }
  };

  document.addEventListener('DOMContentLoaded', function () {
    el.log = document.getElementById('log');
    el.prompt = document.getElementById('prompt');
    el.input = document.getElementById('input');
    el.suggest = document.getElementById('suggest');
    el.hint = document.getElementById('input-hint');
    el.pin = document.getElementById('pin');
    el.pin.addEventListener('mousedown', function (e) { e.preventDefault(); });
    el.pin.addEventListener('click', function () { call('pin'); el.input.focus(); });
    el.input.addEventListener('keydown', onKey);
    el.input.addEventListener('input', function () {
      S.active = 0;
      S.navigated = false;
      S.hpos = -1;
      renderSuggest();
    });
    // Клик по пустому месту окна возвращает фокус в строку.
    document.addEventListener('mouseup', function () {
      if (!window.getSelection().toString()) el.input.focus();
    });
    document.addEventListener('contextmenu', function (e) { e.preventDefault(); });
    call('ready');
  });
})();
