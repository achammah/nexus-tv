// Settings: the approved design (design/settings): 7 sections on the left (Account & sources, Channels, Home & views,
// Lists, Playback & subtitles, Data & storage, About), grouped rows on the right, detail pages for the deeper ones.
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

    // ---------- screen: the approved design (design/settings s1 to s4) ----------
    // Left: 7 sections, each with a live summary; the selected one is the white pill. Right: small-caps headers over
    // grouped rows (label and help line left; value, pills, toggle or chevron right); the focused row has the white
    // outline. Left / Right move between the column and the rows (and across a row's pills), Up / Down move within,
    // OK toggles or opens, Back goes from a detail page to its section, then to the column, then to the menu.
    var X_NAV = 112, X_PANE = 640, W_PANE = 1168, TOP = 240, ROW_H = 92, HD_H = 60, GAP = 0, BOTTOM = 1040;
    var SECTIONS = [['account', 'Account & sources'], ['channels', 'Channels'], ['views', 'Home & views'], ['lists', 'Lists'],
        ['playback', 'Playback & subtitles'], ['data', 'Data & storage'], ['about', 'About']];
    var BADGE = { x: ['XTREAM', 'x'], m: ['M3U', 'm'], p: ['PORTAL', 'p'] };
    var SRC_TITLE = { x: 'Xtream login', m: 'M3U playlist', p: 'Stalker portal' };
    var CC_NAME = { be: 'Belgium', fr: 'France', uk: 'United Kingdom', us: 'United States' };
    var CC_FLAG = { be: 'be', fr: 'fr', uk: 'gb', us: 'us' };
    // Region codes of the provider and their names: the same table as js/livehome.js REGIONS (titles only).
    var REGION_NAME = { AR: 'Arabic', ASIA: 'Asia', LAT: 'Latin America', LA: 'Latin America', BEE: 'beIN & Arabic sports', EXYU: 'Ex-Yugoslavia', AFR: 'Africa', CRB: 'Caribbean', KU: 'Kurdish', EU: 'Europe', NA: 'North Africa' };
    var LANGS = [['en', 'English'], ['fr', 'French'], ['nl', 'Dutch'], ['de', 'German'], ['es', 'Spanish'], ['it', 'Italian'], ['ar', 'Arabic'], ['orig', 'Original']];
    var LIB_LANGS = [['EN', 'English'], ['FR', 'Français'], ['', 'All languages']];

    // Playback preferences with no reader yet: kept here so the choice survives; nothing else in the app reads them
    // (the player keeps choosing per title from U.getTrackPref and its own language order).
    var P_KEY = 'nx_play';
    var P = (function () { var p; try { p = JSON.parse(localStorage.getItem(P_KEY) || 'null'); } catch (e) { p = null; } p = p || {};
        return { audio: p.audio || ['en', 'fr', 'orig'], remember: p.remember !== false, show: p.show || 'notmine', subLangs: p.subLangs || ['en', 'fr'], autoFetch: p.autoFetch !== false, hideSmall: p.hideSmall !== false }; })();
    function saveP() { try { localStorage.setItem(P_KEY, JSON.stringify(P)); } catch (e) { /* full */ } }
    function liveView() { try { return localStorage.getItem('nx_live_view') === 'full' ? 'full' : 'cat'; } catch (e) { return 'cat'; } }
    function libLang() { try { var v = localStorage.getItem('nx_lib_lang'); return v === null ? 'EN' : v; } catch (e) { return 'EN'; } }
    function langName(c) { for (var i = 0; i < LANGS.length; i++) if (LANGS[i][0] === c) return LANGS[i][1]; return c; }
    function fmt(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
    function favsOf(cc) { return U.favs().filter(function (f) { return (f.cc || '') === cc; }); }
    function flag(cc) { return '<img class="stflag" src="img/flags/' + (CC_FLAG[cc] || cc) + '.png" onerror="this.style.display=\'none\'">'; }
    function chev() { return '<span class="stchev">&#8250;</span>'; }
    function tog(on) { return '<span class="sttog' + (on ? ' on' : '') + '"><i></i></span>'; }
    function badge(t) { var b = BADGE[t] || BADGE.x; return '<span class="stbadge ' + b[1] + '">' + b[0] + '</span>'; }
    var counts = null;
    function loadCounts() {
        if (counts || !U.accounts.has()) return;
        counts = { live: null, vod: null, series: null };
        ['live', 'vod', 'series'].forEach(function (t) { Data.categories(t, function (l) { counts[t] = (l || []).length; if (built) render(); }); });
    }

    var el, active = false, built = false, col = 0, sec = 0, row = 0, pi = 0, page = null, moving = false, shift = 0, rowsNow = [];

    // ---------- the rows of a section (or of a detail page): [{ hd } | { id, label, help, right, kind, ... }] ----------
    function sectionRows(id) {
        var out = [];
        if (id === 'account') {
            var act = U.accounts.active(), others = U.accounts.list().filter(function (a) { return a.id !== act.id; });
            var t = act.type || 'x', parts = [];
            if (counts && counts.live != null) parts.push(fmt(counts.live) + ' live lists');
            if (counts && counts.vod != null && t === 'x') parts.push(fmt(counts.vod) + ' film lists');
            if (counts && counts.series != null && t === 'x') parts.push(fmt(counts.series) + ' series lists');
            parts.push('1 stream at a time');
            out.push({ hd: 'Active source' });
            out.push({ id: 'src:' + act.id, label: act.name || act.user || 'My source', help: parts.join(' · '), right: badge(t) + '<b>Active</b>' + chev(), open: function () { return sourcePage(act, true); } });
            out.push({ hd: 'Other sources' });
            others.forEach(function (a) {
                var ty = a.type || 'x';
                out.push({ id: 'src:' + a.id, label: a.name || a.user || 'Source', help: SRC_TITLE[ty] + (a.big ? ' · ' + (a.groups || []).length + ' of ' + (a.ngroups || '?') + ' groups chosen' : ''),
                    right: badge(ty) + 'Switch' + (a.big ? ' · Choose groups' : '') + ' · Remove' + chev(), open: function () { return sourcePage(a, false); } });
            });
            out.push({ id: 'add', label: 'Add a source', right: 'Xtream login · M3U playlist · Stalker portal' + chev(), run: function () { Onboard.open({ add: true }); } });
            var last = 0; try { last = +localStorage.getItem('nx_refreshed') || 0; } catch (e) { /* none */ }
            out.push({ hd: 'Catalogue' });
            out.push({ id: 'refresh', label: 'Refresh catalogue', help: last ? 'Last refreshed ' + when(last) : 'Loads the source’s lists again', right: 'Refresh now' + chev(), run: function () {
                try { localStorage.setItem('nx_refreshed', String(Date.now())); } catch (e) { /* full */ }
                U.toast('Refreshing…'); setTimeout(function () { location.reload(); }, 600); } });
        } else if (id === 'channels') {
            var flags = '<span class="stflags">' + S.countries.map(flag).join('') + '</span>';
            out.push({ hd: 'Countries on Live and Home' });
            out.push({ id: 'pinned', label: 'Pinned countries', help: 'Shown first on Live, each with its own row on Home', right: flags + '<b>&nbsp;' + S.countries.length + '</b>' + chev(), open: pinnedPage });
            out.push({ id: 'regions', label: 'Regions', right: (regionNames || 'Every region of your source') + chev(), run: function () { goLive(); } });
            out.push({ hd: 'Starred channels' });
            S.countries.forEach(function (cc) {
                var f = favsOf(cc), names = f.slice(0, 4).map(function (x) { return x.name; }).join(', ') + (f.length > 4 ? ' + ' + (f.length - 4) : '');
                var logos = ''; f.slice(0, 3).forEach(function (x) { if (x.img) logos += '<span class="stlogo">' + U.imgTag(x.img) + '</span>'; });
                out.push({ id: 'fav:' + cc, label: CC_NAME[cc] || cc.toUpperCase(), help: f.length ? names : 'None yet', right: f.length ? logos + '<b>' + f.length + ' &#9733;</b>' + chev() : 'Browse channels' + chev(), run: function () { ChannelPicker.open(cc); } });
            });
            var other = U.favs().filter(function (x) { return S.countries.indexOf(x.cc || '') < 0; });
            if (other.length) out.push({ id: 'fav:other', label: 'Other countries', help: other.slice(0, 4).map(function (x) { return x.name; }).join(', '), right: '<b>' + other.length + ' &#9733;</b>' + chev(), run: function () { ChannelPicker.open(); } });
            out.push({ hd: 'Channel pages' });
            out.push({ id: 'liveview', label: 'Live view', pills: [['cat', 'Categories', liveView() === 'cat'], ['full', 'Full list', liveView() === 'full']], pick: function (v) { try { localStorage.setItem('nx_live_view', v); } catch (e) { /* full */ } } });
            // stored only: the Live pages always hide lists under 8 channels for now; nothing reads this value yet
            out.push({ id: 'small', label: 'Hide small lists', help: 'Lists under 8 channels stay behind a button', toggle: P.hideSmall, flip: function () { P.hideSmall = !P.hideSmall; saveP(); } });
        } else if (id === 'views') {
            out.push({ hd: 'Home rows · in order' });
            S.rows.forEach(function (r) {
                var cc = /^(be|fr|uk|us)$/.test(r);
                out.push({ id: 'row:' + r, label: cc ? CC_NAME[r] : label(ALL_ROWS, r), help: cc ? 'Live now' : '', move: true, toggle: S.hideRows.indexOf(r) < 0,
                    flip: function () { flip(S.hideRows, r); changed('rows'); } });
            });
            out.push({ hd: 'Menu tabs' });
            out.push({ id: 'tabs', label: 'Tabs shown in the top menu', pills: S.tabs.map(function (t) { return [t, label(ALL_TABS, t), S.hideTabs.indexOf(t) < 0]; }), multi: true,
                pick: function (t) { if (t === 'home') { U.toast('Home is always shown'); return; } flip(S.hideTabs, t); changed('tabs'); } });
            out.push({ hd: 'Look' });
            out.push({ id: 'reset', label: 'Reset layout', help: 'Rows, tabs and tile order back to default', right: 'Reset' + chev(), run: function () {
                S.tabs = ids(ALL_TABS); S.hideTabs = []; S.rows = ids(ALL_ROWS); S.hideRows = []; S.tileOrder = {};
                S.lists.forEach(function (l) { S.rows.splice(1, 0, l.key); });
                changed('tabs'); changed('rows'); U.toast('Layout reset'); } });
        } else if (id === 'lists') {
            out.push({ hd: 'Lists on Home' });
            S.lists.forEach(function (l) { out.push({ id: l.key, label: l.name, help: TYPE[l.t] + ' · a row on Home', right: 'Remove' + chev(), run: function () { Settings.removeList(l.key); } }); });
            out.push({ id: 'addlist', label: 'Add a list', help: 'Every category of your source: live, films and series', right: 'Browse all lists' + chev(), run: function () { Picker.open(); } });
        } else if (id === 'playback') {
            var oa = Subs.account(), left = Subs.left();
            out.push({ hd: 'Audio' });
            out.push({ id: 'audio', label: 'Preferred audio languages', help: 'Picked in this order when a film has them', right: langList(P.audio) + chev(), open: function () { return orderPage('Preferred audio languages', 'audio'); } });
            out.push({ id: 'remember', label: 'Remember my choice per title', toggle: P.remember, flip: function () { P.remember = !P.remember; saveP(); } });
            out.push({ hd: 'Subtitles' });
            out.push({ id: 'show', label: 'Show subtitles', pills: [['always', 'Always', P.show === 'always'], ['notmine', 'When audio is not my language', P.show === 'notmine'], ['never', 'Never', P.show === 'never']],
                pick: function (v) { P.show = v; saveP(); } });
            out.push({ id: 'sublang', label: 'Subtitle language', right: langList(P.subLangs) + chev(), open: function () { return orderPage('Subtitle language', 'subLangs'); } });
            var ll = libLang(), lln = ''; LIB_LANGS.forEach(function (x) { if (x[0] === ll) lln = x[1]; });
            out.push({ id: 'liblang', label: 'Film and series languages', help: 'Which catalogue lists you see', right: '<b>' + U.esc(lln) + '</b>' + chev(), open: libPage });
            out.push({ hd: 'OpenSubtitles' });
            out.push({ id: 'osub', label: 'Account', help: 'Online subtitles when a file has none, aligned to the speech',
                right: (oa && oa.key ? '<span class="stbadge g">SIGNED IN</span>' + U.esc(oa.user || 'API key') + (left != null ? ' · ' + left + ' downloads left today' : '') : '<span class="stbadge">SIGNED OUT</span>Sign in') + chev(),
                run: function () { SubsForm.open(); } });
            // stored only: the player fetches online subtitles from each title's own choice; nothing reads this yet
            out.push({ id: 'autofetch', label: 'Auto-fetch when missing', toggle: P.autoFetch, flip: function () { P.autoFetch = !P.autoFetch; saveP(); } });
        } else if (id === 'data') {
            out.push({ hd: 'On this TV' });
            out.push({ id: 'favs', label: 'Favourite channels', help: count(U.favs().length, 'channel'), right: 'Clear' + chev(), run: function () { U.clearList('favs'); changed('rows'); } });
            out.push({ id: 'continue', label: 'Continue watching', help: count(U.continueList().length, 'title'), right: 'Clear' + chev(), run: function () { U.clearList('continue'); changed('rows'); } });
            out.push({ id: 'mylist', label: 'My List', help: count(U.myList().length, 'title'), right: 'Clear' + chev(), run: function () { U.clearList('mylist'); changed('rows'); } });
            out.push({ id: 'cache', label: 'Cached catalogue', help: 'Lists in memory and the subtitle timing index', right: 'Clear' + chev(), run: function () {
                try { localStorage.removeItem('nx_subref'); } catch (e) { /* none */ } Data.reset(); counts = null; U.toast('Cache cleared'); } });
        } else {
            var model = ''; try { model = webapis.productinfo.getRealModel() || webapis.productinfo.getModel(); } catch (e) { model = 'Samsung TV'; }
            out.push({ hd: 'Nexus TV' });
            out.push({ id: 'ver', label: 'Version', right: '1.1' });
            out.push({ id: 'srcname', label: 'Source', right: U.esc(U.accounts.active().name || 'Signed in') });
            out.push({ id: 'model', label: 'TV model', right: U.esc(model || 'Samsung TV') });
        }
        return out;
    }
    function count(n, unit) { return n + ' ' + unit + (n === 1 ? '' : 's') + ' on this TV'; }
    function langList(a) { return a.map(function (c, i) { return i === 0 ? '<b>' + langName(c) + '</b>' : langName(c); }).join(', '); }
    function when(t) { var d = new Date(t), now = new Date(), hm = (d.getHours() < 10 ? '0' : '') + d.getHours() + ':' + (d.getMinutes() < 10 ? '0' : '') + d.getMinutes();
        return (d.toDateString() === now.toDateString() ? 'today at ' : d.getDate() + '/' + (d.getMonth() + 1) + ' at ') + hm; }
    var regionNames = '';
    function loadRegions() {
        if (regionNames || U.accounts.type() !== 'x') return;
        Data.categories('live', function (list) {
            var seen = {}, n = [];
            (list || []).forEach(function (c) { var m = /^\s*([A-Z0-9]{2,5})\s*\|/.exec(c.name || ''); if (m && REGION_NAME[m[1]] && !seen[REGION_NAME[m[1]]]) { seen[REGION_NAME[m[1]]] = 1; n.push(REGION_NAME[m[1]]); } });
            regionNames = n.length ? n.slice(0, 3).join(', ') + (n.length > 3 ? ' + ' + (n.length - 3) : '') : 'None in this source';
            if (built) render();
        });
    }
    function goLive() { for (var t = 0; t < App.tabs.length; t++) if (App.tabs[t].id === 'guide') { App.goTab(t, true); return; } }

    // ---------- detail pages ----------
    function sourcePage(a, isActive) {
        var rows = [{ hd: SRC_TITLE[a.type || 'x'] }];
        if (!isActive) rows.push({ id: 'switch', label: 'Switch to this source', help: 'The app reloads on it', right: chev(), run: function () { U.toast('Switching source…'); setTimeout(function () { U.accounts.use(a.id); }, 400); } });
        if (a.big) rows.push({ id: 'groups', label: 'Choose groups', help: (a.groups || []).length + ' of ' + (a.ngroups || '?') + ' groups chosen', right: chev(), run: function () {
            if (a.id !== U.accounts.active().id) { U.toast('Switch to this source first'); return; }
            Src.repick(a, function (e, info) {
                if (e) { if (e.message !== 'cancelled') U.toast('Could not read the playlist'); render(); return; }
                a.groups = info.groups; a.ngroups = info.groupCount; U.accounts.persist(); U.toast('Saved. Reloading…');
                setTimeout(function () { location.reload(); }, 700);
            }); } });
        if (!isActive) rows.push({ id: 'remove', label: 'Remove this source', help: 'Its favourites and lists stay on this TV', right: chev(), run: function () {
            if (U.accounts.remove(a.id)) { U.toast('Source removed'); closePage(); } else U.toast('Switch to another source first'); } });
        if (rows.length === 1) rows.push({ id: 'info', label: 'In use', help: 'Switch to another source to remove this one', right: '' });
        return { title: a.name || a.user || 'Source', rows: rows };
    }
    function pinnedPage() {
        var rows = [{ hd: 'Countries on Live and Home' }];
        ALL_CC.forEach(function (c) {
            rows.push({ id: 'cc:' + c[0], label: CC_NAME[c[0]], flag: c[0], toggle: S.countries.indexOf(c[0]) >= 0, flip: function () {
                var i = S.countries.indexOf(c[0]);
                if (i >= 0) { if (S.countries.length > 1) S.countries.splice(i, 1); else { U.toast('Keep at least one country'); return; } }
                else S.countries = ids(ALL_CC).filter(function (x) { return x === c[0] || S.countries.indexOf(x) >= 0; });
                changed('countries'); } });
        });
        return { title: 'Pinned countries', rows: rows };
    }
    function orderPage(title, key) {
        var rows = [{ hd: title + ' · in order' }], list = P[key];
        list.forEach(function (c) { rows.push({ id: 'lang:' + c, label: langName(c), move: true, list: list, toggle: true, flip: function () { if (list.length > 1) { list.splice(list.indexOf(c), 1); saveP(); } else U.toast('Keep at least one'); } }); });
        LANGS.forEach(function (l) { if (list.indexOf(l[0]) < 0) rows.push({ id: 'lang:' + l[0], label: l[1], toggle: false, flip: function () { list.push(l[0]); saveP(); } }); });
        return { title: title, rows: rows, order: key };
    }
    function libPage() {
        var rows = [{ hd: 'Film and series lists' }], cur0 = libLang();
        LIB_LANGS.forEach(function (l) { rows.push({ id: 'lib:' + l[0], label: l[1], right: l[0] === cur0 ? '<b>&#10003;</b>' : '', run: function () {
            try { localStorage.setItem('nx_lib_lang', l[0]); } catch (e) { /* full */ } U.toast('Films and Series show ' + l[1] + ' lists after the next launch'); } });
        });
        return { title: 'Film and series languages', rows: rows };
    }

    // ---------- drawing ----------
    function summary(id) {
        if (id === 'account') return '1 active';
        if (id === 'channels') return S.countries.length + ' countries · ' + U.favs().length + ' &#9733;';
        if (id === 'views') return (S.rows.length - S.hideRows.filter(function (r) { return S.rows.indexOf(r) >= 0; }).length) + ' rows';
        if (id === 'lists') return String(S.lists.length);
        if (id === 'playback') { var oa = Subs.account(); return (P.subLangs[0] || 'en').toUpperCase() + (oa && oa.key ? ' · CC' : ''); }
        if (id === 'about') return '1.1';
        return '';
    }
    function current() { return page ? page.rows : sectionRows(SECTIONS[sec][0]); }
    function focusable(r) { return r && !r.hd; }
    function firstRow(rows) { for (var i = 0; i < rows.length; i++) if (focusable(rows[i])) return i; return 0; }
    function rightHtml(r, f) {
        var h = '';
        if (r.move) h += '<span class="stmove' + (f && pi === 0 ? ' pf' : '') + (f && moving ? ' on-move' : '') + '" data-pi="0">Move &#9650; &#9660;</span>';
        if (r.pills) r.pills.forEach(function (p, i) { h += '<span class="stpill' + (p[2] ? ' on' : '') + (f && pi === i ? ' pf' : '') + '" data-pi="' + i + '">' + U.esc(p[1]) + '</span>'; });
        if (r.right !== undefined) h += r.right;
        if (r.toggle !== undefined) h += '<span class="sttogw' + (f && r.move && pi === 1 ? ' pf' : '') + '"' + (r.move ? ' data-pi="1"' : '') + '>' + tog(r.toggle) + '</span>';
        return h;
    }
    function rowHtml(r, i, y, f) {
        if (r.hd) return '<div class="sthd" style="top:' + y + 'px">' + U.esc(r.hd) + '</div>';
        return '<div class="strw' + (f ? ' f' : '') + (r.first ? ' first' : '') + (r.last ? ' last' : '') + '" id="str' + i + '" style="top:' + y + 'px">' +
            (r.flag ? flag(r.flag) : '') + '<div class="stl' + (r.help ? ' two' : '') + (r.flag ? ' fl' : '') + '">' + U.esc(r.label) + (r.help ? '<small>' + U.esc(r.help) + '</small>' : '') + '</div>' +
            '<div class="stv" id="stv' + i + '">' + rightHtml(r, f) + '</div></div>';
    }
    // positions: a header, then its rows as one rounded group
    function layout(rows) {
        var y = 0, boxes = [], box = null;
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i];
            if (r.hd) { if (box) { boxes.push(box); box = null; } r.y = y + (i ? 26 : 0); y = r.y + 46; continue; }
            if (!box) { box = { y: y, h: 0 }; r.first = true; }
            r.y = y; y += ROW_H; box.h += ROW_H;
            r.last = !rows[i + 1] || rows[i + 1].hd;
        }
        if (box) boxes.push(box);
        rows.boxes = boxes; rows.end = y;
    }
    function render() {
        built = true;
        var nav = '';
        for (var s = 0; s < SECTIONS.length; s++)
            nav += '<div class="stnav' + (s === sec ? ' sel' : '') + (active && col === 0 && s === sec ? ' f' : '') + '" style="top:' + (s * 90) + 'px">' + U.esc(SECTIONS[s][1]) + '<em>' + summary(SECTIONS[s][0]) + '</em></div>';
        U.$('stNav').innerHTML = nav;
        U.$('stCrumb').innerHTML = 'Settings<i>&#8250;</i><span>' + U.esc(SECTIONS[sec][1]) + '</span>' + (page ? '<i>&#8250;</i><span>' + U.esc(page.title) + '</span>' : '');
        var rows = current(); rowsNow = rows; layout(rows);
        if (!focusable(rows[row])) row = firstRow(rows);
        var h = '';
        rows.boxes.forEach(function (b) { h += '<div class="stgrp" style="top:' + b.y + 'px;height:' + b.h + 'px"></div>'; });
        for (var i = 0; i < rows.length; i++) h += rowHtml(rows[i], i, rows[i].y, active && col === 1 && i === row);
        U.$('stPane').innerHTML = h;
        scroll();
    }
    function scroll() {
        var r = rowsNow[row], y = r ? r.y : 0, vis = BOTTOM - TOP;
        if (col === 0) shift = 0;
        else {
            if (y - shift < 60) shift = Math.max(0, y - 60);
            if (y + ROW_H - shift > vis) shift = y + ROW_H - vis;
            // the header of the first group stays when the first rows fit
            if (y + ROW_H <= vis) shift = 0;
        }
        U.setT(U.$('stPane'), 0, -shift);
    }
    // a key press that only moves the focus changes classes, never the pane's content
    function marks(i, on) {
        var v = U.$('stv' + i); if (!v) return;
        var c = v.querySelectorAll('[data-pi]');
        for (var k = 0; k < c.length; k++) {
            var want = on && +c[k].getAttribute('data-pi') === pi, cls = c[k].className.replace(/ pf\b| on-move\b/g, '');
            if (want) cls += ' pf';
            if (want && moving && /stmove/.test(cls)) cls += ' on-move';
            c[k].className = cls;
        }
    }
    function refocus(prev) {
        var a = U.$('str' + prev); if (a && prev !== row) { a.className = a.className.replace(/ f\b/g, ''); marks(prev, false); }
        var b = U.$('str' + row), on = active && col === 1;
        if (b) { b.className = b.className.replace(/ f\b/g, '') + (on ? ' f' : ''); marks(row, on); }
        scroll();
    }
    function navFocus() {
        var list = U.$('stNav').childNodes;
        for (var s = 0; s < list.length; s++) list[s].className = 'stnav' + (s === sec ? ' sel' : '') + (active && col === 0 && s === sec ? ' f' : '');
    }

    // ---------- actions ----------
    function changed(what) { save(); App.applySettings(what); }
    function flip(list, id) { var i = list.indexOf(id); if (i >= 0) list.splice(i, 1); else list.push(id); }
    function openPage(p) { page = p; row = firstRow(p.rows); pi = 0; moving = false; render(); }
    function closePage() { page = null; row = 0; pi = 0; moving = false; render(); }
    function ok() {
        var r = rowsNow[row]; if (!focusable(r)) return;
        if (r.move && pi === 0) { moving = !moving; refocus(row); return; }
        if (r.pills) {
            var p = r.pills[pi]; r.pick(p[0]);
            if (!r.multi) r.pills.forEach(function (x) { x[2] = x[0] === p[0]; }); else if (p[0] !== 'home') p[2] = !p[2];
            var cs = U.$('stv' + row).querySelectorAll('.stpill');   // the pills' on state: classes only
            for (var q = 0; q < cs.length; q++) cs[q].className = 'stpill' + (r.pills[q][2] ? ' on' : '') + (q === pi ? ' pf' : '');
            navFocus(); return;
        }
        if (r.flip) { r.flip(); if (page && page.order) { page = orderPage(page.title, page.order); } else if (page && page.title === 'Pinned countries') page = pinnedPage(); render(); return; }
        if (r.open) { openPage(r.open()); return; }
        if (r.run) { r.run(); if (!SubsForm.isOpen() && !Picker.isOpen() && !ChannelPicker.isOpen() && !Onboard.isOpen()) { if (page && page.title === 'Film and series languages') page = libPage(); render(); } }
    }
    // Move on a Home row (or a language in order): Up / Down carry it
    function moveBy(d) {
        var r = rowsNow[row];
        if (page && page.order) {
            var L = P[page.order], id = r.id.slice(5), i = L.indexOf(id), j = i + d;
            if (i < 0 || j < 0 || j >= L.length) return;
            L[i] = L[j]; L[j] = id; saveP(); page = orderPage(page.title, page.order); row += d; render(); return;
        }
        var key = r.id.slice(4), a = S.rows.indexOf(key), b = a + d;
        if (a < 0 || b < 0 || b >= S.rows.length) return;
        S.rows[a] = S.rows[b]; S.rows[b] = key; changed('rows'); row += d; render();
    }
    function width(r) { return r ? (r.pills ? r.pills.length : r.move ? 2 : 1) : 1; }
    function key(c) {
        if (Picker.isOpen()) return Picker.key(c);
        if (ChannelPicker.isOpen()) return ChannelPicker.key(c);
        if (SubsForm.isOpen()) return SubsForm.key(c);
        var rows = rowsNow;
        if (col === 0) {
            if (c === 38) { if (sec > 0) { sec--; page = null; row = 0; pi = 0; render(); } else return 'up'; }
            else if (c === 40) { if (sec < SECTIONS.length - 1) { sec++; page = null; row = 0; pi = 0; render(); } }
            else if (c === 39 || c === 13) { col = 1; row = firstRow(rows); pi = rows[row] && rows[row].move ? 1 : 0; navFocus(); refocus(row); }
            return true;
        }
        if (moving) {
            if (c === 38) moveBy(-1); else if (c === 40) moveBy(1); else if (c === 13 || c === 37) { moving = false; refocus(row); }
            return true;
        }
        var prev = row, r = rows[row];
        if (c === 38) {
            var i = row - 1; while (i >= 0 && !focusable(rows[i])) i--;
            if (i >= 0) { row = i; pi = startPi(rows[row]); refocus(prev); } else return 'up';
        } else if (c === 40) {
            var j = row + 1; while (j < rows.length && !focusable(rows[j])) j++;
            if (j < rows.length) { row = j; pi = startPi(rows[row]); refocus(prev); }
        } else if (c === 37) {
            if (pi > 0) { pi--; refocus(row); }
            else { col = 0; navFocus(); refocus(row); }
        } else if (c === 39) { if (pi < width(r) - 1) { pi++; refocus(row); } }
        else if (c === 13) ok();
        return true;
    }
    function startPi(r) { if (!r) return 0; if (r.move) return 1; if (r.pills) { for (var i = 0; i < r.pills.length; i++) if (r.pills[i][2]) return r.multi ? 0 : i; } return 0; }
    function back() {
        if (Picker.isOpen()) { Picker.close(); return true; } if (ChannelPicker.isOpen()) { ChannelPicker.close(); return true; } if (SubsForm.isOpen()) { SubsForm.close(); return true; }
        if (moving) { moving = false; refocus(row); return true; }
        if (page) { closePage(); return true; }
        if (col === 1) { col = 0; navFocus(); refocus(row); return true; }
        return false;
    }
    function longPress() { var r = rowsNow[row]; if (!active || col !== 1 || !r || !r.move) return false; pi = 0; moving = true; refocus(row); return true; }
    function init() {
        el = U.$('settings');
        el.innerHTML = '<div class="stcrumb" id="stCrumb"></div>' +
            '<div class="abs" id="stNav" style="left:' + X_NAV + 'px;top:' + TOP + 'px;width:470px;height:800px"></div>' +
            '<div class="abs" id="stClip" style="left:' + (X_PANE - 20) + 'px;top:' + (TOP - 20) + 'px;width:' + (W_PANE + 40) + 'px;height:' + (BOTTOM - TOP + 40) + 'px;overflow:hidden">' +
            '<div class="abs t" id="stPane" style="left:20px;top:20px;width:' + W_PANE + 'px;height:10px"></div></div>' +
            '<div class="overlay" id="stOver"></div>';
    }
    return {
        init: init, key: key, back: back, longPress: longPress,
        show: function () { loadCounts(); loadRegions(); render(); },
        focus: function () { active = true; render(); },
        blur: function () { active = false; if (built) { navFocus(); refocus(row); } },
        refresh: function () { render(); },
        get: function () { return S; },
        addList: function (t, id, name) {
            var key = 'list:' + t + ':' + id;
            for (var i = 0; i < S.lists.length; i++) if (S.lists[i].key === key) { U.toast('Already on Home'); return; }
            S.lists.push({ key: key, t: t, id: id, name: name });
            S.rows.splice(1, 0, key);          // right after Continue watching
            changed('rows'); U.toast('Added to Home: ' + name);
        },
        redraw: function () { if (built) render(); },
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
        // cc (optional): open on that country ('uk' is the provider's UK)
        open: function (cc) { open = true; zone = 0; draw(); load(function () {
            if (cc) for (var i = 0; i < countries.length; i++) if (countries[i].code === cc.toUpperCase()) { ci = i; gi = 0; ch = 0; gTop = 0; hTop = 0; zone = 1; }
            ensure(); if (open) draw(); }); },
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
