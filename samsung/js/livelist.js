// One live list as a grid of channel tiles (the Mac BrowseListPage + ChannelTile): the list name on top, 7 dark
// rounded tiles per row, each with the channel logo centred and the cleaned name under it in capitals; a channel
// without a logo is its wordmark tile. OK plays the channel, Up/Down while watching zap through this list.
// Opened from a list card of a country page (js/livecountry.js); Back returns to that card.
var LiveList = (function () {
    'use strict';
    var X0 = 112, COLS = 7, GAP = 24, TW = Math.floor((1920 - 2 * X0 - (COLS - 1) * GAP) / COLS), TH = 124, VG = 26, TOP = 236, VIS = 5;
    var el, active = false, d = null, list = null, chans = [], sel = 0, rowTop = 0, token = 0, win = '', lastFocus = null, ctx = null;

    // the list's channels in the guide's order: each group of the list in turn
    function collect() {
        chans = [];
        for (var k = 0; k < list.gi.length; k++) { var g = d.byGroup[list.gi[k]] || []; for (var j = 0; j < g.length; j++) chans.push(d.c[g[j]]); }
    }
    function loaded() { if (!d.lazy) return true; for (var k = 0; k < list.gi.length; k++) if (!d.loaded[list.gi[k]]) return false; return true; }
    function tile(i, focus) {
        var c = chans[i], x = X0 + (i % COLS) * (TW + GAP), y = (Math.floor(i / COLS) - rowTop) * (TH + VG);
        var nm = U.cleanName(c[0]) || c[0];
        return '<div class="chl' + (c[4] ? ' light' : '') + (focus ? ' focus' : '') + '" id="ll' + i + '" style="left:' + x + 'px;top:' + y + 'px;width:' + TW + 'px;height:' + TH + 'px">' +
            U.wordmark(c[0], false) + U.imgTag(c[1]) + '<div class="cn">' + U.esc(nm) + '</div></div>';
    }
    // only the rows on screen are in the page; a key press inside them only moves the focus outline
    function draw() {
        var r0 = Math.floor(sel / COLS);
        if (r0 < rowTop) rowTop = r0;
        if (r0 >= rowTop + VIS - 1 && r0 > 0) rowTop = Math.max(0, r0 - (VIS - 2));
        var from = rowTop * COLS, to = Math.min(chans.length, (rowTop + VIS + 1) * COLS), sig = from + ':' + to + ':' + chans.length;
        U.$('llTitle').innerHTML = U.esc(list ? list.label : '') + '<span>' + (loaded() ? Browse.fmt(chans.length) + (chans.length === 1 ? ' channel' : ' channels') : '') + '</span>';
        if (sig === win && U.$('llGrid').firstChild) { moveFocus(); return; }
        win = sig;
        var h = '';
        if (!loaded()) h = U.skelRow(COLS, X0, 0, TW, TH, GAP) + U.skelRow(COLS, X0, TH + VG, TW, TH, GAP);
        else if (!chans.length) h = '<div class="empty" style="left:' + X0 + 'px;top:40px">No channels in this list.</div>';
        for (var i = from; i < to; i++) h += tile(i, active && i === sel);
        U.$('llGrid').innerHTML = h;
        lastFocus = document.getElementById('ll' + sel);
    }
    function moveFocus() {
        var e = document.getElementById('ll' + sel);
        if (lastFocus && lastFocus !== e) lastFocus.className = lastFocus.className.replace(/ focus\b/g, '');
        if (e && active && e.className.indexOf(' focus') < 0) e.className += ' focus';
        if (e && !active) e.className = e.className.replace(/ focus\b/g, '');
        lastFocus = e;
    }
    function play() {
        if (!chans[sel]) return;
        var sub = (ctx ? ctx.name + ' · ' : '') + list.label, items = [];
        for (var i = 0; i < chans.length; i++) items.push({ sid: chans[i][3], name: chans[i][0], sub: sub });
        Player.start({ k: 'live', url: U.liveUrl(items[sel].sid), name: items[sel].name, sub: sub, list: items, idx: sel,
            onZap: function (i) { sel = i; } });
    }
    // o = { d: the country's live data, list: a Browse.live item {label, gi}, ctx: { cc, name } }
    function open(o) {
        var my = ++token;
        d = o.d; list = o.list; ctx = o.ctx; sel = 0; rowTop = 0; win = '';
        collect();
        App.show('livel', null, true); active = true; draw();
        if (loaded()) return;
        var left = 0;
        list.gi.forEach(function (g) { if (!d.loaded[g]) { left++; Data.loadGroup(d, g, function () { if (--left === 0 && my === token) { collect(); win = ''; draw(); } }); } });
    }
    function key(c) {
        var n = chans.length;
        if (!n) return c === 38 ? 'up' : true;
        if (c === 38) { if (sel - COLS >= 0) { sel -= COLS; draw(); } else return 'up'; }
        else if (c === 40) { if (sel + COLS < n) sel += COLS; else if (Math.floor(sel / COLS) < Math.floor((n - 1) / COLS)) sel = n - 1; draw(); }
        else if (c === 37) { if (sel % COLS > 0) { sel--; draw(); } }
        else if (c === 39) { if (sel % COLS < COLS - 1 && sel < n - 1) { sel++; draw(); } }
        else if (c === 427) { sel = Math.max(0, sel - COLS * (VIS - 1)); draw(); }
        else if (c === 428) { sel = Math.min(n - 1, sel + COLS * (VIS - 1)); draw(); }
        else if (c === 13) play();
        return true;
    }
    function init() {
        el = U.$('livel');
        el.innerHTML = '<div class="rowtitle" id="llTitle" style="left:' + X0 + 'px;top:166px"></div>' +
            '<div class="abs" id="llGrid" style="left:0;top:' + TOP + 'px;width:1920px;height:844px"></div>';
    }
    return {
        init: init, key: key, open: open,
        show: function () { if (list) draw(); },
        focus: function () { active = true; if (list) draw(); },
        blur: function () { active = false; if (list) draw(); },
        refresh: function () { if (list) { win = ''; draw(); } }
    };
})();
