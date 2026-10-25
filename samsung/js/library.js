// Films and Series: family shelves of banner cards (the long-list design lock), a grid per list, My List.
// Detail page for one film or series.
var Library = (function () {
    'use strict';
    var el, mode = 'films', active = false;
    var view = 'shelves', shelves = [], sr = 0, sc = 0, scrollRow = 0, offs = {}, page = null, onPill = false;
    var lang = (function () { try { return localStorage.getItem('nx_lib_lang') || 'EN'; } catch (e) { return 'EN'; } })();
    var items = [], sel = 0, rowTop = 0, cache = {}, loadingKey = '', gridCat = null;
    var P = { w: 180, h: 270, gx: 30, gy: 82 };
    var X0 = 112, CW = 384, CH = 216, CG = 24, ROW = 316, TOP = 236, VIS = 5;
    var LANGS = [['EN', 'English'], ['FR', 'Français'], ['', 'All languages']];

    function cols() { return 8; }
    function visRows() { return 3; }
    function pillLabel() { for (var i = 0; i < LANGS.length; i++) if (LANGS[i][0] === lang) return LANGS[i][1]; return 'English'; }

    function setMode(m) {
        if (m === mode && (items.length || shelves.length)) { draw(); return; }
        mode = m; items = []; sel = 0; rowTop = 0; shelves = []; page = null; onPill = false; sr = 0; sc = 0; scrollRow = 0; offs = {};
        if (mode === 'mylist') { view = 'grid'; gridCat = null; loadMyList(); draw(); return; }
        view = 'shelves';
        Data.library(function (lib) { buildShelves(lib); draw(); });
    }
    function buildShelves(lib) {
        var src = mode === 'films' ? lib.films : lib.series;
        shelves = Browse.shelves(src, lang);
        if (page) shelves = [page];
        if (sr >= shelves.length) sr = Math.max(0, shelves.length - 1);
    }
    function loadMyList() {
        items = U.myList().map(function (x) { return { k: x.k, id: x.id, name: x.name, img: x.img, ext: x.ext, sid: x.sid }; });
    }
    function loadCat(c) {
        var key = mode + ':' + c.id;
        items = []; sel = 0; rowTop = 0; gridCat = c; view = 'grid';
        if (cache[key]) { items = cache[key]; draw(); return; }
        loadingKey = key; draw();
        var sk = '';
        for (var r = 0; r < 3; r++) sk += U.skelRow(cols(), 0, r * (P.h + P.gy), P.w, P.h, P.gx);
        U.$('lGrid').innerHTML = sk;
        var t0 = Date.now();
        U.api(mode === 'films' ? { action: 'get_vod_streams', category_id: c.id } : { action: 'get_series', category_id: c.id }, function (err, list) {
            U.log({ ev: 'cat.load', mode: mode, ms: Date.now() - t0, n: list ? list.length : 0, err: err ? String(err) : null });
            var out = [];
            if (list && list.length) {
                for (var i = 0; i < list.length; i++) {
                    var s = list[i];
                    if (mode === 'films') out.push({ k: 'film', id: s.stream_id, name: clean(s.name), img: s.stream_icon || '', ext: s.container_extension || 'mp4' });
                    else out.push({ k: 'series', id: s.series_id, name: clean(s.name), img: s.cover || '' });
                }
            }
            cache[key] = out;
            if (loadingKey !== key) return;
            items = out; drawGrid();
            if (err) U.toast('Could not load this list');
        });
    }
    function clean(n) { return String(n || '').replace(/^\s*[A-Z]{2,3}\s*-\s*/, '').replace(/\s+-\s+UNCUT\b|\s+4K\b/g, '').replace(/\s+\([A-Z]{2}\)$/, ''); }

    // ---- shelves of banner cards ----
    function rgba(t, a) { return 'rgba(' + t[0] + ',' + t[1] + ',' + t[2] + ',' + a + ')'; }
    function card(c, x, y, focus) {
        var t = c.tint, art = '';
        if (c.kind === 'service' && c.logo) art = '<div class="lgb' + (c.dark ? ' lite' : '') + '"><img src="' + c.logo + '" alt="" onerror="this.parentNode.style.display=\'none\'"></div>';
        else if (c.art && c.art.length) { for (var i = 0; i < Math.min(4, c.art.length); i++) art += '<div class="mo" style="left:' + (i * 25) + '%;background-image:url(' + U.img(c.art[i], 'w185') + ')"></div>'; }
        var wash = 'background:-webkit-linear-gradient(left,' + rgba(t, .82) + ' 0%,' + rgba(t, .55) + ' 48%,rgba(0,0,0,.18) 100%);';
        var wash2 = 'background:-webkit-linear-gradient(bottom,rgba(0,0,0,.6),rgba(0,0,0,0) 55%);';
        if (c.kind === 'service' && c.logo) { wash = 'background:-webkit-radial-gradient(80% 20%,120% 120%,' + rgba(t, .5) + ' 0%,#121216 75%);'; wash2 = ''; }
        var count = Browse.fmt(c.n) + ' ' + (c.unit === 'list' ? (c.n === 1 ? 'list' : 'lists') : mode === 'films' ? (c.n === 1 ? 'film' : 'films') : 'series');
        var showName = !(c.kind === 'service' && c.logo);
        return '<div class="card' + (c.muted ? ' muted' : '') + (focus ? ' focus' : '') + '" style="left:' + x + 'px;top:' + y + 'px;width:' + CW + 'px;height:' + CH + 'px;background:' + rgba(t, 1) + '">' +
            (c.kind === 'service' && c.logo ? '<div class="wash" style="' + wash + '"></div>' + art : art + '<div class="wash" style="' + wash + '"></div>' + (wash2 ? '<div class="wash" style="' + wash2 + '"></div>' : '')) +
            '<div class="tx">' + (showName ? '<span class="ct">' + count + '</span><b>' + U.esc(c.name) + '</b>' : '<span class="ct">' + U.esc(c.name) + ' · ' + count + '</span>') + '</div></div>';
    }
    function drawShelves() {
        var g = U.$('lGrid'), h = '';
        U.$('lLeft').style.display = 'none';
        var head = page ? page.title : (mode === 'films' ? 'Films' : 'Series');
        var nLists = 0; for (var i = 0; i < shelves.length; i++) nLists += shelves[i].cards.length;
        U.$('lTitle').innerHTML = U.esc(head) + '<span>' + nLists + ' lists</span>';
        U.$('lTitle').style.left = X0 + 'px';
        var pill = U.$('lPill'); pill.style.display = page ? 'none' : 'block';
        pill.className = 'pill' + (active && onPill ? ' focus' : ''); pill.innerHTML = 'Language&nbsp; <b>' + pillLabel() + '</b>';
        if (sr < scrollRow) scrollRow = sr;
        if (sr > scrollRow + 1) scrollRow = sr - 1;
        var perRow = Math.floor((1920 - X0 * 2 + CG) / (CW + CG));
        for (var r = scrollRow; r < shelves.length && r < scrollRow + 3; r++) {
            var S = shelves[r], y = (r - scrollRow) * ROW;
            var off = offs[r] || 0;
            if (r === sr) { if (sc < off) off = sc; if (sc >= off + perRow) off = sc - perRow + 1; offs[r] = off; }
            h += '<div class="rowtitle" style="left:' + X0 + 'px;top:' + y + 'px">' + U.esc(S.title) + '<span>' + S.cards.length + '</span></div>';
            for (var c = off; c < S.cards.length && c < off + perRow + 1; c++)
                h += card(S.cards[c], X0 + (c - off) * (CW + CG), y + 50, active && !onPill && r === sr && c === sc);
        }
        if (!shelves.length) h = '<div class="empty" style="left:' + X0 + 'px;top:40px">No lists for this language.</div>';
        g.innerHTML = h; g.style.left = '0px'; g.style.top = TOP + 'px';
    }
    function openCard(c) {
        if (c.kind === 'service') {
            if (c.cats.length === 1) { loadCat(c.cats[0]); return; }
            page = { key: 'svc:' + c.name, title: c.name, cards: c.cats.map(function (x) { return { kind: 'list', name: x.label, n: x.n, cat: x, art: x.art, tint: c.tint }; }) };
            shelves = [page]; sr = 0; sc = 0; scrollRow = 0; offs = {}; draw(); return;
        }
        loadCat(c.cat);
    }
    function cyclePill() {
        var i = 0; for (var k = 0; k < LANGS.length; k++) if (LANGS[k][0] === lang) i = k;
        lang = LANGS[(i + 1) % LANGS.length][0];
        try { localStorage.setItem('nx_lib_lang', lang); } catch (e) { /* full */ }
        sr = 0; sc = 0; scrollRow = 0; offs = {};
        Data.library(function (lib) { buildShelves(lib); draw(); });
    }

    // ---- the grid of one list, and My List ----
    function drawGrid() {
        var n = cols(), g = U.$('lGrid'), r0 = Math.floor(sel / n);
        U.$('lLeft').style.display = 'none'; U.$('lPill').style.display = 'none';
        if (r0 < rowTop) rowTop = r0;
        if (r0 >= rowTop + visRows() - 1 && r0 > 0) rowTop = Math.max(0, r0 - (visRows() - 2));
        var h = '', from = rowTop * n, to = Math.min(items.length, (rowTop + visRows()) * n);
        for (var i = from; i < to; i++) {
            var it = items[i], x = (i % n) * (P.w + P.gx), y = (Math.floor(i / n) - rowTop) * (P.h + P.gy);
            var isLive = it.k === 'live';
            h += '<div class="tile ' + (isLive ? 'logo' : 'poster') + (active && i === sel ? ' focus' : '') + '" style="left:' + x + 'px;top:' + y + 'px;width:' + P.w + 'px;height:' + P.h + 'px">' +
                '<div class="nm">' + U.esc(it.name) + '</div>' + U.imgTag(it.img, 'w342') + (isLive ? '' : U.ccBadge(it, gridCat && gridCat.raw)) + '</div>' +
                '<div class="cap" style="left:' + x + 'px;top:' + (y + P.h + 12) + 'px;width:' + P.w + 'px;font-size:19px;text-align:left' + (i === sel ? ';color:#fff' : ';color:rgba(255,255,255,.55)') + '">' + U.esc(it.name) + '</div>';
        }
        if (!items.length && mode === 'mylist') h = '<div class="mlEmpty"><div class="mlBadge"><svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z"/></svg></div>' +
            '<div class="mlTitle">Your list is empty</div><div class="mlSub">Press OK on &#43; My List on any channel, film or series to save it here.</div></div>';
        if (loadingKey === (gridCat ? mode + ':' + gridCat.id : '') && !items.length && mode !== 'mylist') return;
        g.innerHTML = h; g.style.left = X0 + 'px'; g.style.top = '226px';
        var head = mode === 'mylist' ? 'My List' : (gridCat ? gridCat.label : '');
        U.$('lTitle').innerHTML = U.esc(head) + (items.length ? '<span>' + items.length + ' titles</span>' : '');
        U.$('lTitle').style.left = X0 + 'px';
    }
    function draw() { if (view === 'grid') drawGrid(); else drawShelves(); }
    function open(it) {
        if (it.k === 'live') {
            Player.start({ k: 'live', url: U.liveUrl(it.sid || it.id), name: it.name, sub: 'My List', list: [{ sid: it.sid || it.id, name: it.name, sub: 'My List' }], idx: 0 });
            return;
        }
        App.show('detail', it, true);
    }
    function key(c) {
        if (view === 'shelves') {
            var S = shelves[sr];
            if (onPill) {
                if (c === 13) cyclePill();
                else if (c === 40) { onPill = false; draw(); }
                else if (c === 38) return 'up';
                return true;
            }
            if (c === 38) { if (sr > 0) { sr--; sc = Math.min(sc, shelves[sr].cards.length - 1); draw(); } else if (!page) { onPill = true; draw(); } else return 'up'; }
            else if (c === 40 && sr < shelves.length - 1) { sr++; sc = Math.min(sc, shelves[sr].cards.length - 1); draw(); }
            else if (c === 37 && sc > 0) { sc--; draw(); }
            else if (c === 39 && S && sc < S.cards.length - 1) { sc++; draw(); }
            else if (c === 13 && S && S.cards[sc]) openCard(S.cards[sc]);
            return true;
        }
        var n = cols();
        if (c === 37 && sel % n > 0) { sel--; drawGrid(); }
        else if (c === 39 && sel % n < n - 1 && sel < items.length - 1) { sel++; drawGrid(); }
        else if (c === 38) { if (sel >= n) { sel -= n; drawGrid(); } else return 'up'; }
        else if (c === 40 && sel + n < items.length) { sel += n; drawGrid(); }
        else if (c === 40 && Math.floor(sel / n) < Math.floor((items.length - 1) / n)) { sel = items.length - 1; drawGrid(); }
        else if (c === 13 && items[sel]) open(items[sel]);
        return true;
    }
    // Back: a list grid returns to its shelves; a service page returns to the families.
    function back() {
        if (mode === 'mylist') return false;
        if (view === 'grid') { view = 'shelves'; loadingKey = ''; draw(); return true; }
        if (page) { page = null; sr = 0; sc = 0; scrollRow = 0; offs = {}; Data.library(function (lib) { buildShelves(lib); draw(); }); return true; }
        return false;
    }
    function init() {
        el = U.$('lib');
        el.innerHTML = '<div class="glass" id="lLeft" style="left:112px;top:150px;width:400px;height:840px;display:none"></div>' +
            '<div class="rowtitle" id="lTitle" style="top:166px"></div>' +
            '<div class="pill" id="lPill" style="display:none"></div>' +
            '<div class="abs" id="lGrid" style="left:0;top:226px;width:1920px;height:854px"></div>';
    }
    return {
        init: init, key: key, back: back,
        show: function (m) { if (m === 'mylist') { mode = ''; } setMode(m); },
        focus: function () { active = true; draw(); },
        blur: function () { active = false; draw(); },
        refresh: function () { if (mode === 'mylist') loadMyList(); draw(); },
        // long press on a series poster (the Series page grid, My List): the show menu. Anything else opens as on a short press.
        longPress: function () {
            if (!active || onPill || view !== 'grid') return false;
            var it = items[sel];
            if (!it || it.k !== 'series') return false;
            return SeriesMenu.open(it, [], function () { if (mode === 'mylist') loadMyList(); draw(); });
        }
    };
})();

var Detail = (function () {
    'use strict';
    var el, it = null, info = null, row = 0, b = 0, season = 0, ep = 0, seasons = [], eps = {}, req = 0, newIds = {};

    function playFilm() {
        var res = U.getResume({ k: 'film', id: it.id });
        Player.start({ k: 'film', url: U.filmUrl(it.id, it.ext), name: it.name, sub: info ? info.facts : '', pos: res ? res.pos : 0,
            osub: it.tmdb ? { k: 'film', tmdb: it.tmdb } : null,
            resumeItem: { k: 'film', id: it.id, name: it.name, img: it.img, ext: it.ext, tmdb: it.tmdb || '' } });
    }
    function playEp(sIdx, eIdx) { startEp(it, seasons, eps, sIdx, eIdx, function (s2, e2) { season = s2; ep = e2; }); }
    // Plays one episode of a series and chains the next one, from any screen.
    function nextOf(seasons, eps, sIdx, eIdx) {
        var nS = sIdx, nE = eIdx + 1;
        if (nE >= (eps[seasons[sIdx]] || []).length) { nS = sIdx + 1; nE = 0; }
        var e = nS < seasons.length && (eps[seasons[nS]] || [])[nE];
        if (!e) return null;
        var num = e.episode_num || nE + 1, secs = e.info && e.info.duration_secs ? e.info.duration_secs : 0;
        return { s: nS, e: nE, name: 'S' + seasons[nS] + ' E' + num + (e.title ? ' \u00b7 ' + e.title : ''),
            info: { tag: (nS !== sIdx ? 'S' + seasons[nS] + ' ' : '') + 'E' + num, title: cleanEp(e.title), mins: secs ? Math.round(secs / 60) : 0, img: e.info && e.info.movie_image ? e.info.movie_image : '', newSeason: nS !== sIdx } };
    }
    function cleanEp(t) { return t ? String(t).replace(/^.*?-\s*S\d+E\d+\s*-?\s*/i, '') : ''; }
    function startEp(it, seasons, eps, sIdx, eIdx, moved) {
        var list = eps[seasons[sIdx]] || [], e = list[eIdx]; if (!e) return;
        if (moved) moved(sIdx, eIdx);
        U.recordSeen(it.id, eps);
        var res = U.getResume({ k: 'ep', id: e.id });
        var label = it.name + ' · S' + seasons[sIdx] + ' E' + (e.episode_num || eIdx + 1);
        var nx = nextOf(seasons, eps, sIdx, eIdx);
        Player.start({ k: 'ep', url: U.epUrl(e.id, e.container_extension), name: label, sub: e.title || '', pos: res ? res.pos : 0,
            next: nx ? function () { startEp(it, seasons, eps, nx.s, nx.e, moved); } : null, nextName: nx ? nx.name : '', nextInfo: nx ? nx.info : null,
            epctx: { ser: { id: it.id, name: it.name, img: it.img, tmdb: it.tmdb || '' }, seasons: seasons, eps: eps, s: sIdx, e: eIdx, play: function (s2, e2) { startEp(it, seasons, eps, s2, e2, moved); } },
            osub: it.tmdb ? { k: 'ep', stmdb: it.tmdb, season: +seasons[sIdx], episode: +(e.episode_num || eIdx + 1) } : null,
            resumeItem: { k: 'ep', id: e.id, name: label, img: it.img, ext: e.container_extension, series: { id: it.id, name: it.name, img: it.img, tmdb: it.tmdb || '' } } });
    }
    function playSeries() {
        // resume the most recent episode of this series, else season 1 episode 1
        var cont = U.continueList();
        for (var i = 0; i < cont.length; i++) {
            var x = cont[i];
            if (x.k === 'ep' && x.series && String(x.series.id) === String(it.id)) {
                for (var s = 0; s < seasons.length; s++) { var l = eps[seasons[s]] || []; for (var e = 0; e < l.length; e++) if (String(l[e].id) === String(x.id)) { playEp(s, e); return; } }
            }
        }
        playEp(0, 0);
    }
    function buttons() {
        var res = it.k === 'film' ? U.getResume({ k: 'film', id: it.id }) : null;
        var first = it.k === 'film' ? (res ? '&#9654;&nbsp; Resume ' + U.fmtTime(res.pos) : '&#9654;&nbsp; Play') : '&#9654;&nbsp; Play';
        return [first, U.inList(it) ? '&#10003;&nbsp; In My List' : '&#43;&nbsp; My List'];
    }
    function draw() {
        if (!it) return;
        var y = 170, h = '';
        h += '<h1 id="dT">' + U.esc(U.cleanTitle(it.name)) + '</h1>';
        U.$('dBody').innerHTML = h;
        var tH = U.$('dT').offsetHeight;
        y += tH + 18;
        h += '<div class="facts" style="top:' + y + 'px">' + (info ? info.facts : '') + '</div>';
        y += 50;
        h += '<div class="plot" style="top:' + y + 'px">' + U.esc(info ? info.plot : '') + '</div>';
        y += (info && info.plot ? Math.min(136, Math.ceil(info.plot.length / 70) * 34) : 0) + 34;
        var bl = buttons(), x = 112;
        for (var i = 0; i < bl.length; i++) {
            h += '<div class="btn' + (row === 0 && b === i ? ' focus' : '') + '" id="db' + i + '" style="left:' + x + 'px;top:' + y + 'px">' + bl[i] + '</div>';
            x += i === 0 ? (bl[0].length > 30 ? 290 : 186) : 0;
        }
        if (it.k === 'series' && seasons.length) {
            var sy = Math.max(y + 100, 600), sx = 112;
            for (var s = 0; s < seasons.length; s++) {
                h += '<div class="season' + (s === season ? (row === 1 ? ' focus' : ' on') : '') + '" id="ds' + s + '" style="left:' + sx + 'px;top:' + sy + 'px">Season ' + U.esc(seasons[s]) + '</div>';
                sx += 150 + String(seasons[s]).length * 12;
            }
            var list = eps[seasons[season]] || [], ex = 112, off = Math.max(0, ep - 3) * 406;
            h += '<div class="abs t" id="dEps" style="left:0;top:' + (sy + 76) + 'px;width:1920px;height:260px">';
            for (var e = 0; e < list.length && e < 60; e++) {
                var E = list[e], still = E.info && E.info.movie_image ? E.info.movie_image : it.img;
                h += '<div class="ep' + (row === 2 && e === ep ? ' focus' : '') + '" style="left:' + (ex + e * 406 - off) + 'px;top:0"><div class="nm"></div>' + U.imgTag(still, 'w185') +
                    '<div class="fade"></div>' + (newIds[E.id] ? '<div class="newp">NEW</div>' : '') + '<div class="num">' + (E.episode_num || e + 1) + '. ' + U.esc(E.title ? String(E.title).replace(/^.*?-\s*S\d+E\d+\s*-?\s*/i, '') : '') + '</div></div>';
            }
            h += '</div>';
        }
        U.$('dBody').innerHTML = h;
        // lay the buttons out by their real widths
        var bx = 112;
        for (var k = 0; k < bl.length; k++) { var be = U.$('db' + k); if (be) { be.style.left = bx + 'px'; bx += be.offsetWidth + 16; } }
        var px = 112;
        for (var q = 0; q < seasons.length; q++) { var se = U.$('ds' + q); if (se) { se.style.left = px + 'px'; px += se.offsetWidth + 10; } }
    }
    function load(arg) {
        it = arg; info = null; row = 0; b = 0; season = 0; ep = 0; seasons = []; eps = {}; newIds = {};
        var my = ++req;
        U.$('dBack').className = 'back'; U.$('dBack').style.backgroundImage = '';
        draw();
        var p = it.k === 'film' ? { action: 'get_vod_info', vod_id: it.id } : { action: 'get_series_info', series_id: it.id };
        U.api(p, function (err, d) {
            if (my !== req) return;
            if (err || !d) { U.toast('Could not load details'); return; }
            var inf = d.info || {};
            var year = String(inf.releasedate || inf.releaseDate || inf.release_date || '').slice(0, 4);
            var dur = inf.duration || (inf.episode_run_time ? inf.episode_run_time + ' min' : '');
            var facts = [year, U.esc(String(inf.genre || '').split(/[\/,]/)[0]), inf.rating ? '&#9733; ' + U.esc(String(inf.rating).slice(0, 3)) : '', U.esc(dur)].filter(function (x) { return x && !/^0\b/.test(x); });
            if (U.hasSubs(it)) facts.push('<span class="pill dim">CC</span>');
            info = { facts: facts.join('<i>&middot;</i>'), plot: inf.plot || inf.description || '' };
            if (it.k === 'film' && d.movie_data && d.movie_data.container_extension) it.ext = d.movie_data.container_extension;
            it.tmdb = String(inf.tmdb_id || inf.tmdb || '').replace(/\D/g, '');
            if (it.k === 'series') {
                eps = d.episodes || {};
                for (var s in eps) seasons.push(s);
                seasons.sort(function (a, b2) { return (+a) - (+b2); });
                // episodes not seen before: their NEW pills stay for this visit; the seen set is recorded now, which clears Home's badge
                var df = U.diffSeen(it.id, eps); for (var nq = 0; nq < df.news.length; nq++) newIds[df.news[nq].id] = 1;
                U.recordSeen(it.id, eps);
                if (it.goto) {
                    var gi = seasons.indexOf(String(it.goto.season));
                    if (gi >= 0) { season = gi; var gl = eps[seasons[gi]] || []; for (var gj = 0; gj < gl.length; gj++) if (String(gl[gj].id) === String(it.goto.epId)) ep = gj; row = 2; }
                }
            }
            var back = (inf.backdrop_path && inf.backdrop_path[0]) || inf.cover_big || inf.movie_image || inf.cover || it.img;
            if (back) {
                var im = new Image();
                im.onload = function () { if (my !== req) return; U.$('dBack').style.backgroundImage = 'url("' + U.img(back, 'w1280') + '")'; U.$('dBack').className = 'back show'; };
                im.src = U.img(back, 'w1280');
            }
            draw();
        });
    }
    function key(c) {
        if (row === 0) {
            if (c === 37 && b > 0) { b--; draw(); }
            else if (c === 39 && b < 1) { b++; draw(); }
            else if (c === 40 && it.k === 'series' && seasons.length) { row = 1; draw(); }
            else if (c === 13) {
                if (b === 0) { if (it.k === 'film') playFilm(); else if (seasons.length) playSeries(); }
                else { U.toggleList(it); draw(); }
            }
            return true;
        }
        if (row === 1) {
            if (c === 37 && season > 0) { season--; ep = 0; draw(); }
            else if (c === 39 && season < seasons.length - 1) { season++; ep = 0; draw(); }
            else if (c === 38) { row = 0; draw(); }
            else if (c === 40 || c === 13) { row = 2; draw(); }
            return true;
        }
        var list = eps[seasons[season]] || [];
        if (c === 37 && ep > 0) { ep--; draw(); }
        else if (c === 39 && ep < list.length - 1) { ep++; draw(); }
        else if (c === 38) { row = 1; draw(); }
        else if (c === 13) playEp(season, ep);
        return true;
    }
    function playResume(r) {
        if (r.k === 'film') {
            Player.start({ k: 'film', url: U.filmUrl(r.id, r.ext), name: r.name, sub: '', pos: r.pos, osub: r.tmdb ? { k: 'film', tmdb: r.tmdb } : null,
                resumeItem: { k: 'film', id: r.id, name: r.name, img: r.img, ext: r.ext, tmdb: r.tmdb || '' } });
        } else if (r.k === 'ep') {
            var item = { k: 'ep', url: U.epUrl(r.id, r.ext), name: r.name, sub: '', pos: r.pos, resumeItem: { k: 'ep', id: r.id, name: r.name, img: r.img, ext: r.ext, series: r.series } };
            Player.start(item);
            if (!r.series || !r.series.id) return;
            U.api({ action: 'get_series_info', series_id: r.series.id }, function (err, d) {
                if (err || !d || !d.episodes) return;
                var eps2 = d.episodes, ss = []; for (var s in eps2) ss.push(s); ss.sort(function (a, b2) { return (+a) - (+b2); });
                for (var i = 0; i < ss.length; i++) for (var j = 0; j < eps2[ss[i]].length; j++) if (String(eps2[ss[i]][j].id) === String(r.id)) {
                    var stm = String((d.info || {}).tmdb || (d.info || {}).tmdb_id || '').replace(/\D/g, ''), ep0 = eps2[ss[i]][j];
                    if (stm) Player.setSubsItem(item, { k: 'ep', stmdb: stm, season: +ss[i], episode: +(ep0.episode_num || j + 1) });
                    var nx = nextOf(ss, eps2, i, j), ser = { id: r.series.id, name: r.series.name, img: r.series.img, tmdb: stm };
                    if (nx) Player.setNext(item, function () { startEp(ser, ss, eps2, nx.s, nx.e); }, nx.name, nx.info);
                    Player.setEps(item, { ser: ser, seasons: ss, eps: eps2, s: i, e: j, play: function (s2, e2) { startEp(ser, ss, eps2, s2, e2); } });
                    return;
                }
            });
        }
    }
    function init() {
        el = U.$('detail');
        el.innerHTML = '<div class="back" id="dBack" style="background-size:cover;background-position:center top"></div><div class="shade"></div><div class="shade2"></div><div class="abs" id="dBody" style="left:0;top:0;width:1920px;height:1080px"></div>';
    }
    // plays one episode of a series from outside the page (the long-press menu): chained to the next one like any other
    function playEpisode(ser, seasons, eps, sIdx, eIdx) { startEp(ser, seasons, eps, sIdx, eIdx); }
    // the hero's Play on a show with new episodes: the newest new episode
    function playNewest(u) {
        U.api({ action: 'get_series_info', series_id: u.id }, function (err, d) {
            if (err || !d || !d.episodes) { U.toast('Could not load the episodes'); return; }
            var eps2 = d.episodes, ss = []; for (var s in eps2) ss.push(s); ss.sort(function (a, b2) { return (+a) - (+b2); });
            var si = ss.indexOf(String(u.newest.season)), ei = 0;
            if (si < 0) { si = ss.length - 1; }
            var l2 = eps2[ss[si]] || []; for (var j = 0; j < l2.length; j++) if (String(l2[j].id) === String(u.newest.id)) ei = j;
            startEp({ id: u.id, name: u.name || u.t, img: u.img, tmdb: String((d.info || {}).tmdb || (d.info || {}).tmdb_id || '').replace(/\D/g, '') }, ss, eps2, si, ei);
        });
    }
    return { init: init, key: key, show: load, focus: function () { draw(); }, refresh: function () { draw(); }, playResume: playResume, playEpisode: playEpisode, playNewest: playNewest };
})();

// Long press on a series tile (Home rows, Series page, Continue watching, My List): where you are in the show, resume,
// open it, jump to any episode through season then episode chips, My List. `extra` adds the caller's own entries (Move, Hide row).
var SeriesMenu = (function () {
    'use strict';
    function parseSE(name) { var m = /S(\d+)\s*E(\d+)/i.exec(name || ''); return m ? { s: m[1], e: m[2] } : null; }
    function lastResume(sid) {
        var c = U.continueList();
        for (var i = 0; i < c.length; i++) if (c[i].k === 'ep' && c[i].series && String(c[i].series.id) === String(sid)) return c[i];
        return null;
    }
    function chips(show, seasons, eps, si, ei, tmdb, head) {
        var sc = seasons.map(function (sn, i) { return { label: 'S' + sn, on: i === si, run: function () { chips(show, seasons, eps, i, 0, tmdb, head); } }; });
        var list = eps[seasons[si]] || [];
        var ec = list.map(function (e, i) { return { label: 'E' + (e.episode_num || i + 1), on: i === ei, run: function () { Detail.playEpisode({ id: show.id, name: show.name, img: show.img, tmdb: tmdb }, seasons, eps, si, i); } }; });
        Menu.open(show.name, [{ label: 'Season', chips: sc, ci: si }, { label: 'Episode', chips: ec, ci: ei }], head, 1);
    }
    function goTo(show, r, head) {
        U.toast('Loading episodes\u2026');
        U.api({ action: 'get_series_info', series_id: show.id }, function (err, d) {
            if (err || !d || !d.episodes) { U.toast('Could not load the episodes'); return; }
            var eps = d.episodes, seasons = []; for (var s in eps) seasons.push(s);
            seasons.sort(function (a, b) { return (+a) - (+b); });
            if (!seasons.length) { U.toast('No episodes listed'); return; }
            var tmdb = String((d.info || {}).tmdb || (d.info || {}).tmdb_id || '').replace(/\D/g, ''), si = 0, ei = 0, se = r ? parseSE(r.name) : null;
            if (se) for (var i = 0; i < seasons.length; i++) if (String(seasons[i]) === String(se.s)) { si = i; var l = eps[seasons[i]] || []; for (var j = 0; j < l.length; j++) if (String(l[j].id) === String(r.id)) ei = j; }
            chips(show, seasons, eps, si, ei, tmdb, head);
        });
    }
    function open(it, extra, after) {
        var ser = it.k === 'ep' ? it.series : it;
        if (!ser || ser.id == null) return false;
        var show = { k: 'series', id: ser.id, name: ser.name, img: ser.img || '' }, r = lastResume(show.id), se = r ? parseSE(r.name) : null, acts = [];
        var head = U.cleanTitle(show.name) + (se ? ' \u00b7 S' + se.s + ' E' + se.e + (r.pos ? ' at ' + U.fmtTime(r.pos) : '') : '');
        if (r) acts.push({ label: 'Resume' + (se ? ' E' + se.e : ''), icon: '&#9654;', note: r.dur ? U.fmtTime(r.pos) + ' of ' + U.fmtTime(r.dur) : '', run: function () { Detail.playResume(r); } });
        acts.push({ label: 'Open the show', note: 'seasons and episodes', run: function () { App.show('detail', show, true); } });
        acts.push({ label: 'Go to episode\u2026', icon: '&#8250;', run: function () { goTo(show, r, head); } });
        acts.push({ label: U.inList(show) ? 'Remove from My List' : 'Add to My List', icon: U.inList(show) ? '&#8854;' : '&#43;', red: U.inList(show), run: function () { U.toggleList(show); if (after) after(); } });
        Menu.open(show.name, acts.concat(extra || []), head);
        return true;
    }
    return { open: open };
})();
