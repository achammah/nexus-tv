// Online subtitles from OpenSubtitles: search by TMDb id (films) or series TMDb id + season + episode,
// download one SRT on a pick, parse it into timed cues. Search is free; each download counts toward the daily quota.
var Subs = (function () {
    'use strict';
    var API = 'https://api.opensubtitles.com/api/v1', UA = 'NexusLive v1.0';
    function load(k, d) { try { var v = JSON.parse(localStorage.getItem(k) || 'null'); return v === null ? d : v; } catch (e) { return d; } }
    function save(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* full */ } }
    var acct = load('nx_osub', null) || (window.OSUB ? { key: OSUB.key, user: OSUB.user, pass: OSUB.pass } : null);
    var tok = load('nx_osub_tok', null);   // { token, base, left, at }

    function req(method, path, body, auth, cb, base) {
        var x = new XMLHttpRequest(), done = false;
        x.open(method, 'https://' + (base || 'api.opensubtitles.com') + '/api/v1' + path, true);
        x.setRequestHeader('Api-Key', acct.key); x.setRequestHeader('Accept', 'application/json');
        if (body) x.setRequestHeader('Content-Type', 'application/json');
        if (auth && tok) x.setRequestHeader('Authorization', 'Bearer ' + tok.token);
        x.timeout = 20000;
        x.onreadystatechange = function () {
            if (x.readyState !== 4 || done) return; done = true;
            var d = null; try { d = JSON.parse(x.responseText); } catch (e) { /* not json */ }
            if (x.status >= 200 && x.status < 300) cb(null, d); else cb({ status: x.status, message: (d && (d.message || d.errors && d.errors[0])) || ('HTTP ' + x.status) }, d);
        };
        x.ontimeout = function () { if (!done) { done = true; cb({ status: 0, message: 'timeout' }); } };
        x.send(body ? JSON.stringify(body) : null);
    }
    function login(cb) {
        if (!acct || !acct.key) { cb({ message: 'No OpenSubtitles account' }); return; }
        if (!acct.user) { tok = null; cb(null); return; }                   // key only: fewer downloads
        if (tok && Date.now() - tok.at < 20 * 3600 * 1000) { cb(null); return; }
        req('POST', '/login', { username: acct.user, password: acct.pass }, false, function (e, d) {
            if (e || !d || !d.token) { cb(e || { message: 'Login refused' }); return; }
            tok = { token: d.token, base: d.base_url || 'api.opensubtitles.com', left: d.user ? d.user.allowed_downloads : null, at: Date.now() };
            save('nx_osub_tok', tok); cb(null);
        });
    }
    // item: { k: 'film', tmdb } or { k: 'ep', stmdb, season, episode }. langs: ['fr', 'en'].
    function search(item, langs, cb) {
        if (!acct || !acct.key) { cb(null, []); return; }
        if (item.url && item.hash === undefined) { fileHash(item.url, function (hh) { item.hash = hh; search(item, langs, cb); }); return; }
        var q = item.k === 'film' ? 'tmdb_id=' + encodeURIComponent(item.tmdb)
            : 'parent_tmdb_id=' + encodeURIComponent(item.stmdb) + '&season_number=' + item.season + '&episode_number=' + item.episode;
        if ((item.k === 'film' && !item.tmdb) || (item.k === 'ep' && (!item.stmdb || !item.season || !item.episode))) { cb(null, []); return; }
        if (item.hash) q += '&moviehash=' + item.hash;
        q += '&languages=' + langs.slice().sort().join(',') + '&order_by=download_count';
        req('GET', '/subtitles?' + q, null, false, function (e, d) {
            if (e) { cb(e, []); return; }
            var out = [], seen = {};
            (d && d.data || []).forEach(function (r) {
                var a = r.attributes || {}, f = (a.files || [])[0]; if (!f || a.machine_translated || a.ai_translated || (a.nb_cd || 1) > 1) return;
                out.push({ file: f.file_id, lang: a.language, name: a.release || f.file_name || '', hi: !!a.hearing_impaired, n: a.download_count || 0,
                    fps: +a.fps || 0, trusted: !!a.from_trusted, exact: !!a.moviehash_match });
            });
            // same language first, then the same frame rate as the file (no drift), then trusted uploaders, then most downloaded
            var fps = +item.fps || 0, same = function (r) { return fps && r.fps && Math.abs(r.fps - fps) < 0.05 ? 0 : 1; };
            // A named web or disc release with a frame rate is cut like the files providers carry; a nameless one
            // (often a cinema recording) is timed for another cut. Measured: 46 of 88 lines in time against 21.
            var q = function (r) { return (r.fps ? 1 : 0) + (/web|blu-?ray|bdrip|brrip|hdtv|amzn|nf\b|dsnp|hmax|atvp/i.test(r.name) ? 2 : 0) + (r.trusted ? 1 : 0); };
            out.sort(function (x, y) { return langs.indexOf(x.lang) - langs.indexOf(y.lang) || (y.exact - x.exact) || same(x) - same(y) || q(y) - q(x) || (x.hi - y.hi) || y.n - x.n; });
            var all = out.slice();
            out = out.filter(function (r) { var c = seen[r.lang] = (seen[r.lang] || 0) + 1; return c === 1; });   // the best one per language
            out.forEach(function (r) { r.alts = all.filter(function (x) { return x.lang === r.lang && x !== r && !x.hi; }).slice(0, 3); });
            cb(null, out);
        });
    }
    // OpenSubtitles file hash: size + 64-bit sum of the first and last 64 KB. A match means subtitles made for this exact file.
    var hashes = {};
    function chunk(url, range, cb) {
        var x = new XMLHttpRequest(); x.open('GET', url, true); x.responseType = 'arraybuffer'; x.setRequestHeader('Range', 'bytes=' + range); x.timeout = 15000;
        x.onreadystatechange = function () { if (x.readyState !== 4) return; if (x.status !== 206 || !x.response) { cb(null); return; } cb(x.response, x.getResponseHeader('Content-Range')); };
        x.ontimeout = function () { cb(null); };
        x.send(null);
    }
    function fileHash(url, cb) {
        if (hashes[url] !== undefined) { cb(hashes[url]); return; }
        var C = 65536, h = [0, 0];
        function add(lo, hi) { var l = h[0] + lo; h[0] = l >>> 0; h[1] = (h[1] + hi + (l > 0xFFFFFFFF ? 1 : 0)) >>> 0; }
        function sum(buf) { var v = new DataView(buf); for (var i = 0; i + 8 <= v.byteLength; i += 8) add(v.getUint32(i, true), v.getUint32(i + 4, true)); }
        chunk(url, '0-' + (C - 1), function (head, cr) {
            var size = cr ? +String(cr).split('/')[1] : 0;
            if (!head || !(size > C * 2)) { hashes[url] = ''; cb(''); return; }
            chunk(url, (size - C) + '-' + (size - 1), function (tail) {
                if (!tail) { hashes[url] = ''; cb(''); return; }
                add(size % 4294967296, Math.floor(size / 4294967296)); sum(head); sum(tail);
                var hx = function (n) { var t = n.toString(16); return new Array(9 - t.length).join('0') + t; };
                hashes[url] = hx(h[1]) + hx(h[0]); cb(hashes[url]);
            });
        });
    }
    // A sign-in pass OpenSubtitles has cancelled (signed in again elsewhere, or expired early) answers 401
    // "invalid token": sign in once more and retry.
    function download(fileId, cb, again) {
        login(function (e) {
            if (e) { cb(e); return; }
            req('POST', '/download', { file_id: fileId, sub_format: 'srt' }, true, function (e2, d) {
                if (e2 && !again && (e2.status === 401 || /token/i.test(e2.message || ''))) { tok = null; save('nx_osub_tok', null); download(fileId, cb, true); return; }
                if (e2 || !d || !d.link) { cb(e2 || { message: 'No link' }); return; }
                if (tok) { tok.left = d.remaining; save('nx_osub_tok', tok); }
                var x = new XMLHttpRequest(); x.open('GET', d.link, true); x.timeout = 20000;
                x.onreadystatechange = function () { if (x.readyState === 4) { if (x.status === 200) cb(null, parse(x.responseText), d.remaining); else cb({ message: 'HTTP ' + x.status }); } };
                x.send(null);
            }, tok ? tok.base : null);
        });
    }
    function ms(t) { var m = /(\d+):(\d+):(\d+)[,.](\d+)/.exec(t); return m ? ((+m[1] * 60 + +m[2]) * 60 + +m[3]) * 1000 + +m[4] : 0; }
    function parse(srt) {
        var cues = [], blocks = String(srt || '').replace(/\r/g, '').split(/\n\s*\n/);
        for (var i = 0; i < blocks.length; i++) {
            var l = blocks[i].split('\n'), j = 0;
            while (j < l.length && l[j].indexOf('-->') < 0) j++;
            if (j >= l.length) continue;
            var t = l[j].split('-->');
            cues.push({ a: ms(t[0]), b: ms(t[1]), x: l.slice(j + 1).join('\n').replace(/<[^>]+>/g, '').replace(/\{[^}]+\}/g, '') });
        }
        return cues;
    }
    // The cue on screen at time t (ms), by binary search.
    function at(cues, t) {
        var lo = 0, hi = cues.length - 1;
        while (lo <= hi) { var m = (lo + hi) >> 1; if (cues[m].b < t) lo = m + 1; else if (cues[m].a > t) hi = m - 1; else return cues[m].x; }
        return '';
    }
    return {
        ready: function () { return !!(acct && acct.key); },
        account: function () { return acct; },
        left: function () { return tok ? tok.left : null; },
        setAccount: function (a, cb) { var old = acct, oldTok = tok; acct = a; tok = null; login(function (e) { if (e) { acct = old; tok = oldTok; cb(e); return; } save('nx_osub', acct); cb(null); }); },
        search: search, download: download, at: at
    };
})();
