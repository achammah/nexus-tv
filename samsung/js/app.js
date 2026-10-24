// App core: data, the top menu, screen switching and the remote.
var Data = (function () {
    'use strict';
    var live = {}, waiting = {}, BUNDLED_CC = ['be', 'fr', 'uk', 'us'];
    var ALL = [['be', 'Belgium'], ['fr', 'France'], ['uk', 'UK'], ['us', 'US']], COUNTRIES = ALL.slice();
    function applyCountries() {
        var on = Settings.get().countries; COUNTRIES.length = 0;
        // a playlist or portal has no country split: one list of everything it holds
        if (U.accounts.type() !== 'x') COUNTRIES.push(['all', 'Live']);
        else for (var i = 0; i < ALL.length; i++) if (on.indexOf(ALL[i][0]) >= 0) COUNTRIES.push(ALL[i]);
        if (window.Guide && Guide.reset) Guide.reset();
    }
    function countryIndex(cc) { for (var i = 0; i < COUNTRIES.length; i++) if (COUNTRIES[i][0] === cc) return i; return -1; }
    // ---------- provider catalogue (any account) ----------
    var cats = {};   // 'live' | 'vod' | 'series' -> [{id, name}]
    var ACTION = { live: 'get_live_categories', vod: 'get_vod_categories', series: 'get_series_categories' };
    function categories(type, cb) {
        if (cats[type]) { cb(cats[type]); return; }
        U.api({ action: ACTION[type] }, function (e, list) {
            cats[type] = (list || []).map(function (c) { return { id: c.category_id, name: c.category_name }; });
            cb(cats[type]);
        });
    }
    function langTag(n) { var m = /^\s*\|\s*([A-Z]+)\s*\|/.exec(n || ''); return m ? m[1] : ''; }
    function cleanCat(n) { return String(n || '').replace(/^\s*\|\s*[A-Z]+\s*\|\s*/, '').replace(/^\s*[A-Z]{2,3}\s*\|\s*/, '').replace(/[ᴀ-ᶿ⁰-₟ʰ-˿]+/g, '').replace(/\s+/g, ' ').trim(); }
    // Items of one provider category, as tiles: live channels, films or series.
    function itemsOf(type, catId, cb) {
        var action = type === 'live' ? 'get_live_streams' : type === 'vod' ? 'get_vod_streams' : 'get_series';
        U.api({ action: action, category_id: catId }, function (e, list) {
            var out = [];
            (list || []).forEach(function (s) {
                if (String(s.is_adult) === '1') return;
                var nm = U.cleanTitle(String(s.name || '').replace(/^\s*[A-Z]{2}\s*\|\s*/, ''));
                if (!nm || /^[#=*\-_~|]{3,}/.test(nm)) return;
                if (type === 'live') out.push({ k: 'live', id: s.stream_id, sid: s.stream_id, name: nm, img: s.stream_icon || '' });
                else if (type === 'vod') out.push({ k: 'film', id: s.stream_id, name: nm, img: s.stream_icon || '', ext: s.container_extension || 'mp4' });
                else out.push({ k: 'series', id: s.series_id, name: nm, img: s.cover || '' });
            });
            cb(out, e);
        });
    }

    // Live channels for one country: {g: [group names], c: [[name, logo, groupIndex, streamId, dark]], byGroup}.
    // The app's own account reads the bundled file; any other account lists the country's categories
    // and loads each one when it is opened (loadGroup).
    function liveOf(cc, cb) {
        if (live[cc]) { cb(live[cc]); return; }
        if (waiting[cc]) { waiting[cc].push(cb); return; }
        waiting[cc] = [cb];
        var t0 = Date.now();
        var done = function (d) {
            live[cc] = d;
            var w = waiting[cc]; delete waiting[cc];
            for (var k = 0; k < w.length; k++) w[k](d);
        };
        // the bundled files hold the four built-in countries; any other country of the source loads like another account's
        if (!U.accounts.bundled() || BUNDLED_CC.indexOf(cc) < 0) {
            categories('live', function (list) {
                var re = cc === 'all' ? /./ : new RegExp('^\\s*' + cc.toUpperCase() + '\\s*\\|'), d = { g: [], ids: [], c: [], byGroup: [], lazy: true, loaded: {} };
                list.forEach(function (c) {
                    if (!re.test(c.name) || /REPLAY/i.test(c.name)) return;
                    d.g.push(cleanCat(c.name)); d.ids.push(c.id); d.byGroup.push([]);
                });
                U.log({ ev: 'live.cats', cc: cc, ms: Date.now() - t0, n: d.g.length });
                done(d);
            });
            return;
        }
        U.getJSON('data/live-' + cc + '.json', function (err, d) {
            U.log({ ev: 'live.load', cc: cc, ms: Date.now() - t0, n: d ? d.c.length : 0, err: err ? String(err) : null });
            d = d || { g: [], c: [] };
            d.byGroup = [];
            for (var i = 0; i < d.g.length; i++) d.byGroup.push([]);
            for (var j = 0; j < d.c.length; j++) d.byGroup[d.c[j][2]].push(j);
            done(d);
        }, 60000);
    }
    function loadGroup(d, gi, cb) {
        if (!d || !d.lazy || d.loaded[gi]) { cb(); return; }
        itemsOf('live', d.ids[gi], function (items) {
            if (d.loaded[gi]) { cb(); return; }
            d.loaded[gi] = true;
            items.forEach(function (it) { d.byGroup[gi].push(d.c.length); d.c.push([it.name, it.img, gi, it.sid, 0]); });
            cb();
        });
    }

    var lib = null, home = null, search = null, searchWait = [];
    function library(cb) {
        if (lib) { cb(lib); return; }
        if (U.accounts.bundled()) { U.getJSON('data/library.json', function (e, d) { lib = d || { films: [], series: [] }; cb(lib); }); return; }
        var keep = function (c) { var t = langTag(c.name); return t === '' || t === 'EN' || t === 'FR' || t === 'MULTI'; };
        categories('vod', function (v) { categories('series', function (sr) {
            lib = { films: v.filter(keep).map(function (c) { return [c.id, cleanCat(c.name), '', langTag(c.name)]; }),
                    series: sr.filter(keep).map(function (c) { return [c.id, cleanCat(c.name), '', langTag(c.name)]; }) };
            cb(lib);
        }); });
    }
    function homeData(cb) {
        if (home) { cb(home); return; }
        if (U.accounts.bundled()) { U.getJSON('data/home.json', function (e, d) { home = d || { hero: [], newFilms: [], topSeries: [] }; cb(home); }); return; }
        // another account: new films and top series from its own catalogue
        var pick = function (list, re) { for (var i = 0; i < list.length; i++) if (re.test(list[i].name)) return list[i]; return list[0]; };
        categories('vod', function (v) { categories('series', function (sr) {
            var fc = pick(v, /NEW|RECENT|LATEST|TOP/i), sc = pick(sr, /TOP|POPULAR|LATEST/i);
            home = { hero: [], newFilms: [], topSeries: [] };
            var left = 2, fin = function () { if (--left === 0) cb(home); };
            if (fc) itemsOf('vod', fc.id, function (items) { home.newFilms = items.slice(0, 30).map(function (f) { return [f.id, f.name, f.img, f.ext]; }); fin(); }); else fin();
            if (sc) itemsOf('series', sc.id, function (items) { home.topSeries = items.slice(0, 30).map(function (x) { return [x.id, x.name, x.img]; }); fin(); }); else fin();
        }); });
    }
    // The search index is large (≈5 MB): loaded once, after Home is on screen.
    function searchIndex(cb) {
        if (search) { cb(search); return; }
        searchWait.push(cb);
        if (searchWait.length > 1) return;
        var t0 = Date.now();
        U.getJSON('data/search.json', function (e, d) {
            search = d || { f: [], s: [] };
            // lower-case names once, for fast matching
            search.fl = []; search.sl = [];
            for (var i = 0; i < search.f.length; i++) search.fl.push(search.f[i][1].toLowerCase());
            for (var j = 0; j < search.s.length; j++) search.sl.push(search.s[j][1].toLowerCase());
            U.log({ ev: 'search.load', ms: Date.now() - t0, n: search.f.length + search.s.length, err: e ? String(e) : null });
            var w = searchWait; searchWait = [];
            for (var k = 0; k < w.length; k++) w[k](search);
        }, 120000);
    }
    // Titles in every other language, names only (≈8 MB): loaded the first time a search needs it.
    var more = null, moreWait = [];
    function searchMore(cb) {
        if (more) { cb(more); return; }
        moreWait.push(cb); if (moreWait.length > 1) return;
        U.getJSON('data/search-more.json', function (e, d) {
            more = d || { f: [], s: [], langs: [] };
            more.fl = []; more.sl = [];
            for (var i = 0; i < more.f.length; i++) more.fl.push(more.f[i][1].toLowerCase());
            for (var j = 0; j < more.s.length; j++) more.sl.push(more.s[j][1].toLowerCase());
            more.c = more.c || []; more.cl = [];
            for (var q = 0; q < more.c.length; q++) more.cl.push(more.c[q][1].toLowerCase());
            var w = moreWait; moreWait = []; for (var k = 0; k < w.length; k++) w[k](more);
        }, 120000);
    }
    // A new source: forget everything loaded for the previous one.
    function reset() { live = {}; waiting = {}; cats = {}; lib = null; home = null; search = null; searchWait = []; more = null; moreWait = []; }
    return { reset: reset, searchMore: searchMore, COUNTRIES: COUNTRIES, applyCountries: applyCountries, countryIndex: countryIndex, liveOf: liveOf, loadGroup: loadGroup,
        categories: categories, itemsOf: itemsOf, cleanCat: cleanCat, langTag: langTag, library: library, home: homeData, searchIndex: searchIndex };
})();

// The opening: the brand video (img/opening.mp4) full screen at launch, over the boot frame, while Home
// loads. It ends on its own, on any key, or on a failure, and never holds a ready Home past its length.
var Intro = (function () {
    'use strict';
    // pending: asked to play, first frame not shown yet (the black boot frame stays up meanwhile)
    var on = false, pending = false, t = null, guard = null;
    function lift(fade) {
        var b = U.$('boot'), a = U.$('app');
        // after the opening: hold 0.3 s on black, then black fades to Home in 0.5 s (same as Mac and Apple TV)
        if (fade) { a.style.webkitTransition = a.style.transition = 'none'; a.style.opacity = '0'; void a.offsetHeight;
            a.style.webkitTransition = a.style.transition = 'opacity .5s ease-in-out .3s'; a.style.opacity = '1'; }
        b.className = 'gone'; setTimeout(function () { b.style.display = 'none'; }, 300);
    }
    function close() { try { webapis.avplay.stop(); webapis.avplay.close(); } catch (e) { /* already closed */ } }
    // fade: Home fades in under the last frame (the end of the opening); no fade when the app is being hidden
    function end(noFade) {
        if (!on && !pending) return;
        var was = on; on = false; pending = false; clearTimeout(t); clearTimeout(guard);
        if (was && !noFade) {
            // the last frame (the lockup) stays on the video plane; Home fades in over it, then the video closes
            document.documentElement.className = 'introOut';
            lift(true);
            setTimeout(function () { if (!on && !pending) { close(); if (document.documentElement.className === 'introOut') document.documentElement.className = ''; } }, 900);
        } else {
            close();
            document.documentElement.className = '';
            lift(false);
        }
        U.log({ ev: 'intro.end' });
    }
    function fail(ev, e) { U.log({ ev: ev, err: String(e && (e.name || e.message) || e) }); on = true; end(true); }
    function start() {
        if (on || pending || !window.webapis || !webapis.avplay || !window.tizen || location.search.indexOf('boot') >= 0) return false;
        pending = true;
        guard = setTimeout(function () { if (pending && !on) fail('intro.timeout', 'no first frame in 2.5 s'); }, 2500);
        try {
            tizen.filesystem.resolve('wgt-package', function (dir) {
                var uri = dir.toURI() + '/img/opening.mp4';
                try {
                    webapis.avplay.open(uri);
                    webapis.avplay.setDisplayRect(0, 0, 1920, 1080);
                    webapis.avplay.setListener({ onstreamcompleted: function () { end(); }, onerror: function (e) { fail('intro.error', e); } });
                    webapis.avplay.prepareAsync(function () {
                        if (!pending) { close(); return; }
                        clearTimeout(guard);
                        on = true; pending = false; document.documentElement.className = 'intro'; webapis.avplay.play();
                        var b = U.$('boot'); b.className = 'gone'; b.style.display = 'none';
                        t = setTimeout(function () { end(); }, 3400); U.log({ ev: 'intro.play' });
                    }, function (e) { fail('intro.prepare.error', e); });
                } catch (e) { fail('intro.open.error', e); }
            }, function (e) { fail('intro.resolve.error', e); }, 'r');
        } catch (e) { fail('intro.exception', e); }
        return true;
    }
    return { start: start, end: end, lift: lift, active: function () { return on; }, busy: function () { return on || pending; } };
})();

var App = (function () {
    'use strict';
    var SEARCH_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5L21 21"/></svg>';
    var GEAR = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" style="margin-right:0"><circle cx="12" cy="12" r="3.2"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/></svg>';
    var TABS = [];
    // Menu tabs from Settings (order, hidden ones left out), with the Settings gear always last.
    function buildTabs() {
        var S = Settings.get(); TABS.length = 0;
        if (!U.accounts.has()) {   // no source yet: Home (the empty library) and Settings
            TABS.push({ id: 'home', label: Settings.tabLabel('home') }, { id: 'settings', label: GEAR });
            return;
        }
        for (var i = 0; i < S.tabs.length; i++) {
            var id = S.tabs[i];
            if (S.hideTabs.indexOf(id) >= 0 && id !== 'home') continue;
            if (U.accounts.type() !== 'x' && (id === 'series' || (id === 'films' && !Src.hasFilms()))) continue;   // a playlist or portal has no series; films only if it holds some
            TABS.push({ id: id, label: id === 'search' ? SEARCH_ICON + 'Search' : Settings.tabLabel(id) });
        }
        TABS.push({ id: 'settings', label: GEAR });
    }
    var screens = {}, cur = null, tab = 0, navFocus = false, navIdx = 0, stack = [];

    function screenOfTab(i) {
        var id = TABS[i].id;
        if (id === 'films' || id === 'series' || id === 'mylist') return { s: 'lib', arg: id };
        if (id === 'settings') return { s: 'settings', arg: null };
        if (id === 'guide') return { s: 'live', arg: null };   // the Live page; a country opens the guide on top
        return { s: id, arg: null };
    }
    function renderNav() {
        var h = '';
        for (var i = 0; i < TABS.length; i++) {
            var c = 'it' + (i === tab ? ' on' : '') + (navFocus && i === navIdx ? ' focus' : '');
            h += '<div class="' + c + '">' + TABS[i].label + '</div>';
        }
        var nav = U.$('nav'); nav.innerHTML = h;
        nav.style.left = Math.round((1920 - nav.offsetWidth) / 2) + 'px';
    }
    function show(name, arg, push) {
        if (cur && push) stack.push({ s: cur.name, arg: cur.arg });
        if (cur && cur.name !== name) { screens[cur.name].el.className = 'scr'; if (screens[cur.name].hide) screens[cur.name].hide(); }
        cur = { name: name, arg: arg };
        screens[name].el.className = 'scr on';
        screens[name].show(arg);
        U.$('nav').style.visibility = name === 'detail' ? 'hidden' : '';   // '' lets the player hide it
    }
    function goTab(i, focusContent) {
        tab = i; stack = [];
        var t = screenOfTab(i);
        show(t.s, t.arg, false);
        navFocus = !focusContent; navIdx = i; renderNav();
        var sc = screens[t.s];
        if (focusContent) { if (sc.focus) sc.focus(); } else if (sc.blur) sc.blur();
        U.log({ ev: 'tab', tab: TABS[i].id });
        setTimeout(function () { if (window.diagLayout) diagLayout('tab-' + TABS[i].id); }, 800);
    }
    function focusNav() { navFocus = true; navIdx = tab; renderNav(); if (screens[cur.name].blur) screens[cur.name].blur(); }
    function back() {
        if (stack.length) { var p = stack.pop(); show(p.s, p.arg, false); return; }
        if (!navFocus) { focusNav(); return; }
        if (tab !== 0) { goTab(0, false); return; }
        // Leave on the same picture the launcher shrinks back into its tile: fade to the opening frame, then exit.
        try { tizen.application.getCurrentApplication().hide(); } catch (e) { /* not on a TV */ }
    }
    // OK held for 0.6 s = long press (favourite a channel). A short press acts on release.
    var okDown = 0, okLong = false, okT = null;
    function onKeyUp(e) {
        if (e.keyCode !== 13 || !okDown) return;
        okDown = 0; clearTimeout(okT);
        if (!okLong && !Menu.isOpen()) contentKey(13, e);
    }
    function contentKey(c, e) {
        var r = screens[cur.name].key(c);
        if (r === 'up') focusNav();
        if (r && e) e.preventDefault();
    }
    function onKey(e) {
        var c = e.keyCode;
        if (Intro.active()) { e.preventDefault(); Intro.end(); return; }   // any key skips the opening
        if (GroupPicker.isOpen()) { e.preventDefault(); GroupPicker.key(c); return; }
        if (Onboard.isOpen()) { e.preventDefault(); Onboard.key(c); return; }
        if (Player.active()) { if (Player.key(c)) e.preventDefault(); return; }
        if (Menu.isOpen()) { e.preventDefault(); if (c !== 13 || !okDown) Menu.key(c); return; }
        if (c === 13 && !navFocus && screens[cur.name].longPress) {
            e.preventDefault();
            if (okDown) return;                        // auto-repeat while held
            okDown = Date.now(); okLong = false;
            okT = setTimeout(function () {
                okLong = true;
                if (!screens[cur.name].longPress()) contentKey(13);
            }, 600);
            return;
        }
        if (c === 10009 || c === 8 || c === 27) { e.preventDefault(); if (!navFocus && screens[cur.name].back && screens[cur.name].back()) return; back(); return; }
        if (navFocus) {
            if (c === 37 && navIdx > 0) { navIdx--; goTab(navIdx, false); }
            else if (c === 39 && navIdx < TABS.length - 1) { navIdx++; goTab(navIdx, false); }
            else if (c === 40 || c === 13) { navFocus = false; renderNav(); if (screens[cur.name].focus) screens[cur.name].focus(); }
            e.preventDefault();
            return;
        }
        contentKey(c, e);
    }
    function init() {
        screens = { home: Home, live: LiveHome, guide: Guide, lib: Library, detail: Detail, search: Search, settings: Settings };
        buildTabs(); Data.applyCountries();
        for (var k in screens) { screens[k].name = k; screens[k].el = U.$(k); screens[k].init(); }
        Onboard.init(); GroupPicker.init();
        Player.init(function () {
            // the TV leaves the video plane black: force the page to redraw before repainting the screen
            var a = U.$('app'); a.style.display = 'none'; void a.offsetHeight; a.style.display = '';
            if (screens[cur.name].refresh) screens[cur.name].refresh();
        });
        try {
            tizen.tvinputdevice.registerKeyBatch(['ChannelUp', 'ChannelDown', 'MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop', 'MediaRewind', 'MediaFastForward']);
        } catch (e) { /* not on a TV */ }
        Intro.start();   // the opening video plays while Home loads underneath
        setTimeout(function () { try { U.repairFavLogos(Data.liveOf); } catch (e) { U.log({ ev: 'favs.logos.error', err: String(e) }); } }, 6000);
        document.addEventListener('keydown', onKey);
        document.addEventListener('keyup', onKeyUp);
        // Hidden: return to the opening state under the opening frame. Shown again (the launcher's card
        // has landed on that same frame): lift the frame.
        document.addEventListener('visibilitychange', function () {
            var b = U.$('boot');
            if (document.hidden) {
                if (Player.active()) return;
                Intro.end(true);
                b.style.display = 'block'; b.className = '';   // the black frame, same as the launcher's card
                U.log({ ev: 'hidden' });
            } else {
                U.log({ ev: 'shown' });
                // every open from the launcher plays the opening; the black frame stays until its first frame
                if (Player.active() || !Intro.start()) { b.className = 'gone'; setTimeout(function () { b.style.display = 'none'; }, 300); }
            }
        });
        // ?boot renders the opening frame for the launcher: no clock, so the picture never shows a stale time
        if (location.search.indexOf('boot') < 0) { U.clock(); setInterval(U.clock, 10000); }
        goTab(0, true);
        refreshTabs();
        if (!U.accounts.has()) Onboard.open();   // first launch, no source: the sign-in comes first
        // drop the boot frame once Home has drawn its first picture
        Home.ready(function () {
            if (!Intro.busy()) Intro.lift(true);   // otherwise the opening lifts it when it ends
            U.log({ ev: 'ready', ms: Date.now() - (window.T0 || Date.now()) });
            setTimeout(function () { if (window.diagLayout) diagLayout('ready'); }, 1500);

        });
    }
    function applySettings(what) {
        if (what === 'tabs') { var id = TABS[tab] && TABS[tab].id; buildTabs(); for (var i = 0; i < TABS.length; i++) if (TABS[i].id === id) tab = navIdx = i; renderNav(); }
        if (what === 'countries') Data.applyCountries();
    }
    // The first source was just signed in: load everything for it, behind the sign-in screen.
    function signedIn() { Data.reset(); Data.applyCountries(); buildTabs(); goTab(0, true); refreshTabs(); }
    function refreshTabs() { if (U.accounts.type() === 'x' || !U.accounts.has()) return; Src.probe(U.accounts.active(), function () { applySettings('tabs'); }); }
    return { signedIn: signedIn, init: init, show: show, back: back, goTab: goTab, focusNav: focusNav, tabs: TABS, applySettings: applySettings };
})();

window.T0 = Date.now();
App.init();
