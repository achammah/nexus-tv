// Long-press menu: a small panel of actions for the focused item. Up/Down choose, OK runs, Back closes.
var Menu = (function () {
    'use strict';
    var open = false, items = [], sel = 0, title = '';
    function draw() {
        var el = U.$('menu'), h = '';
        for (var i = 0; i < items.length; i++) h += '<div class="mi' + (i === sel ? ' focus' : '') + (items[i].red ? ' red' : '') + '"><span>' + items[i].label + '</span><i>' + (items[i].icon || '') + '</i></div>';
        el.innerHTML = h; el.className = open ? 'show' : '';
        // attach the card to the focused tile: below it, or above when the tile is low on screen
        var a = document.querySelector('.tile.focus, .ch.focus');
        if (open && a) {
            var r = a.getBoundingClientRect();
            el.style.left = Math.max(40, Math.min(1920 - 460, Math.round(r.left + 10))) + 'px';
            el.style.top = (r.bottom + 16 + el.offsetHeight < 1060 ? Math.round(r.bottom + 16) : Math.round(r.top - 16 - el.offsetHeight)) + 'px';
        }
    }
    return {
        open: function (t, list) { title = t; items = list; sel = 0; open = true; draw(); },
        close: function () { open = false; draw(); },
        isOpen: function () { return open; },
        key: function (c) {
            if (c === 38 && sel > 0) sel--;
            else if (c === 40 && sel < items.length - 1) sel++;
            else if (c === 13) { var it = items[sel]; open = false; draw(); if (it && it.run) it.run(); return true; }
            else if (c === 10009 || c === 8 || c === 27 || c === 37) { open = false; }
            draw(); return true;
        }
    };
})();
