// Shared helpers. ES5 only: the Tizen 3 engine (WebKit 538) has no arrow functions, let/const or fetch for local files.
var U = (function () {
    'use strict';
    // Accounts (sources: a server address, a username and a password). 'bundled' is the one this app was built with: its channel lists ship
    // inside the app. Any other account loads everything from its provider when needed.
    var BUNDLED = window.IPTV || { base: '', user: '', pass: '' };
    function readAccounts() {
        var a; try { a = JSON.parse(localStorage.getItem('nx_accounts') || 'null'); } catch (e) { a = null; }
        if (!a || !a.list || !a.list.length) a = { active: 'bundled', list: [{ id: 'bundled', name: 'My source', base: BUNDLED.base, user: BUNDLED.user, pass: BUNDLED.pass }] };
        return a;
    }
    var ACC = readAccounts();
    function activeAcc() { for (var i = 0; i < ACC.list.length; i++) if (ACC.list[i].id === ACC.active) return ACC.list[i]; return ACC.list[0]; }
    var IP = activeAcc();
    function saveAcc() { try { localStorage.setItem('nx_accounts', JSON.stringify(ACC)); } catch (e) { /* storage blocked */ } }
    var accounts = {
        list: function () { return ACC.list; },
        active: function () { return activeAcc(); },
        // true once the app has a source with a server and a username; false on a first launch with none
        // x = Xtream login (server, username, password) · m = M3U playlist (link) · p = Stalker portal (link, MAC)
        has: function () { var a = activeAcc(), t = a && a.type || 'x'; return !!(a && a.base && (t === 'x' ? a.user : t === 'p' ? a.mac : true)); },
        persist: function () { saveAcc(); },
        type: function () { return (activeAcc() && activeAcc().type) || 'x'; },
        bundled: function () { return activeAcc().id === 'bundled' && BUNDLED.user === IP.user; },
        // the first source replaces the empty placeholder and becomes the active one at once
        add: function (a) {
            a.id = 'a' + Date.now(); a.base = normBase(a.base);
            if (!accounts.has()) { ACC.list = [a]; ACC.active = a.id; IP = a; } else ACC.list.push(a);
            saveAcc(); return a;
        },
        remove: function (id) { if (id === ACC.active || ACC.list.length < 2) return false; ACC.list = ACC.list.filter(function (x) { return x.id !== id; }); saveAcc(); return true; },
        // switching reloads the app so every screen starts clean on the new account
        use: function (id) { ACC.active = id; saveAcc(); location.reload(); }
    };

    // Plain-text GET (playlists, portal answers). headers: optional {name: value}; a header the engine forbids is skipped.
    function getText(url, cb, timeoutMs, headers, maxBytes) {
        var x = new XMLHttpRequest(), done = false;
        var t = setTimeout(function () { if (!done) { done = true; x.abort(); cb(new Error('timeout')); } }, timeoutMs || 20000);
        x.open('GET', url, true);
        for (var h in (headers || {})) { try { x.setRequestHeader(h, headers[h]); } catch (e) { /* forbidden header */ } }
        x.onload = function () {
            if (done) return; done = true; clearTimeout(t);
            if (x.status !== 0 && (x.status < 200 || x.status >= 300)) { cb(new Error('HTTP ' + x.status)); return; }
            cb(null, x.responseText);
        };
        x.onerror = function () { if (done) return; done = true; clearTimeout(t); cb(new Error('network')); };
        // a huge file is cut after maxBytes: what arrived is returned (third argument true), the rest never loads
        if (maxBytes) x.onprogress = function (e) {
            if (done || !e.loaded || e.loaded < maxBytes) return;
            done = true; clearTimeout(t); var part = x.responseText; x.abort(); cb(null, part, true);
        };
        x.send();
    }
    function normBase(b) { b = String(b || '').replace(/^\s+|\s+$/g, '').replace(/\/+$/, ''); if (b && !/^https?:\/\//.test(b)) b = 'http://' + b; return b; }
    // One login check for every form. cb(stage, why): 'ok' | 'server' (no answer from that address) | 'auth' (reached, login refused)
    function checkLogin(base, user, pass, cb) {
        getJSON(base + '/player_api.php?username=' + encodeURIComponent(user) + '&password=' + encodeURIComponent(pass), function (e, d) {
            if (e) { var m = String(e.message || e); cb(/^HTTP (401|403)$/.test(m) ? 'auth' : 'server', m); return; }
            if (!d || !d.user_info) { cb('server', 'not a media server'); return; }
            cb(String(d.user_info.auth) === '1' ? 'ok' : 'auth', 'refused');
        }, 20000);
    }

    function $(id) { return document.getElementById(id); }
    function accSuffix() { return IP && IP.id && IP.id !== 'bundled' ? '@' + IP.id : ''; }
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function setT(el, x, y, s) {
        var v = 'translate3d(' + (x || 0) + 'px,' + (y || 0) + 'px,0)' + (s ? ' scale(' + s + ')' : '');
        el.style.webkitTransform = v; el.style.transform = v;
    }
    function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }

    // XHR loader: works for the app's own files (status 0) and for the provider API.
    function getJSON(url, cb, timeoutMs) {
        var x = new XMLHttpRequest(), done = false;
        var t = setTimeout(function () { if (!done) { done = true; x.abort(); cb(new Error('timeout')); } }, timeoutMs || 20000);
        x.open('GET', url, true);
        x.onload = function () {
            if (done) return; done = true; clearTimeout(t);
            if (x.status !== 0 && (x.status < 200 || x.status >= 300)) { cb(new Error('HTTP ' + x.status)); return; }
            var d; try { d = JSON.parse(x.responseText); } catch (e) { cb(e); return; }
            cb(null, d);
        };
        x.onerror = function () { if (done) return; done = true; clearTimeout(t); cb(new Error('network')); };
        x.send();
    }
    function api(params, cb) {
        if (IP.type === 'm' || IP.type === 'p') { Src.api(IP, params, cb); return; }   // playlist and portal sources answer the same calls
        var q = 'username=' + encodeURIComponent(IP.user) + '&password=' + encodeURIComponent(IP.pass);
        for (var k in params) q += '&' + k + '=' + encodeURIComponent(params[k]);
        getJSON(IP.base + '/player_api.php?' + q, cb, 30000);
    }
    function liveUrl(sid) { if (IP.type === 'm') return sid; if (IP.type === 'p') return 'stalker:itv:' + sid; return IP.base + '/live/' + IP.user + '/' + IP.pass + '/' + sid + '.m3u8'; }
    function filmUrl(id, ext) { if (IP.type === 'm') return id; if (IP.type === 'p') return 'stalker:vod:' + id; return IP.base + '/movie/' + IP.user + '/' + IP.pass + '/' + id + '.' + (ext || 'mp4'); }
    function epUrl(id, ext) { if (IP.type === 'm') return id; if (IP.type === 'p') return 'stalker:vod:' + id; return IP.base + '/series/' + IP.user + '/' + IP.pass + '/' + id + '.' + (ext || 'mkv'); }

    // 'T:<file>' = a TMDB picture; size picks the width ('w185' stills, 'w342' posters, 'w780' hero, 'w1280' detail backdrop).
    // Any TMDB URL the provider gives (often "original", 1 to 3 MB) is rewritten to the wanted size: "original" never reaches the TV.
    var TMDB_RE = /^https?:\/\/(?:image\.tmdb\.org|www\.themoviedb\.org)\/t\/p\/[^\/]+\/(.+)$/;
    function img(src, size) {
        if (!src) return '';
        if (src.indexOf('T:') === 0) return 'https://image.tmdb.org/t/p/' + (size || 'w342') + '/' + src.slice(2);
        var m = TMDB_RE.exec(src);
        if (m) return 'https://image.tmdb.org/t/p/' + (size || 'w342') + '/' + m[1];
        // a saved remote logo (favourites, Continue watching) uses the copy bundled in the app when there is one
        if (window.LOGOS_LOCAL && /^https?:/.test(src)) { var f = src.split('/').pop().replace(/[^A-Za-z0-9._-]/g, '_'); if (window.LOGOS_LOCAL[f]) return window.LOGOS_LOCAL[f]; }
        return src;
    }
    // ---- lazy picture loader: at most 4 downloads at a time, only for tiles on screen, nearest to the focus first ----
    var LZ = { max: 4, busy: [], timer: null, logged: 0, idle: 0, done: {} };   // done: pictures already shown this session, drawn at once on a redraw
    function lzVisible(im) {
        if (!im.parentNode || !document.body.contains(im)) return null;
        if (document.documentElement.className.indexOf('playing') >= 0 && !U_inPlayer(im)) return null;
        var r = im.getBoundingClientRect();
        if (!r.width || !r.height || r.right <= 0 || r.left >= 1920 || r.bottom <= 0 || r.top >= 1080) return null;
        return r;
    }
    function U_inPlayer(im) { for (var n = im; n; n = n.parentNode) if (n.id === 'player') return true; return false; }
    function lzHost(u) { var m = /^https?:\/\/([^\/]+)/.exec(u); return m ? m[1] : 'local'; }
    function lzLog(ok, im, t0) {
        if (LZ.logged >= 20) return; LZ.logged++;
        diagLog({ ev: ok ? 'img.ok' : 'img.err', ms: Date.now() - t0, host: lzHost(im.getAttribute('data-src') || '') });
    }
    function lzDone(im) { var i = LZ.busy.indexOf(im); if (i >= 0) LZ.busy.splice(i, 1); lzKick(); }
    function lzScan() {
        LZ.timer = null;
        // loads that scrolled away or left the page are cancelled
        for (var k = LZ.busy.length - 1; k >= 0; k--) {
            var b = LZ.busy[k];
            if (!lzVisible(b)) { b.onload = b.onerror = null; b.removeAttribute('src'); b.setAttribute('data-lz', ''); LZ.busy.splice(k, 1); }
        }
        var all = document.querySelectorAll('img[data-src]'), cand = [], fe = document.querySelector('.tile.focus, .ch.focus, .card.focus, .ep.focus, .ec.ring, .big, .focus');
        var fr = fe ? fe.getBoundingClientRect() : null, fx = fr ? fr.left + fr.width / 2 : 960, fy = fr ? fr.top + fr.height / 2 : 540;
        for (var i = 0; i < all.length; i++) {
            var im = all[i]; if (im.getAttribute('data-lz') === 'run') continue;
            var r = lzVisible(im); if (!r) continue;
            // the focused row first, then the rows above and below: vertical distance counts more than horizontal
            cand.push({ im: im, d: Math.abs(r.top + r.height / 2 - fy) * 3 + Math.abs(r.left + r.width / 2 - fx) });
        }
        cand.sort(function (x, y) { return x.d - y.d; });
        for (var j = 0; j < cand.length && LZ.busy.length < LZ.max; j++) lzStart(cand[j].im);
        // keep watching while pictures wait: the focus moves without any redraw, and new tiles scroll into view
        if (cand.length || LZ.busy.length) { LZ.idle = 0; LZ.timer = setTimeout(lzScan, 250); }
        else if (all.length) LZ.timer = setTimeout(lzScan, 500);
        else LZ.logged = 0;
    }
    function lzStart(im) {
        var t0 = Date.now(), p = im.parentNode;
        im.setAttribute('data-lz', 'run'); LZ.busy.push(im);
        im.onload = function () { LZ.done[im.getAttribute('data-src')] = 1; im.removeAttribute('data-src'); im.removeAttribute('data-lz'); im.onload = im.onerror = null; if (im.parentNode) im.parentNode.className += ' hasimg'; lzLog(true, im, t0); lzDone(im); };
        im.onerror = function () { var par = im.parentNode; lzLog(false, im, t0); im.onload = im.onerror = null; if (par) par.removeChild(im); lzDone(im); };
        im.src = im.getAttribute('data-src');
    }
    function lzKick() { if (!LZ.timer) LZ.timer = setTimeout(lzScan, 30); }
    // A tile picture: a placeholder now, filled by the queue when it is on screen; the name stays when it fails.
    function imgTag(src, size) {
        var u = img(src, size);
        if (!u) return '';
        // a redraw (search results, a grid page, a row) must not blank a picture the TV already holds
        if (LZ.done[u]) return '<img src="' + esc(u) + '" alt="" onload="if(this.parentNode)this.parentNode.className+=\' hasimg\'" onerror="if(this.parentNode)this.parentNode.removeChild(this)">';
        lzKick();
        return '<img data-src="' + esc(u) + '" alt="">';
    }
    // A channel logo by its name: the copy bundled in the app first (saved favourites can carry a dead provider link)
    function logoFor(name, src) {
        if (window.LOGOS_NAME) {
            var k = cleanName(name).normalize ? cleanName(name).normalize('NFKD') : cleanName(name);
            k = k.toLowerCase().replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]/g, '');
            if (window.LOGOS_NAME[k]) return window.LOGOS_NAME[k];
        }
        return src;
    }
    // A channel with no logo: its cleaned name set as a wordmark on a tile tinted from the name (same name, same tint).
    function cleanName(n) {
        n = String(n || '').replace(/^\s*[A-Za-z]{2,3}\s*\([^)]*\)\s*/, '').replace(/\[[^\]]*\]|\([^)]*\)/g, ' ').replace(/^\s*[A-Za-z]{2,4}\s*[:|]\s*/, '');
        return n.replace(/\b(FHD|UHD|HD|SD|HEVC|4K|LQ|RAW|VIP)\b/gi, ' ').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '');
    }
    function wordmark(name, badge) {
        var c = cleanName(name) || String(name || ''), h = 0, q = /\b(FHD|UHD|HD|HEVC|LQ|4K)\b/i.exec(String(name || ''));
        for (var i = 0; i < c.length; i++) h = (h * 31 + c.charCodeAt(i)) % 360;
        var bg = 'hsla(' + h + ',40%,28%,.9)';
        return '<div class="wm ' + (c.length > 22 ? 's3' : c.length > 14 ? 's2' : 's1') + '" style="background:-webkit-radial-gradient(30% 20%,ellipse farthest-corner,' + bg + ' 0%,#1b1b20 70%);background:radial-gradient(farthest-corner at 30% 20%,' + bg + ' 0%,#1b1b20 70%)"><span>' +
            esc(c) + '</span>' + (badge && q ? '<i>' + q[1].toUpperCase() + '</i>' : '') + '</div>';
    }
    function initials(name) {
        var w = String(name || '').replace(/[^A-Za-z0-9 ]/g, '').split(' ');
        return (w[0] || '').slice(0, 4).toUpperCase();
    }

    // ---- storage: My List + resume points ----
    function load(k, d) { k = k + accSuffix(); try { var v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch (e) { return d; } }
    function save(k, v) { k = k + accSuffix(); try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* storage full or blocked */ } }
    var myList = load('nx_mylist', []);
    function itemKey(it) { return it.k + ':' + it.id; }
    function inList(it) { for (var i = 0; i < myList.length; i++) if (itemKey(myList[i]) === itemKey(it)) return true; return false; }
    function toggleList(it) {
        var key = itemKey(it), out = [], had = false;
        for (var i = 0; i < myList.length; i++) { if (itemKey(myList[i]) === key) had = true; else out.push(myList[i]); }
        if (!had) out.unshift({ k: it.k, id: it.id, name: it.name, img: it.img || '', ext: it.ext || '', sid: it.sid || '' });
        myList = out; save('nx_mylist', myList);
        toast(had ? 'Removed from My List' : 'Added to My List');
        if (!had && it.k === 'series') baseline(it.id);
        return !had;
    }
    // ---- followed shows and their new episodes ----
    // Followed = every series in My List plus every series with a Continue watching entry. Per followed series the app keeps the
    // set of episode ids it has SEEN (nx_seen); episodes outside that set are new. The last refresh result is cached (nx_updates).
    var seenMap = load('nx_seen', {}), updCache = load('nx_updates', { t: 0, items: {} });
    function followed() {
        var out = [], seen = {};
        function add(id, name, img) { id = String(id); if (!id || id === 'undefined' || seen[id]) return; seen[id] = 1; out.push({ id: id, name: name || '', img: img || '' }); }
        var c = continueList(); for (var i = 0; i < c.length; i++) if (c[i].series && c[i].series.id != null) add(c[i].series.id, c[i].series.name, c[i].series.img);
        for (var j = 0; j < myList.length; j++) if (myList[j].k === 'series') add(myList[j].id, myList[j].name, myList[j].img);
        return out;
    }
    function isFollowed(id) { var f = followed(); for (var i = 0; i < f.length; i++) if (f[i].id === String(id)) return true; return false; }
    function epCleanTitle(t) { return t ? String(t).replace(/^.*?-\s*S\d+E\d+\s*-?\s*/i, '') : ''; }
    // The provider's episodes map ({season: [episode]}) against the seen set. seenBefore false: nothing recorded yet (no news can be told).
    function diffSeen(id, episodes) {
        var rec = seenMap[String(id)], news = [];
        if (!rec) return { seenBefore: false, news: news };
        for (var s in episodes) { var l = episodes[s] || []; for (var j = 0; j < l.length; j++) if (!rec.ids[String(l[j].id)]) news.push({ season: s, num: +(l[j].episode_num || j + 1), title: epCleanTitle(l[j].title), id: String(l[j].id) }); }
        news.sort(function (a, b) { return (+a.season) - (+b.season) || a.num - b.num; });
        return { seenBefore: true, news: news };
    }
    function recordSeen(id, episodes) {
        var ids = {}; for (var s in episodes) { var l = episodes[s] || []; for (var j = 0; j < l.length; j++) ids[String(l[j].id)] = 1; }
        seenMap[String(id)] = { ids: ids, t: Date.now() };
        var ks = []; for (var k in seenMap) ks.push(k);
        if (ks.length > 120) { ks.sort(function (a, b) { return seenMap[a].t - seenMap[b].t; }); for (var q = 0; q < ks.length - 120; q++) delete seenMap[ks[q]]; }
        save('nx_seen', seenMap);
        clearUpdate(id);
    }
    function clearUpdate(id) { if (updCache.items[String(id)]) { delete updCache.items[String(id)]; save('nx_updates', updCache); } }
    function updatesCache() { return updCache; }
    function saveUpdates(c) { updCache = c; save('nx_updates', updCache); }
    // shows with new episodes that are still followed, in the order of use
    function updatesList() {
        var f = followed(), out = [];
        for (var i = 0; i < f.length; i++) { var u = updCache.items[f[i].id]; if (u && u.count > 0) out.push(u); }
        return out;
    }
    // a show just followed: its current episodes are the baseline (nothing is new yet)
    function baseline(id) { if (seenMap[String(id)]) return; api({ action: 'get_series_info', series_id: id }, function (e, d) { if (!e && d && d.episodes && !seenMap[String(id)]) recordSeen(id, d.episodes); }); }
    var favs = load('nx_favs', []);
    function isFav(sid) { for (var i = 0; i < favs.length; i++) if (String(favs[i].sid) === String(sid)) return true; return false; }
    // Favourites saved with a logo on a provider server that no longer answers get the logo from the
    // country's current channel list (same channel id), once per launch
    var DEAD_LOGO = /^https?:\/\/103\.176\.90\.95\//;
    function repairFavLogos(liveOf) {
        var byCc = {};
        for (var i = 0; i < favs.length; i++) if (DEAD_LOGO.test(favs[i].img || '') && favs[i].cc) byCc[favs[i].cc] = 1;
        for (var cc in byCc) (function (cc) {
            liveOf(cc, function (d) {
                if (!d || !d.c) return;
                var ids = {}, fixed = 0;
                for (var j = 0; j < d.c.length; j++) if (d.c[j][1]) ids[String(d.c[j][3])] = d.c[j][1];
                for (var k = 0; k < favs.length; k++) { var f = favs[k]; if (f.cc === cc && DEAD_LOGO.test(f.img || '') && ids[String(f.sid)]) { f.img = ids[String(f.sid)]; fixed++; } }
                if (fixed) { save('nx_favs', favs); diagLog({ ev: 'favs.logos.repaired', cc: cc, n: fixed }); }
            });
        })(cc);
    }
    function toggleFav(ch) {
        var out = [], had = false;
        for (var i = 0; i < favs.length; i++) { if (String(favs[i].sid) === String(ch.sid)) had = true; else out.push(favs[i]); }
        if (!had) out.unshift({ sid: ch.sid, name: ch.name, img: ch.img || '', dark: ch.dark || 0, sub: ch.sub || '', cc: ch.cc || '' });
        favs = out; save('nx_favs', favs);
        toast(had ? 'Removed from Favourites' : '\u2605  Added to Favourites');
        return !had;
    }
    function clearList(which) {
        if (which === 'favs') { favs = []; save('nx_favs', favs); }
        else if (which === 'continue') { resume = {}; save('nx_resume', resume); }
        else if (which === 'mylist') { myList = []; save('nx_mylist', myList); }
        toast('Cleared');
    }
    // Subtitles: the provider does not list them. Known from (1) names that say so, (2) files already opened.
    var SUB_RE = /\bSUBS?\b|ENG-SUB|VOST|SOUS-TITR|SUBTITLED/i;
    var subsSeen = load('nx_subs', {});
    function hasSubs(it, catName) {
        if (!it) return false;
        var k = (it.k === 'ep' && it.series ? 'series:' + it.series.id : it.k + ':' + it.id);
        if (subsSeen[k] !== undefined) return !!subsSeen[k];
        return SUB_RE.test(String(it.name || '')) || SUB_RE.test(String(catName || ''));
    }
    function learnSubs(it, yes) {
        if (!it) return;
        subsSeen[it.k + ':' + it.id] = yes ? 1 : 0;
        if (it.series) subsSeen['series:' + it.series.id] = yes ? 1 : (subsSeen['series:' + it.series.id] || 0);
        save('nx_subs', subsSeen);
    }
    function ccBadge(it, catName) { return hasSubs(it, catName) ? '<div class="ccb">CC</div>' : ''; }
    // Audio and subtitle choice per film or series (a series' choice covers every episode).
    var trackPrefs = load('nx_tracks', {});
    function prefKey(it) { return it ? (it.series ? 'series:' + it.series.id : it.k + ':' + it.id) : ''; }
    // A title's own choice first; a title never set uses the last language picked anywhere (by language only,
    // since track positions differ from file to file).
    function getTrackPref(it) {
        var own = trackPrefs[prefKey(it)] || null, last = trackPrefs['*'] || null;
        if (!last) return own;
        var out = {}; for (var k in (own || {})) out[k] = own[k];
        if (!out.audio && last.audio && last.audio.lang) out.audio = { lang: last.audio.lang, pos: -1 };
        if (!out.subs && last.subs) out.subs = last.subs.online || last.subs.off ? last.subs : (last.subs.lang ? { lang: last.subs.lang, pos: -1 } : null);
        return out;
    }
    function setTrackPref(it, kind, val) {
        var k = prefKey(it); if (!k) return;
        var p = trackPrefs[k] || {}; p[kind] = val; trackPrefs[k] = p;
        var g = trackPrefs['*'] || {}; g[kind] = val; trackPrefs['*'] = g;
        save('nx_tracks', trackPrefs);
    }
    var resume = load('nx_resume', {});
    // Episodes played to their end: the strip in the player marks them WATCHED. Kept per source, newest 400.
    var watchedMap = load('nx_watched', {});
    function markWatched(it) {
        watchedMap[itemKey(it)] = Date.now();
        var ks = []; for (var k in watchedMap) ks.push(k);
        if (ks.length > 400) { ks.sort(function (a, b) { return watchedMap[a] - watchedMap[b]; }); for (var i = 0; i < ks.length - 400; i++) delete watchedMap[ks[i]]; }
        save('nx_watched', watchedMap);
    }
    function isWatched(it) { return !!watchedMap[itemKey(it)]; }
    // Where each show's credits start, as seconds before the end of an episode: the last 5 samples per series, their median is the cue.
    var creditsMap = load('nx_credits', {});
    function creditsAdd(seriesId, secs) {
        var a = creditsMap[seriesId] || []; a.push(secs); if (a.length > 5) a.shift(); creditsMap[seriesId] = a; save('nx_credits', creditsMap);
    }
    function creditsMem(seriesId) {
        var a = creditsMap[seriesId]; if (!a || !a.length) return 0;
        var b = a.slice().sort(function (x, y) { return x - y; }), m = b.length >> 1;
        return b.length % 2 ? b[m] : Math.round((b[m - 1] + b[m]) / 2);
    }
    function setResume(it, pos, dur) {
        var key = itemKey(it);
        if (dur && pos > dur - 60000) { delete resume[key]; if (it.k === 'ep') markWatched(it); }
        else {
            // a save never drops a picture the entry already had (a film started from a page without art)
            var old = resume[key], img = it.img || (old && old.img) || '', ser = it.series || null;
            if (ser && !ser.img && old && old.series && old.series.img) { ser = { id: ser.id, name: ser.name, img: old.series.img, tmdb: ser.tmdb }; }
            resume[key] = { k: it.k, id: it.id, name: it.name, img: img, ext: it.ext || '', series: ser, tmdb: it.tmdb || '', pos: pos, dur: dur, t: Date.now() };
        }
        save('nx_resume', resume);
    }
    function getResume(it) { return resume[itemKey(it)] || null; }
    // a poster found later (Continue watching fetches it once) is kept on the entry
    function setResumeArt(r, img) {
        for (var k in resume) { var x = resume[k]; if (x.k === r.k && x.id === r.id) { x.img = img; if (x.series && !x.series.img) x.series.img = img; } }
        save('nx_resume', resume);
    }
    function continueList() {
        var a = [], seen = {}, out = [];
        for (var k in resume) a.push(resume[k]);
        a.sort(function (x, y) { return y.t - x.t; });
        for (var i = 0; i < a.length && out.length < 20; i++) {
            var key = a[i].series ? 'series:' + a[i].series.id : a[i].k + ':' + a[i].id;
            if (seen[key]) continue; seen[key] = 1; out.push(a[i]);
        }
        return out;
    }
    // Remove an entry; for a series, every episode of it.
    function removeResume(r) {
        for (var k in resume) {
            var x = resume[k];
            if ((r.series && x.series && String(x.series.id) === String(r.series.id)) || (x.k === r.k && String(x.id) === String(r.id))) delete resume[k];
        }
        save('nx_resume', resume); toast('Removed from Continue watching');
    }

    // ---- last device wins: one stream per account, the newest app takes it (ntfy.sh signal) ----
    function sha256hex(msg) {
        var K = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
        var H = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
        var b = unescape(encodeURIComponent(msg)), n = b.length, w = [], i, j;
        for (i = 0; i < n; i++) w[i >> 2] |= b.charCodeAt(i) << (24 - (i % 4) * 8);
        w[n >> 2] |= 0x80 << (24 - (n % 4) * 8);
        var len = (((n + 8) >> 6) + 1) * 16; w[len - 1] = n * 8;
        for (i = 0; i < len; i++) if (!w[i]) w[i] = 0;
        function rr(x, c) { return (x >>> c) | (x << (32 - c)); }
        for (i = 0; i < len; i += 16) {
            var W = w.slice(i, i + 16), a = H[0], bb = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
            for (j = 16; j < 64; j++) {
                var s0 = rr(W[j - 15], 7) ^ rr(W[j - 15], 18) ^ (W[j - 15] >>> 3), s1 = rr(W[j - 2], 17) ^ rr(W[j - 2], 19) ^ (W[j - 2] >>> 10);
                W[j] = (W[j - 16] + s0 + W[j - 7] + s1) | 0;
            }
            for (j = 0; j < 64; j++) {
                var S1 = rr(e, 6) ^ rr(e, 11) ^ rr(e, 25), ch = (e & f) ^ (~e & g), t1 = (h + S1 + ch + K[j] + W[j]) | 0;
                var S0 = rr(a, 2) ^ rr(a, 13) ^ rr(a, 22), mj = (a & bb) ^ (a & c) ^ (bb & c), t2 = (S0 + mj) | 0;
                h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = bb; bb = a; a = (t1 + t2) | 0;
            }
            H[0] = (H[0] + a) | 0; H[1] = (H[1] + bb) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0; H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
        }
        var out = ''; for (i = 0; i < 8; i++) out += ('00000000' + (H[i] >>> 0).toString(16)).slice(-8);
        return out;
    }
    // one random id per install; the topic is a secret derived from the active source: never logged, never shown
    var devId = (function () { try { var d = localStorage.getItem('nx_dev'); if (!d) { d = ''; for (var i = 0; i < 16; i++) d += Math.floor(Math.random() * 16).toString(16); localStorage.setItem('nx_dev', d); } return d; } catch (e) { return 'x' + Date.now(); } })();
    function topic() { return 'nxtv-' + sha256hex((IP.base || '') + '|' + (IP.user || '') + '|' + (IP.pass || '')).slice(0, 24); }
    var NTFY = 'https://ntfy.sh/';
    var takeover = {
        dev: devId, name: 'Frame TV',
        claim: function (kind, t) {
            try {
                var x = new XMLHttpRequest(); x.open('POST', NTFY + topic(), true);
                x.onerror = function () { diagLog({ ev: 'takeover.err', why: 'publish' }); };
                x.onload = function () { if (x.status < 200 || x.status >= 300) diagLog({ ev: 'takeover.err', why: 'publish ' + x.status }); };
                x.send(JSON.stringify({ v: 1, dev: devId, name: 'Frame TV', kind: kind, t: t }));
            } catch (e) { diagLog({ ev: 'takeover.err', why: 'publish' }); }
        },
        // cb(msgs, lastId): the messages since `since` (an id, or '30s'), oldest first
        poll: function (since, cb) {
            try {
                var x = new XMLHttpRequest(); x.open('GET', NTFY + topic() + '/json?poll=1&since=' + encodeURIComponent(since), true);
                x.timeout = 8000;
                x.onload = function () {
                    if (x.status < 200 || x.status >= 300) { diagLog({ ev: 'takeover.err', why: 'poll ' + x.status }); cb([], since); return; }
                    var lines = String(x.responseText || '').split('\n'), out = [], last = since;
                    for (var i = 0; i < lines.length; i++) {
                        if (!lines[i]) continue;
                        try { var ev = JSON.parse(lines[i]); if (ev.id) last = ev.id; if (ev.event === 'message') { var m = JSON.parse(ev.message); if (m && m.v === 1) out.push(m); } } catch (e) { /* not ours */ }
                    }
                    cb(out, last);
                };
                x.onerror = x.ontimeout = function () { diagLog({ ev: 'takeover.err', why: 'poll' }); cb([], since); };
                x.send();
            } catch (e) { diagLog({ ev: 'takeover.err', why: 'poll' }); cb([], since); }
        }
    };
    var toastT;
    function toast(msg) {
        var el = $('toast'); el.firstChild.textContent = msg; el.className = 'show';
        clearTimeout(toastT); toastT = setTimeout(function () { el.className = ''; }, 2600);
    }
    function clock() {
        var d = new Date(), h = d.getHours(), m = d.getMinutes();
        $('clock').textContent = (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
    }
    function fmtTime(ms) {
        var s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
        return (h ? h + ':' + (m < 10 ? '0' : '') : '') + m + ':' + (x < 10 ? '0' : '') + x;
    }
    // "NETFLIX KIDS" -> "Netflix Kids", keeping short codes (HD, UK, PPV...) in capitals
    function titleCase(t) {
        t = String(t || '').toLowerCase().replace(/(^|[\s\/(+-])([a-z\u00e0-\u00ff])/g, function (m, a, b) { return a + b.toUpperCase(); });
        return t.replace(/\b(Hd|Fhd|Uhd|Vip|Ppv|Bk|Tv|Uk|Us|Bbc|Nba|Nfl|Nhl|Mlb|Dazn|Espn|Imdb|4k|Raw|Mena|Hbo|Ufc|Wwe|Epl|Cnn|Bein)\b/g, function (m) { return m.toUpperCase(); });
    }
    function cleanTitle(n) {
        return String(n || '').replace(/^\s*[A-Z]{2,3}\s*-\s*/, '').replace(/\s+-\s+UNCUT\b|\s+4K\b/g, '').replace(/\s*\((19|20)\d\d\)\s*$/, '').replace(/\s+\([A-Z]{2}\)$/, '');
    }
    // n placeholder cards (x, y, w, h, gap) laid out in a row
    function skelRow(n, x, y, w, h, gap) {
        var s = '';
        for (var i = 0; i < n; i++) s += '<div class="skel" style="left:' + (x + i * (w + gap)) + 'px;top:' + y + 'px;width:' + w + 'px;height:' + h + 'px"><i></i></div>';
        return s;
    }
    function diagLog(o) { if (window.diag) window.diag(o); }

    return { $: $, esc: esc, setT: setT, clamp: clamp, getJSON: getJSON, api: api, liveUrl: liveUrl, filmUrl: filmUrl, epUrl: epUrl,
        img: img, imgTag: imgTag, logoFor: logoFor, repairFavLogos: repairFavLogos, wordmark: wordmark, cleanName: cleanName, initials: initials, inList: inList, toggleList: toggleList, myList: function () { return myList; },
        setResume: setResume, getResume: getResume, setResumeArt: setResumeArt, continueList: continueList, removeResume: removeResume, toast: toast, clock: clock, fmtTime: fmtTime, log: diagLog, titleCase: titleCase, cleanTitle: cleanTitle, clearList: clearList, skelRow: skelRow, accounts: accounts, normBase: normBase, getText: getText, checkLogin: checkLogin, followed: followed, isFollowed: isFollowed, diffSeen: diffSeen, recordSeen: recordSeen, clearUpdate: clearUpdate, updatesCache: updatesCache, saveUpdates: saveUpdates, updatesList: updatesList, epCleanTitle: epCleanTitle, takeover: takeover, hasSubs: hasSubs, learnSubs: learnSubs, isWatched: isWatched, markWatched: markWatched, creditsAdd: creditsAdd, creditsMem: creditsMem, ccBadge: ccBadge, getTrackPref: getTrackPref, setTrackPref: setTrackPref,
        isFav: isFav, toggleFav: toggleFav, favs: function () { return favs; } };
})();
