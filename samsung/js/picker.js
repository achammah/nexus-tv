// A very large playlist: while it downloads, this screen lists every group seen so far with its entry count (live),
// and the viewer ticks the groups to keep. Same look as the sign-in. ES5 only (Tizen 3, WebKit 538).
var GroupPicker = (function () {
    'use strict';
    var P = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">';
    var SEARCH = P + '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>', CHECK = P + '<path d="M20 6 9 17l-5-5"/></svg>';
    var CAP = 60000, VIS = 8, ROWH = 66;
    var el, isOpen = false, ctl = null, st = null, z = 1, p = 2, sel = 0, top = 0, q = '', editing = false, busy = false, ticked = {}, kb = null, built = false;

    function fmt(n) { return String(n).replace(/\B(?=(\d{3})+$)/g, ','); }
    function mb(n) { return (n / 1048576).toFixed(1); }
    function visible() {
        var out = [], o = st ? st.order : [], f = q.toLowerCase();
        for (var i = 0; i < o.length; i++) if (!f || o[i].toLowerCase().indexOf(f) >= 0) out.push(o[i]);
        return out;
    }
    function selected() { var n = 0, g; for (g in ticked) if (ticked[g] === 1 && st && st.idx[g]) n += st.idx[g].n; return n; }
    function ticks() { var n = 0, g; for (g in ticked) if (ticked[g] === 1) n++; return n; }

    function init() {
        el = document.getElementById('gpk');
        el.innerHTML = '<div id="gL"><div class="oglow" id="pg1"></div><div class="oglow" id="pg2"></div><div class="oglow" id="pg3"></div>' +
            '<div id="glcol">' + Onboard.lock.replace(/onPearlR/g, 'gpPearlR').replace(/onPearl/g, 'gpPearl').replace(/onTv/g, 'gpTv') +
            '<div class="oh1" style="font-size:44px;line-height:52px">This playlist is very large</div>' +
            '<div class="olede" style="top:150px">Choose the groups you want. The rest is skipped. You can change this later in Settings, Sources.</div>' +
            '<div id="gprog"></div><div id="gbar"><i></i></div><div id="gcnt"></div></div>' +
            '<div id="gkb"></div><div class="olegal">Nexus TV is a player. It includes no content.</div></div>' +
            '<div id="gR"><div id="grcol"><div id="gsearch"><div class="oic">' + SEARCH + '</div><div class="gq" id="gq"></div></div>' +
            '<div class="gpill" id="gp0" style="left:0">Select all</div><div class="gpill" id="gp1" style="left:176px">None</div>' +
            '<div class="gpill prim" id="gp2" style="right:0">Keep selected</div>' +
            '<div id="glist"></div><div id="gempty"></div><div id="ghint"></div></div></div>';
    }

    function draw() {
        if (!isOpen || !st) return;
        var vis = visible(), i, h = '';
        if (sel >= vis.length) sel = Math.max(0, vis.length - 1);
        if (sel < top) top = sel; if (sel >= top + VIS) top = sel - VIS + 1;
        for (i = top; i < vis.length && i < top + VIS; i++) {
            var g = vis[i], on = ticked[g] === 1;
            h += '<div class="grow2' + (on ? ' on' : '') + (z === 2 && i === sel ? ' focus' : '') + '" style="top:' + (190 + (i - top) * ROWH) + 'px"><div class="box">' + CHECK + '</div><div class="gn">' + U.esc(g) + '</div><div class="gc">' + fmt(st.idx[g].n) + '</div></div>';
        }
        document.getElementById('glist').innerHTML = h;
        document.getElementById('gempty').textContent = vis.length ? '' : (st.order.length ? 'No group matches this search.' : 'Reading the playlist…');
        var s = document.getElementById('gsearch'), gq = document.getElementById('gq');
        s.className = z === 0 ? 'focus' : '';
        gq.className = 'gq' + (q ? '' : ' ph');
        gq.innerHTML = U.esc(q || 'Search groups') + (editing ? '<span class="ocaret"></span>' : '');
        var n = selected(), ok = ticks() > 0 && !busy;
        for (i = 0; i < 3; i++) document.getElementById('gp' + i).className = 'gpill' + (i === 2 ? ' prim' + (ok ? '' : ' off') : '') + (z === 1 && p === i ? ' focus' : '');
        var pct = st.total ? Math.min(100, Math.round(100 * st.off / st.total)) : 0;
        document.getElementById('gprog').textContent = busy ? 'Reading the groups you kept… ' + mb(st.off) + ' of ' + mb(st.total) + ' MB' : (st.done ? 'Read ' + mb(st.total) + ' MB. All ' + fmt(st.order.length) + ' groups are listed.' : 'Reading ' + mb(st.off) + ' of ' + (st.total ? mb(st.total) : '?') + ' MB · ' + fmt(st.order.length) + ' groups so far');
        document.getElementById('gbar').firstChild.style.width = pct + '%';
        var cn = document.getElementById('gcnt');
        cn.className = n > CAP ? 'over' : '';
        cn.textContent = busy ? (fmt(st.kept) + ' entries kept') : (ticks() + ' groups ticked · ' + fmt(n) + ' entries' + (n > CAP ? ' (only the first ' + fmt(CAP) + ' are kept)' : ' of ' + fmt(CAP) + ' allowed'));
        document.getElementById('ghint').textContent = editing ? 'DONE closes the keyboard. Back closes it too.' : 'OK ticks a group. Right and left move between the buttons. Back leaves the playlist unread.';
        document.getElementById('gkb').innerHTML = editing ? Keyboard.draw(kb, true) : '';
        el.className = editing ? 'edit' : '';
    }

    function show(c) {
        ctl = c; st = c.state();
        if (!isOpen) { isOpen = true; busy = false; z = 1; p = 2; sel = 0; top = 0; q = ''; editing = false; ticked = {}; kb = Keyboard.make(120, 540); el.style.display = 'block'; }
        draw();
    }
    function progress(s) { st = s; draw(); }
    function reading() { busy = true; editing = false; draw(); }
    function close() { isOpen = false; busy = false; ctl = null; if (el) { el.style.display = 'none'; el.className = ''; } }

    function setVisible(on) {
        var v = visible();
        for (var i = 0; i < v.length; i++) { if (on) ticked[v[i]] = 1; else delete ticked[v[i]]; }
    }
    function key(c) {
        if (!isOpen || !st) return;
        var back = c === 10009 || c === 8 || c === 27;
        if (busy) { if (back && ctl) ctl.cancel(); return; }
        if (editing) {
            if (back) { editing = false; draw(); return; }
            var r = Keyboard.key(kb, c);
            if (r && r.ch !== undefined) { q += r.ch; sel = 0; top = 0; }
            else if (r === 'del') { q = q.slice(0, -1); sel = 0; top = 0; }
            else if (r === 'done') editing = false;
            draw(); return;
        }
        if (back) { if (ctl) ctl.cancel(); return; }
        var n = visible().length;
        if (c === 38) { if (z === 2) { if (sel > 0) sel--; else z = 1; } else if (z === 1) z = 0; }
        else if (c === 40) { if (z === 0) z = 1; else if (z === 1) { if (n) z = 2; } else if (sel < n - 1) sel++; }
        else if (c === 37) { if (z === 1 && p > 0) p--; }
        else if (c === 39) { if (z === 1 && p < 2) p++; }
        else if (c === 427 && z === 2) sel = Math.max(0, sel - VIS);
        else if (c === 428 && z === 2) sel = Math.min(n - 1, sel + VIS);
        else if (c === 13) {
            if (z === 0) editing = true;
            else if (z === 1) {
                if (p === 0) setVisible(true);
                else if (p === 1) setVisible(false);
                else if (ticks() > 0) { var set = {}, g; for (g in ticked) if (ticked[g] === 1) set[g] = 1; busy = true; ctl.keep(set); }
            } else {
                var gname = visible()[sel];
                if (gname) { if (ticked[gname] === 1) delete ticked[gname]; else ticked[gname] = 1; }
            }
        }
        draw();
    }
    return { init: init, show: show, progress: progress, reading: reading, close: close, key: key, isOpen: function () { return isOpen; } };
})();
