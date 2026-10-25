// Exterminatus — окно обновлений наших плагинов. Состояние живёт в Ruby
// (Updater); Ruby присылает U.update({...}), окно только рисует и шлёт клики.
(function () {
  'use strict';

  var state = null;
  var open = {}; // id → показаны ли изменения

  function call(name) {
    var args = Array.prototype.slice.call(arguments, 1);
    if (window.sketchup && typeof window.sketchup[name] === 'function') {
      window.sketchup[name].apply(window.sketchup, args);
    }
  }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined && text !== null) e.textContent = text;
    return e;
  }

  // Кнопка и подпись по состоянию плагина.
  var ACTIONS = {
    update: { label: 'Update', enabled: true, primary: true },
    missing: { label: 'Install', enabled: true },
    current: { label: 'Up to date', enabled: false },
    newer: { label: 'Newer than release', enabled: false },
    restart: { label: 'Restart to finish', enabled: false },
    busy: { label: 'Working…', enabled: false },
    error: { label: 'Try again', enabled: true },
    unpublished: { label: 'Not published', enabled: false },
    nolang: { label: 'No build in your language', enabled: false }
  };

  function versions(r) {
    var box = el('div', 'row__versions');
    if (r.status === 'update') {
      box.appendChild(document.createTextNode((r.installed || '') + ' → '));
      box.appendChild(el('span', 'new', r.latest));
    } else if (r.status === 'restart') {
      box.textContent = (r.installed || '') + ' → ' + r.pending;
    } else if (r.installed) {
      box.textContent = r.installed + (r.lang ? ' · ' + r.lang.toUpperCase() : '');
    } else if (r.latest) {
      box.textContent = 'not installed · ' + r.latest;
    } else {
      box.textContent = 'no releases yet';
    }
    if (r.date && r.status !== 'unpublished') {
      box.appendChild(el('div', 'muted', 'released ' + r.date));
    }
    return box;
  }

  function row(r) {
    var item = el('section', 'row');
    item.setAttribute('aria-label', r.name);

    var info = el('div', 'row__info');
    info.appendChild(el('div', 'row__name', r.name));
    if (r.description) info.appendChild(el('div', 'row__desc', r.description));
    var links = el('div', 'row__links');
    if (r.notes) {
      var notes = el('button', 'link', open[r.id] ? 'Hide changes' : "What's new");
      notes.type = 'button';
      notes.setAttribute('aria-expanded', open[r.id] ? 'true' : 'false');
      notes.addEventListener('click', function () { open[r.id] = !open[r.id]; render(); });
      links.appendChild(notes);
    }
    if (r.previous && r.status !== 'busy' && r.status !== 'restart') {
      var back = el('button', 'link', 'Roll back to ' + r.previous);
      back.type = 'button';
      back.addEventListener('click', function () { call('rollback', r.id); });
      links.appendChild(back);
    }
    if (links.children.length) info.appendChild(links);
    item.appendChild(info);

    item.appendChild(versions(r));

    var a = ACTIONS[r.status] || ACTIONS.current;
    var wrap = el('div', 'row__action');
    var btn = el('button', a.primary ? 'primary' : '', r.status === 'busy' && r.message ? r.message : a.label);
    btn.type = 'button';
    btn.disabled = !a.enabled || (state && state.checking);
    btn.addEventListener('click', function () { call('install', r.id); });
    wrap.appendChild(btn);
    item.appendChild(wrap);

    if (r.status === 'error' && r.message) item.appendChild(el('div', 'row__message row__message--error', r.message));
    if (open[r.id] && r.notes) item.appendChild(el('pre', 'row__notes', r.notes));
    return item;
  }

  function render() {
    if (!state) return;
    var list = document.getElementById('list');
    list.textContent = '';
    list.setAttribute('aria-busy', state.checking ? 'true' : 'false');
    if (!state.rows.length) {
      list.appendChild(el('p', 'empty muted', state.checking ? 'Checking for updates…' : 'No plugins in the catalog.'));
    }
    state.rows.forEach(function (r) { list.appendChild(row(r)); });

    var checked = document.getElementById('checked');
    checked.textContent = state.checking ? 'Checking…' : (state.checkedAt ? 'Checked ' + state.checkedAt : '');

    var err = document.getElementById('error');
    err.textContent = state.error || '';
    err.classList.toggle('is-hidden', !state.error);

    var all = document.getElementById('all');
    all.textContent = state.updates ? 'Update all (' + state.updates + ')' : 'Update all';
    all.disabled = !state.updates || state.checking;
    document.getElementById('refresh').disabled = state.checking || state.busy;

    Array.prototype.forEach.call(document.querySelectorAll('.lang button'), function (b) {
      b.setAttribute('aria-checked', b.getAttribute('data-lang') === state.lang ? 'true' : 'false');
    });

    document.getElementById('restart').classList.toggle('is-hidden', !state.restart);
    // Перезапуск оборвал бы установку остальных — только когда всё готово.
    document.getElementById('restart-now').disabled = state.busy;
  }

  window.U = {
    update: function (data) {
      state = data;
      render();
    }
  };

  document.addEventListener('DOMContentLoaded', function () {
    document.getElementById('refresh').addEventListener('click', function () { call('refresh'); });
    document.getElementById('all').addEventListener('click', function () { call('update_all'); });
    document.getElementById('restart-now').addEventListener('click', function () { call('restart'); });
    Array.prototype.forEach.call(document.querySelectorAll('.lang button'), function (b) {
      b.addEventListener('click', function () { call('lang', b.getAttribute('data-lang')); });
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') call('close');
    });
    document.addEventListener('contextmenu', function (e) { e.preventDefault(); });
    call('ready');
  });
})();
