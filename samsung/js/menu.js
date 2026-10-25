// Long-press menu: a small panel of actions for the focused item. Up/Down choose, OK runs, Back closes.
var Menu = (function () {
    'use strict';
    var open = false, items = [], sel = 0, title = '', head = '';
    function draw() {
        var el = U.$('menu'), h = head ? '<div class="mh">' + U.esc(head) + '</div>' : '';
        for (var i = 0; i < items.length; i++) {
            var it0 = items[i];
            if (it0.chips) {   // a row of chips: Left/Right choose, OK runs it (the show menu's season and episode rows)
                h += '<div class="mi chips' + (i === sel ? ' focus' : '') + '"><div class="mc">' + U.esc(it0.label) + '</div><div class="cr">';
                for (var c = 0; c < it0.chips.length; c++) h += '<span class="' + (it0.chips[c].on ? 'on' : '') + (i === sel && c === it0.ci ? ' cf' : '') + '">' + U.esc(it0.chips[c].label) + '</span>';
                h += '</div></div>'; continue;
            }
            h += '<div class="mi' + (i === sel ? ' focus' : '') + (it0.red ? ' red' : '') + '"><span>' + it0.label + '</span><i' + (it0.note ? ' class="mn"' : '') + '>' + (it0.note || it0.icon || '') + '</i></div>';
        }
        el.innerHTML = h; el.className = open ? 'show' : '';
        // attach the card to the focused tile: below it, or above when the tile is low on screen
        var a = document.querySelector('.tile.focus, .ch.focus');
        if (open && a) {
            var r = a.getBoundingClientRect();
            el.style.left = Math.max(40, Math.min(1920 - 500, Math.round(r.left + 10))) + 'px';
            el.style.top = (r.bottom + 16 + el.offsetHeight < 1060 ? Math.round(r.bottom + 16) : Math.round(r.top - 16 - el.offsetHeight)) + 'px';
        }
    }
    return {
        // head: a grey line above the entries; start: the entry that has the focus first
        open: function (t, list, hd, start) { title = t; items = list; head = hd || ''; sel = start || 0; open = true; draw(); },
        close: function () { open = false; draw(); },
        isOpen: function () { return open; },
        key: function (c) {
            var cur = items[sel];
            if (c === 38 && sel > 0) sel--;
            else if (c === 40 && sel < items.length - 1) sel++;
            else if (cur && cur.chips && (c === 37 || c === 39)) cur.ci = Math.max(0, Math.min(cur.chips.length - 1, (cur.ci || 0) + (c === 37 ? -1 : 1)));
            else if (c === 13 && cur && cur.chips) { var ch = cur.chips[cur.ci || 0]; open = false; draw(); if (ch && ch.run) ch.run(); return true; }
            else if (c === 13) { var it = items[sel]; open = false; draw(); if (it && it.run) it.run(); return true; }
            else if (c === 10009 || c === 8 || c === 27 || c === 37) { open = false; }
            draw(); return true;
        }
    };
})();
