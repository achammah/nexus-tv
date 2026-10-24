// Live guide: countries + categories (left), channels (middle), preview (right).
var Guide = (function () {
    'use strict';
    var el, d = null, cc = 0, col = 1, cat = 0, ch = 0, catTop = 0, chTop = 0, pbtn = 0, active = false;
    var CAT_H = 58, CAT_VIS = 12, CH_H = 78, CH_VIS = 9, HEAD_H = 46, COL_H = 730;
    // The category column: Browse.live(d) sections (a header row each) over merged, cleaned categories.
    // cats = the categories in column order; rows = headers + categories with their y; catTop = scroll in px.
    var cats = [], rows = [];
    // C = the countries in the strip: the pinned ones (Data.COUNTRIES), or one country opened from the Live page.
    var C = [];   // set to Data.COUNTRIES in init (app.js loads after this file)

    function layoutCats() {
        var keep = cats[cat] ? cats[cat].label : null, y = 0;
        cats = []; rows = [];
        if (!d) return;
        Browse.live(d).forEach(function (sec) {
            rows.push({ head: sec.title, y: y }); y += HEAD_H;
            sec.items.forEach(function (it, i) { it.y = y; it.first = i === 0; it.i = cats.length; cats.push(it); rows.push(it); y += CAT_H; });
        });
        rows.h = y;
        cat = 0;
        for (var i = 0; i < cats.length; i++) if (cats[i].label === keep) { cat = i; break; }
    }
    function cur() { return cats[cat] || null; }
    function group() {
        var it = cur(); if (!d || !it) return [];
        if (it.idx && it.len === d.c.length) return it.idx;
        var idx = [];
        for (var k = 0; k < it.gi.length; k++) { var g = d.byGroup[it.gi[k]] || []; for (var j = 0; j < g.length; j++) idx.push(g[j]); }
        it.idx = idx; it.len = d.c.length;
        return idx;
    }
    function loaded(it) { if (!d.lazy) return true; for (var k = 0; k < it.gi.length; k++) if (!d.loaded[it.gi[k]]) return false; return true; }
    function chan(i) { var g = group(); return d && g[i] !== undefined ? d.c[g[i]] : null; }
    function skelList() {
        var sk = '';
        for (var i = 0; i < CH_VIS; i++) sk += '<div class="skel" style="left:18px;top:' + (i * CH_H + 13) + 'px;width:86px;height:52px"><i></i></div><div class="skel line" style="left:186px;top:' + (i * CH_H + 28) + 'px;width:' + (220 + (i * 53) % 180) + 'px"><i></i></div>';
        return sk;
    }
    function load(i, keepPos) {
        cc = i;
        var sk = '';
        for (var i = 0; i < CH_VIS; i++) sk += '<div class="skel" style="left:18px;top:' + (i * CH_H + 13) + 'px;width:86px;height:52px"><i></i></div><div class="skel line" style="left:186px;top:' + (i * CH_H + 28) + 'px;width:' + (220 + (i * 53) % 180) + 'px"><i></i></div>';
        U.$('gChs').innerHTML = sk;
        Data.liveOf(C[cc][0], function (data) {
            d = data;
            if (!keepPos) { cats = []; cat = 0; ch = 0; catTop = 0; chTop = 0; }
            layoutCats();
            if (col === 1 && cats.length === 1) col = 2;      // one list only: open its channels directly
            draw();
        });
        drawCountries();
    }
    function drawCountries() {
        var h = '', box = U.$('gCtry');
        for (var i = 0; i < C.length; i++) {
            var c = 'ctry' + (i === cc ? ' on' : '') + (active && col === 0 && i === cc ? ' focus' : '');
            h += '<div class="' + c + '" id="gc' + i + '">' + C[i][1] + '</div>';
        }
        box.innerHTML = h;
        var x = 0;
        for (var j = 0; j < C.length; j++) { var e = U.$('gc' + j); e.style.left = x + 'px'; x += e.offsetWidth + 8; }
    }
    function drawCats() {
        if (!d) return;
        var it = cur();
        if (it) {
            var top = it.y - (it.first ? HEAD_H : 0);
            if (top < catTop) catTop = top;
            if (it.y + CAT_H > catTop + COL_H) catTop = it.y + CAT_H - COL_H;
        }
        catTop = Math.max(0, Math.min(catTop, Math.max(0, rows.h - COL_H)));
        var h = '';
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i], y = r.y - catTop;
            if (y + CAT_H < 0 || y > COL_H) continue;
            if (r.head) { h += '<div class="li head" style="top:' + y + 'px;width:364px">' + U.esc(r.head) + '</div>'; continue; }
            var c = 'li' + (r.i === cat ? (active && col === 1 ? ' focus' : ' on') : '');
            h += '<div class="' + c + '" style="top:' + y + 'px;width:364px">' + U.esc(r.label) + (loaded(r) ? '<em>' + group2(r).length + '</em>' : '') + '</div>';
        }
        U.$('gCats').innerHTML = h;
        scrollbar('gCatBar', catTop, COL_H, rows.h, 724);
    }
    function group2(it) { var n = 0; for (var k = 0; k < it.gi.length; k++) n += (d.byGroup[it.gi[k]] || []).length; return { length: n }; }
    function drawChs() {
        if (!d) return;
        var g = group();
        if (ch < chTop) chTop = ch;
        if (ch >= chTop + CH_VIS) chTop = ch - CH_VIS + 1;
        var h = '';
        for (var i = chTop; i < g.length && i < chTop + CH_VIS; i++) {
            var c = d.c[g[i]];
            var fav = U.isFav(c[3]);
            h += '<div class="ch' + (i === ch && active && col === 2 ? ' focus' : '') + '" style="top:' + ((i - chTop) * CH_H) + 'px;width:652px">' +
                '<span class="n">' + (i + 1) + '</span><span class="lg">' + U.wordmark(c[0], false) + U.imgTag(c[1]) + '</span>' +
                '<span class="nm">' + U.esc(c[0]) + '</span>' + (fav ? '<span class="star">&#9733;</span>' : '') + '</div>';
        }
        U.$('gChs').innerHTML = h || (cur() && !loaded(cur()) ? skelList() : '<div class="empty" style="left:24px;top:20px">No channels</div>');
        U.$('gChHead').innerHTML = U.esc(cur() ? cur().label : '') + ' &nbsp;&middot;&nbsp; ' + g.length + ' channels';
        scrollbar('gChBar', chTop, CH_VIS, g.length, 700);
    }
    function scrollbar(id, top, vis, total, h) {
        var b = U.$(id);
        if (total <= vis) { b.style.display = 'none'; return; }
        b.style.display = 'block';
        var th = Math.max(40, Math.round(h * vis / total));
        b.firstChild.style.height = th + 'px';
        b.firstChild.style.top = Math.round((h - th) * top / (total - vis)) + 'px';
    }
    function drawPreview() {
        var c = chan(ch), p = U.$('gPrev');
        if (!c) { p.innerHTML = ''; return; }
        var fav = U.isFav(c[3]);
        p.innerHTML = '<div class="screen"><span class="pill live" style="position:absolute;left:20px;top:20px">LIVE</span>' +
            '<div class="big' + (c[4] ? ' light' : '') + '">' + U.wordmark(c[0], true) + U.imgTag(c[1]) + '</div></div>' +
            '<h2>' + U.esc(c[0]) + '</h2><p>' + C[cc][1] + ' &nbsp;&middot;&nbsp; ' + U.esc(cur().label) + ' &nbsp;&middot;&nbsp; Channel ' + (ch + 1) + '</p>' +
            '<div class="btn' + (active && col === 3 && pbtn === 0 ? ' focus' : '') + '" style="left:30px;top:480px">&#9654;&nbsp; Watch</div>' +
            '<div class="btn' + (active && col === 3 && pbtn === 1 ? ' focus' : '') + '" style="left:196px;top:480px">' + (fav ? '&#9733;&nbsp; Favourite' : '&#9734;&nbsp; Favourite') + '</div>';
    }
    function draw() { drawCountries(); drawCats(); drawChs(); drawPreview(); ensure(); }
    function ensure() {
        var it = cur();
        if (!d || !d.lazy || !it || loaded(it)) return;
        var want = it, left = 0, done = function () { if (--left === 0 && want === cur()) { drawCats(); drawChs(); drawPreview(); } };
        for (var k = 0; k < it.gi.length; k++) if (!d.loaded[it.gi[k]]) { left++; Data.loadGroup(d, it.gi[k], done); }
    }
    function favCur() {
        var x = chan(ch); if (!x) return false;
        U.toggleFav({ sid: x[3], name: x[0], img: x[1], dark: x[4], sub: C[cc][1] + ' · ' + cur().label, cc: C[cc][0] });
        draw(); return true;
    }
    function play() {
        var g = group(); if (!g.length) return;
        var list = [];
        for (var i = 0; i < g.length; i++) { var c = d.c[g[i]]; list.push({ sid: c[3], name: c[0], sub: C[cc][1] + ' · ' + cur().label }); }
        Player.start({ k: 'live', url: U.liveUrl(list[ch].sid), name: list[ch].name, sub: list[ch].sub, list: list, idx: ch,
            onZap: function (i) { ch = i; } });
    }
    function key(c) {
        if (!d) return c === 38 ? 'up' : true;
        var g = group();
        switch (col) {
            case 0:
                if (c === 37 && cc > 0) load(cc - 1);
                else if (c === 39 && cc < C.length - 1) load(cc + 1);
                else if (c === 40 || c === 13) { col = cats.length === 1 ? 2 : 1; draw(); }
                else if (c === 38) return 'up';
                return true;
            case 1:
                if (c === 38) { if (cat > 0) { cat--; ch = 0; chTop = 0; } else col = 0; draw(); }
                else if (c === 40 && cat < cats.length - 1) { cat++; ch = 0; chTop = 0; draw(); }
                else if (c === 39 || c === 13) { col = 2; draw(); }
                else if (c === 427) { cat = Math.max(0, cat - CAT_VIS); ch = 0; chTop = 0; draw(); }
                else if (c === 428) { cat = Math.min(cats.length - 1, cat + CAT_VIS); ch = 0; chTop = 0; draw(); }
                return true;
            case 2:
                if (c === 38) { if (ch > 0) { ch--; drawChs(); drawPreview(); } else return 'up'; }
                else if (c === 40 && ch < g.length - 1) { ch++; drawChs(); drawPreview(); }
                else if (c === 427) { ch = Math.max(0, ch - CH_VIS); drawChs(); drawPreview(); }
                else if (c === 428) { ch = Math.min(g.length - 1, ch + CH_VIS); drawChs(); drawPreview(); }
                else if (c === 37) { col = cats.length === 1 ? 0 : 1; draw(); }
                else if (c === 39) { col = 3; pbtn = 0; draw(); }
                else if (c === 13) play();
                return true;
            case 3:
                if (c === 37) { if (pbtn > 0) pbtn--; else col = 2; draw(); }
                else if (c === 39 && pbtn < 1) { pbtn++; draw(); }
                else if (c === 13) {
                    if (pbtn === 0) play();
                    else { favCur(); }
                }
                return true;
        }
        return true;
    }
    function init() {
        el = U.$('guide'); C = Data.COUNTRIES;
        el.innerHTML = '<div class="abs bgshade" style="background:#000"></div>' +
            '<div class="glass" style="left:112px;top:150px;width:400px;height:840px">' +
            '<div class="abs" id="gCtry" style="left:18px;top:24px;width:364px;height:44px"></div>' +
            '<div class="abs" id="gCats" style="left:18px;top:98px;width:364px;height:730px;overflow:hidden"></div>' +
            '<div class="scrollbar" id="gCatBar" style="left:390px;top:98px;height:724px"><i></i></div></div>' +
            '<div class="glass" style="left:532px;top:150px;width:680px;height:840px">' +
            '<div class="sect" id="gChHead" style="left:32px;top:30px"></div>' +
            '<div class="abs" id="gChs" style="left:14px;top:70px;width:652px;height:710px"></div>' +
            '<div class="scrollbar" id="gChBar" style="left:670px;top:70px;height:700px"><i></i></div></div>' +
            '<div class="glass prev" id="gPrev" style="left:1232px;top:150px;width:576px;height:840px"></div>' +
            '<div class="hint abs" style="left:112px;top:1010px;font-size:20px;color:rgba(255,255,255,.42)">OK watch &nbsp;&middot;&nbsp; hold OK favourite &nbsp;&middot;&nbsp; &#8592; &#8594; columns &nbsp;&middot;&nbsp; CH +/&#8722; page &nbsp;&middot;&nbsp; CH +/&#8722; while watching changes channel</div>';
    }
    return {
        init: init, key: key,
        reset: function () { C = Data.COUNTRIES; cc = 0; d = null; cats = []; rows = []; cat = 0; ch = 0; catTop = 0; chTop = 0; },
        longPress: function () { return active && col === 2 ? favCur() : false; },
        // a pinned country (index in Data.COUNTRIES); a country with one list opens its channels directly
        openCountry: function (i) {
            if (C !== Data.COUNTRIES) { C = Data.COUNTRIES; d = null; }
            col = 1;
            if (i !== cc || !d) load(i); else if (cats.length === 1) col = 2;
        },
        // any other country or region of the source: code = provider code in lower case ('de'), name = its title
        openCode: function (code, name) {
            if (C.length === 1 && C[0][0] === code && d) { col = cats.length === 1 ? 2 : 1; return; }
            C = [[code, name]]; d = null; col = 1; load(0);
        },
        show: function () { if (!d) load(cc); else draw(); },
        focus: function () { active = true; draw(); },
        blur: function () { active = false; if (d) draw(); },
        refresh: function () { if (d) draw(); }
    };
})();
