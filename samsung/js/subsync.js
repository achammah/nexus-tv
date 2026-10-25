// Subtitle auto sync from the file's own index (the Apple app's SubAutoSync + MatroskaSubIndex, ported to ES5).
// Before a film or episode opens (the account allows one connection, so never while it plays), a few HTTP range
// reads get the Matroska head (Tracks, SeekHead) and the Cues element, or an MP4's moov atom (the tx3g tracks' sample
// tables): every start time of the embedded text track (English first). They are kept per title. When an OpenSubtitles file is picked, its cues are matched against them
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
    // ---------- MP4: the subtitle tracks' sample table in the moov atom ----------
    // A tx3g (mov_text) track lists every sample with its duration (stts) and size (stsz); an empty sample (2 bytes,
    // no text) fills each gap, so a cue starts at the running time of every sample larger than 2 bytes.
    var MOOV_CAP = 2 * 1024 * 1024, MP4_HEAD = 64 * 1024;
    function u32(b, i) { return b[i] * 16777216 + ((b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]); }
    function u64(b, i) { return u32(b, i) * 4294967296 + u32(b, i + 4); }
    function type4(b, i) { return String.fromCharCode(b[i], b[i + 1], b[i + 2], b[i + 3]); }
    // boxes between from and to: [type, data start, box end]; size 1 = 64-bit size, 0 = to the end
    function boxes(b, from, to) {
        var out = [], i = from;
        while (i + 8 <= to) {
            var size = u32(b, i), t = type4(b, i + 4), hdr = 8;
            if (size === 1) { size = u64(b, i + 8); hdr = 16; } else if (size === 0) size = to - i;
            if (size < hdr) break;
            out.push([t, i + hdr, Math.min(to, i + size)]);
            i += size;
        }
        return out;
    }
    function child(b, box, t) { var k = boxes(b, box[1], box[2]); for (var i = 0; i < k.length; i++) if (k[i][0] === t) return k[i]; return null; }
    function path(b, box, names) { for (var i = 0; box && i < names.length; i++) box = child(b, box, names[i]); return box; }
    // the moov atom (its bytes, from its own header): every text track's cue starts, English first, else the fullest
    function parseMoov(m) {
        var moov = ['moov', u32(m, 0) === 1 ? 16 : 8, m.length], mvhd = child(m, moov, 'mvhd'), movieTs = 1000, tracks = [];
        if (mvhd) movieTs = u32(m, mvhd[1] + (m[mvhd[1]] === 1 ? 20 : 12)) || 1000;
        boxes(m, moov[1], m.length).forEach(function (trak) {
            if (trak[0] !== 'trak') return;
            var hdlr = path(m, trak, ['mdia', 'hdlr']), h = hdlr ? type4(m, hdlr[1] + 8) : '';
            if (h !== 'sbtl' && h !== 'text' && h !== 'subt') return;
            var tkhd = child(m, trak, 'tkhd'), mdhd = path(m, trak, ['mdia', 'mdhd']), stbl = path(m, trak, ['mdia', 'minf', 'stbl']);
            if (!mdhd || !stbl) return;
            var v1 = m[mdhd[1]] === 1, ts = u32(m, mdhd[1] + (v1 ? 20 : 12)) || 1000, lc = (m[mdhd[1] + (v1 ? 32 : 20)] << 8) | m[mdhd[1] + (v1 ? 33 : 21)];
            var lang = String.fromCharCode(((lc >> 10) & 31) + 0x60, ((lc >> 5) & 31) + 0x60, (lc & 31) + 0x60);
            var id = tkhd ? u32(m, tkhd[1] + (m[tkhd[1]] === 1 ? 20 : 12)) : tracks.length + 1;
            var stts = child(m, stbl, 'stts'), stsz = child(m, stbl, 'stsz');
            if (!stts) return;
            var one = stsz ? u32(m, stsz[1] + 4) : 0, nsz = stsz ? u32(m, stsz[1] + 8) : 0;
            var sizeOf = function (k) { return one || (k < nsz ? u32(m, stsz[1] + 12 + 4 * k) : 3); };
            // edit list: an empty edit delays the track (movie timescale); a first media time skips into it
            var off = 0, elst = path(m, trak, ['edts', 'elst']);
            if (elst) {
                var ev1 = m[elst[1]] === 1, n = u32(m, elst[1] + 4), p = elst[1] + 8;
                for (var e = 0; e < n; e++) {
                    var dur = ev1 ? u64(m, p) : u32(m, p), mt = ev1 ? u64(m, p + 8) : u32(m, p + 4);
                    if (!ev1 && mt >= 2147483648) mt -= 4294967296;
                    if (ev1 && mt >= 18446744073709552000 / 2) mt = -1;
                    p += ev1 ? 20 : 12;
                    if (mt === -1) off += dur * 1000 / movieTs; else { off -= mt * 1000 / ts; break; }
                }
            }
            var entries = u32(m, stts[1] + 4), q = stts[1] + 8, t = 0, k2 = 0, starts = [];
            for (var s = 0; s < entries; s++, q += 8) {
                var cnt = u32(m, q), delta = u32(m, q + 4);
                for (var c = 0; c < cnt; c++, k2++) { if (sizeOf(k2) > 2) starts.push(Math.round(t * 1000 / ts + off)); t += delta; }
            }
            tracks.push({ n: id, lang: lang, starts: starts });
        });
        if (!tracks.length) return null;
        var pick = null;
        for (var i = 0; i < tracks.length; i++) if (/^en/.test(tracks[i].lang) && tracks[i].starts.length && !pick) pick = tracks[i];
        if (!pick) { pick = tracks[0]; for (var j = 1; j < tracks.length; j++) if (tracks[j].starts.length > pick.starts.length) pick = tracks[j]; }
        return { starts: pick.starts, track: pick.n, lang: pick.lang };
    }
    // Finds moov among the top-level atoms (at the front after faststart, else after mdat) with 16-byte header reads.
    function mp4Starts(url, cb, over, setLive) {
        function readMoov(at, size) {
            if (size > MOOV_CAP) { cb(null, 'moov too big'); return; }
            setLive(range(url, at, size, function (m) {
                if (over()) return;
                if (!m) { cb(null, 'moov'); return; }
                var r; try { r = parseMoov(m); } catch (e) { r = null; }
                cb(r && r.starts.length ? r : null, r ? 'ok' : 'no text track');
            }));
        }
        var hops = 0;
        function hop(at) {   // one atom header at a time, past the media data
            if (++hops > 12) { cb(null, 'no moov'); return; }
            setLive(range(url, at, 16, function (h) {
                if (over()) return;
                if (!h || h.length < 8) { cb(null, 'no moov'); return; }
                var size = u32(h, 0), t = type4(h, 4);
                if (size === 1) size = u64(h, 8);
                if (t === 'moov') { readMoov(at, size); return; }
                if (size < 8) { cb(null, 'no moov'); return; }
                hop(at + size);
            }));
        }
        setLive(range(url, 0, MP4_HEAD, function (b) {
            if (over()) return;
            if (!b || type4(b, 4) !== 'ftyp') { cb(null, b ? 'not mp4' : 'head'); return; }
            var i = 0;
            while (i + 16 <= b.length) {
                var size = u32(b, i), t = type4(b, i + 4);
                if (size === 1) size = u64(b, i + 8);
                if (t === 'moov') {
                    if (i + size <= b.length) { var r; try { r = parseMoov(b.subarray(i, i + size)); } catch (e) { r = null; } cb(r && r.starts.length ? r : null, r ? 'ok' : 'no text track'); }
                    else readMoov(i, size);
                    return;
                }
                if (size < 8) { cb(null, 'no moov'); return; }
                i += size;
            }
            hop(i);   // the next atom header lies past this first read (after the media data)
        }));
    }

    var MP4 = /\.(mp4|m4v)(\?|$)/i;
    // cb(result or null) within CAP_MS; result = { starts, track, lang }. MP4 and M4V: the moov sample tables; else Matroska.
    function referenceStarts(url, cb) {
        var over = false, live = null, t0 = Date.now();
        var finish = function (r, why) { if (over) return; over = true; clearTimeout(cap); cb(r, why, Date.now() - t0); };
        var cap = setTimeout(function () { try { if (live) live.abort(); } catch (e) { /* closed */ } finish(null, 'timeout'); }, CAP_MS);
        if (MP4.test(String(url))) { mp4Starts(url, finish, function () { return over; }, function (x) { live = x; }); return; }
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
    // A title worth reading first: a film or episode in an MKV, MP4 or M4V whose starts are not known yet (one try per session).
    function wants(item) {
        var key = keyOf(item);
        return !!(key && /\.(mkv|mp4|m4v)(\?|$)/i.test(String(item.url || '')) && !cached(key) && !tried[key]);
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
    return { referenceStarts: referenceStarts, parseMoov: parseMoov, parseHead: parseHead, parseCues: parseCues, vote: vote, wants: wants, prefetch: prefetch, cached: cached, keyOf: keyOf };
})();
