// A country's Live page (the Mac LiveBrowsePage): its lists as banner cards on family shelves ("Main channels",
// "Sports, kids & documentary", "Regional", events and pay-per-view last). OK on a card opens that list's channels
// in the guide (js/guide.js) on top of this page; Back returns to the same card. A country with one list skips
// this page and opens its channels directly. Cards and headings match the Films page (js/library.js).
var LiveCountry = (function () {
    'use strict';
    // families of Browse.live in the Mac app (Shared/Core/Browse.swift), first rule that matches wins
    var FAMS = [['main', 'Main channels'], ['sport', 'Sports'], ['news', 'News'], ['movies', 'Films & series'], ['kids', 'Kids'],
        ['doc', 'Documentary'], ['music', 'Music'], ['reg', 'Regional'], ['ev', 'Events & pay-per-view']];
    var RULES = [['ev', /PPV|EVENT|PAY PER VIEW|PACKAGE|VIP|RED BUTTON|ⱽ/],
        ['sport', /SPORT|LEAGUE|FOOTBALL|EPL|CHAMPIONSHIP|CUP|F1|FORMULA|EUROSPORT|NBA|NFL|MLB|NHL|NCAA|ESPN|DAZN|TENNIS|MLS|LIGUE|RUGBY|GAA|FLO|SOCCER|BEIN|EQUIPE|DEPORTES/],
        ['news', /NEWS/], ['kids', /KIDS|KINDEREN|ENFANTS/], ['doc', /DOC|DISCOVERY/],
        ['movies', /MOVIE|CINE|SERIES|NETFLIX|SKY STORE|24\/7|SKYMIX|APPLE TV|TUBI|PLUTO|REALITY|^PRIME|AMAZON PRIME/],
        ['music', /MUSIC|MC VIDEO/], ['reg', /WALLONIË|CARIBBEAN|SPECTRUM|TELEMUNDO|TELESAT|REGIO/]];
    var QUAL = /\s+(HEVC|FHD|UHD|HD|LQ|SD|4K)$/;

    // the Films page grid: title row, shelves of 384 x 216 cards
    var X0 = 112, CW = 384, CH = 216, CG = 24, ROW = 316, TOP = 236;
    var PER_ROW = Math.floor((1920 - X0 * 2 + CG) / (CW + CG));

    var el, active = false, cur = null, d = null, shelves = [], sr = 0, sc = 0, scrollRow = 0, offs = {}, token = 0;

    function family(raw) {
        raw = String(raw || '').toUpperCase().replace(QUAL, '');
        for (var i = 0; i < RULES.length; i++) if (RULES[i][1].test(raw)) return RULES[i][0];
        return 'main';
    }
    // Lists = the guide's own categories (Browse.live: quality copies merged, small lists hidden), on Mac families.
    function build() {
        var lists = [];
        Browse.live(d).forEach(function (sec) { sec.items.forEach(function (it) { lists.push(it); }); });
        var by = {};
        lists.forEach(function (it) { var f = family(d.g[it.gi[0]]); it.lfam = f; (by[f] = by[f] || []).push(it); });
        var out = [];
        FAMS.forEach(function (f) {
            var l = by[f[0]]; if (!l) return;
            if (!d.lazy) l.sort(function (a, b) { return b.n - a.n; });
            out.push({ key: f[0], name: f[1], lists: l });
        });
        // families of one list share one shelf ("Sports, kids & documentary"), where the first of them stood
        var single = out.filter(function (s) { return s.lists.length === 1 && s.key !== 'main' && s.key !== 'ev'; });
        if (single.length >= 2) {
            var names = single.map(function (s, i) { return i === 0 ? s.name : s.name.toLowerCase(); });
            var joined = names.slice(0, -1).join(', ') + ' & ' + names[names.length - 1];
            var merged = { key: 'mixed', name: joined, lists: [] };
            single.forEach(function (s) { merged.lists.push(s.lists[0]); });
            var at = out.indexOf(single[0]);
            out = out.filter(function (s) { return single.indexOf(s) < 0; });
            out.splice(Math.min(at, out.length), 0, merged);
        }
        shelves = out;
        return lists.length;
    }

    // ---- a card: colour wash from the left, count + name, a 2 x 3 mosaic of the list's channel logos at right ----
    function tint(name) {   // the TV cannot read a logo's colour across origins: a hue from the list name
        var h = 0, s = String(name);
        for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360;
        var c = 0.62 * 0.88, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = 0.88 - c, r = 0, g = 0, b = 0;
        if (h < 60) { r = c; g = x; } else if (h < 120) { r = x; g = c; } else if (h < 180) { g = c; b = x; } else if (h < 240) { g = x; b = c; } else if (h < 300) { r = x; b = c; } else { r = c; b = x; }
        return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
    }
    function mix(t, k) { return 'rgb(' + Math.round(t[0] * k + 11 * (1 - k)) + ',' + Math.round(t[1] * k + 11 * (1 - k)) + ',' + Math.round(t[2] * k + 13 * (1 - k)) + ')'; }
    // up to 6 channels, a channel with a logo before one without (the wordmark), one tile per logo
    function tiles(it) {
        var withLogo = [], without = [], seen = {};
        for (var k = 0; k < it.gi.length && withLogo.length < 6; k++) {
            var idx = d.byGroup[it.gi[k]] || [];
            for (var j = 0; j < idx.length && withLogo.length < 6; j++) {
                var c = d.c[idx[j]], key = c[1] || '#' + c[0];
                if (seen[key]) continue; seen[key] = 1;
                if (c[1]) withLogo.push(c); else if (without.length < 6) without.push(c);
            }
        }
        return withLogo.concat(without).slice(0, 6);
    }
    function loaded(it) { if (!d.lazy) return true; for (var k = 0; k < it.gi.length; k++) if (!d.loaded[it.gi[k]]) return false; return true; }
    function card(it, x, y, focus) {
        var t = tint(it.label), mos = '', tl = loaded(it) ? tiles(it) : [];
        for (var i = 0; i < tl.length; i++) {
            var c = tl[i];
            mos += '<div class="lct' + (c[4] ? ' light' : '') + '" style="left:' + (CW - 13 - 226 + (i % 2) * 117) + 'px;top:' + (13 + Math.floor(i / 2) * 66) + 'px">' + U.wordmark(c[0], false) + U.imgTag(c[1]) + '</div>';
        }
        var n = d.lazy && !loaded(it) ? '' : Browse.fmt(it.n) + (it.n === 1 ? ' channel' : ' channels');
        var wash = '-webkit-linear-gradient(left,' + mix(t, .70) + ' 0%,' + mix(t, .45) + ' 42%,rgba(0,0,0,0) 70%)';
        return '<div class="card lcard' + (it.lfam === 'ev' ? ' muted' : '') + (focus ? ' focus' : '') + '" id="lc' + it.__r + '_' + it.__c + '" style="left:' + x + 'px;top:' + y + 'px;width:' + CW + 'px;height:' + CH + 'px;background:#141418">' +
            mos + '<div class="wash" style="background:' + wash + ';background:' + wash.replace('-webkit-linear-gradient(left,', 'linear-gradient(90deg,') + '"></div>' +
            '<div class="tx"><span class="ct">' + n + '</span><b>' + U.esc(it.label) + '</b></div></div>';
    }
    function ensure(it) {   // another account: load a list's channels once its card is on screen (count + mosaic)
        if (loaded(it) || it.asked) return;
        it.asked = true;
        var left = 0, my = token;
        it.gi.forEach(function (g) { if (!d.loaded[g]) { left++; Data.loadGroup(d, g, function () { if (--left === 0 && my === token) { it.n = 0; it.gi.forEach(function (q) { it.n += (d.byGroup[q] || []).length; }); redraw(); } }); } });
    }
    // A key press that keeps the same cards on screen only moves the focus outline: rebuilding the page would
    // reload every logo and make the mosaics flash.
    var lastSig = '', lastFocus = null;
    function moveFocus() {
        var id = 'lc' + sr + '_' + sc, el2 = document.getElementById(id);
        if (lastFocus && lastFocus !== el2) lastFocus.className = lastFocus.className.replace(/ focus\b/g, '');
        if (el2 && !active) el2.className = el2.className.replace(/ focus\b/g, '');
        else if (el2 && el2.className.indexOf(' focus') < 0) el2.className += ' focus';
        lastFocus = el2;
    }
    function draw() {
        if (sr < scrollRow) scrollRow = sr;
        if (sr > scrollRow + 1) scrollRow = sr - 1;
        var S0 = shelves[sr], off0 = offs[sr] || 0;
        if (S0) { if (sc < off0) off0 = sc; if (sc >= off0 + PER_ROW) off0 = sc - PER_ROW + 1; offs[sr] = off0; }
        var sig = scrollRow + '|' + shelves.length;
        for (var q = scrollRow; q < shelves.length && q < scrollRow + 3; q++) sig += '|' + (offs[q] || 0);
        if (sig === lastSig && U.$('lcGrid').firstChild) { moveFocus(); return; }
        lastSig = sig;
        var g = U.$('lcGrid'), h = '', nLists = 0;
        for (var i = 0; i < shelves.length; i++) nLists += shelves[i].lists.length;
        U.$('lcTitle').innerHTML = U.esc(cur ? cur.name : '') + '<span>' + nLists + (nLists === 1 ? ' list' : ' lists') + '</span>';
        if (sr < scrollRow) scrollRow = sr;
        if (sr > scrollRow + 1) scrollRow = sr - 1;
        for (var r = scrollRow; r < shelves.length && r < scrollRow + 3; r++) {
            var S = shelves[r], y = (r - scrollRow) * ROW, off = offs[r] || 0;
            if (r === sr) { if (sc < off) off = sc; if (sc >= off + PER_ROW) off = sc - PER_ROW + 1; offs[r] = off; }
            h += '<div class="rowtitle" style="left:' + X0 + 'px;top:' + y + 'px">' + U.esc(S.name) + '<span>' + S.lists.length + (S.lists.length === 1 ? ' list' : ' lists') + '</span></div>';
            h += '<div class="lcall" style="top:' + (y + 4) + 'px">See all ' + S.lists.length + ' &#8250;</div>';
            for (var c = off; c < S.lists.length && c < off + PER_ROW + 1; c++) {
                ensure(S.lists[c]); S.lists[c].__r = r; S.lists[c].__c = c;
                h += card(S.lists[c], X0 + (c - off) * (CW + CG), y + 50, active && r === sr && c === sc);
            }
        }
        if (!shelves.length) h = '<div class="empty" style="left:' + X0 + 'px;top:40px">No channel lists in this country.</div>';
        g.innerHTML = h;
        lastFocus = document.getElementById('lc' + sr + '_' + sc);
    }
    function redraw() { lastSig = ''; draw(); }
    function toGuide(gi) {
        if (cur.pin >= 0) Guide.openCountry(cur.pin, gi); else Guide.openCode(cur.cc, cur.name, gi);
        App.show('guide', null, true); Guide.focus();
    }
    // o = { cc: 'be', name: 'Belgium', pin: index in Data.COUNTRIES or -1 }
    function open(o) {
        var my = ++token;
        Data.liveOf(o.cc, function (data) {
            if (my !== token) return;
            var same = cur && cur.cc === o.cc && d === data;
            cur = o; d = data;
            var n = build();
            if (!same) { sr = 0; sc = 0; scrollRow = 0; offs = {}; }
            if (n === 1) { LiveList.open({ d: d, list: shelves[0].lists[0], ctx: cur }); return; }   // one list only: its channels straight away
            if (n === 0) { toGuide(); return; }
            App.show('livec', null, true); active = true; redraw();
        });
    }
    function key(c) {
        var S = shelves[sr];
        if (!S) return c === 38 ? 'up' : true;
        if (c === 38) { if (sr > 0) { sr--; sc = Math.min(sc, shelves[sr].lists.length - 1); draw(); return true; } return 'up'; }
        if (c === 40) { if (sr < shelves.length - 1) { sr++; sc = Math.min(sc, shelves[sr].lists.length - 1); draw(); } return true; }
        if (c === 37) { if (sc > 0) { sc--; draw(); } return true; }
        if (c === 39) { if (sc < S.lists.length - 1) { sc++; draw(); } return true; }
        if (c === 13) { LiveList.open({ d: d, list: S.lists[sc], ctx: cur }); return true; }   // the list's channels as a grid, like the Mac
        return true;
    }
    function init() {
        el = U.$('livec');
        el.innerHTML = '<div class="rowtitle" id="lcTitle" style="left:' + X0 + 'px;top:166px"></div>' +
            '<div class="abs" id="lcGrid" style="left:0;top:' + TOP + 'px;width:1920px;height:844px"></div>';
    }
    return {
        init: init, key: key, open: open,
        show: function () { if (d) draw(); },
        focus: function () { active = true; if (d) redraw(); },
        blur: function () { active = false; if (d) draw(); },
        refresh: function () { if (d) draw(); }
    };
})();
