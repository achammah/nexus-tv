// First launch: the sign-in screen. Split screen: brand and features on the left, Server / Username / Password on the right.
// Shown when the app has no source. "Later" (or Back) leaves it for Home's empty library; a good login ends in a short
// transition into Home. Icons: Lucide (ISC licence). ES5 only: the Tizen 3 engine is WebKit 538.
var Onboard = (function () {
    'use strict';
    var P = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">';
    var IC = {
        server: P + '<rect width="20" height="8" x="2" y="2" rx="2" ry="2"/><rect width="20" height="8" x="2" y="14" rx="2" ry="2"/><line x1="6" x2="6.01" y1="6" y2="6"/><line x1="6" x2="6.01" y1="18" y2="18"/></svg>',
        user: P + '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>',
        key: P + '<path d="M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z"/><circle cx="16.5" cy="7.5" r=".5" fill="currentColor"/></svg>',
        arrow: P + '<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>',
        spin: P + '<path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>',
        check: P + '<path d="M20 6 9 17l-5-5"/></svg>',
        x: P + '<path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>',
        library: P + '<rect width="8" height="18" x="3" y="3" rx="1"/><path d="M7 3v18"/><path d="M20.4 18.9c.2.5-.1 1.1-.6 1.3l-1.9.7c-.5.2-1.1-.1-1.3-.6L11.1 5.1c-.2-.5.1-1.1.6-1.3l1.9-.7c.5-.2 1.1.1 1.3.6Z"/></svg>',
        play: P + '<circle cx="12" cy="12" r="10"/><polygon points="10 8 16 12 10 16 10 8"/></svg>',
        captions: P + '<rect width="18" height="14" x="3" y="5" rx="2" ry="2"/><path d="M7 15h4M15 15h2M7 11h2M13 11h4"/></svg>',
        shield: P + '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/></svg>'
    };
    var LOCK = '<svg class="olk" width="611" height="260" viewBox="0 0 611 260" style="overflow:visible"><defs>' +
        '<linearGradient id="onPearl" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="79" y2="260"><stop offset="0" stop-color="#FDFEFF"/><stop offset="0.5" stop-color="#F3E7F7"/><stop offset="1" stop-color="#D394E6"/></linearGradient>' +
        '<linearGradient id="onPearlR" gradientUnits="userSpaceOnUse" x1="224.71428571428572" y1="0" x2="90" y2="260"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/><stop offset="1" stop-color="#C6B8C5" stop-opacity="0"/></linearGradient>' +
        '<linearGradient id="onTv" gradientUnits="userSpaceOnUse" x1="0" y1="22" x2="0" y2="257"><stop offset="0" stop-color="#FEFEFE"/><stop offset="0.55" stop-color="#F4F7EE"/><stop offset="1" stop-color="#AEDB8E"/></linearGradient></defs>' +
        '<g transform="scale(0.92857)" fill="url(#onPearl)"><path d="M0 69.855L0.000167052 209.566L120.954 279.421L120.954 176.948C120.954 153.905 108.665 132.613 88.7154 121.092L0 69.855Z"/><path d="M164.313 77.4323C184.262 88.9537 196.551 110.246 196.551 133.289L196.551 183.37L241.909 209.566L241.909 107.093C241.909 84.0505 229.62 62.758 209.67 51.2365L120.955 9.45148e-06L120.955 52.3915L164.313 77.4323Z"/><path d="M103.836 112.36C123.785 123.881 136.074 145.174 136.074 168.217L136.074 218.298L181.432 244.494L181.432 142.021C181.432 118.978 169.143 97.6856 149.193 86.1641L60.4779 34.9276L60.478 87.3191L103.836 112.36Z"/><path d="M43.3578 147.287C63.307 158.809 75.5963 180.101 75.5963 203.144L75.5964 253.225L120.954 279.421L120.954 176.948C120.954 153.905 108.665 132.613 88.7154 121.092L0 69.855L7.91518e-05 122.247L43.3578 147.287Z"/></g>' +
        '<g transform="scale(0.92857)" fill="url(#onPearlR)"><path d="M0 69.855L0.000167052 209.566L120.954 279.421L120.954 176.948C120.954 153.905 108.665 132.613 88.7154 121.092L0 69.855Z"/><path d="M164.313 77.4323C184.262 88.9537 196.551 110.246 196.551 133.289L196.551 183.37L241.909 209.566L241.909 107.093C241.909 84.0505 229.62 62.758 209.67 51.2365L120.955 9.45148e-06L120.955 52.3915L164.313 77.4323Z"/><path d="M103.836 112.36C123.785 123.881 136.074 145.174 136.074 168.217L136.074 218.298L181.432 244.494L181.432 142.021C181.432 118.978 169.143 97.6856 149.193 86.1641L60.4779 34.9276L60.478 87.3191L103.836 112.36Z"/><path d="M43.3578 147.287C63.307 158.809 75.5963 180.101 75.5963 203.144L75.5964 253.225L120.954 279.421L120.954 176.948C120.954 153.905 108.665 132.613 88.7154 121.092L0 69.855L7.91518e-05 122.247L43.3578 147.287Z"/></g>' +
        '<text x="337" y="257" font-size="327" font-weight="500" letter-spacing="-4.9" fill="url(#onTv)" style="font-family:-apple-system,\'SF Pro Display\',\'Helvetica Neue\',Arial,sans-serif">tv</text></svg>';
    var FEATS = [
        ['library', 'Your library, organized', 'Whatever your service holds, sorted into clear shelves.'],
        ['play', 'Pick up where you left off', 'Resume anything; the next episode starts after a short countdown.'],
        ['captions', 'Subtitles that stay in sync', 'Matched to your file, then realigned while you watch.'],
        ['shield', 'Private by design', 'Your sign-in stays on this device. No account with us.']
    ];
    // Three ways to add a source. Only Xtream signs in for now; the other two show their fields and wait.
    var TYPES = {
        x: { name: 'Xtream login', sub: 'Use the server and login your service gave you. Xtream Codes compatible.',
            rows: [['server', 'Server', 'http://server:port'], ['user', 'Username', 'Username'], ['key', 'Password', 'Password']] },
        m: { name: 'M3U playlist', sub: 'Paste the playlist link your service gave you.',
            rows: [['server', 'Playlist', 'https://\u2026/playlist.m3u'], ['library', 'TV guide', 'Optional EPG link (XMLTV)'], ['user', 'Name', 'My playlist']] },
        p: { name: 'Portal', sub: 'Use the portal link and the MAC address your service registered.',
            rows: [['server', 'Portal', 'http://portal:port/c/'], ['key', 'MAC', '00:1A:79:00:00:00'], ['user', 'Name', 'My portal']] }
    };
    var ORDER = ['x', 'm', 'p'];
    var HINT = '<b>Remote:</b> OK to type, the number keys work too. Up and down move between fields.';
    var HINT_KB = '<b>Keyboard:</b> DONE saves a field and moves to the next. Back closes the keyboard.';
    var MSG_SERVER = 'Could not reach this server. Check the address and the network.';
    var MSG_AUTH = 'Server reached, but it refused this username and password.';
    var MSG_NEED = { x: 'Server, username and password are all needed.', m: 'The playlist link is needed.', p: 'The portal link and the MAC address are needed.' };
    // An Xtream export link (.../get.php?username=U&password=P, any order, any extra parameters) is not downloaded:
    // its server and login go through the Xtream path, which gives the full library.
    function xtreamLink(u) {
        var m = /^(https?:\/\/[^\/?#]+)[^?#]*get\.php\?([^#]*)/i.exec(String(u || '').replace(/^\s+|\s+$/g, '').replace(/^(?!https?:\/\/)/i, 'http://'));
        if (!m) return null;
        var q = {}, parts = m[2].split('&');
        for (var i = 0; i < parts.length; i++) {
            var k = parts[i].indexOf('='); if (k < 0) continue;
            try { q[parts[i].slice(0, k).toLowerCase()] = decodeURIComponent(parts[i].slice(k + 1).replace(/\+/g, ' ')); } catch (e) { q[parts[i].slice(0, k).toLowerCase()] = parts[i].slice(k + 1); }
        }
        return q.username && q.password ? { base: m[1], user: q.username, pass: q.password } : null;
    }
    var XFAIL = { server: ['Could not reach this server. Check the link and the network.', ['bad', null, null]], auth: ['Server reached, but it refused the login in this link.', ['bad', null, null]] };
    var REQ = { x: [0, 1, 2], m: [0], p: [0, 1] };
    // what each failed check says, and which rows turn red: [message, marks]
    var FAIL = {
        x: { server: [MSG_SERVER, ['bad', null, null]], auth: [MSG_AUTH, ['ok', 'bad', 'bad']] },
        m: { server: ['Could not reach this link. Check the address and the network.', ['bad', null, null]], auth: ['That server refused the link.', ['bad', null, null]], invalid: ['This link is not a playlist.', ['bad', null, null]], cancel: ['Playlist not loaded. Press Sign in to try again.', [null, null, null]] },
        p: { server: ['Could not reach this portal. Check the address and the network.', ['bad', null, null]], auth: ['Portal reached, but it refused this MAC address.', ['ok', 'bad', null]] }
    };

    // focus: 0..2 = the three rows, 3 = Sign in, 4 = Later, 5 = the source type
    var el, isOpen = false, f = 0, type = 'x', valsBy = { x: ['', '', ''], m: ['', '', ''], p: ['', '', ''] }, vals = valsBy.x, marks = [null, null, null], editing = false, busy = false, run = 0;
    var kb = Keyboard.make(120, 520), addMode = false, state = 'idle', msgKind = '', msgText = '', ending = false, timers = [];

    function $(id) { return document.getElementById(id); }
    function later(fn, ms) { var t = setTimeout(fn, ms); timers.push(t); return t; }
    function clearTimers() { for (var i = 0; i < timers.length; i++) clearTimeout(timers[i]); timers = []; }

    function init() {
        el = U.$('onb');
        var feats = '', rows = '', i;
        for (i = 0; i < FEATS.length; i++)
            feats += '<div class="oft" style="top:' + (321 + i * 88) + 'px"><div class="otile">' + IC[FEATS[i][0]] + '</div><b>' + FEATS[i][1] + '</b><span>' + FEATS[i][2] + '</span></div>';
        for (i = 0; i < 3; i++)
            rows += '<div class="orow" id="or' + i + '"><div class="oic" id="oi' + i + '"></div><div class="ol" id="ol' + i + '"></div><div class="ov" id="ov' + i + '"></div><div class="ost" id="ost' + i + '"></div></div>';
        var segs = '';
        for (i = 0; i < 3; i++) segs += '<div class="oty" id="oty' + i + '" style="left:' + (4 + i * 229) + 'px">' + TYPES[ORDER[i]].name + '</div>';
        el.innerHTML =
            '<div id="onL"><div class="oglow" id="og1"></div><div class="oglow" id="og2"></div><div class="oglow" id="og3"></div>' +
            '<div id="olcol">' + LOCK + '<div class="oh1">Your media,<br>beautifully organized.</div>' +
            '<div class="olede">A player for the service you already have. Sign in once and everything is in its place.</div>' +
            '<div id="ofeats">' + feats + '</div></div>' +
            '<div id="okb"></div>' +
            '<div class="olegal">Nexus TV is a player. It includes no content.</div></div>' +
            '<div id="onR"><div id="olater">Later</div><div id="orcol">' +
            '<div class="oh2" id="oh2">Sign in</div><div class="osub" id="osub"></div>' +
            '<div id="otypes">' + segs + '</div><div id="oform">' + rows + '</div><div id="obar"><i></i></div><div id="omsg"></div>' +
            '<div id="oacts"><div id="ogo" class="obtn opri"><span id="ogolbl">Sign in</span><i id="ogoic"></i></div></div>' +
            '<div class="ohint" id="ohint"></div></div></div>';
    }

    function setMsg(kind, text) { msgKind = kind || ''; msgText = text || ''; }
    function ico(name) { return IC[name]; }

    function draw() {
        var i, busyNow = state === 'checking', cls;
        for (i = 0; i < 3; i++) {
            var R = TYPES[type].rows[i];
            var v = type === 'x' && i === 2 ? new Array(vals[i].length + 1).join('\u2022') : vals[i];
            var caret = f === i && !busyNow ? '<span class="ocaret"></span>' : '';
            var node = $('ov' + i);
            node.className = 'ov' + (v ? '' : ' ph');
            node.innerHTML = U.esc(v || R[2]) + caret;
            $('oi' + i).innerHTML = IC[R[0]]; $('ol' + i).textContent = R[1];
            cls = 'orow' + (f === i && !busyNow ? ' focus' : '') + (marks[i] ? ' ' + marks[i] : '');
            $('or' + i).className = cls;
            $('ost' + i).innerHTML = marks[i] ? ico(marks[i] === 'ok' ? 'check' : 'x') : '';
        }
        $('osub').textContent = TYPES[type].sub;
        for (i = 0; i < 3; i++) $('oty' + i).className = 'oty' + (ORDER[i] === type ? ' on' : '');
        $('otypes').className = f === 5 ? 'focus' : '';
        $('olater').textContent = addMode ? 'Cancel' : 'Later';
        $('oh2').textContent = addMode ? 'Add a source' : 'Sign in';
        $('orcol').setAttribute('data-t', type);
        $('oform').className = busyNow ? 'dim' : '';
        $('obar').className = busyNow ? 'on' : '';
        var m = $('omsg');
        m.className = msgKind ? 'on ' + msgKind : '';
        m.innerHTML = msgKind ? ico(msgKind === 'bad' ? 'x' : msgKind === 'ok' ? 'check' : 'spin') + '<span>' + U.esc(msgText) + '</span>' : '';
        var g = $('ogo');
        g.className = 'obtn opri' + (state === 'checking' ? ' busy' : state === 'done' ? ' done' : '') + (f === 3 ? ' focus' : '');
        $('ogolbl').textContent = state === 'checking' ? 'Checking' : state === 'done' ? (addMode ? 'Added' : 'Signed in') : 'Sign in';
        $('ogoic').innerHTML = ico(state === 'checking' ? 'spin' : state === 'done' ? 'check' : 'arrow');
        $('olater').className = f === 4 ? 'focus' : '';
        $('ohint').innerHTML = editing ? HINT_KB : HINT;
        $('okb').innerHTML = editing ? Keyboard.draw(kb, true) : '';
        el.className = (editing ? 'edit ' : '') + (isOpen ? 'on' : '') + (ending ? ' go' : '');
    }

    function clearResult() { marks = [null, null, null]; setMsg(); state = 'idle'; }

    function submit() {
        if (busy) return;
        var need = [], i, req = REQ[type];
        for (i = 0; i < req.length; i++) if (!vals[req[i]]) need.push(req[i]);
        if (need.length) { marks = [null, null, null]; for (i = 0; i < need.length; i++) marks[need[i]] = 'bad'; setMsg('bad', MSG_NEED[type]); f = need[0]; draw(); return; }
        busy = true; editing = false; f = 3; clearResult(); state = 'checking';
        var xl = type === 'm' ? xtreamLink(vals[0]) : null;
        setMsg('wait', xl ? 'Recognised as an Xtream link: full library' : type === 'x' ? 'Contacting your server\u2026' : type === 'm' ? 'Reading your playlist\u2026' : 'Contacting your portal\u2026'); draw();
        var mine = ++run, t = type, v = vals.slice();
        var check = xl ? function (cb) { Src.check('x', [xl.base, xl.user, xl.pass], cb); } : function (cb) { Src.check(t, v, cb); };
        check(function (stage) {
            if (mine !== run || !isOpen) return;
            busy = false;
            state = 'idle';
            if (stage !== 'ok') { var fl = xl ? (XFAIL[stage] || XFAIL.server) : (FAIL[t][stage] || FAIL[t].server); marks = fl[1].slice(); setMsg('bad', fl[0]); shake(); draw(); return; }
            marks = [];
            for (i = 0; i < 3; i++) marks.push(i === 0 || v[i] ? 'ok' : null);
            state = 'done'; setMsg('ok', addMode ? 'Source added' : 'Signed in \u00b7 preparing your library'); draw();
            var first = !U.accounts.has(), name, acc;
            if (xl) { name = v[2] || xl.user; acc = { type: 'x', name: name, base: xl.base, user: xl.user, pass: xl.pass }; }
            else if (t === 'x') { name = v[1]; acc = { type: 'x', name: name, base: v[0], user: v[1], pass: v[2] }; }
            else if (t === 'm') { name = v[2] || 'My playlist'; acc = { type: 'm', name: name, base: v[0], epg: v[1] || Src.guideOf(U.normBase(v[0])) }; }
            else { name = v[2] || 'My portal'; acc = { type: 'p', name: name, base: v[0], mac: v[1].replace(/^\s+|\s+$/g, '').toUpperCase() }; }
            if (t === 'm' && !xl) { var bi = Src.bigInfo(U.normBase(v[0])); if (bi && bi.big) { acc.big = true; acc.groups = bi.groups; acc.ngroups = bi.groupCount; } }
            U.accounts.add(acc);
            U.log({ ev: 'onboard.signedin', type: t });
            if (first) { App.signedIn(); later(finish, 1300); return; }   // Home loads for the new source while this screen is still up
            later(function () { close(); Settings.redraw(); U.toast('Source added: ' + name); }, 900);
        });
    }
    function shake() {
        var c = $('orcol'); c.className = ''; void c.offsetWidth; c.className = 'shake';
        later(function () { c.className = ''; }, 600);
    }
    // The halves slide apart and fade; Home rises from a slight zoom behind them.
    function finish() {
        var app = U.$('app');
        app.style.webkitTransition = 'none'; app.style.transition = 'none';
        app.style.opacity = '0'; app.style.webkitTransform = 'scale(1.06)'; app.style.transform = 'scale(1.06)';
        void app.offsetWidth;
        app.style.webkitTransition = 'opacity .9s ease .25s, -webkit-transform 1.2s cubic-bezier(.2,.8,.2,1) .2s';
        app.style.transition = 'opacity .9s ease .25s, transform 1.2s cubic-bezier(.2,.8,.2,1) .2s';
        app.style.opacity = '1'; app.style.webkitTransform = 'none'; app.style.transform = 'none';
        ending = true; draw();
        later(function () {
            app.style.webkitTransition = ''; app.style.transition = ''; app.style.opacity = ''; app.style.webkitTransform = ''; app.style.transform = '';
            close();
        }, 1400);
    }
    function close() {
        clearTimers(); run++; busy = false; isOpen = false; addMode = false; ending = false; editing = false;
        el.className = ''; el.style.display = 'none';
        valsBy = { x: ['', '', ''], m: ['', '', ''], p: ['', '', ''] }; vals = valsBy[type = 'x']; clearResult(); f = 0;
    }
    function open(opts) {
        if (isOpen) return;
        addMode = !!(opts && opts.add) && U.accounts.has();
        clearTimers(); kb = Keyboard.make(120, 520); isOpen = true; ending = false; editing = false; busy = false; f = 0; valsBy = { x: ['', '', ''], m: ['', '', ''], p: ['', '', ''] }; vals = valsBy[type = 'x']; clearResult();
        el.style.display = 'block'; draw();
    }

    function setType(d) {
        var k = ORDER.indexOf(type) + d;
        if (k < 0 || k > 2) return;
        type = ORDER[k]; vals = valsBy[type]; clearResult();
    }
    function key(c) {
        var i, r;
        if (ending) return;
        if (busy) { if (c === 10009 || c === 8 || c === 27) close(); return; }
        if (editing) {
            if (c === 10009 || c === 8 || c === 27) { editing = false; draw(); return; }
            r = Keyboard.key(kb, c);
            if (r && r.ch !== undefined) vals[f] += r.ch;
            else if (r === 'del') vals[f] = vals[f].slice(0, -1);
            else if (r === 'up') { if (f > 0) f--; }
            else if (r === 'done') { if (f < 2) f++; else { submit(); return; } }
            draw(); return;
        }
        if (c === 10009 || c === 8 || c === 27) { close(); return; }      // Back on the form = Later
        if (c === 38) { f = f === 0 ? 5 : f === 5 ? 4 : f === 4 ? 4 : f - 1; }
        else if (c === 40) { f = f === 4 ? 5 : f === 5 ? 0 : f === 3 ? 3 : f + 1; }
        else if (c === 39) { if (f === 5) setType(1); else if (f < 3) f = 3; }
        else if (c === 37) { if (f === 5) setType(-1); else if (f === 3) f = 2; }
        else if (c === 13) {
            if (f === 5) return;
            if (f === 3) { submit(); return; }
            if (f === 4) { close(); return; }
            clearResult(); editing = true;
        }
        else if (c >= 48 && c <= 57 && f < 3) { clearResult(); editing = true; vals[f] += String(c - 48); }
        draw();
    }
    return { lock: LOCK, xtreamLink: xtreamLink, init: init, open: open, close: close, key: key, isOpen: function () { return isOpen; } };
})();
