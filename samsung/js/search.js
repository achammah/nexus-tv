// Search: letter grid on the left, results on the right grouped as Channels, Films, Series.
var Search = (function () {
    'use strict';
    var el, q = '', zone = 0, kr = 0, kc = 0, rr = 0, rc = [0, 0, 0], active = false, res = [[], [], []], timer = null;
    var KEYS = ['abcdef', 'ghijkl', 'mnopqr', 'stuvwx', 'yz0123', '456789'];
    var WIDE = ['SPACE', 'DELETE', 'CLEAR'];
    var ROWS = [
        { title: 'Channels', w: 220, h: 132, gap: 22, kind: 'logo' },
        { title: 'Films', w: 150, h: 225, gap: 22, kind: 'poster' },
        { title: 'Series', w: 150, h: 225, gap: 22, kind: 'poster' }
    ];
    var RX = 760, MAX = 30;

    function drawKeys() {
        var h = '';
        for (var r = 0; r < KEYS.length; r++)
            for (var c = 0; c < 6; c++)
                h += '<div class="key' + (active && zone === 0 && kr === r && kc === c ? ' focus' : '') + '" style="left:' + (112 + c * 94) + 'px;top:' + (270 + r * 82) + 'px">' + KEYS[r].charAt(c).toUpperCase() + '</div>';
        for (var w = 0; w < 3; w++)
            h += '<div class="key w2' + (active && zone === 0 && kr === KEYS.length && kc === w ? ' focus' : '') + '" style="left:' + (112 + w * 188) + 'px;top:' + (270 + KEYS.length * 82) + 'px">' + WIDE[w] + '</div>';
        U.$('sKeys').innerHTML = h;
        U.$('sQ').innerHTML = q ? U.esc(q) + '<span class="caret"></span>' : '<span class="ph">Channels, films, series</span><span class="caret"></span>';
    }
    // groups with no results take no space
    function rowY(i) { var y = 160; for (var k = 0; k < i; k++) if (res[k].length) y += 48 + ROWS[k].h + 56; return y; }
    function drawResults() {
        var h = '';
        if (!q) h = '<div class="empty" style="left:' + RX + 'px;top:170px">Type a few letters. Results show here as you type.</div>';
        else if (!res[0].length && !res[1].length && !res[2].length) h = '<div class="empty" style="left:' + RX + 'px;top:170px">' + (U.$('sQ').getAttribute('data-wait') ? 'Loading the catalogue...' : 'Nothing found for “' + U.esc(q) + '”') + '</div>';
        for (var i = 0; i < 3; i++) {
            if (!res[i].length) continue;
            var R = ROWS[i], y = rowY(i), step = R.w + R.gap, vis = Math.floor((1808 - RX) / step);
            var off = Math.max(0, Math.min(rc[i] - (vis - 2), res[i].length - vis)) * step;
            h += '<div class="rowtitle" style="left:' + RX + 'px;top:' + y + 'px">' + R.title + '<span>' + res[i].length + (res[i].length >= MAX ? '+' : '') + '</span></div>';
            for (var j = 0; j < res[i].length; j++) {
                var it = res[i][j], x = RX + j * step - off;
                if (x < RX || x > 1920) continue;  // a tile scrolled off the left would sit over the keyboard and the input
                h += '<div class="tile ' + R.kind + (active && zone === 1 && rr === i && rc[i] === j ? ' focus' : '') + '" style="left:' + x + 'px;top:' + (y + 48) + 'px;width:' + R.w + 'px;height:' + R.h + 'px">' +
                    '<div class="nm">' + U.esc(it.name) + '</div>' + U.imgTag(it.img, 'w342') + (it.k === 'live' ? '' : U.ccBadge(it)) + (it.lang ? '<div class="langb">' + U.esc(it.lang) + '</div>' : '') + '</div>';
                if (active && zone === 1 && rr === i && rc[i] === j)
                    h += '<div class="cap" style="left:' + (x - 40) + 'px;top:' + (y + 48 + R.h + 14) + 'px;width:' + (R.w + 80) + 'px;font-size:20px">' + U.esc(it.name) + '</div>';
            }
        }
        U.$('sRes').innerHTML = h;
    }
    function draw() { drawKeys(); drawResults(); }

    function score(name, needle) {
        var i = name.indexOf(needle);
        if (i < 0) return -1;
        if (i === 0) return 0;
        var p = name.charAt(i - 1);
        return (p === ' ' || p === '-' || p === ':' || p === '(') ? 1 : 2;
    }
    function pick(names, needle) {
        var out = [];
        for (var i = 0; i < names.length; i++) {
            var s = score(names[i], needle);
            if (s >= 0) { out.push([s, names[i].length, i]); if (out.length > 600) break; }
        }
        out.sort(function (a, b) { return a[0] - b[0] || a[1] - b[1]; });
        return out;
    }
    // same title listed in several categories: keep the first, the one with a picture when possible
    function uniq(list) {
        var seen = {}, out = [];
        for (var i = 0; i < list.length && out.length < MAX; i++) {
            var k = list[i].name.toLowerCase() + '|' + (list[i].lang || '');
            if (seen[k] !== undefined) { if (!out[seen[k]].img && list[i].img) out[seen[k]] = list[i]; continue; }
            seen[k] = out.length; out.push(list[i]);
        }
        return out;
    }
    // Lists added in Settings (any category of the account, any language): searched too.
    var listCache = {};
    function searchLists(needle, done) {
        var lists = Settings.get().lists || [], left = lists.length, hits = [[], [], []];
        if (!left) { done(hits); return; }
        lists.forEach(function (l) {
            var use = function (items) {
                var slot = l.t === 'live' ? 0 : l.t === 'vod' ? 1 : 2;
                items.forEach(function (it) {
                    var lc = it.name.toLowerCase(), sc = score(lc, needle);
                    if (sc >= 0) hits[slot].push({ s: sc, it: it });
                });
                if (--left === 0) {
                    for (var i = 0; i < 3; i++) hits[i] = hits[i].sort(function (a, b) { return a.s - b.s; }).map(function (h) { return h.it; });
                    done(hits);
                }
            };
            if (listCache[l.key]) use(listCache[l.key]);
            else Data.itemsOf(l.t, l.id, function (items) { listCache[l.key] = items; use(items); });
        });
    }
    function run() {
        var needle = q.toLowerCase().replace(/^\s+|\s+$/g, '');
        rc = [0, 0, 0];
        if (!needle) { res = [[], [], []]; drawResults(); return; }
        var chans = [], pending = Data.COUNTRIES.length;
        Data.COUNTRIES.forEach(function (c) {
            Data.liveOf(c[0], function (d) {
                if (!d.lower) { d.lower = []; for (var i = 0; i < d.c.length; i++) d.lower.push(d.c[i][0].toLowerCase()); }
                var hits = pick(d.lower, needle);
                for (var k = 0; k < hits.length; k++) { var ch = d.c[hits[k][2]]; chans.push({ s: hits[k][0], k: 'live', id: ch[3], sid: ch[3], name: ch[0], img: ch[1], sub: c[1] + ' · ' + d.g[ch[2]] }); }
                if (--pending === 0) {
                    chans.sort(function (a, b) { return a.s - b.s; });
                    res[0] = uniq(chans);
                    drawResults();
                }
            });
        });
        U.$('sQ').setAttribute('data-wait', '1');
        Data.searchIndex(function (ix) {
            U.$('sQ').removeAttribute('data-wait');
            if (needle !== q.toLowerCase().replace(/^\s+|\s+$/g, '')) return;
            var films = pick(ix.fl, needle).map(function (h) { var f = ix.f[h[2]]; return { k: 'film', id: f[0], name: f[1], img: f[2], ext: f[4] }; });
            var series = pick(ix.sl, needle).map(function (h) { var s = ix.s[h[2]]; return { k: 'series', id: s[0], name: s[1], img: s[2] }; });
            res[1] = uniq(films); res[2] = uniq(series);
            searchLists(needle, function (hits) {
                if (needle !== q.toLowerCase().replace(/^\s+|\s+$/g, '')) return;
                res[0] = uniq(hits[0].concat(res[0])); films = hits[1].concat(films); series = hits[2].concat(series);
                res[1] = uniq(films); res[2] = uniq(series);
                drawResults();
                // then every other language, after the main results
                if (needle.length < 3) return;
                Data.searchMore(function (mx) {
                    if (needle !== q.toLowerCase().replace(/^\s+|\s+$/g, '')) return;
                    var mf = pick(mx.fl, needle).map(function (h) { var f = mx.f[h[2]]; return { k: 'film', id: f[0], name: f[1], img: '', ext: f[3], lang: mx.langs[f[2]] }; });
                    var ms = pick(mx.sl, needle).map(function (h) { var s = mx.s[h[2]]; return { k: 'series', id: s[0], name: s[1], img: '', lang: mx.langs[s[2]] }; });
                    var mc = pick(mx.cl, needle).map(function (h) { var c = mx.c[h[2]]; return { k: 'live', id: c[0], sid: c[0], name: c[1], img: '', lang: mx.langs[c[2]], sub: mx.langs[c[2]] }; });
                    res[0] = uniq(res[0].concat(mc));
                    res[1] = uniq(films.concat(mf)); res[2] = uniq(series.concat(ms));
                    drawResults();
                });
            });
            U.log({ ev: 'search', q: needle.length, films: res[1].length, series: res[2].length });
            drawResults();
        });
        drawResults();
    }
    function typed() { drawKeys(); clearTimeout(timer); timer = setTimeout(run, 300); }
    function firstRow() { for (var i = 0; i < 3; i++) if (res[i].length) return i; return -1; }
    function open(it) {
        if (it.k === 'live') {
            var list = res[0].map(function (x) { return { sid: x.sid, name: x.name, sub: x.sub }; });
            Player.start({ k: 'live', url: U.liveUrl(it.sid), name: it.name, sub: it.sub, list: list, idx: rc[0] });
        } else App.show('detail', it, true);
    }
    function key(c) {
        if (zone === 0) {
            var wideRow = kr === KEYS.length, width = wideRow ? 3 : 6;
            if (c === 38) { if (kr > 0) { kr--; if (wideRow) kc = kc * 2; } else return 'up'; }
            else if (c === 40 && kr < KEYS.length) { kr++; if (kr === KEYS.length) kc = Math.min(2, Math.floor(kc / 2)); }
            else if (c === 37 && kc > 0) kc--;
            else if (c === 39) { if (kc < width - 1) kc++; else if (firstRow() >= 0) { zone = 1; rr = firstRow(); } }
            else if (c === 13) {
                if (!wideRow) q += KEYS[kr].charAt(kc);
                else if (kc === 0) q += ' ';
                else if (kc === 1) q = q.slice(0, -1);
                else q = '';
                typed();
            }
            else if (c >= 48 && c <= 57) { q += String(c - 48); typed(); }
            draw();
            return true;
        }
        var row = res[rr];
        if (c === 37) { if (rc[rr] > 0) rc[rr]--; else zone = 0; }
        else if (c === 39 && rc[rr] < row.length - 1) rc[rr]++;
        else if (c === 38) { for (var u = rr - 1; u >= 0; u--) if (res[u].length) { rr = u; break; } }
        else if (c === 40) { for (var d = rr + 1; d < 3; d++) if (res[d].length) { rr = d; break; } }
        else if (c === 13 && row[rc[rr]]) open(row[rc[rr]]);
        draw();
        return true;
    }
    function init() {
        el = U.$('search');
        el.innerHTML = '<div class="q" id="sQ"></div><div class="abs" id="sKeys" style="left:0;top:0"></div><div class="abs" id="sRes" style="left:0;top:0;width:1920px;height:1080px"></div>';
    }
    return {
        init: init, key: key,
        show: function () { Data.searchIndex(function () {}); draw(); },
        focus: function () { active = true; draw(); },
        blur: function () { active = false; draw(); },
        refresh: function () { draw(); }
    };
})();
