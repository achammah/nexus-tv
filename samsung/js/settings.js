// Settings: show, hide and reorder menu tabs and Home rows, choose Live countries, clear lists.
// Stored on the TV under 'nx_settings'. Other screens read Settings.get().
var Settings = (function () {
    'use strict';
    var ALL_TABS = [['home', 'Home'], ['guide', 'Live'], ['films', 'Films'], ['series', 'Series'], ['mylist', 'My List'], ['search', 'Search']];
    var ALL_ROWS = [['favmore', 'More favourites'], ['continue', 'Continue watching'], ['mylist', 'My List'], ['be', 'Belgium live'], ['newfilms', 'New films'],
        ['fr', 'France live'], ['topseries', 'Top series'], ['uk', 'UK live'], ['us', 'US live']];
    var ALL_CC = [['be', 'Belgium'], ['fr', 'France'], ['uk', 'UK'], ['us', 'US']];
    var DEF = { tabs: ids(ALL_TABS), hideTabs: [], rows: ids(ALL_ROWS), hideRows: [], countries: ids(ALL_CC), lists: [], tileOrder: {} };
    function ids(a) { return a.map(function (x) { return x[0]; }); }
    function load() {
        var s; try { s = JSON.parse(localStorage.getItem('nx_settings') || 'null'); } catch (e) { s = null; }
        s = s || {};
        var out = {};
        for (var k in DEF) out[k] = k === 'tileOrder' ? (s[k] && typeof s[k] === 'object' ? s[k] : {}) : (s[k] && s[k].slice ? s[k].slice() : DEF[k].slice());
        out.rows = out.rows.filter(function (id) { return id !== 'favs'; });   // favourites now live inside their country row
        // keep lists complete when a new tab or row ships
        [['tabs', ALL_TABS], ['rows', ALL_ROWS]].forEach(function (p) {
            p[1].forEach(function (x) { if (out[p[0]].indexOf(x[0]) < 0) out[p[0]].push(x[0]); });
        });
        if (!out.countries.length) out.countries = ['be'];
        return out;
    }
    var S = load();
    function save() { try { localStorage.setItem('nx_settings', JSON.stringify(S)); } catch (e) { /* storage blocked */ } }
    function label(list, id) {
        if (String(id).indexOf('list:') === 0) { for (var j = 0; j < S.lists.length; j++) if (S.lists[j].key === id) return S.lists[j].name + ' (' + TYPE[S.lists[j].t] + ')'; }
        for (var i = 0; i < list.length; i++) if (list[i][0] === id) return list[i][1];
        return id;
    }
    var TYPE = { live: 'Live', vod: 'Films', series: 'Series' };
    var TYPE_NAME = { x: 'Xtream', m: 'M3U', p: 'Portal' };

    // ---------- screen ----------
    var ALL_SECTIONS = [
        { id: 'tabs', title: 'Menu tabs', hint: 'OK shows or hides a tab. Edit order moves them.' },
        { id: 'rows', title: 'Home rows', hint: 'OK shows or hides a row. Edit order moves them.' },
        { id: 'countries', title: 'Live countries', hint: 'OK adds or removes a country. At least one stays on.' },
        { id: 'channels', title: 'Channels', hint: 'Browse every channel of your source and star the ones you want first on Home.' },
        { id: 'lists', title: 'Lists', hint: 'Every category of your source. Add any as a Home row. OK on a list removes it.' },
        { id: 'accounts', title: 'Sources', hint: 'OK switches source. Hold OK to remove one.' },
        { id: 'subs', title: 'Subtitles', hint: 'Online subtitles from OpenSubtitles for any film or episode, in the CC menu.' },
        { id: 'clear', title: 'Clear lists', hint: 'OK clears the list on this TV.' },
        { id: 'about', title: 'About', hint: '' }
    ];
    // Live countries only means something for an Xtream source
    var SECTIONS = [];
    function sections() { SECTIONS.length = 0; for (var i = 0; i < ALL_SECTIONS.length; i++) if (ALL_SECTIONS[i].id !== 'countries' || U.accounts.type() === 'x') SECTIONS.push(ALL_SECTIONS[i]); if (sec >= SECTIONS.length) sec = 0; }
    var el, sec = 0, col = 0, item = 0, active = false, moving = false, editing = false;

    function items() {
        var s = SECTIONS[sec].id;
        var EDIT = { id: 'edit', label: editing ? '\u2713  Done' : '\u2195  Edit order', action2: true, edit: true };
        if (s === 'tabs') return [EDIT].concat(S.tabs.map(function (id) { return { id: id, label: label(ALL_TABS, id), on: S.hideTabs.indexOf(id) < 0, fixed: id === 'home', move: true }; }));
        if (s === 'rows') return [EDIT].concat(S.rows.map(function (id) { return { id: id, label: label(ALL_ROWS, id), on: S.hideRows.indexOf(id) < 0, move: true }; }));
        if (s === 'channels') return [{ id: 'browse', label: '\u2605  Browse all channels', action2: true }].concat(U.favs().map(function (f) { return { id: f.sid, label: f.name, note: String(f.cc || '').toUpperCase(), info2: true }; }));
        if (s === 'lists') return [{ id: '+', label: '+  Browse all lists', action2: true }].concat(S.lists.map(function (l) { return { id: l.key, label: l.name, note: TYPE[l.t], info2: true }; }));
        if (s === 'accounts') {
            var act = U.accounts.active().id;
            var rows = [{ id: '+', label: '+  Add a source', action2: true }];
            U.accounts.list().forEach(function (a) {
                rows.push({ id: a.id, label: a.name || a.user || 'Source', note: TYPE_NAME[a.type || 'x'] + ' \u00b7 ' + (a.id === act ? 'Active' : String(a.base).replace(/^https?:\/\//, '').replace(/[\/?].*$/, '')), info2: true, on: a.id === act });
                if (a.big) rows.push({ id: 'g:' + a.id, label: '    Choose groups', note: (a.groups || []).length + ' of ' + (a.ngroups || '?') + ' groups', info2: true });
            });
            return rows;
        }
        if (s === 'subs') {
            var oa = Subs.account(), left = Subs.left();
            return [{ id: 'osub', label: oa && oa.key ? 'OpenSubtitles \u00b7 ' + (oa.user || 'key only') : 'Sign in to OpenSubtitles', note: oa && oa.key ? (left != null ? left + ' downloads left today' : 'Signed in') : '', action2: true }];
        }
        if (s === 'countries') return ALL_CC.map(function (c) { return { id: c[0], label: c[1], on: S.countries.indexOf(c[0]) >= 0 }; });
        if (s === 'clear') return [
            { id: 'favs', label: 'Favourite channels', note: U.favs().length + ' channels', action: true },
            { id: 'continue', label: 'Continue watching', note: U.continueList().length + ' titles', action: true },
            { id: 'mylist', label: 'My List', note: U.myList().length + ' titles', action: true }];
        return [{ id: 'v', label: 'Nexus TV', note: 'Version 1.1', info: true }, { id: 'acc', label: 'Source', note: U.accounts.active().name || 'Signed in', info: true }];
    }
    function draw() {
        var h = '';
        for (var i = 0; i < SECTIONS.length; i++)
            h += '<div class="li' + (i === sec ? (active && col === 0 ? ' focus' : ' on') : '') + '" style="top:' + (i * 58) + 'px;width:364px">' + SECTIONS[i].title + '</div>';
        U.$('stSec').innerHTML = h;
        var it = items(), r = '';
        for (var j = 0; j < it.length; j++) {
            var x = it[j], f = active && col === 1 && j === item;
            var right = x.action2 ? '' : x.info2 ? '<span class="sv" style="right:22px' + (x.on ? ';color:#34C759;font-weight:700' : '') + '">' + U.esc(x.note) + '</span>' : x.action ? '<span class="sv">' + U.esc(x.note) + '</span><span class="tg act">Clear</span>'
                : x.info ? '<span class="sv">' + U.esc(x.note) + '</span>'
                : editing && x.move ? ''
                : '<span class="tg' + (x.on ? ' on' : '') + '">' + (x.fixed ? 'Always on' : x.on ? 'On' : 'Off') + '</span>';
            r += '<div class="srow' + (f ? ' focus' : '') + (f && moving ? ' moving' : '') + (x.on === false ? ' off' : '') + '" style="top:' + (j * 74) + 'px">' +
                (x.move ? '<span class="mv">' + (f && moving ? '&#8597;' : '&#8801;') + '</span>' : '') + '<span class="sl">' + U.esc(x.label) + '</span>' + right + '</div>';
        }
        U.$('stItems').innerHTML = r;
        U.$('stTitle').textContent = SECTIONS[sec].title + (editing ? ' · editing order' : '');
        U.$('stHint').textContent = editing ? (moving ? 'Up and Down move the row. OK drops it.' : 'OK picks up a row. Back or Done finishes.') : SECTIONS[sec].hint;
    }
    function changed(what) { save(); App.applySettings(what); }
    function toggle() {
        var s = SECTIONS[sec].id, it = items()[item]; if (!it) return;
        if (it.edit) { editing = !editing; moving = false; draw(); return; }
        if (editing) { moving = !moving; draw(); return; }      // pick up / drop the row
        if (s === 'tabs' && !it.fixed) { flip(S.hideTabs, it.id); changed('tabs'); }
        else if (s === 'rows') { flip(S.hideRows, it.id); changed('rows'); }
        else if (s === 'countries') {
            var i = S.countries.indexOf(it.id);
            if (i >= 0) { if (S.countries.length > 1) S.countries.splice(i, 1); else { U.toast('Keep at least one country'); return; } }
            else { S.countries = ids(ALL_CC).filter(function (c) { return c === it.id || S.countries.indexOf(c) >= 0; }); }
            changed('countries');
        } else if (s === 'clear') { U.clearList(it.id); changed('rows'); }
        else if (s === 'channels') {
            if (it.id === 'browse') { ChannelPicker.open(); return; }
            var f = null; U.favs().forEach(function (x) { if (String(x.sid) === String(it.id)) f = x; });
            if (f) { U.toggleFav(f); changed('rows'); item = Math.max(0, item - 1); }
        }
        else if (s === 'lists') {
            if (it.id === '+') { Picker.open(); return; }
            S.lists = S.lists.filter(function (l) { return l.key !== it.id; });
            S.rows = S.rows.filter(function (r) { return r !== it.id; });
            changed('rows'); U.toast('List removed'); item = Math.max(0, item - 1);
        } else if (s === 'subs') { SubsForm.open(); return;
        } else if (s === 'accounts') {
            if (it.id === '+') { Onboard.open({ add: true }); return; }
            if (String(it.id).indexOf('g:') === 0) {      // pick the groups of a very large playlist again
                var acc = null; U.accounts.list().forEach(function (a) { if ('g:' + a.id === it.id) acc = a; });
                if (!acc || acc.id !== U.accounts.active().id) { U.toast('Switch to this source first'); return; }
                Src.repick(acc, function (e, info) {
                    if (e) { if (e.message !== 'cancelled') U.toast('Could not read the playlist'); draw(); return; }
                    acc.groups = info.groups; acc.ngroups = info.groupCount; U.accounts.persist(); U.toast('Saved. Reloading\u2026');
                    setTimeout(function () { location.reload(); }, 700);
                });
                return;
            }
            if (it.on) { U.toast('Already active'); return; }
            U.toast('Switching source…'); setTimeout(function () { U.accounts.use(it.id); }, 400);
        }
        draw();
    }
    function flip(list, id) { var i = list.indexOf(id); if (i >= 0) list.splice(i, 1); else list.push(id); }
    function move(d) {
        var s = SECTIONS[sec].id; if (s !== 'tabs' && s !== 'rows') return;
        var list = S[s], at = item - 1, j = at + d;
        if (at < 0 || j < 0 || j >= list.length) return;
        if (s === 'tabs' && (list[j] === 'home' || list[at] === 'home')) { U.toast('Home stays first'); return; }
        var t = list[at]; list[at] = list[j]; list[j] = t; item = j + 1;
        changed(s); draw();
    }
    function key(c) {
        if (Picker.isOpen()) return Picker.key(c);
        if (ChannelPicker.isOpen()) return ChannelPicker.key(c);
        if (SubsForm.isOpen()) return SubsForm.key(c);
        if (col === 0) {
            if (c === 38) { if (sec > 0) { sec--; item = 0; editing = moving = false; draw(); } else return 'up'; }
            else if (c === 40 && sec < SECTIONS.length - 1) { sec++; item = 0; editing = moving = false; draw(); }
            else if (c === 39 || c === 13) { col = 1; item = 0; draw(); }
            return true;
        }
        var n = items().length;
        if (moving) {                                   // reorder mode: Up/Down carry the item, OK drops it
            if (c === 38) move(-1);
            else if (c === 40) move(1);
            else if (c === 13) { moving = false; draw(); }
            return true;
        }
        if (c === 38) { if (item > 0) { item--; draw(); } else return 'up'; }
        else if (c === 40 && item < n - 1) { item++; draw(); }
        else if (c === 13) toggle();
        else if (c === 37) { if (editing) { editing = false; } col = 0; draw(); }
        return true;
    }
    function back() { if (Picker.isOpen()) { Picker.close(); return true; } if (ChannelPicker.isOpen()) { ChannelPicker.close(); return true; } if (SubsForm.isOpen()) { SubsForm.close(); return true; } if (moving) { moving = false; draw(); return true; } if (editing) { editing = false; draw(); return true; } if (col === 1) { col = 0; draw(); return true; } return false; }
    function longPress() {
        var s = SECTIONS[sec].id;
        if (active && col === 1 && s === 'accounts') {
            var it = items()[item];
            if (it && it.id !== '+' && String(it.id).indexOf('g:') !== 0) { if (U.accounts.remove(it.id)) { U.toast('Source removed'); item = Math.max(0, item - 1); draw(); } else U.toast('Switch to another source first'); }
            return true;
        }
        if (!active || col !== 1 || (s !== 'tabs' && s !== 'rows')) return false;
        if (item === 0) return false;
        editing = true; moving = true; draw(); return true;
    }
    function init() {
        sections();
        el = U.$('settings');
        el.innerHTML = '<div class="glass" style="left:112px;top:150px;width:400px;height:840px">' +
            '<div class="sect" style="left:32px;top:30px">Settings</div><div class="abs" id="stSec" style="left:18px;top:66px;width:364px;height:700px"></div></div>' +
            '<div class="rowtitle" id="stTitle" style="left:560px;top:166px"></div>' +
            '<div class="abs" id="stHint" style="left:560px;top:212px;font-size:22px;color:rgba(255,255,255,.5)"></div>' +
            '<div class="abs" id="stItems" style="left:560px;top:270px;width:900px;height:760px"></div>' +
            '<div class="overlay" id="stOver"></div>';
    }
    return {
        init: init, key: key, back: back, longPress: longPress,
        show: function () { sections(); draw(); },
        focus: function () { active = true; draw(); },
        blur: function () { active = false; draw(); },
        refresh: function () { draw(); },
        get: function () { return S; },
        addList: function (t, id, name) {
            var key = 'list:' + t + ':' + id;
            for (var i = 0; i < S.lists.length; i++) if (S.lists[i].key === key) { U.toast('Already on Home'); return; }
            S.lists.push({ key: key, t: t, id: id, name: name });
            S.rows.splice(1, 0, key);          // right after Continue watching
            changed('rows'); U.toast('Added to Home: ' + name);
        },
        redraw: function () { draw(); },
        removeList: function (key) { S.lists = S.lists.filter(function (l) { return l.key !== key; }); S.rows = S.rows.filter(function (r) { return r !== key; }); changed('rows'); U.toast('List removed from Home'); },
        saveTileOrder: function (rowKey, ids) { S.tileOrder[rowKey] = ids; save(); },
        hideRow: function (key) { if (S.hideRows.indexOf(key) < 0) S.hideRows.push(key); changed('rows'); U.toast('Row hidden · Settings > Home rows shows it again'); },
        // move a Home row past its visible neighbour; visibleKeys = rows on screen, in order
        moveRow: function (key, d, visibleKeys) {
            var vi = visibleKeys.indexOf(key), other = visibleKeys[vi + d];
            if (vi < 0 || !other) return false;
            var a = S.rows.indexOf(key), b = S.rows.indexOf(other);
            if (a < 0 || b < 0) return false;
            S.rows[a] = other; S.rows[b] = key; changed('rows'); return true;
        },
        tabLabel: function (id) { return label(ALL_TABS, id); }
    };
})();

// On-screen keyboard used by the list search and the source form (js/onboard.js). Lower/UPPER case, digits and URL symbols.
var Keyboard = (function () {
    'use strict';
    var ROWS = [['abcdefghij', 'klmnopqrst', 'uvwxyz-_.@', '1234567890', ':/?&=#%+!$'], ['ABCDEFGHIJ', 'KLMNOPQRST', 'UVWXYZ-_.@', '1234567890', ':/?&=#%+!$']];
    var WIDE = ['aA', 'SPACE', 'DELETE', 'DONE'];
    function make(x, y) { return { x: x, y: y, r: 0, c: 0, up: 0 }; }
    function draw(k, focused) {
        var h = '', rows = ROWS[k.up];
        for (var r = 0; r < rows.length; r++)
            for (var c = 0; c < 10; c++)
                h += '<div class="key' + (focused && k.r === r && k.c === c ? ' focus' : '') + '" style="left:' + (k.x + c * 76) + 'px;top:' + (k.y + r * 72) + 'px;width:68px;height:62px;line-height:62px;font-size:26px">' + U.esc(rows[r].charAt(c)) + '</div>';
        for (var w = 0; w < 4; w++)
            h += '<div class="key w2' + (focused && k.r === rows.length && k.c === w ? ' focus' : '') + '" style="left:' + (k.x + w * 190) + 'px;top:' + (k.y + rows.length * 72) + 'px;width:180px;height:62px;line-height:62px">' + WIDE[w] + '</div>';
        return h;
    }
    // returns {ch} for a character, 'del', 'done', or null after moving
    function key(k, code) {
        var rows = ROWS[k.up], wide = k.r === rows.length, width = wide ? 4 : 10;
        if (code === 38) { if (k.r > 0) { k.r--; if (wide) k.c = Math.min(9, k.c * 3); } else return 'up'; }
        else if (code === 40) { if (k.r < rows.length) { k.r++; if (k.r === rows.length) k.c = Math.min(3, Math.floor(k.c / 3)); } else return 'down'; }
        else if (code === 37) { if (k.c > 0) k.c--; else return 'left'; }
        else if (code === 39) { if (k.c < width - 1) k.c++; else return 'right'; }
        else if (code === 13) {
            if (!wide) return { ch: rows[k.r].charAt(k.c) };
            if (k.c === 0) { k.up = 1 - k.up; return null; }
            if (k.c === 1) return { ch: ' ' };
            if (k.c === 2) return 'del';
            return 'done';
        }
        else if (code >= 48 && code <= 57) return { ch: String(code - 48) };
        return null;
    }
    return { make: make, draw: draw, key: key };
})();

// Settings > Lists > Add a list: search every category of the active source (live, films, series).
var Picker = (function () {
    'use strict';
    // Every category of the source (live, films, series), no cap. Tabs switch type; typing filters; OK adds or removes.
    var open = false, q = '', kb = Keyboard.make(160, 330), zone = 0, sel = 0, top = 0, all = null, res = [], tab = 0;
    var TABS = [['', 'All'], ['live', 'Live'], ['vod', 'Films'], ['series', 'Series']];
    var TYPE = { live: 'Live', vod: 'Films', series: 'Series' }, VIS = 9;
    function load(cb) {
        if (all) { cb(); return; }
        var got = [], left = 3;
        ['live', 'vod', 'series'].forEach(function (t) {
            Data.categories(t, function (list) {
                list.forEach(function (c) { got.push({ t: t, id: c.id, name: Data.cleanCat(c.name), raw: c.name, lc: c.name.toLowerCase() }); });
                if (--left === 0) { all = got; cb(); }
            });
        });
    }
    function added(c) { var k = 'list:' + c.t + ':' + c.id, L = Settings.get().lists; for (var i = 0; i < L.length; i++) if (L[i].key === k) return true; return false; }
    function tag(c) { var t = Data.langTag(c.raw); if (t) return t; var m = /^\s*([A-Z]{2,4})\s*\|/.exec(c.raw); return m ? m[1] : ''; }
    function filter() {
        var n = q.toLowerCase().replace(/^\s+|\s+$/g, ''), ty = TABS[tab][0];
        res = all.filter(function (c) { return (!ty || c.t === ty) && (!n || c.lc.indexOf(n) >= 0); });
        sel = Math.min(sel, Math.max(0, res.length - 1)); if (top > sel) top = sel;
    }
    function draw() {
        var o = U.$('stOver');
        var h = '<div class="ovbg"></div><div class="rowtitle" style="left:160px;top:150px">Lists</div>' +
            '<div class="q" style="position:absolute;left:160px;top:220px;width:740px;height:76px;border-radius:20px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.16);font-size:30px;line-height:74px;padding:0 24px;white-space:nowrap;overflow:hidden">' +
            (q ? U.esc(q) : '<span style="color:rgba(255,255,255,.4)">Filter: Morocco, Netflix, Kids, Sport…</span>') + '<span class="caret"></span></div>' +
            Keyboard.draw(kb, zone === 0);
        var x = 980;
        for (var t = 0; t < TABS.length; t++) {
            h += '<div class="ctry' + (t === tab ? (zone === 1 ? ' focus' : ' on') : '') + '" style="left:' + x + 'px;top:150px">' + TABS[t][1] + '</div>';
            x += 40 + TABS[t][1].length * 14;
        }
        if (!all) h += '<div class="empty" style="left:980px;top:240px">Loading every category of your source…</div>';
        else {
            if (sel < top) top = sel; if (sel >= top + VIS) top = sel - VIS + 1;
            h += '<div class="sect" style="left:980px;top:226px">' + res.length + ' of ' + all.length + ' categories &nbsp;·&nbsp; ✓ = on Home</div>';
            for (var i = top; i < res.length && i < top + VIS; i++) {
                var c = res[i], on = added(c);
                h += '<div class="srow' + (zone === 2 && i === sel ? ' focus' : '') + '" style="left:980px;top:' + (262 + (i - top) * 70) + 'px;width:780px">' +
                    '<span class="sl" style="left:24px;right:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + (on ? '✓&nbsp; ' : '') + U.esc(c.name) + '</span><span class="sv" style="right:22px">' + TYPE[c.t] + (tag(c) ? ' · ' + tag(c) : '') + '</span></div>';
            }
            if (res.length > VIS) {
                var th = Math.max(40, Math.round(630 * VIS / res.length));
                h += '<div class="scrollbar" style="left:1772px;top:262px;height:630px;display:block"><i style="height:' + th + 'px;top:' + Math.round((630 - th) * top / Math.max(1, res.length - VIS)) + 'px"></i></div>';
            }
        }
        h += '<div class="abs" style="left:160px;top:1010px;font-size:20px;color:rgba(255,255,255,.45)">Right: tabs and the full list · CH +/− pages · OK adds or removes a list on Home · Back closes</div>';
        o.innerHTML = h; o.className = 'overlay on';
    }
    function key(c) {
        if (zone === 0) {
            var r = Keyboard.key(kb, c);
            if (r && r.ch !== undefined) { q += r.ch; filter(); }
            else if (r === 'del') { q = q.slice(0, -1); filter(); }
            else if (r === 'done' || r === 'right') { zone = 1; }
            draw(); return true;
        }
        if (zone === 1) {                         // tabs
            if (c === 37) { if (tab > 0) { tab--; sel = 0; top = 0; filter(); } else zone = 0; }
            else if (c === 39 && tab < TABS.length - 1) { tab++; sel = 0; top = 0; filter(); }
            else if (c === 40 || c === 13) { if (res.length) zone = 2; }
            draw(); return true;
        }
        if (c === 38) { if (sel > 0) sel--; else zone = 1; }
        else if (c === 40) { if (sel < res.length - 1) sel++; }
        else if (c === 427) sel = Math.max(0, sel - VIS);
        else if (c === 428) sel = Math.min(res.length - 1, sel + VIS);
        else if (c === 37) zone = 0;
        else if (c === 13 && res[sel]) { var it = res[sel]; if (added(it)) Settings.removeList('list:' + it.t + ':' + it.id); else Settings.addList(it.t, it.id, it.name); }
        draw(); return true;
    }
    return {
        open: function () { open = true; zone = 1; tab = 0; draw(); load(function () { filter(); if (open) draw(); }); },
        close: function () { open = false; U.$('stOver').className = 'overlay'; U.$('stOver').innerHTML = ''; Settings.redraw(); },
        isOpen: function () { return open; }, key: key
    };
})();

// Settings > Channels: every live channel of the source, by country and category; OK stars it.
// Starred channels sit first in their country row on Home (other countries: the "More favourites" row).
var ChannelPicker = (function () {
    'use strict';
    var open = false, zone = 0, ci = 0, gi = 0, ch = 0, cTop = 0, gTop = 0, hTop = 0, countries = null, items = {}, VIS = 11;
    function load(cb) {
        if (countries) { cb(); return; }
        Data.categories('live', function (list) {
            var by = {}, order = [];
            list.forEach(function (c) {
                var m = /^\s*([A-Z0-9]{2,5})\s*\|/.exec(c.name), code = m ? m[1] : 'OTHER';
                if (!by[code]) { by[code] = { code: code, cats: [] }; order.push(code); }
                by[code].cats.push({ id: c.id, name: Data.cleanCat(c.name) });
            });
            countries = order.map(function (k) { return by[k]; });
            cb();
        });
    }
    function cur() { return countries && countries[ci] ? countries[ci].cats[gi] : null; }
    function ensure() {
        var c = cur(); if (!c || items[c.id]) return;
        items[c.id] = 'loading';
        Data.itemsOf('live', c.id, function (list) { items[c.id] = list; if (open) draw(); });
    }
    function col(x, w, list, sel, topv, focused, label) {
        if (sel < topv) topv = sel; if (sel >= topv + VIS) topv = sel - VIS + 1;
        var h = '';
        for (var i = topv; i < list.length && i < topv + VIS; i++)
            h += '<div class="li' + (i === sel ? (focused ? ' focus' : ' on') : '') + '" style="left:' + x + 'px;top:' + (230 + (i - topv) * 62) + 'px;width:' + w + 'px">' + label(list[i]) + '</div>';
        return { h: h, top: topv };
    }
    function draw() {
        var o = U.$('stOver'), h = '<div class="ovbg"></div><div class="rowtitle" style="left:160px;top:150px">Channels<span>Starred channels go first on Home</span></div>';
        if (!countries) { h += '<div class="empty" style="left:160px;top:240px">Loading every channel group…</div>'; o.innerHTML = h; o.className = 'overlay on'; return; }
        var a = col(160, 220, countries, ci, cTop, zone === 0, function (c) { return U.esc(c.code) + '<em>' + c.cats.length + '</em>'; }); cTop = a.top; h += a.h;
        var cats = countries[ci].cats;
        var b = col(400, 520, cats, gi, gTop, zone === 1, function (c) { return U.esc(U.titleCase(c.name)); }); gTop = b.top; h += b.h;
        var c = cur(), list = c && items[c.id];
        if (list === 'loading' || !list) h += '<div class="empty" style="left:960px;top:240px">Loading…</div>';
        else {
            var cc = countries[ci].code.toLowerCase();
            var r = col(960, 800, list, ch, hTop, zone === 2, function (x) { return (U.isFav(x.sid) ? '<span style="color:#FFC94D">★</span>&nbsp; ' : '') + U.esc(x.name); }); hTop = r.top; h += r.h;
            if (!list.length) h += '<div class="empty" style="left:960px;top:240px">No channels in this group</div>';
            h += '<div class="sect" style="left:960px;top:200px">' + list.length + ' channels</div>';
        }
        h += '<div class="abs" style="left:160px;top:1010px;font-size:20px;color:rgba(255,255,255,.45)">Left / Right: country, group, channels · OK stars or unstars a channel · Back closes</div>';
        o.innerHTML = h; o.className = 'overlay on';
    }
    function key(c) {
        var lists = [countries || [], countries ? countries[ci].cats : [], (cur() && Array.isArray(items[cur().id])) ? items[cur().id] : []];
        var idx = [ci, gi, ch];
        if (c === 37) { if (zone > 0) zone--; }
        else if (c === 39) { if (zone < 2 && lists[zone + 1].length) zone++; else if (zone === 1) zone = 2; }
        else if (c === 38 || c === 40 || c === 427 || c === 428) {
            var step = c === 38 ? -1 : c === 40 ? 1 : c === 427 ? -VIS : VIS;
            var n = Math.max(0, Math.min(lists[zone].length - 1, idx[zone] + step));
            if (zone === 0) { ci = n; gi = 0; ch = 0; gTop = 0; hTop = 0; } else if (zone === 1) { gi = n; ch = 0; hTop = 0; } else ch = n;
        }
        else if (c === 13 && zone === 2 && lists[2][ch]) {
            var x = lists[2][ch], code = countries[ci].code.toLowerCase();
            U.toggleFav({ sid: x.sid, name: x.name, img: x.img, sub: countries[ci].code + ' · ' + U.titleCase(cur().name), cc: code });
        }
        else if (c === 13 && zone < 2) zone++;
        ensure(); draw(); return true;
    }
    return {
        open: function () { open = true; zone = 0; draw(); load(function () { ensure(); if (open) draw(); }); },
        close: function () { open = false; U.$('stOver').className = 'overlay'; U.$('stOver').innerHTML = ''; Settings.redraw(); },
        isOpen: function () { return open; }, key: key
    };
})();

// OpenSubtitles sign-in: API key (opensubtitles.com > profile > API consumers), username, password.
var SubsForm = (function () {
    'use strict';
    var open = false, f = 0, vals = ['', '', ''], kb = Keyboard.make(160, 446), busy = false;
    var FIELDS = ['API key', 'Username', 'Password'];
    function draw(msg) {
        var o = U.$('stOver'), h = '<div class="ovbg"></div><div class="rowtitle" style="left:160px;top:150px">OpenSubtitles account</div>';
        for (var i = 0; i < 3; i++) {
            var v = i === 2 ? new Array(vals[i].length + 1).join('\u2022') : vals[i];
            h += '<div class="srow' + (i === f ? ' focus' : '') + '" style="left:160px;top:' + (210 + i * 74) + 'px;width:1600px">' +
                '<span class="sl" style="left:24px;width:300px;color:' + (i === f ? 'rgba(0,0,0,.55)' : 'rgba(255,255,255,.5)') + '">' + FIELDS[i] + '</span>' +
                '<span class="sl" style="left:340px">' + U.esc(v) + (i === f ? '<span class="caret" style="background:#000"></span>' : '') + '</span></div>';
        }
        h += Keyboard.draw(kb, true);
        h += '<div class="abs" style="left:980px;top:466px;width:800px;font-size:24px;line-height:1.5;color:rgba(255,255,255,.6)">' + (msg || 'Create the key on opensubtitles.com, profile, API consumers. DONE on the password signs in. Username and password raise the daily downloads.') + '</div>';
        o.innerHTML = h; o.className = 'overlay on';
    }
    function save() {
        if (busy) return;
        if (!vals[0]) { draw('The API key is needed.'); return; }
        busy = true; draw('Signing in\u2026');
        Subs.setAccount({ key: vals[0], user: vals[1], pass: vals[2] }, function (e) {
            busy = false;
            if (e) { draw('That did not work (' + (e.message || 'refused') + '). Check the details.'); return; }
            close(); U.toast('OpenSubtitles signed in' + (Subs.left() != null ? ' \u00b7 ' + Subs.left() + ' downloads a day' : ''));
        });
    }
    function key(c) {
        var r = Keyboard.key(kb, c);
        if (r && r.ch !== undefined) vals[f] += r.ch;
        else if (r === 'del') vals[f] = vals[f].slice(0, -1);
        else if (r === 'up') { if (f > 0) f--; }
        else if (r === 'done') { if (f < 2) f++; else { save(); return true; } }
        draw(); return true;
    }
    function close() { open = false; vals = ['', '', '']; f = 0; U.$('stOver').className = 'overlay'; U.$('stOver').innerHTML = ''; Settings.redraw(); }
    return { open: function () { var a = Subs.account(); vals = a ? [a.key || '', a.user || '', ''] : ['', '', '']; open = true; draw(); }, close: close, isOpen: function () { return open; }, key: key };
})();
