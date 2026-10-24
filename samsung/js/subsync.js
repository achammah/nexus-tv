// Subtitle auto sync from the file's own index (the Apple app's SubAutoSync + MatroskaSubIndex, ported to ES5).
// Before a film or episode opens (the account allows one connection, so never while it plays), a few HTTP range
// reads get the Matroska head (Tracks, SeekHead) and the Cues element: every start time of the embedded text track
// (English first). They are kept per title. When an OpenSubtitles file is picked, its cues are matched against them
// at once: the offset most starts agree on wins, with the usual 25 / 23.976 frame-rate rescales tried too.
var SubSync = (function () {
    'use strict';
    var WINDOW = 20000, BIN = 100, AGREE = 0.4, MIN_STARTS = 10, MAX_STARTS = 4000, KEEP_TITLES = 12;
    var CAP_MS = 4000, HEAD = 256 * 1024, MAX_CUES = 16 * 1024 * 1024;
    var STORE = 'nx_subref', mem = {};

    // ---------- EBML ----------
    function vint(b, i, keepMarker) {
        if (i >= b.length) return [0, 1];
        var x = b[i], n = 1;
        while (n <= 8 && (x & (0x80 >> (n - 1))) === 0) n++;
        var v = keepMarker ? x : (x & (0xFF >> n));
        for (var j = 1; j < n; j++) if (i + j < b.length) v = v * 256 + b[i + j];
        return [v, n];
    }
    function uint(b, i, n) { var v = 0; for (var j = 0; j < n; j++) if (i + j < b.length) v = v * 256 + b[i + j]; return v; }
    function str(b, i, n) { var s = ''; for (var j = 0; j < n && i + j < b.length; j++) s += String.fromCharCode(b[i + j]); return s.replace(/[\x00-\x1f]/g, ''); }
    // elements between from and to: [id, data start, size] (size -1 = unknown, the rest of the parent)
    function children(b, from, to) {
        var out = [], i = from, end = Math.min(to, b.length);
        while (i < end) {
            var a = vint(b, i, true), s = vint(b, i + a[1], false), unknown = s[0] === Math.pow(2, 7 * s[1]) - 1;
            out.push([a[0], i + a[1] + s[1], unknown ? -1 : s[0]]);
            if (unknown || s[0] < 0) break;
            i += a[1] + s[1] + s[0];
        }
        return out;
    }
    // Head: the Segment's data start, the seek table, the time scale and the subtitle tracks.
    function parseHead(head) {
        var top = children(head, 0, head.length), seg = -1;
        for (var i = 0; i < top.length; i++) if (top[i][0] === 0x18538067) seg = top[i][1];
        if (seg < 0) return null;
        var seeks = {}, tracks = [], scale = 1000000, kids = children(head, seg, head.length);
        for (var k = 0; k < kids.length; k++) {
            var id = kids[k][0], p = kids[k][1], size = kids[k][2];
            if (size < 0) break;
            if (id === 0x114D9B74) {
                children(head, p, p + size).forEach(function (s) {
                    if (s[0] !== 0x4DBB) return;
                    var eid = 0, pos = 0;
                    children(head, s[1], s[1] + Math.max(0, s[2])).forEach(function (e) { if (e[0] === 0x53AB) eid = uint(head, e[1], e[2]); if (e[0] === 0x53AC) pos = uint(head, e[1], e[2]); });
                    seeks[eid] = pos;
                });
            } else if (id === 0x1549A966) {
                children(head, p, p + size).forEach(function (e) { if (e[0] === 0x2AD7B1) scale = uint(head, e[1], e[2]); });
            } else if (id === 0x1654AE6B) {
                children(head, p, p + size).forEach(function (e) {
                    if (e[0] !== 0xAE) return;
                    var n = 0, type = 0, lang = 'eng', codec = '';
                    children(head, e[1], e[1] + Math.max(0, e[2])).forEach(function (f) {
                        if (f[0] === 0xD7) n = uint(head, f[1], f[2]);
                        if (f[0] === 0x83) type = uint(head, f[1], f[2]);
                        if (f[0] === 0x22B59C) lang = str(head, f[1], f[2]);
                        if (f[0] === 0x86) codec = str(head, f[1], f[2]);
                    });
                    if (type === 0x11 && /^S_(TEXT|ASS|SSA)/.test(codec)) tracks.push({ n: n, lang: lang });
                });
            }
            if (id === 0x1F43B675) break;      // the first cluster: the head is over
        }
        return { seg: seg, seeks: seeks, scale: scale, tracks: tracks };
    }
    // Cues body: the start times (ms) of one text track, English first; a track with under 100 entries (forced lines
    // only) is passed over when a fuller one exists.
    function parseCues(body, H) {
        var want = {}, by = {};
        H.tracks.forEach(function (t) { want[t.n] = 1; });
        children(body, 0, body.length).forEach(function (pt) {
            if (pt[0] !== 0xBB) return;
            var t = 0, trs = [];
            children(body, pt[1], pt[1] + Math.max(0, pt[2])).forEach(function (e) {
                if (e[0] === 0xB3) t = uint(body, e[1], e[2]);
                if (e[0] === 0xB7) children(body, e[1], e[1] + Math.max(0, e[2])).forEach(function (f) { if (f[0] === 0xF7) trs.push(uint(body, f[1], f[2])); });
            });
            for (var i = 0; i < trs.length; i++) if (want[trs[i]]) (by[trs[i]] = by[trs[i]] || []).push(Math.round(t * H.scale / 1000000));
        });
        var full = H.tracks.filter(function (t) { return (by[t.n] || []).length >= 100; }), pool = full.length ? full : H.tracks, pick = pool[0];
        for (var j = 0; j < pool.length; j++) if (/^en/.test(pool[j].lang)) { pick = pool[j]; break; }
        var seen = {}, out = [];
        (by[pick.n] || []).forEach(function (x) { if (!seen[x]) { seen[x] = 1; out.push(x); } });
        out.sort(function (a, b) { return a - b; });
        return { starts: out, track: pick.n, lang: pick.lang };
    }

    // ---------- range reads (XHR, arraybuffer) ----------
    function range(url, from, count, cb) {
        var x = new XMLHttpRequest(), done = false;
        try {
            x.open('GET', url, true);
            x.responseType = 'arraybuffer';
            x.setRequestHeader('Range', 'bytes=' + from + '-' + (from + count - 1));
        } catch (e) { cb(null, null); return null; }
        x.onload = function () { if (done) return; done = true; cb(x.status === 206 && x.response ? new Uint8Array(x.response) : null, x); };
        x.onerror = function () { if (!done) { done = true; cb(null, x); } };
        x.send();
        return x;
    }
    // cb(result or null) within CAP_MS; result = { starts, track, lang }
    function referenceStarts(url, cb) {
        var over = false, live = null, t0 = Date.now();
        var finish = function (r, why) { if (over) return; over = true; clearTimeout(cap); cb(r, why, Date.now() - t0); };
        var cap = setTimeout(function () { try { if (live) live.abort(); } catch (e) { /* closed */ } finish(null, 'timeout'); }, CAP_MS);
        live = range(url, 0, HEAD, function (head) {
            if (over) return;
            if (!head) { finish(null, 'head'); return; }
            var H; try { H = parseHead(head); } catch (e) { H = null; }
            if (!H || !H.tracks.length) { finish(null, 'no text track'); return; }
            var at = H.seeks[0x1C53BB6B];
            if (at === undefined) { finish(null, 'no cues'); return; }
            live = range(url, H.seg + at, 16, function (top) {
                if (over) return;
                if (!top) { finish(null, 'cues head'); return; }
                var a = vint(top, 0, true), s = vint(top, a[1], false);
                if (a[0] !== 0x1C53BB6B || s[0] <= 0 || s[0] > MAX_CUES) { finish(null, 'cues id'); return; }
                live = range(url, H.seg + at + a[1] + s[1], s[0], function (body) {
                    if (over) return;
                    if (!body) { finish(null, 'cues body'); return; }
                    var r; try { r = parseCues(body, H); } catch (e) { r = null; }
                    finish(r && r.starts.length ? r : null, r ? 'ok' : 'parse');
                });
            });
        });
    }

    // ---------- the store: starts per title, ms deltas, the last KEEP_TITLES titles ----------
    function readAll() { try { return JSON.parse(localStorage.getItem(STORE) || '{}') || {}; } catch (e) { return {}; } }
    function cached(key) {
        if (!key) return null;
        if (mem[key]) return mem[key];
        var e = readAll()[key]; if (!e || !e.d) return null;
        var out = [], t = 0, p = e.d.split(',');
        for (var i = 0; i < p.length; i++) { t += parseInt(p[i], 36); out.push(t); }
        mem[key] = out; return out;
    }
    function keep(key, starts) {
        mem[key] = starts;
        var all = readAll(), d = [], last = 0;
        for (var i = 0; i < starts.length && i < MAX_STARTS; i++) { d.push((starts[i] - last).toString(36)); last = starts[i]; }
        all[key] = { d: d.join(','), t: Date.now() };
        var keys = []; for (var k in all) keys.push(k);
        keys.sort(function (a, b) { return all[b].t - all[a].t; });
        for (var j = KEEP_TITLES; j < keys.length; j++) delete all[keys[j]];
        try { localStorage.setItem(STORE, JSON.stringify(all)); } catch (e) { /* full: kept in memory for this session */ }
    }
    var tried = {};
    // A title worth reading first: a film or episode in an MKV whose starts are not known yet (one try per session).
    function wants(item) {
        var key = keyOf(item);
        return !!(key && /\.mkv(\?|$)/i.test(String(item.url || '')) && !cached(key) && !tried[key]);
    }
    function keyOf(item) { var r = item && item.resumeItem; return r && r.id != null ? r.k + ':' + r.id : ''; }
    // Reads the starts before the stream opens; cb() always comes, within CAP_MS.
    function prefetch(item, cb) {
        var key = keyOf(item); tried[key] = true;
        referenceStarts(item.url, function (r, why, ms) {
            if (r) keep(key, r.starts);
            U.log({ ev: 'subs.index', n: r ? r.starts.length : 0, lang: r ? r.lang : null, why: why, ms: ms });
            cb();
        });
    }

    // ---------- the vote ----------
    // starts: reference ms (video clock); cues: online cue starts (ms, subtitle clock), sorted. The online cue shown at
    // video time t is the one at t * k - off. Returns { off, k, score, n, ok }.
    function score(starts, cues, k) {
        var bins = {}, best = 0, top = 0;
        for (var i = 0; i < starts.length; i++) {
            var te = starts[i] * k, lo = 0, hi = cues.length - 1;
            while (lo < hi) { var m = (lo + hi) >> 1; if (cues[m] < te - WINDOW) lo = m + 1; else hi = m; }
            for (var j = lo; j < cues.length && cues[j] <= te + WINDOW; j++) { var b = Math.round((te - cues[j]) / BIN); bins[b] = (bins[b] || 0) + 1; }
        }
        for (var key in bins) {
            var q = +key, c = (bins[q - 2] || 0) + (bins[q - 1] || 0) + bins[q] + (bins[q + 1] || 0) + (bins[q + 2] || 0);
            if (c > top || (c === top && Math.abs(q * BIN) < Math.abs(best))) { top = c; best = q * BIN; }
        }
        return { off: best, score: top };
    }
    // ks: the clock scales to try (the file's own one when the frame rates are known, else 1 and the 25 / 23.976 pair)
    function vote(starts, cues, ks) {
        var a = [], res = null;
        for (var i = 0; i < cues.length; i++) a.push(typeof cues[i] === 'number' ? cues[i] : cues[i].a);
        a.sort(function (x, y) { return x - y; });
        for (var q = 0; q < ks.length; q++) {
            var s = score(starts, a, ks[q]);
            if (!res || s.score > res.score) res = { off: s.off, k: ks[q], score: s.score };
        }
        res = res || { off: 0, k: 1, score: 0 };
        // the vote around the winning bin, refined to the ms: the mean of the matched differences
        var k = res.k, sum = 0, n = 0;
        for (var j = 0; j < starts.length; j++) {
            var te = starts[j] * k, lo = 0, hi = a.length - 1;
            while (lo < hi) { var m = (lo + hi) >> 1; if (a[m] < te - res.off - 250) lo = m + 1; else hi = m; }
            if (lo < a.length && Math.abs(te - a[lo] - res.off) <= 250) { sum += te - a[lo]; n++; }
        }
        if (n) res.off = Math.round(sum / n);
        res.n = starts.length;
        res.ok = starts.length >= MIN_STARTS && res.score >= Math.min(starts.length, a.length) * AGREE;
        return res;
    }
    return { referenceStarts: referenceStarts, parseHead: parseHead, parseCues: parseCues, vote: vote, wants: wants, prefetch: prefetch, cached: cached, keyOf: keyOf };
})();
