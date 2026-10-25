// Home: rotating featured title on top, rows below (Continue watching, My List, live channels, new films, top series).
var Home = (function () {
    'use strict';
    // Continue watching entries saved without a picture: read the poster from the provider once, keep it, redraw
    var artAsked = {};
    function fillArt(cont) {
        for (var i = 0; i < cont.length; i++) (function (x) {
            if (x.img || (x.series && x.series.img)) return;
            var sid = x.k === 'ep' ? (x.series && x.series.id) : x.id, key = x.k + ':' + sid;
            if (!sid || artAsked[key]) return; artAsked[key] = 1;
            var p = x.k === 'ep' ? { action: 'get_series_info', series_id: sid } : { action: 'get_vod_info', vod_id: sid };
            U.api(p, function (err, d) {
                var inf = (d && d.info) || {}, img = inf.cover || inf.movie_image || inf.cover_big || (inf.backdrop_path && inf.backdrop_path[0]) || '';
                if (err || !img) return;
                U.setResumeArt(x, img);
                if (window.Data && Data.home) Data.home(function (hd) { buildRows(hd); });
            });
        })(cont[i]);
    }
    var el, page, rowsEl, heroA, heroB, heroFront = 0, dots, meta;
    var moving = false, tileMoving = false, active = false, hero = [], heroIdx = 0, heroT = null, rows = [], r = -1, cols = [], btn = 0, readyCb = null, isReady = false;
    var LOGO = { w: 260, h: 156, gap: 26, cap: 52 }, POSTER = { w: 200, h: 300, gap: 26, cap: 0 };
    var X0 = 114, FIRST_Y = 600, TITLE_H = 64, ROW_GAP = 40;
    // No source yet: Home shows an empty library with one action, Add a source (it opens the sign-in).
    var emptyMode = false, emptyEl = null;
    function noSource() { return !U.accounts.has(); }
    function showEmpty() {
        emptyMode = true; hero = []; rows = []; clearInterval(heroT);
        page.style.display = 'none'; emptyEl.style.display = 'block'; paintEmpty();
    }
    function paintEmpty() { var b = U.$('homeEmptyBtn'); if (b) b.className = 'btn' + (active ? ' focus' : ''); }
    var BTNS = [{ id: 'watch', label: '&#9654;&nbsp; Watch' }, { id: 'list', label: '&#43;&nbsp; My List' }];

    function heroItem() { return hero[heroIdx] || null; }
    function setHero(i, first) {
        if (!hero.length) return;
        heroIdx = (i + hero.length) % hero.length;
        var h = hero[heroIdx], next = heroFront ? heroA : heroB, prev = heroFront ? heroB : heroA;
        var url = U.img(h.back, 'w780');
        var im = new Image();
        im.onload = function () {
            next.style.backgroundImage = 'url("' + url + '")';
            next.className = 'heroimg show'; prev.className = 'heroimg';
            heroFront = 1 - heroFront;
            if (first) markReady();
        };
        im.onerror = function () { if (first) markReady(); };
        im.src = url;
        meta.innerHTML = '<div class="kicker">Top series</div><h1>' + U.esc(h.t) + '</h1>' +
            '<div class="facts">' + [h.year, h.genre, h.rating ? '&#9733; ' + U.esc(h.rating) : ''].filter(function (x) { return x; }).join('<i>&middot;</i>') + '</div>' +
            '<div class="plot">' + U.esc(h.plot) + '</div>';
        var d = '';
        for (var k = 0; k < hero.length; k++) d += '<i class="dot' + (k === heroIdx ? ' on' : '') + '"></i>';
        dots.innerHTML = d;
        drawButtons();
    }
    function markReady() { if (isReady) return; isReady = true; if (readyCb) readyCb(); }
    function rotate() {
        clearInterval(heroT);
        heroT = setInterval(function () { if (r === -1 && !Player.active() && el.className.indexOf('on') > 0) setHero(heroIdx + 1); }, 9000);
    }
    function drawButtons() {
        var h = heroItem(), html = '', x = 112;
        var labels = [BTNS[0].label, h && U.inList({ k: 'series', id: h.id }) ? '&#10003;&nbsp; In My List' : BTNS[1].label];
        for (var i = 0; i < BTNS.length; i++) {
            html += '<div class="btn' + (r === -1 && i === btn && active ? ' focus' : '') + '" id="hb' + i + '" style="left:' + x + 'px;top:494px">' + labels[i] + '</div>';
            x += i === 0 ? 196 : 230;
        }
        U.$('heroBtns').innerHTML = html;
    }

    // ---- rows ----
    // First channels of a country's everyday groups, then a tile that opens that country in the Live guide.
    function liveRow(title, sub, ci, max) {
        var row = { title: title, sub: sub, kind: 'logo', items: [], loading: true, cc: Data.COUNTRIES[ci][0] };
        var code = Data.COUNTRIES[ci][0], favIds = {};
        U.favs().forEach(function (f) {
            var fcc = f.cc || ({ Belgium: 'be', France: 'fr', UK: 'uk', US: 'us' })[String(f.sub || '').split(' ')[0]] || '';
            if (fcc !== code) return;
            favIds[f.sid] = 1;
            row.items.push({ k: 'live', id: f.sid, sid: f.sid, name: f.name, img: f.img, dark: f.dark, sub: f.sub, fav: true });
        });
        var pre = homeData && homeData.live && homeData.live[code];
        if (pre) {
            for (var p = 0; p < pre.c.length; p++) { var x = pre.c[p]; if (favIds[x[3]]) continue; row.items.push({ k: 'live', id: x[3], sid: x[3], name: x[0], img: x[1], dark: x[4], sub: title + ' · ' + U.titleCase(x[2]) }); }
            row.items.push({ k: 'all', ci: ci, name: 'All ' + title + ' channels', n: pre.n });
            row.loading = false;
            return row;
        }
        Data.liveOf(Data.COUNTRIES[ci][0], function fill(d) {
            if (d.lazy && d.g.length && !d.loaded[0]) { Data.loadGroup(d, 0, function () { fill(d); }); return; }   // other accounts: first category
            var seen = {};
            for (var g = 0; g < d.g.length && row.items.length < max; g++) {
                var idx = d.byGroup[g];
                for (var i = 0; i < idx.length && row.items.length < max; i++) {
                    var c = d.c[idx[i]], key = c[0].toLowerCase().replace(/\s+(fhd|uhd|hd|sd|hevc|4k|raw|vip)\b/g, '').replace(/\s+/g, ' ');
                    if (seen[key]) continue; seen[key] = 1;
                    row.items.push({ k: 'live', id: c[3], sid: c[3], name: c[0], img: c[1], sub: title + ' · ' + U.titleCase(d.g[g]) });
                }
            }
            row.items.push({ k: 'all', ci: ci, name: 'All ' + title + ' channels', n: d.c.length });
            row.loading = false;
            layout();
        });
        return row;
    }
    var homeData = null;
    function buildRows(hd) {
        homeData = hd;
        var S = Settings.get(), make = {};
        make['continue'] = function () { var cont = U.continueList(); fillArt(cont); return cont.length ? { title: 'Continue watching', kind: 'poster', items: cont.map(function (x) { return { k: x.k, id: x.id, name: x.name, img: x.img || (x.series && x.series.img), ext: x.ext, series: x.series, resume: x }; }) } : null; };
        make.mylist = function () { var ml = U.myList(); return ml.length ? { title: 'My List', kind: 'poster', items: ml.map(function (x) { return { k: x.k, id: x.id, name: x.name, img: x.img, ext: x.ext, sid: x.sid }; }) } : null; };
        make.newfilms = function () { return { title: 'New films', kind: 'poster', items: hd.newFilms.map(function (f) { return { k: 'film', id: f[0], name: f[1], img: f[2], ext: f[3] }; }) }; };
        make.topseries = function () { return { title: 'Top series', kind: 'poster', items: hd.topSeries.map(function (s) { return { k: 'series', id: s[0], name: s[1], img: s[2] }; }) }; };
        ['be', 'fr', 'uk', 'us'].forEach(function (cc) {
            make[cc] = function () { var ci = Data.countryIndex(cc); return ci < 0 ? null : liveRow(Data.COUNTRIES[ci][1], 'Live now', ci, 24); };
        });
        // lists added in Settings: one row each, filled from the account's catalogue
        S.lists.forEach(function (l) {
            make[l.key] = function () {
                var row = { title: l.name, sub: { live: 'Live', vod: 'Films', series: 'Series' }[l.t], kind: l.t === 'live' ? 'logo' : 'poster', items: [], loading: true };
                Data.itemsOf(l.t, l.id, function (items) { row.items = items.slice(0, 40); row.loading = false; layout(); });
                return row;
            };
        });
        make.all = function () { var ci = Data.countryIndex('all'); return ci < 0 ? null : liveRow('Live', 'Live now', ci, 24); };
        make.favmore = function () {
            var shown = {}; Data.COUNTRIES.forEach(function (c) { shown[c[0]] = 1; });
            var fv = U.favs().filter(function (f) { return !shown[f.cc || ''] ; });
            return fv.length ? { title: 'More favourites', kind: 'logo', items: fv.map(function (x) { return { k: 'live', id: x.sid, sid: x.sid, name: x.name, img: x.img, sub: x.sub, fav: true }; }) } : null;
        };
        rows = [];
        if (S.rows.indexOf('favmore') < 0) S.rows.splice(S.rows.indexOf('newfilms') >= 0 ? S.rows.indexOf('newfilms') : S.rows.length, 0, 'favmore');
        var order = S.rows.slice();   // a playlist or portal adds one 'all' Live row after Continue watching
        if (Data.countryIndex('all') >= 0 && order.indexOf('all') < 0) order.splice(Math.min(1, order.length), 0, 'all');
        for (var i = 0; i < order.length; i++) {
            if (S.hideRows.indexOf(order[i]) >= 0 || !make[order[i]]) continue;
            var row = make[order[i]](); if (row) { row.key = order[i]; rows.push(row); }
        }
        cols = []; for (var i = 0; i < rows.length; i++) cols.push(0);
        if (r > rows.length - 1) r = rows.length - 1;
        layout();
    }
    function rowTop(i) {
        var y = FIRST_Y;
        for (var k = 0; k < i && k < rows.length; k++) { var g = rows[k].kind === 'logo' ? LOGO : POSTER; y += TITLE_H + g.h + g.cap + ROW_GAP; }
        return y;
    }
    function itemId(it) { return (it.k || '') + ':' + (it.sid || it.id || it.name); }
    function applyOrder(row) {
        var ord = row.key && Settings.get().tileOrder[row.key];
        if (!ord || !ord.length || row.ordered === row.items.length) return;
        var pos = {}; for (var i = 0; i < ord.length; i++) pos[ord[i]] = i;
        var idx = row.items.map(function (it, n) { return [it, pos[itemId(it)] !== undefined ? pos[itemId(it)] : 10000 + n]; });
        idx.sort(function (x, y) { return x[1] - y[1]; });
        row.items = idx.map(function (x) { return x[0]; }); row.ordered = row.items.length;
    }
    function layout() {
        rows.forEach(applyOrder);
        var h = '';
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i], g = row.kind === 'logo' ? LOGO : POSTER, y = rowTop(i);
            h += '<div class="rowtitle" style="left:' + X0 + 'px;top:' + y + 'px">' + U.esc(row.title) + (row.sub ? '<span>' + U.esc(row.sub) + '</span>' : '') + '</div>';
            h += '<div class="abs t" id="hr' + i + '" style="left:0;top:' + (y + TITLE_H) + 'px;width:1920px;height:' + (g.h + g.cap) + 'px">';
            if (row.loading || !row.items.length) h += U.skelRow(Math.ceil((1920 - X0) / (g.w + g.gap)), X0, 0, g.w, g.h, g.gap);
            for (var j = 0; j < row.items.length && j < 40; j++) {
                var it = row.items[j];
                var bar = it.resume && it.resume.dur ? '<div class="bar" style="width:' + Math.round(100 * it.resume.pos / it.resume.dur) + '%"></div>' : '';
                h += '<div class="tile ' + (it.k === 'live' || it.k === 'all' ? 'logo' : 'poster') + (it.dark ? ' light' : '') + '" id="h' + i + '_' + j + '" style="left:' + (X0 + j * (g.w + g.gap)) + 'px;top:0;width:' + g.w + 'px;height:' + g.h + 'px">' +
                    (it.fav ? '<div class="favstar">&#9733;</div>' : '') + (it.k === 'all' ? '<div class="nm" style="font-weight:600">' + U.esc(it.name) + '<br><span style="font-size:18px;color:rgba(255,255,255,.55)">' + it.n + ' channels &#8250;</span></div>' : (it.k === 'live' ? U.wordmark(it.name, true) : '<div class="nm">' + U.esc(it.name) + '</div>') + U.imgTag(it.k === 'live' ? U.logoFor(it.name, it.img) : it.img, 'w342')) + (it.k !== 'live' && it.k !== 'all' ? U.ccBadge(it.resume || it) : '') + bar + '</div>';
            }
            if (row.kind === 'logo') h += '<div class="cap" id="hc' + i + '" style="left:0;top:' + (g.h + 18) + 'px;width:380px"></div>';
            h += '</div>';
        }
        // ?boot (opening-frame render): hero only, rows differ per viewer and fade in on the real start
        rowsEl.innerHTML = location.search.indexOf('boot') >= 0 ? '' : h;
        paint();
    }
    function paint() {
        if (emptyMode) { paintEmpty(); return; }
        // vertical: hero visible on row -1 and 0; further rows scroll the page
        var shift = r <= 0 ? 0 : rowTop(r) - 170;
        U.setT(page, 0, -shift);
        U.$('homeTop').style.opacity = r >= 1 ? '1' : '0';
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i], g = row.kind === 'logo' ? LOGO : POSTER, c = cols[i] || 0, step = g.w + g.gap;
            var visible = Math.floor((1920 - X0 * 2) / step);
            var off = Math.max(0, Math.min(c - (visible - 2), row.items.length - visible)) * step;
            var rel = U.$('hr' + i); if (rel) U.setT(rel, -Math.max(0, off), 0);
            for (var j = 0; j < row.items.length && j < 40; j++) {
                var t = U.$('h' + i + '_' + j);
                if (t) t.className = 'tile ' + (row.items[j].k === 'live' || row.items[j].k === 'all' ? 'logo' : 'poster') + (row.items[j].dark ? ' light' : '') + (t.className.indexOf('hasimg') > 0 ? ' hasimg' : '') + (active && i === r && j === c ? ' focus' : '') + (moving && i === r ? ' jiggle' + (j % 2 ? ' odd' : '') : '') + (tileMoving && i === r && j === c ? ' lifted' : '');
            }
            var cap = U.$('hc' + i);
            if (cap) {
                var it = row.items[c];
                cap.innerHTML = active && i === r && it && it.k === 'live' ? U.esc(it.name) + ' &nbsp;<span class="pill live">LIVE</span>' : '';
                cap.style.left = (X0 + c * step - 60) + 'px';
            }
        }
        drawButtons();
    }
    function activate(it, rowIdx, colIdx) {
        if (it.k === 'all') { LiveHome.openPinned(it.ci); return; }
        if (it.k === 'live') {
            var list = rows[rowIdx].items.filter(function (x) { return x.k === 'live'; }).map(function (x) { return { sid: x.sid, name: x.name, sub: x.sub }; });
            Player.start({ k: 'live', url: U.liveUrl(it.sid), name: it.name, sub: it.sub, list: list, idx: colIdx });
        } else if (it.resume) {
            Detail.playResume(it.resume);
        } else {
            App.show('detail', { k: it.k, id: it.id, name: it.name, img: it.img, ext: it.ext }, true);
        }
    }
    function key(c) {
        if (emptyMode) {
            if (c === 38) return 'up';
            if (c === 13) Onboard.open();
            return true;
        }
        if (r === -1) {
            if (c === 38) return 'up';
            if (c === 37) { if (btn > 0) btn--; else { setHero(heroIdx - 1); rotate(); } drawButtons(); return true; }
            if (c === 39) { if (btn < BTNS.length - 1) btn++; else { setHero(heroIdx + 1); rotate(); } drawButtons(); return true; }
            if (c === 40 && rows.length) { r = 0; paint(); return true; }
            if (c === 13) {
                var h = heroItem(); if (!h) return true;
                if (btn === 0) App.show('detail', { k: 'series', id: h.id, name: h.t, img: h.img }, true);
                else { U.toggleList({ k: 'series', id: h.id, name: h.t, img: h.img }); drawButtons(); }
                return true;
            }
            return true;
        }
        if (tileMoving) {
            var R = rows[r], ci = cols[r], last = R.items.length - 1;
            while (last >= 0 && R.items[last].k === 'all') last--;            // the 'All channels' tile stays last
            if (c === 37 || c === 39) {
                var to = ci + (c === 37 ? -1 : 1);
                if (to >= 0 && to <= last) {
                    var t = R.items.splice(ci, 1)[0]; R.items.splice(to, 0, t); cols[r] = to;
                    // slide the existing tiles to their new places (no redraw): the others glide aside
                    var els = [], g = R.kind === 'logo' ? LOGO : POSTER;
                    for (var q = 0; q < R.items.length + 1 && q < 41; q++) { var e = U.$('h' + r + '_' + q); if (e) els.push(e); }
                    var moved = els.splice(ci, 1)[0]; els.splice(to, 0, moved);
                    for (var q2 = 0; q2 < els.length; q2++) { els[q2].id = 'h' + r + '_' + q2; els[q2].style.left = (X0 + q2 * (g.w + g.gap)) + 'px'; }
                    paint();
                }
            } else if (c === 13 || c === 10009 || c === 8) {
                tileMoving = false;
                Settings.saveTileOrder(R.key, R.items.filter(function (x) { return x.k !== 'all'; }).map(itemId));
                R.ordered = R.items.length; paint(); U.toast('Order saved');
            }
            return true;
        }
        if (moving) {
            if (c === 38 || c === 40) { var to = Settings.moveRow(rows[r].key, c === 38 ? -1 : 1, rows.map(function (x) { return x.key; })); if (to) { var k = rows[r].key; Data.home(function (hd) { buildRows(hd); for (var q = 0; q < rows.length; q++) if (rows[q].key === k) r = q; paint(); }); } }
            else if (c === 13 || c === 10009 || c === 8) { moving = false; paint(); U.toast('Row moved'); }
            return true;
        }
        if (r > rows.length - 1) r = rows.length - 1;
        var row = rows[r];
        if (!row) { r = -1; paint(); return true; }
        if (c === 38) { r--; paint(); return true; }
        if (c === 40) { if (r < rows.length - 1) { r++; cols[r] = Math.min(cols[r] || 0, Math.max(0, rows[r].items.length - 1)); paint(); } return true; }
        if (c === 37) { if (cols[r] > 0) { cols[r]--; paint(); } return true; }
        if (c === 39) { if (cols[r] < row.items.length - 1) { cols[r]++; paint(); } return true; }
        if (c === 13 && row.items[cols[r]]) { activate(row.items[cols[r]], r, cols[r]); return true; }
        return true;
    }
    // Fetch and draw Home for the active source; with none, the empty library.
    function load() {
        if (noSource()) { showEmpty(); markReady(); return; }
        emptyMode = false; emptyEl.style.display = 'none'; page.style.display = '';
        Data.home(function (hd) {
            hero = hd.hero || [];
            setHero(0, true);
            buildRows(hd);
            rotate();
        });
    }
    function reloadRows() {
        if (noSource()) { showEmpty(); return; }
        if (emptyMode) { load(); return; }
        Data.home(function (hd) { var keepR = r; buildRows(hd); r = Math.min(keepR, rows.length - 1); paint(); });
    }
    function init() {
        el = U.$('home');
        el.innerHTML = '<div class="page t" id="homePage">' +
            '<div class="heroimg" id="heroA"></div><div class="heroimg" id="heroB"></div><div class="shade"></div><div class="shade2"></div>' +
            '<div class="meta" id="heroMeta"></div><div class="dots" id="heroDots"></div><div id="heroBtns"></div><div id="homeRows"></div></div>' +
            '<div id="homeEmpty"><div class="eh">Your library is empty</div><div class="es">Add a source to see your channels, films and series here.</div>' +
            '<div class="btn" id="homeEmptyBtn" style="left:800px;top:510px;width:320px;text-align:center">Add a source</div></div>' +
            '<div class="abs" id="homeTop" style="left:0;top:0;width:1920px;height:160px;opacity:0;z-index:10;-webkit-transform:translateZ(0);transform:translateZ(0);background:-webkit-linear-gradient(top,#000 78%,rgba(0,0,0,0));background:linear-gradient(180deg,#000 78%,rgba(0,0,0,0))"></div>';
        page = U.$('homePage'); rowsEl = U.$('homeRows'); heroA = U.$('heroA'); heroB = U.$('heroB'); dots = U.$('heroDots'); meta = U.$('heroMeta');
        meta.innerHTML = '<div class="skel line" style="position:relative;width:200px;margin:8px 0 26px"><i></i></div><div class="skel" style="position:relative;width:640px;height:70px;margin-bottom:26px"><i></i></div><div class="skel line" style="position:relative;width:820px;margin-bottom:12px"><i></i></div><div class="skel line" style="position:relative;width:700px"><i></i></div>';
        rowsEl.innerHTML = U.skelRow(7, X0, FIRST_Y + TITLE_H, LOGO.w, LOGO.h, LOGO.gap) + U.skelRow(9, X0, FIRST_Y + TITLE_H * 2 + LOGO.h + LOGO.cap + ROW_GAP, POSTER.w, POSTER.h, POSTER.gap);
        emptyEl = U.$('homeEmpty');
        load();
        setTimeout(markReady, 3000);   // never hold the boot frame longer than this
    }
    return {
        init: init, key: key,
        // favourites, My List and Continue watching can change on other screens: rebuild the rows on return
        show: reloadRows, reload: load,
        focus: function () { active = true; paint(); },
        blur: function () { active = false; paint(); },
        longPress: function () {
            if (emptyMode) return false;
            if (!active || r < 0 || !rows[r]) return false;
            var row = rows[r], it = row.items[cols[r]], acts = [];
            // a series (a tile, or the episode in Continue watching): the show menu, plus this row's own entries
            if (it && (it.k === 'series' || (it.k === 'ep' && it.series && it.series.id != null))) {
                var after = function () { Data.home(function (hd) { buildRows(hd); }); }, own = [];
                if (row.key) own.push({ label: 'Move', icon: '&#8596;', run: function () { tileMoving = true; paint(); U.toast('Left / Right to move \u00b7 OK when done'); } });
                if (it.resume) own.push({ label: 'Remove from Continue watching', icon: '&#8854;', red: true, run: function () { U.removeResume(it.resume); after(); } });
                if (row.key) own.push({ label: 'Hide this row', icon: '&#8854;', red: true, run: function () { Settings.hideRow(row.key); after(); } });
                if (SeriesMenu.open(it, own, after)) return true;
            }
            if (it && it.k === 'live') {
                acts.push({ label: U.isFav(it.sid) ? 'Remove from Favourites' : 'Add to Favourites', icon: U.isFav(it.sid) ? '&#9734;' : '&#9733;', run: function () {
                    U.toggleFav({ sid: it.sid, name: it.name, img: it.img, dark: it.dark, sub: it.sub, cc: (row.cc || '') }); Data.home(function (hd) { buildRows(hd); }); } });
            }
            if (it && it.resume) acts.push({ label: 'Remove from Continue watching', icon: '&#8854;', red: true, run: function () { U.removeResume(it.resume); Data.home(function (hd) { buildRows(hd); }); } });
            if (it && (it.k === 'film' || it.k === 'series') && !it.resume) acts.push({ label: U.inList(it) ? 'Remove from My List' : 'Add to My List', icon: U.inList(it) ? '&#8854;' : '&#43;', red: U.inList(it), run: function () { U.toggleList(it); Data.home(function (hd) { buildRows(hd); }); } });
            if (row.key && it && it.k !== 'all') acts.unshift({ label: 'Move', icon: '&#8596;', run: function () { tileMoving = true; paint(); U.toast('Left / Right to move · OK when done'); } });
            if (row.key) acts.push({ label: 'Hide this row', icon: '&#8854;', red: true, run: function () { Settings.hideRow(row.key); Data.home(function (hd) { buildRows(hd); }); } });
            Menu.open(it ? it.name : row.title, acts);
            return true;
        },
        refresh: reloadRows,
        // back to the state the launcher's card shows: Home, top, first featured title
        resetTop: function () { if (emptyMode) return; r = -1; btn = 0; for (var i = 0; i < cols.length; i++) cols[i] = 0; if (hero.length && heroIdx !== 0) setHero(0); paint(); rotate(); },
        ready: function (cb) { if (isReady) cb(); else readyCb = cb; }
    };
})();
