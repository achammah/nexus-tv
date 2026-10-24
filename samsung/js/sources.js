// Source adapters. A source is a way to reach a library: an Xtream login (handled by U.api itself), an M3U playlist
// or a Stalker portal. The two adapters here answer the same calls the screens already make (get_live_categories,
// get_live_streams, get_vod_streams ...) with the same shapes, so Home, Live, Films and Search work unchanged.
// ES5 only: the Tizen 3 engine is WebKit 538.
var Src = (function () {
    'use strict';
    function trim(s) { return String(s == null ? '' : s).replace(/^\s+|\s+$/g, ''); }
    function enc(s) { return encodeURIComponent(s); }

    // ---------- M3U playlist ----------
    function attrs(line) {
        var o = {}, re = /([A-Za-z0-9_-]+)="([^"]*)"/g, m;
        while ((m = re.exec(line))) o[m[1].toLowerCase()] = m[2];
        return o;
    }
    function isFilm(u) { return /\.(mp4|mkv)(\?.*)?$/i.test(u); }
    function extOf(u) { var m = /\.(mp4|mkv)(\?.*)?$/i.exec(u || ''); return m ? m[1].toLowerCase() : 'mp4'; }
    // #EXTINF:-1 tvg-id="" tvg-name="" tvg-logo="" group-title="Group",Display name  then the stream URL on the next line.
    // group-title is the group (several, separated by ;, put the channel in each); .mp4 / .mkv entries are films, everything else is live.
    // Also read: url-tvg / x-tvg-url in the header (the guide link), #EXTGRP, http-user-agent / http-referrer from #EXTVLCOPT lines,
    // from EXTINF attributes or from a Kodi style "url|User-Agent=..&Referer=..". CRLF and a BOM are tolerated.
    var opts = {};      // stream URL -> { ua, ref }: what the player sends for that channel
    var CAP_KEPT = 60000;               // a very large playlist keeps at most this many entries
    var LIMIT = 8 * 1024 * 1024, CHUNK = 4 * 1024 * 1024;      // up to LIMIT bytes everything is kept; beyond it the group picker asks

    // The parser is incremental: lines go in one by one (or as byte chunks), so a huge file never sits in memory.
    // mode 'all' keeps every entry · 'index' keeps only a count per group · 'filter' keeps entries of the ticked groups.
    function Parser() {
        this.out = { live: { g: [], by: {} }, vod: { g: [], by: {} }, guide: '', n: 0, odd: 0, orphans: 0 };
        this.info = null; this.idx = {}; this.order = []; this.mode = 'all'; this.keep = null; this.kept = 0; this.capped = false; this.carry = null;
    }
    Parser.prototype.line = function (raw) {
        var l = trim(raw), out = this.out;
        if (!l) return;
        if (l.indexOf('#EXTM3U') === 0) {
            var h = attrs(l), gl = h['url-tvg'] || h['x-tvg-url'] || h['tvg-url'] || '';
            out.guide = trim(gl.split(',')[0]);
            return;
        }
        if (l.indexOf('#EXTINF') === 0) {
            var a = attrs(l), q = l.lastIndexOf('"'), c = l.indexOf(',', q < 0 ? 0 : q);
            this.info = { name: c >= 0 ? trim(l.slice(c + 1)) : '', tvgName: a['tvg-name'] || '', logo: a['tvg-logo'] || '', group: a['group-title'] || '', tvgId: a['tvg-id'] || '',
                ua: a['http-user-agent'] || '', ref: a['http-referrer'] || a['http-referer'] || '' };
            return;
        }
        var info = this.info;
        if (l.indexOf('#EXTGRP:') === 0) { if (info && !info.group) info.group = trim(l.slice(8)); return; }
        if (l.indexOf('#EXTVLCOPT:') === 0) {
            var kv = l.slice(11), eq = kv.indexOf('=');
            if (info && eq > 0) {
                var k = kv.slice(0, eq).toLowerCase(), val = trim(kv.slice(eq + 1));
                if (k === 'http-user-agent') info.ua = val; else if (k === 'http-referrer' || k === 'http-referer') info.ref = val;
            }
            return;
        }
        if (l.charAt(0) === '#') { out.odd++; return; }
        if (!info) { out.orphans++; return; }
        var bar = l.indexOf('|');
        if (bar > 0 && /^https?:/i.test(l)) {      // Kodi style headers after the address
            var hs = l.slice(bar + 1).split('&'); l = l.slice(0, bar);
            for (var z = 0; z < hs.length; z++) {
                var e2 = hs[z].indexOf('='); if (e2 < 0) continue;
                var hk = hs[z].slice(0, e2).toLowerCase(), hv = hs[z].slice(e2 + 1);
                try { hv = decodeURIComponent(hv); } catch (x) { /* keep as is */ }
                if (hk === 'user-agent') info.ua = hv; else if (hk === 'referer' || hk === 'referrer') info.ref = hv;
            }
        }
        var film = isFilm(l);
        this.add(film ? out.vod : out.live, film ? 'f' : 'l', { stream_id: l, name: info.name || info.tvgName || l, stream_icon: info.logo, container_extension: extOf(l), tvg_id: info.tvgId }, (info.group || 'Other').split(';'), info);
        this.info = null;
    };
    Parser.prototype.add = function (T, kind, ent, gs, info) {
        var any = false;
        for (var gi = 0; gi < gs.length; gi++) {
            var g = trim(gs[gi]) || 'Other', key = 'g:' + g, ix = this.idx[g];
            if (!ix) { ix = this.idx[g] = { n: 0, dropped: 0, kind: kind }; this.order.push(g); }
            ix.n++;
            var store = this.mode === 'all' || (this.mode === 'filter' && this.keep[g] === 1 && this.kept < CAP_KEPT);
            if (!store) { ix.dropped++; if (this.mode === 'filter' && this.keep[g] === 1) this.capped = true; continue; }
            if (!T.by[key]) { T.by[key] = []; T.g.push(g); }
            T.by[key].push(ent); any = true; this.kept++;
        }
        if (any) { this.out.n++; if (info.ua || info.ref) opts[ent.stream_id] = { ua: info.ua, ref: info.ref }; }
    };
    // switch to 'filter': entries already held for groups that are not ticked go away
    Parser.prototype.setKeep = function (keep) {
        this.keep = keep; this.mode = 'filter'; this.kept = 0; this.out.n = 0;
        var kinds = [this.out.live, this.out.vod];
        for (var i = 0; i < 2; i++) {
            var T = kinds[i], g2 = [];
            for (var j = 0; j < T.g.length; j++) {
                var g = T.g[j];
                if (keep[g] === 1) { g2.push(g); this.kept += T.by['g:' + g].length; this.out.n += T.by['g:' + g].length; }
                else { if (this.idx[g]) this.idx[g].dropped += T.by['g:' + g].length; delete T.by['g:' + g]; }
            }
            T.g = g2;
        }
    };
    function utf8(u8) {
        var bin = '', i, part;
        for (i = 0; i < u8.length; i += 8192) { part = Array.prototype.slice.call(u8.subarray(i, i + 8192)); bin += String.fromCharCode.apply(null, part); }
        try { return decodeURIComponent(escape(bin)); } catch (e) { return bin; }
    }
    // bytes in; only whole lines are parsed (a newline byte never occurs inside a UTF-8 character), the rest waits for the next chunk
    Parser.prototype.feedBytes = function (u8, last) {
        var data = u8;
        if (this.carry && this.carry.length) { data = new Uint8Array(this.carry.length + u8.length); data.set(this.carry, 0); data.set(u8, this.carry.length); }
        var cut = data.length;
        if (!last) { cut = -1; for (var i = data.length - 1; i >= 0; i--) if (data[i] === 10) { cut = i + 1; break; } }
        if (cut < 0) { this.carry = data; return; }
        var lines = utf8(data.subarray(0, cut)).split('\n');
        this.carry = new Uint8Array(data.subarray(cut));     // a copy: the big chunk can go
        for (var j = 0; j < lines.length; j++) this.line(lines[j]);
    };
    function parseM3U(text) {
        var p = new Parser(), lines = String(text).replace(/^﻿/, '').split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) p.line(lines[i]);
        return p.out;
    }

    // ---------- very large playlists: read in ranges, ask which groups to keep ----------
    // One range request. cb(err, { status, bytes, total, big }) ; big = the server ignored Range and the file is bigger than LIMIT.
    function fetchRange(url, from, to, cb) {
        var x = new XMLHttpRequest(), done = false, t = setTimeout(function () { if (!done) { done = true; x.abort(); cb(new Error('timeout')); } }, 120000);
        x.open('GET', url, true);
        x.responseType = 'arraybuffer';
        try { x.setRequestHeader('Range', 'bytes=' + from + '-' + to); } catch (e) { /* the engine may refuse */ }
        x.onreadystatechange = function () {
            if (x.readyState !== 2 || done) return;
            if (x.status === 200) {
                var len = +x.getResponseHeader('Content-Length') || 0;
                if (len > LIMIT) { done = true; clearTimeout(t); x.abort(); cb(null, { status: 200, big: true, total: len }); }
            }
        };
        x.onload = function () {
            if (done) return; done = true; clearTimeout(t);
            if (x.status === 416) { cb(null, { status: 416, bytes: new Uint8Array(0), total: from }); return; }
            if (x.status !== 200 && x.status !== 206) { cb(new Error('HTTP ' + x.status)); return; }
            var cr = /\/(\d+)\s*$/.exec(x.getResponseHeader('Content-Range') || ''), bytes = new Uint8Array(x.response);
            cb(null, { status: x.status, bytes: bytes, total: cr ? +cr[1] : (x.status === 200 ? bytes.length : 0) });
        };
        x.onerror = function () { if (done) return; done = true; clearTimeout(t); cb(new Error('network')); };
        x.send();
    }
    // Reads the whole playlist in ranges. opts.keep: a ticked set to read with (no picker) · opts.force: ask even for a small file.
    // ctl is handed to the picker (GroupPicker): keep(set), cancel(). cb(err, parserOut, info).
    function bigRead(acc, opts, cb) {
        var firstDone = false, parser = new Parser(), off = 0, total = 0, token = {}, picking = false, streamDone = false, current = token, pickedSet = null;
        if (opts.keep) { parser.keep = opts.keep; parser.mode = 'filter'; }
        else if (opts.force) { parser.mode = 'index'; picking = true; }
        var ctl = {
            state: function () { return { off: off, total: total, idx: parser.idx, order: parser.order, done: streamDone, kept: parser.kept, mode: parser.mode }; },
            cancel: function () { current = null; if (window.GroupPicker) GroupPicker.close(); cb(new Error('cancelled')); },
            keep: function (set) {
                var need = false;
                for (var g in set) if (set[g] === 1 && parser.idx[g] && parser.idx[g].dropped > 0) need = true;
                var list = Object.keys(set).filter(function (g) { return set[g] === 1; });
                if (M.info) { M.info.big = true; M.info.groups = list; M.info.groupCount = parser.order.length; }
                var live = U.accounts.active(); if (live && live.base === acc.base) { live.big = true; live.groups = list; live.ngroups = parser.order.length; U.accounts.persist(); }
                if (need) {                 // a ticked group lost entries while only counting: the app restarts and reads again with the choice
                    current = null; if (window.GroupPicker) GroupPicker.reading();
                    if (opts.onReload) opts.onReload(); else bigRead(acc, { keep: set, again: true }, cb);
                    return;
                }
                parser.setKeep(set); picking = false;
                if (window.GroupPicker) GroupPicker.reading();
                if (streamDone) finish(set);
            }
        };
        function finish(set) {
            if (!parser.carry || parser.carry.length) parser.feedBytes(new Uint8Array(0), true);
            if (window.GroupPicker) GroupPicker.close();
            var info = { big: total > LIMIT || !!opts.force, groups: set ? Object.keys(set).filter(function (g) { return set[g] === 1; }) : null, groupCount: parser.order.length, capped: parser.capped };
            cb(null, parser.out, info);
        }
        function step() {
            var mine = current;
            fetchRange(acc.base, off, off + CHUNK - 1, function (e, r) {
                if (mine !== current || current === null) return;
                if (e) { if (window.GroupPicker) GroupPicker.close(); cb(e); return; }
                if (r.big) { if (window.GroupPicker) GroupPicker.close(); cb(null, null, { norange: true }); return; }
                total = r.total || (off + r.bytes.length);
                if (off === 0 && !/#EXTM3U|#EXTINF/.test(utf8(r.bytes.subarray(0, 4000)))) { cb(new Error('not a playlist')); return; }
                parser.feedBytes(r.bytes, false);
                off += r.bytes.length;
                var end = off >= total || r.bytes.length === 0 || r.status === 200;
                if (!firstDone && parser.mode === 'all' && parser.out.n > 0) { firstDone = true; if (opts.onFirst) opts.onFirst(parser.out, ctl.state()); }
                if (opts.onProgress) opts.onProgress(ctl.state());
                if (parser.mode === 'all' && off >= LIMIT && !end) { parser.mode = 'index'; picking = true; }
                if (picking && !(opts.keep)) {
                    if (end) streamDone = true;
                    if (window.GroupPicker) GroupPicker.show(ctl);
                    if (end) { return; }       // everything is counted: wait for the choice
                } else if (window.GroupPicker && GroupPicker.isOpen()) GroupPicker.progress(ctl.state());
                if (end) { if (parser.mode === 'filter' || parser.mode === 'all') finish(opts.keep || (parser.mode === 'filter' ? parser.keep : null)); return; }
                step();
            });
        }
        step();
        return ctl;
    }
    // a thin line at the top of the screen while the rest of a big playlist loads in the background
    function bgProgress(stt) {
        var e = document.getElementById('bgprog'); if (!e) return;
        if (!stt || !stt.total) { e.style.display = 'none'; return; }
        e.style.display = 'block'; e.firstChild.style.width = Math.min(100, Math.round(100 * stt.off / stt.total)) + '%';
    }
    var M = { url: null, d: null, wait: null, info: null };
    function loadM3U(acc, cb) {
        if (M.url === acc.base && M.d) { cb(null, M.d); return; }
        if (M.url === acc.base && M.wait) { M.wait.push(cb); return; }
        M = { url: acc.base, d: null, wait: [cb], info: null };
        var mine = M;
        var settle = function (e, d, info) {
            var w = mine.wait; mine.wait = null;
            if (!e && (!d.live.g.length && !d.vod.g.length)) e = new Error('not a playlist');
            if (e) { if (M === mine) M = { url: null, d: null, wait: null, info: null }; for (var i = 0; i < w.length; i++) w[i](e); return; }
            mine.d = d; mine.info = info || null;
            if (info && info.capped) U.toast('The 60,000 entry limit was reached');
            for (var j = 0; j < w.length; j++) w[j](null, d);
        };
        var plain = function () {       // a normal playlist, or a server without ranges: the first LIMIT bytes
            U.getText(acc.base, function (e, text, partial) {
                if (!e && partial) text = text.slice(0, text.lastIndexOf('\n') + 1);
                if (!e && !/#EXTM3U|#EXTINF/.test(String(text).slice(0, 4000))) e = new Error('not a playlist');
                if (e) { settle(e); return; }
                var d = parseM3U(text);
                if (partial) U.toast('Showing the first ' + String(d.n).replace(/\B(?=(\d{3})+$)/g, ',') + ' entries of a very large playlist');
                settle(null, d, null);
            }, 120000, null, LIMIT);
        };
        var big = function (opts) {
            var early = false;
            M.info = { big: true, groups: acc.groups || null };
            opts.onFirst = function (d, stt) { early = true; settle(null, d, M.info); };
            opts.onProgress = function (stt) { bgProgress(stt); };
            opts.onReload = function () { bgProgress(null); U.toast('Reading your groups\u2026'); setTimeout(function () { location.reload(); }, 500); };
            bigRead(acc, opts, function (e, d, info) {
                bgProgress(null);
                if (info && info.norange) { plain(); return; }
                if (early) { if (info) { M.info = info; if (window.Data) Data.reset(); if (window.Home && Home.refresh) Home.refresh(); } return; }
                if (e) { settle(e); return; }
                settle(null, d, info);
            });
        };
        if (acc.groups) { U.toast('Reading the groups you kept…'); big({ keep: toSet(acc.groups) }); return; }
        fetchRange(acc.base, 0, 0, function (e, r) {
            if (!e && r.status === 206 && r.total > LIMIT) big({}); else plain();
        });
    }
    function toSet(list) { var s = {}; for (var i = 0; i < list.length; i++) s[list[i]] = 1; return s; }
    // Settings > Sources > Choose groups: read the playlist again and ask. cb(err, { groups, groupCount }).
    function repick(acc, cb) {
        M = { url: null, d: null, wait: null, info: null };
        bigRead(acc, { force: true }, function (e, d, info) { if (e) { cb(e); return; } if (info && info.norange) { cb(new Error('no ranges')); return; } cb(null, info); });
    }
    function groupsOf(T) { return T.g.map(function (g) { return { category_id: g, category_name: g }; }); }
    function apiM3U(acc, p, cb) {
        loadM3U(acc, function (e, d) {
            if (e) { cb(e); return; }
            var a = p.action;
            if (a === 'get_live_categories') cb(null, groupsOf(d.live));
            else if (a === 'get_vod_categories') cb(null, groupsOf(d.vod));
            else if (a === 'get_live_streams') cb(null, d.live.by['g:' + p.category_id] || []);
            else if (a === 'get_vod_streams') cb(null, d.vod.by['g:' + p.category_id] || []);
            else if (a === 'get_vod_info') cb(null, { info: {}, movie_data: { container_extension: extOf(p.vod_id) } });
            else if (a === 'get_series_info') cb(null, { info: {}, episodes: {} });
            else cb(null, []);    // series categories and series: a playlist has none
        });
    }

    // ---------- Stalker portal ----------
    // The MAC address is the login. It goes out as the cookie mac=..., the way a set-top box sends it.
    var S = { key: '', token: '', ready: false, wait: null, genres: null, ch: null, vodCats: null };
    function endpoint(base) {
        var u = String(base).replace(/\/+$/, '').replace(/\/c$/, '');
        return /stalker_portal/.test(u) ? u + '/server/load.php' : u + '/portal.php';
    }
    function pcall(acc, qs, cb) {
        var h = { Cookie: 'mac=' + String(acc.mac).toUpperCase() + '; stb_lang=en; timezone=Europe/Paris', 'X-User-Agent': 'Model: MAG250; Link: WiFi' };
        if (S.token) h.Authorization = 'Bearer ' + S.token;
        U.getText(endpoint(acc.base) + '?' + qs + '&JsHttpRequest=1-xml', function (e, t) {
            if (e) { cb(e); return; }
            var d; try { d = JSON.parse(t); } catch (x) { cb(new Error('not a portal answer')); return; }
            cb(null, d && d.js !== undefined ? d.js : d);
        }, 20000, h);
    }
    // handshake (token), then get_profile; both must answer before any list call
    function ensure(acc, cb) {
        var key = acc.base + '|' + String(acc.mac).toUpperCase();
        if (S.key !== key) S = { key: key, token: '', ready: false, wait: null, genres: null, ch: null, vodCats: null };
        if (S.ready) { cb(null); return; }
        if (S.wait) { S.wait.push(cb); return; }
        var mine = S; mine.wait = [cb];
        var fin = function (e) { var w = mine.wait; mine.wait = null; if (e) { mine.token = ''; } else mine.ready = true; for (var i = 0; i < w.length; i++) w[i](e || null); };
        pcall(acc, 'type=stb&action=handshake&token=&prehash=0', function (e, js) {
            if (e) { fin(e); return; }
            if (!js || !js.token) { fin(new Error('refused')); return; }
            mine.token = js.token;
            pcall(acc, 'type=stb&action=get_profile&hd=1&auth_second_step=0&client_type=STB&api_signature=263', function (e2, prof) {
                if (e2) { fin(e2); return; }
                if (!prof || typeof prof !== 'object') { fin(new Error('refused')); return; }
                fin(null);
            });
        });
    }
    function logoUrl(acc, logo) {
        if (!logo) return '';
        if (/^https?:\/\//.test(logo)) return logo;
        var m = /^https?:\/\/[^\/]+/.exec(acc.base), origin = m ? m[0] : '';
        return origin + (logo.charAt(0) === '/' ? '' : '/stalker_portal/misc/logos/320/') + logo;
    }
    function cats(list) {
        var out = [];
        for (var i = 0; i < (list || []).length; i++) {
            var c = list[i]; if (!c || String(c.id) === '*') continue;
            out.push({ category_id: String(c.id), category_name: c.title || c.name || String(c.id) });
        }
        return out;
    }
    function channels(acc, cb) {
        if (S.ch) { cb(null, S.ch); return; }
        pcall(acc, 'type=itv&action=get_all_channels', function (e, js) {
            if (e) { cb(e); return; }
            S.ch = (js && js.data) || (js instanceof Array ? js : []); cb(null, S.ch);
        });
    }
    // Films: the portal pages its lists; a few pages fill a shelf.
    function vodPage(acc, cat, page, acc2, cb) {
        pcall(acc, 'type=vod&action=get_ordered_list&category=' + enc(cat) + '&p=' + page + '&sortby=added', function (e, js) {
            if (e) { cb(acc2.length ? null : e, acc2); return; }
            var data = (js && js.data) || [], total = +(js && js.total_items) || 0, per = +(js && js.max_page_items) || data.length || 1;
            for (var i = 0; i < data.length; i++) {
                var v = data[i];
                acc2.push({ stream_id: v.cmd || ('/media/' + v.id + '.mpg'), name: v.name, stream_icon: logoUrl(acc, v.screenshot_uri || ''), container_extension: 'mp4' });
            }
            if (data.length && page < 4 && page * per < total) { vodPage(acc, cat, page + 1, acc2, cb); return; }
            cb(null, acc2);
        });
    }
    function apiPortal(acc, p, cb) {
        ensure(acc, function (e) {
            if (e) { cb(e); return; }
            var a = p.action;
            if (a === 'get_live_categories') {
                if (S.genres) { cb(null, S.genres); return; }
                pcall(acc, 'type=itv&action=get_genres', function (e2, js) {
                    if (e2) { cb(e2); return; }
                    S.genres = cats(js); if (!S.genres.length) S.genres = [{ category_id: '*', category_name: 'All' }];
                    cb(null, S.genres);
                });
            } else if (a === 'get_live_streams') {
                channels(acc, function (e2, list) {
                    if (e2) { cb(e2); return; }
                    var out = [];
                    for (var i = 0; i < list.length; i++) {
                        var c = list[i];
                        if (String(p.category_id) !== '*' && String(c.tv_genre_id) !== String(p.category_id)) continue;
                        out.push({ stream_id: c.cmd, name: c.name, stream_icon: logoUrl(acc, c.logo) });
                    }
                    cb(null, out);
                });
            } else if (a === 'get_vod_categories') {
                if (S.vodCats) { cb(null, S.vodCats); return; }
                pcall(acc, 'type=vod&action=get_categories', function (e2, js) { if (e2) { cb(e2); return; } S.vodCats = cats(js); cb(null, S.vodCats); });
            } else if (a === 'get_vod_streams') {
                vodPage(acc, p.category_id, 1, [], cb);
            } else if (a === 'get_vod_info') {
                cb(null, { info: {}, movie_data: { container_extension: 'mp4' } });
            } else if (a === 'get_series_info') {
                cb(null, { info: {}, episodes: {} });
            } else cb(null, []);    // series: not offered by the portal adapter
        });
    }
    // A play address from the portal is made on demand: create_link turns the stored command into a stream URL.
    function resolve(url, cb) {
        var m = /^stalker:(itv|vod):([\s\S]*)$/.exec(url), acc = U.accounts.active();
        if (!m) { cb(url); return; }
        ensure(acc, function (e) {
            if (e) { cb(''); return; }
            pcall(acc, 'type=' + m[1] + '&action=create_link&cmd=' + enc(m[2]) + '&series=&forced_storage=undefined&disable_ad=0&download=0', function (e2, js) {
                var u = js && js.cmd ? String(js.cmd).replace(/^\S+\s+(?=https?:\/\/)/, '') : '';
                cb(e2 || !/^https?:\/\//.test(u) ? '' : u);
            });
        });
    }

    // Does the source hold films? Known after the first load; false hides the Films tab.
    var films = null;
    function probe(acc, cb) {
        var done = function (e, list) { films = e ? null : !!(list && list.length); cb(); };
        if (acc.type === 'm') loadM3U(acc, function (e, d) { done(e, d && d.vod.g); });
        else if (acc.type === 'p') apiPortal(acc, { action: 'get_vod_categories' }, done);
        else cb();
    }
    function api(acc, p, cb) { if (acc.type === 'p') apiPortal(acc, p, cb); else apiM3U(acc, p, cb); }

    // Checks a source before saving it. cb(stage, why): 'ok' | 'server' (no answer) | 'auth' (refused) | 'invalid' (answered, wrong content)
    function check(type, v, cb) {
        if (type === 'x') { U.checkLogin(U.normBase(v[0]), v[1], v[2], cb); return; }
        var acc = { type: type, base: U.normBase(v[0]), mac: trim(v[1]) };
        if (type === 'm') {
            M = { url: null, d: null, wait: null, info: null };
            loadM3U(acc, function (e) { cb(!e ? 'ok' : e.message === 'cancelled' ? 'cancel' : e.message === 'not a playlist' ? 'invalid' : /^HTTP (401|403)$/.test(e.message) ? 'auth' : 'server', e ? e.message : ''); });
            return;
        }
        S = { key: '', token: '', ready: false, wait: null, genres: null, ch: null, vodCats: null };
        ensure(acc, function (e) { cb(e ? (e.message === 'refused' ? 'auth' : 'server') : 'ok', e ? e.message : ''); });
    }
    return { repick: repick, setLimit: function (l, c) { LIMIT = l; CHUNK = c || CHUNK; }, bigInfo: function (u) { return M.url === u && M.info ? M.info : null; }, opts: function (u) { return opts[u] || null; }, guideOf: function (u) { return M.url === u && M.d ? M.d.guide : ''; }, probe: probe, hasFilms: function () { return films !== false; }, api: api, resolve: resolve, check: check, parseM3U: parseM3U };
})();
