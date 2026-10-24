// Temporary diagnostics: sends playback events to the owner's Mac on the LAN.
(function () {
    var SINK = 'http://__MAC__:8815/log';
    window.diag = function (o) {
        try {
            o.t = new Date().toISOString();
            var x = new XMLHttpRequest();
            x.open('POST', SINK, true);
            x.setRequestHeader('Content-Type', 'text/plain');
            x.send(JSON.stringify(o));
        } catch (e) { /* never break the app */ }
    };
    window.addEventListener('error', function (e) {
        diag({ ev: 'window.error', msg: e.message, src: (e.filename || '').split('/').pop(), line: e.lineno });
    });
    diag({ ev: 'boot', ua: navigator.userAgent, mse: typeof MediaSource });
})();
// Every remote key, seen before the app handles it.
document.addEventListener('keydown', function (e) { if (window.diag) diag({ ev: 'key', code: e.keyCode }); }, true);
// Where things really are on this engine.
window.diagLayout = function (tag) {
    function box(el) { if (!el) return null; var r = el.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)]; }
    var o = { ev: 'layout', tag: tag, nav: box(document.getElementById('nav')), brand: box(document.getElementById('brand')), clock: box(document.getElementById('clock')),
        meta: box(document.getElementById('heroMeta')), rows: box(document.getElementById('homeRows')), items: [], tops: [] };
    var its = document.querySelectorAll('#nav .it');
    for (var i = 0; i < its.length; i++) o.items.push([its[i].textContent, box(its[i])]);
    var pts = [[1700, 90], [1500, 90], [960, 90], [300, 300], [300, 700], [960, 900]];
    for (var j = 0; j < pts.length; j++) { var el = document.elementFromPoint(pts[j][0], pts[j][1]); o.tops.push([pts[j], el ? (el.id || el.className || el.tagName) + ':' + String(el.textContent || '').slice(0, 30) : null]); }
    var rt = document.querySelectorAll('.rowtitle'), ti = document.querySelectorAll('#homeRows .tile');
    o.rowtitles = []; for (var k = 0; k < rt.length && k < 8; k++) o.rowtitles.push([rt[k].textContent, box(rt[k])]);
    o.tiles = ti.length; o.tile0 = box(ti[0]); o.rowsHtml = (document.getElementById('homeRows') || {}).innerHTML ? document.getElementById('homeRows').innerHTML.length : 0;
    o.page = (document.getElementById('homePage') || { style: {} }).style.webkitTransform || '';
    o.search = location.search; o.href = String(location.href).slice(0, 60);
    diag(o);
};
