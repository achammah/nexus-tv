// Live page (design A, same as the Mac and Apple TV): pinned countries as wide flag banners, regions as gradient
// cards, then every other country A to Z. OK on a card opens that country in the guide (js/guide.js) on top of
// this page; Back returns here. Flags: img/flags/<iso>.png (circle-flags, MIT, LICENSES/circle-flags.txt).
var LiveHome = (function () {
    'use strict';
    // ---------- countries: provider code -> name, flag, flag colour (ported from CountryNames.swift) ----------
    var ISO = { UK: 'GB', AFG: 'AF', VT: 'VN', KO: 'XK', EST: 'EE', BH: 'BA', CG: 'ME', KA: 'KZ', UKR: 'UA', BAN: 'BD', SL: 'SI', IS: 'IL' };
    var NAMES = {};
    ('AC:Ascension Island|AD:Andorra|AE:United Arab Emirates|AF:Afghanistan|AG:Antigua & Barbuda|AI:Anguilla|AL:Albania|AM:Armenia|AO:Angola|AQ:Antarctica|AR:Argentina|AS:American Samoa|AT:Austria|AU:Australia|AW:Aruba|AX:Åland Islands|AZ:Azerbaijan|BA:Bosnia|BB:Barbados|BD:Bangladesh|BE:Belgium|BF:Burkina Faso|BG:Bulgaria|BH:Bahrain|BI:Burundi|BJ:Benin|BL:St. Barthélemy|BM:Bermuda|BN:Brunei|BO:Bolivia|BQ:Caribbean Netherlands|BR:Brazil|BS:Bahamas|BT:Bhutan|BW:Botswana|BY:Belarus|BZ:Belize|CA:Canada|CD:Congo - Kinshasa|CF:Central African Republic|CG:Congo - Brazzaville|CH:Switzerland|CI:Côte d’Ivoire|CK:Cook Islands|CL:Chile|CM:Cameroon|CN:China|CO:Colombia|CR:Costa Rica|CU:Cuba|CV:Cape Verde|CW:Curaçao|CY:Cyprus|CZ:Czechia|DE:Germany|DJ:Djibouti|DK:Denmark|DM:Dominica|DO:Dominican Republic|DZ:Algeria|EC:Ecuador|EE:Estonia|EG:Egypt|EH:Western Sahara|ER:Eritrea|ES:Spain|ET:Ethiopia|FI:Finland|FJ:Fiji|FK:Falkland Islands|FM:Micronesia|FO:Faroe Islands|FR:France|GA:Gabon|GB:United Kingdom|GD:Grenada|GE:Georgia|GF:French Guiana|GG:Guernsey|GH:Ghana|GI:Gibraltar|GL:Greenland|GM:Gambia|GN:Guinea|GP:Guadeloupe|GQ:Equatorial Guinea|GR:Greece|GT:Guatemala|GU:Guam|GW:Guinea-Bissau|GY:Guyana|HK:Hong Kong|HN:Honduras|HR:Croatia|HT:Haiti|HU:Hungary|ID:Indonesia|IE:Ireland|IL:Israel|IM:Isle of Man|IN:India|IQ:Iraq|IR:Iran|IS:Iceland|IT:Italy|JE:Jersey|JM:Jamaica|JO:Jordan|JP:Japan|KE:Kenya|KG:Kyrgyzstan|KH:Cambodia|KI:Kiribati|KM:Comoros|KN:St. Kitts & Nevis|KP:North Korea|KR:South Korea|KW:Kuwait|KY:Cayman Islands|KZ:Kazakhstan|LA:Laos|LB:Lebanon|LC:St. Lucia|LI:Liechtenstein|LK:Sri Lanka|LR:Liberia|LS:Lesotho|LT:Lithuania|LU:Luxembourg|LV:Latvia|LY:Libya|MA:Morocco|MC:Monaco|MD:Moldova|ME:Montenegro|MF:St. Martin|MG:Madagascar|MH:Marshall Islands|MK:North Macedonia|ML:Mali|MM:Myanmar|MN:Mongolia|MO:Macao|MP:Northern Mariana Islands|MQ:Martinique|MR:Mauritania|MS:Montserrat|MT:Malta|MU:Mauritius|MV:Maldives|MW:Malawi|MX:Mexico|MY:Malaysia|MZ:Mozambique|NA:Namibia|NC:New Caledonia|NE:Niger|NF:Norfolk Island|NG:Nigeria|NI:Nicaragua|NL:Netherlands|NO:Norway|NP:Nepal|NR:Nauru|NU:Niue|NZ:New Zealand|OM:Oman|PA:Panama|PE:Peru|PF:French Polynesia|PG:Papua New Guinea|PH:Philippines|PK:Pakistan|PL:Poland|PM:St. Pierre & Miquelon|PN:Pitcairn Islands|PR:Puerto Rico|PS:Palestine|PT:Portugal|PW:Palau|PY:Paraguay|QA:Qatar|RE:Réunion|RO:Romania|RS:Serbia|RU:Russia|RW:Rwanda|SA:Saudi Arabia|SB:Solomon Islands|SC:Seychelles|SD:Sudan|SE:Sweden|SG:Singapore|SH:St. Helena|SI:Slovenia|SK:Slovakia|SL:Sierra Leone|SM:San Marino|SN:Senegal|SO:Somalia|SR:Suriname|SS:South Sudan|ST:São Tomé & Príncipe|SV:El Salvador|SX:Sint Maarten|SY:Syria|SZ:Eswatini|TC:Turks & Caicos Islands|TD:Chad|TG:Togo|TH:Thailand|TJ:Tajikistan|TK:Tokelau|TL:Timor-Leste|TM:Turkmenistan|TN:Tunisia|TO:Tonga|TR:Türkiye|TT:Trinidad & Tobago|TV:Tuvalu|TW:Taiwan|TZ:Tanzania|UA:Ukraine|UG:Uganda|US:United States|UY:Uruguay|UZ:Uzbekistan|VA:Vatican City|VC:St. Vincent & Grenadines|VE:Venezuela|VG:British Virgin Islands|VI:U.S. Virgin Islands|VN:Vietnam|VU:Vanuatu|WF:Wallis & Futuna|WS:Samoa|XK:Kosovo|YE:Yemen|YT:Mayotte|ZA:South Africa|ZM:Zambia|ZW:Zimbabwe')
        .split('|').forEach(function (p) { var i = p.indexOf(':'); NAMES[p.slice(0, i)] = p.slice(i + 1); });
    // main colour of a flag, for the wash on a pinned banner
    var COLOUR = { BE: 0x3A3000, FR: 0x0A1A4A, GB: 0x4A0A14, US: 0x0E1A40, ES: 0x5A1010, DE: 0x2A2A2A, NL: 0x4A1A10, CA: 0x5A0F14,
        IT: 0x0F4A24, PL: 0x4A1018, PT: 0x0F4A24, TR: 0x6A0F18, CZ: 0x0E2A5A, BR: 0x0F4A24, GR: 0x0E3A6A, IL: 0x0E3A6A,
        RO: 0x0E2A5A, IR: 0x0F4A24, AU: 0x0A1E4A, AT: 0x5A0F14, AL: 0x5A0F14, CH: 0x5A0F14, ME: 0x5A1010, ID: 0x5A0F14,
        HR: 0x0E2A5A, NZ: 0x0A1E4A, RS: 0x4A1020, HU: 0x0F4A24, SK: 0x0E2A5A, BG: 0x0F4A24, BA: 0x0E2A5A, SG: 0x5A0F14,
        CY: 0x3A3A3A, SI: 0x0E2A5A, MK: 0x5A1010, MY: 0x0E2A5A, RU: 0x0E2A5A, BD: 0x0F4A24, AZ: 0x0E3A6A, AF: 0x1A1A1A,
        AM: 0x5A1010, UA: 0x0E3A6A, TH: 0x0E2A5A, NP: 0x5A0F14, KZ: 0x0E4A6A, HK: 0x5A0F14, JP: 0x3A3A3A, UZ: 0x0E4A6A,
        VN: 0x5A0F14, MU: 0x4A1020, PH: 0x0E2A5A, MT: 0x5A0F14, XK: 0x0E2A5A, EE: 0x0E3A6A, GE: 0x4A1020, FI: 0x0E2A5A,
        SE: 0x0E3A6A, IE: 0x0F4A24, IN: 0x5A3A0F, PK: 0x0F4A24, BY: 0x4A1020, LT: 0x3A3A0A };
    // groups that are not a country: [id, provider codes, title, gradient from, to]
    var REGIONS = [['AR', ['AR'], 'Arabic', 0xC9A227, 0x1F6F5C], ['ASIA', ['ASIA'], 'Asia', 0xE0475B, 0xF2B33D],
        ['LAT', ['LAT', 'LA'], 'Latin America', 0x2BA84A, 0xF2C94C], ['BEE', ['BEE'], 'beIN & Arabic sports', 0x6A2C91, 0xC2185B],
        ['EXYU', ['EXYU'], 'Ex-Yugoslavia', 0x1E4FA0, 0xD52B1E], ['AFR', ['AFR'], 'Africa', 0xE2A33B, 0x2E7D32],
        ['CRB', ['CRB'], 'Caribbean', 0x00A3E0, 0xFFD100], ['KU', ['KU'], 'Kurdish', 0xD32F2F, 0x2E7D32],
        ['EU', ['EU'], 'Europe', 0x1F3A93, 0xFFCC00], ['NA', ['NA'], 'North Africa', 0xC62828, 0x1B5E20]];
    var REGION_OF = {}; REGIONS.forEach(function (r) { r[1].forEach(function (c) { REGION_OF[c] = r; }); });
    function iso(cc) { if (REGION_OF[cc]) return null; var c = ISO[cc] || cc; return NAMES[c] ? c : null; }
    function countryName(cc) { var r = REGION_OF[cc]; if (r) return r[2]; var c = iso(cc); return c ? NAMES[c] : cc; }
    function flagSrc(cc) { var c = iso(cc); return c ? 'img/flags/' + c.toLowerCase() + '.png' : ''; }
    function rgba(hex, a) { return 'rgba(' + ((hex >> 16) & 255) + ',' + ((hex >> 8) & 255) + ',' + (hex & 255) + ',' + a + ')'; }
    function fmt(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
    function groups(n) { return n === 1 ? '1 group' : n + ' groups'; }
    function channels(n) { return n === 1 ? '1 channel' : fmt(n) + ' channels'; }
    var LATE = /PPV|VIP|EVENT|24\/7|RAW|PLAY\b|PRIME|MAX|DAZN|ESPN|PACKAGE|NETWORK HULU|REPLAY/;
    var CODE = /^\s*([A-Z0-9]{2,5})\s*\|/;

    // ---------- layout (px, 1920 x 1080; the same sizes as the Apple TV page) ----------
    var X0 = 112, W = 1920 - 2 * X0;
    var P_GAP = 32, P_W = (W - P_GAP) / 2, P_H = 192, P_VGAP = 28;          // pinned banners, 2 per row
    var R_W = 320, R_H = 170, R_GAP = 26;                                    // region cards, one sideways row
    var A_COLS = 4, A_GAP = 22, A_W = Math.floor((W - (A_COLS - 1) * A_GAP) / A_COLS), A_H = 72, A_VGAP = 18;   // country chips
    var TOP = 172, BOTTOM = 1040, MOSAIC = 16;

    var el, page, active = false, built = false;
    var pinned = [], regions = [], all = [], token = 0;
    var sec = 0, idx = [0, 0, 0], shift = 0, rShift = 0, Y = {}, chipWin = '';

    function secLen(s) { return s === 0 ? pinned.length : s === 1 ? regions.length : all.length; }
    function firstSec() { for (var s = 0; s < 3; s++) if (secLen(s)) return s; return -1; }

    // ---------- the directory ----------
    function pinnedEntry(i) {
        var c = Data.COUNTRIES[i], code = c[0].toUpperCase();
        return { i: i, cc: c[0], code: code, name: c[0] === 'all' ? c[1] : countryName(code), flag: c[0] === 'all' ? '' : flagSrc(code),
            colour: COLOUR[iso(code) || ''] || 0x2A3350, groups: null, channels: null, logos: [] };
    }
    // Up to 16 channels for the mosaic, everyday groups first, a channel with a logo before one without (whose tile is
    // the wordmark), one tile per logo. Same pictures as the channel grid: provider icon or the bundled logo map.
    function mosaic(d) {
        var withLogo = [], without = [], seen = {}, order = [];
        for (var g = 0; g < d.g.length; g++) if (!LATE.test(d.g[g])) order.push(g);
        for (var g2 = 0; g2 < d.g.length; g2++) if (LATE.test(d.g[g2])) order.push(g2);
        for (var k = 0; k < order.length && withLogo.length < MOSAIC; k++) {
            var idx2 = d.byGroup[order[k]] || [];
            for (var j = 0; j < idx2.length && withLogo.length < MOSAIC; j++) {
                var c = d.c[idx2[j]], key = c[1] || ('#' + U.cleanName(c[0]).toLowerCase());
                if (seen[key]) continue; seen[key] = 1;
                if (c[1]) withLogo.push(c); else if (without.length < MOSAIC) without.push(c);
            }
        }
        return withLogo.concat(without).slice(0, MOSAIC);
    }
    function fillPinned(e, d, my) {
        if (my !== token) return;
        e.groups = d.g.length;
        e.channels = d.lazy ? null : d.c.length;
        e.logos = mosaic(d);
        if (built) drawPinnedCard(e.i);
    }
    function loadPinned(e, my) {
        Data.liveOf(e.cc, function (d) {
            fillPinned(e, d, my);
            if (!d.lazy) return;
            // another account: the channels of the first everyday groups, for the mosaic
            var left = 0, want = [];
            for (var g = 0; g < d.g.length && want.length < 2; g++) if (!LATE.test(d.g[g])) want.push(g);
            if (!want.length && d.g.length) want.push(0);
            want.forEach(function (gi) { if (!d.loaded[gi]) left++; });
            want.forEach(function (gi) { if (!d.loaded[gi]) Data.loadGroup(d, gi, function () { if (--left === 0) fillPinned(e, d, my); }); });
        });
    }
    function loadDirectory(my) {
        if (U.accounts.type() !== 'x') return;    // a playlist or portal has no country split
        Data.categories('live', function (list) {
            if (my !== token) return;
            var count = {}, pin = {};
            pinned.forEach(function (p) { pin[p.code] = 1; });
            (list || []).forEach(function (c) {
                var m = CODE.exec(c.name || ''); if (!m || /REPLAY/i.test(c.name)) return;
                count[m[1]] = (count[m[1]] || 0) + 1;
            });
            pinned.forEach(function (p) { if (p.groups === null && count[p.code]) p.groups = count[p.code]; });
            regions = [];
            REGIONS.forEach(function (r) {
                var n = 0, code = null;
                r[1].forEach(function (c) { if (count[c]) { n += count[c]; if (!code) code = c; } });
                if (n) regions.push({ code: code, name: r[2], from: r[3], to: r[4], groups: n });
            });
            all = [];
            for (var cc in count) {
                if (REGION_OF[cc] || pin[cc] || cc === 'OTHER') continue;
                all.push({ code: cc, name: countryName(cc), flag: flagSrc(cc), groups: count[cc] });
            }
            all.sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0; });
            build();
        });
    }

    // ---------- drawing ----------
    function flagImg(src, size) {
        return src ? '<img class="lvflag" src="' + src + '" style="width:' + size + 'px;height:' + size + 'px" onerror="this.style.display=\'none\'">' : '';
    }
    var GLOBE = '<svg viewBox="0 0 100 100" fill="none" stroke="#fff" stroke-width="2.4"><circle cx="50" cy="50" r="44"/><ellipse cx="50" cy="50" rx="19" ry="44"/>' +
        '<path d="M6 50h88M12 28h76M12 72h76M50 6v88"/></svg>';
    function pinnedHtml(e) {
        var tiles = '';
        for (var i = 0; i < e.logos.length; i++) {
            var c = e.logos[i], col = i % 8, row = Math.floor(i / 8);
            tiles += '<div class="mt' + (c[4] ? ' light' : '') + '" style="left:' + (4 + col * 106) + 'px;top:' + (26 + row * 74) + 'px">' + U.wordmark(c[0], false) + U.imgTag(c[1]) + '</div>';
        }
        var detail = (e.channels !== null ? channels(e.channels) + ' · ' : '') + (e.groups !== null ? groups(e.groups) : 'Loading');
        return '<div class="mos">' + tiles + '</div>' +
            '<div class="wash" style="background:-webkit-linear-gradient(left,' + rgba(e.colour, .94) + ' 0%,' + rgba(e.colour, .63) + ' 30%,' + rgba(e.colour, 0) + ' 70%);' +
            'background:linear-gradient(90deg,' + rgba(e.colour, .94) + ' 0%,' + rgba(e.colour, .63) + ' 30%,' + rgba(e.colour, 0) + ' 70%)"></div><div class="shd"></div>' +
            (e.flag ? flagImg(e.flag, 61) : '<div class="lvglobe">' + GLOBE + '</div>') +
            '<div class="pd">' + U.esc(detail) + '</div><div class="pn">' + U.esc(e.name) + '</div>';
    }
    function drawPinnedCard(i) { var c = U.$('lvp' + i); if (c) c.innerHTML = pinnedHtml(pinned[i]); }
    function regionHtml(r) {
        return '<div class="rg" style="background:-webkit-linear-gradient(-45deg,' + rgba(r.from, .8) + ',' + rgba(r.to, .67) + ');background:linear-gradient(135deg,' + rgba(r.from, .8) + ',' + rgba(r.to, .67) + ')"></div>' +
            '<div class="glb">' + GLOBE + '</div><div class="rt">' + U.esc(r.name) + '</div><div class="rn">' + groups(r.groups) + '</div>';
    }
    function sectHead(y, title, note) { return '<div class="rowtitle" style="left:' + X0 + 'px;top:' + y + 'px">' + U.esc(title) + '<span>' + U.esc(note) + '</span></div>'; }
    function pinnedPos(i) { return { x: X0 + (i % 2) * (P_W + P_GAP), y: Y.pin + Math.floor(i / 2) * (P_H + P_VGAP), w: P_W, h: P_H }; }
    function regionPos(i) { return { x: X0 + i * (R_W + R_GAP), y: Y.reg, w: R_W, h: R_H }; }
    function chipPos(i) { return { x: X0 + (i % A_COLS) * (A_W + A_GAP), y: Y.all + Math.floor(i / A_COLS) * (A_H + A_VGAP), w: A_W, h: A_H }; }
    function pos(s, i) { return s === 0 ? pinnedPos(i) : s === 1 ? regionPos(i) : chipPos(i); }

    function build() {
        built = true;
        // same title and headings as Films and Series: "Live  N countries" at 166, shelves from 226
        var h = '<div class="pill lvpill" id="lvPill">' + pillHtml() + '</div><div class="rowtitle" style="left:' + X0 + 'px;top:166px">Live<span>' + (pinned.length + all.length) + ' countries</span></div>', y = 226;
        if (pinned.length) {
            h += sectHead(y, 'Pinned', 'your countries · change in Settings'); Y.pin = y + 50;
            y = Y.pin + Math.ceil(pinned.length / 2) * (P_H + P_VGAP) - P_VGAP + 46;
        }
        if (regions.length) {
            h += sectHead(y, 'Regions', String(regions.length)); Y.reg = y + 50;
            y = Y.reg + R_H + 46;
        }
        if (all.length) {
            h += sectHead(y, 'All countries', all.length + ' · A to Z'); Y.all = y + 50;
            y = Y.all + Math.ceil(all.length / A_COLS) * (A_H + A_VGAP) - A_VGAP;
        }
        Y.end = y + 60;
        if (!pinned.length && !regions.length && !all.length) h += '<div class="empty" style="left:' + X0 + 'px;top:300px">Live channels show here once the account has loaded.</div>';
        for (var i = 0; i < pinned.length; i++) {
            var p = pinnedPos(i);
            h += '<div class="lvc pin" id="lvp' + i + '" style="left:' + p.x + 'px;top:' + p.y + 'px;width:' + p.w + 'px;height:' + p.h + 'px">' + pinnedHtml(pinned[i]) + '</div>';
        }
        if (regions.length) {
            h += '<div class="abs t" id="lvRegRow" style="left:0;top:0;width:1920px;height:1px">';
            for (var r = 0; r < regions.length; r++) {
                var q = regionPos(r);
                h += '<div class="lvc reg" id="lvr' + r + '" style="left:' + q.x + 'px;top:' + q.y + 'px;width:' + q.w + 'px;height:' + q.h + 'px">' + regionHtml(regions[r]) + '</div>';
            }
            h += '</div>';
        }
        h += '<div class="abs" id="lvChips" style="left:0;top:0;width:1920px;height:1px"></div>';
        page.innerHTML = h;
        chipWin = '';
        // the focus is kept while a section is still loading (back from the guide redraws the page)
        for (var s = 0; s < 3; s++) if (secLen(s) && idx[s] >= secLen(s)) idx[s] = secLen(s) - 1;
        paint();
    }
    // only the chip rows on screen are in the page
    function drawChips() {
        if (!all.length) return;
        var rowH = A_H + A_VGAP, r0 = Math.max(0, Math.floor((shift - Y.all) / rowH) - 1), r1 = Math.floor((shift + 1080 - Y.all) / rowH) + 1;
        var a = Math.max(0, r0 * A_COLS), b = Math.min(all.length, (r1 + 1) * A_COLS), f = active && !onPill && sec === 2 ? idx[2] : -1, win = a + ':' + b + ':' + f;
        if (win === chipWin) return;
        chipWin = win;
        var h = '';
        for (var i = a; i < b; i++) {
            var e = all[i], p = chipPos(i);
            h += '<div class="lvc chip' + (i === f ? ' focus' : '') + '" style="left:' + p.x + 'px;top:' + p.y + 'px;width:' + p.w + 'px;height:' + p.h + 'px">' +
                (e.flag ? flagImg(e.flag, 38) : '<div class="nof"></div>') + '<div class="cn">' + U.esc(e.name) + '</div><div class="cg">' + groups(e.groups) + '</div></div>';
        }
        U.$('lvChips').innerHTML = h;
    }
    function paint() {
        if (!built) return;
        if (!secLen(sec) && firstSec() >= 0 && active && sec < firstSec()) sec = firstSec();
        var f = active && !onPill && secLen(sec) ? pos(sec, idx[sec]) : null;
        var pl = U.$('lvPill'); if (pl) { pl.className = 'pill lvpill' + (active && onPill ? ' focus' : ''); }
        // vertical: the first pinned row keeps the title in view; otherwise the focused card stays between TOP and BOTTOM
        if (f) {
            if (sec === firstSec() && (sec !== 0 || idx[0] < 2)) shift = 0;
            else {
                if (f.y - shift < TOP + 60) shift = f.y - TOP - 60;
                if (f.y + f.h - shift > BOTTOM) shift = f.y + f.h - BOTTOM;
            }
        }
        shift = Math.max(0, Math.min(shift, Math.max(0, Y.end - 1080)));
        U.setT(page, 0, -shift);
        U.$('lvTop').style.opacity = shift > 40 ? '1' : '0';
        // regions: sideways, the focused card stays on screen
        if (regions.length) {
            if (sec === 1) {
                var q = regionPos(idx[1]);
                if (q.x - rShift < X0) rShift = q.x - X0;
                if (q.x + R_W - rShift > 1920 - X0) rShift = q.x + R_W - (1920 - X0);
                rShift = Math.max(0, rShift);
            }
            U.setT(U.$('lvRegRow'), -rShift, 0);
            for (var r = 0; r < regions.length; r++) U.$('lvr' + r).className = 'lvc reg' + (active && !onPill && sec === 1 && idx[1] === r ? ' focus' : '');
        }
        for (var i = 0; i < pinned.length; i++) U.$('lvp' + i).className = 'lvc pin' + (active && !onPill && sec === 0 && idx[0] === i ? ' focus' : '');
        drawChips();
    }

    // ---------- remote ----------
    function nearest(s, x) {   // the card of section s whose column is nearest to x
        var n = secLen(s), best = 0, bd = 1e9;
        if (s === 1) { for (var i = 0; i < n; i++) { var d = Math.abs(regionPos(i).x - rShift - x); if (d < bd) { bd = d; best = i; } } return best; }
        var cols = s === 0 ? 2 : A_COLS;
        for (var j = 0; j < cols && j < n; j++) { var d2 = Math.abs(pos(s, j).x - x); if (d2 < bd) { bd = d2; best = j; } }
        return best;
    }
    function curX() { var p = pos(sec, idx[sec]); return sec === 1 ? p.x - rShift : p.x; }
    function goSec(s, fromTop) {
        var x = curX();
        sec = s;
        var col = nearest(s, x);
        if (s === 1) idx[1] = col;
        else if (fromTop) idx[s] = col;
        else { var cols = s === 0 ? 2 : A_COLS, last = secLen(s) - 1, rowStart = last - (last % cols); idx[s] = Math.min(last, rowStart + col); }
        paint();
    }
    function nextSec(s, dir) { for (var t = s + dir; t >= 0 && t < 3; t += dir) if (secLen(t)) return t; return -1; }
    function open() {
        if (sec === 0) { openPinned(pinned[idx[0]].i); return; }
        var e = sec === 1 ? regions[idx[1]] : all[idx[2]];
        LiveCountry.open({ cc: e.code.toLowerCase(), name: e.name, pin: -1 });
    }
    function openPinned(i) {
        if (App.tabs) for (var t = 0; t < App.tabs.length; t++) if (App.tabs[t].id === 'guide') { App.goTab(t, true); break; }
        LiveCountry.open({ cc: pinned[i] ? pinned[i].cc : Data.COUNTRIES[i][0], name: pinned[i] ? pinned[i].name : Data.COUNTRIES[i][1], pin: i });
    }
    // ---------- the two views: Categories (this page) or Full list (the guide with a row of countries) ----------
    var VIEW_KEY = 'nx_live_view', onPill = false;
    function view() { try { return localStorage.getItem(VIEW_KEY) === 'full' ? 'full' : 'cat'; } catch (e) { return 'cat'; } }
    function pillHtml() { var v = view(); return '<span' + (v === 'cat' ? ' class="on"' : '') + '>Categories</span><span' + (v === 'full' ? ' class="on"' : '') + '>Full list</span>'; }
    function setView(v) {
        try { localStorage.setItem(VIEW_KEY, v); } catch (e) { /* storage blocked */ }
        onPill = v === 'cat';
        if (App.tabs) for (var t = 0; t < App.tabs.length; t++) if (App.tabs[t].id === 'guide') { App.goTab(t, true); break; }
        var pl = U.$('lvPill'); if (pl) pl.innerHTML = pillHtml();
    }
    // the countries of the full list: pinned first, then every other country of the source A to Z, then the regions
    function fullList(cb) {
        var out = [], pin = {};
        for (var i = 0; i < Data.COUNTRIES.length; i++) { var c = Data.COUNTRIES[i]; out.push([c[0], c[0] === 'all' ? c[1] : countryName(c[0].toUpperCase())]); pin[c[0].toUpperCase()] = 1; }
        if (U.accounts.type() !== 'x') { cb(out); return; }
        Data.categories('live', function (list) {
            var seen = {}, more = [], regs = [];
            (list || []).forEach(function (x) {
                var m = CODE.exec(x.name || ''); if (!m || /REPLAY/i.test(x.name) || pin[m[1]] || seen[m[1]] || m[1] === 'OTHER') return;
                seen[m[1]] = 1; (REGION_OF[m[1]] ? regs : more).push([m[1].toLowerCase(), countryName(m[1])]);
            });
            more.sort(function (a, b) { return a[1].toLowerCase() < b[1].toLowerCase() ? -1 : a[1].toLowerCase() > b[1].toLowerCase() ? 1 : 0; });
            cb(out.concat(more, regs));
        });
    }
    function key(c) {
        if (onPill) {
            if (c === 40) { onPill = false; paint(); }
            else if (c === 38) { onPill = false; paint(); return 'up'; }
            else if (c === 13 || c === 37 || c === 39) setView(view() === 'cat' ? 'full' : 'cat');
            return true;
        }
        if (!secLen(sec) && firstSec() >= 0) sec = firstSec();
        var n = secLen(sec);
        if (!n) { if (c === 38) { onPill = true; paint(); } return true; }
        var cols = sec === 0 ? 2 : sec === 1 ? n : A_COLS, i = idx[sec];
        if (c === 13) { open(); return true; }
        if (c === 37) { if (i % cols > 0 || (sec === 1 && i > 0)) { idx[sec]--; paint(); } return true; }
        if (c === 39) { if ((sec === 1 || i % cols < cols - 1) && i < n - 1) { idx[sec]++; paint(); } return true; }
        if (c === 38) {
            if (sec !== 1 && i - cols >= 0) { idx[sec] -= cols; paint(); return true; }
            var up = nextSec(sec, -1);
            if (up < 0) { onPill = true; paint(); return true; }   // the view pill, then the menu
            goSec(up, false); return true;
        }
        if (c === 40) {
            if (sec !== 1 && i + cols < n) { idx[sec] += cols; paint(); return true; }
            if (sec !== 1 && Math.floor(i / cols) < Math.floor((n - 1) / cols)) { idx[sec] = n - 1; paint(); return true; }   // a short last row
            var down = nextSec(sec, 1);
            if (down >= 0) goSec(down, true);
            return true;
        }
        if ((c === 427 || c === 428) && sec === 2) {   // CH +/-: a page of countries
            idx[2] = Math.max(0, Math.min(n - 1, i + (c === 428 ? 1 : -1) * A_COLS * 8)); paint(); return true;
        }
        return true;
    }

    function show() {
        token++;
        var my = token;
        pinned = []; regions = []; all = [];
        for (var i = 0; i < Data.COUNTRIES.length; i++) pinned.push(pinnedEntry(i));
        build();
        pinned.forEach(function (e) { loadPinned(e, my); });
        loadDirectory(my);
    }
    function init() {
        el = U.$('live');
        el.innerHTML = '<div class="page t" id="lvPage"></div>' +
            '<div class="abs" id="lvTop" style="left:0;top:0;width:1920px;height:160px;opacity:0;z-index:10;-webkit-transform:translateZ(0);transform:translateZ(0);' +
            'background:-webkit-linear-gradient(top,#000 78%,rgba(0,0,0,0));background:linear-gradient(180deg,#000 78%,rgba(0,0,0,0))"></div>';
        page = U.$('lvPage');
    }
    return {
        init: init, key: key, show: show, openPinned: openPinned, view: view, setView: setView, fullList: fullList,
        focus: function () { active = true; if (!secLen(sec) && firstSec() >= 0) sec = firstSec(); paint(); },
        blur: function () { active = false; paint(); },
        refresh: function () { paint(); }
    };
})();
