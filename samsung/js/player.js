// Full-screen player on Samsung's native AVPlay (the web <video> on Tizen 3 buffers these streams forever).
// Films and episodes get a control bar: back 10 s, play/pause, forward 10 s, "Audio <language>", "Subtitles <language>",
// and for episodes "Episodes n of m" (focus slides the episode strip up) plus "Next episode" once the credits cue is reached.
// Live channels zap with up/down and keep their own bar.
var Player = (function () {
    'use strict';
    var cur = null, infoT = null, tick = null, el, info, busy, subEl, panel, onExit = null;
    var ctl = false, btn = 1, menu = null, mSel = 0, seekAcc = 0, seekT = null;
    // Timeline scrubbing, Apple style: Left/Right move a marker on the bar (faster when held), OK or a pause jumps there.
    var onBar = false, scrub = null, scrubT = null, lastPress = 0, streak = 0;
    // Episode strip (rule 3): open while the Episodes button has the focus, entered with Down.
    var strip = { dis: false, inside: false, sel: 0 };
    // Session memory across the episodes played in a row (rules 4 and 6).
    var sess = { lastKey: Date.now(), autoplays: 0, chainOk: null, quick: 0 };

    function av() { return window.webapis && webapis.avplay; }
    function vod() { return cur && cur.k !== 'live'; }
    function playing() { try { return webapis.avplay.getState() === 'PLAYING'; } catch (e) { return false; } }

    // ---------- control bar: round buttons and labelled pills ----------
    function svg(d, z) { z = z || 30; return '<svg width="' + z + '" height="' + z + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + d + '</svg>'; }
    var PATH = {
        play: '<path d="M7 4.5v15l12-7.5z" fill="currentColor" stroke="none"/>',
        pause: '<rect x="6" y="4.5" width="4" height="15" rx="1" fill="currentColor" stroke="none"/><rect x="14" y="4.5" width="4" height="15" rx="1" fill="currentColor" stroke="none"/>',
        back10: '<path d="M4 12a8 8 0 1 0 2.3-5.6"/><path d="M4 4v4h4"/><text x="12" y="15.5" font-size="7.5" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="Arial">10</text>',
        fwd10: '<path d="M20 12a8 8 0 1 1-2.3-5.6"/><path d="M20 4v4h-4"/><text x="12" y="15.5" font-size="7.5" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="Arial">10</text>',
        audio: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor" stroke="none"/><path d="M15.5 9a4 4 0 0 1 0 6"/><path d="M18 6.5a7.5 7.5 0 0 1 0 11"/>',
        subs: '<rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="M10.5 10.3a2.2 2.2 0 1 0 0 3.4"/><path d="M17 10.3a2.2 2.2 0 1 0 0 3.4"/>',
        eps: '<path d="M4 6h2M4 12h2M4 18h2"/><path d="M9.5 6H20M9.5 12H20M9.5 18H20"/>',
        next: '<path d="M5 5v14l10-7z" fill="currentColor" stroke="none"/><rect x="16.5" y="5" width="2.6" height="14" rx="1" fill="currentColor" stroke="none"/>'
    };
    var ICON = { play: svg(PATH.play), pause: svg(PATH.pause), back10: svg(PATH.back10), fwd10: svg(PATH.fwd10) };
    function pillHtml(path, word, second) { return '<span class="pi">' + svg(PATH[path], 26) + '</span><b>' + word + '</b>' + (second ? '<em>' + U.esc(second) + '</em>' : ''); }
    // current choice of a track kind, for the second word of its pill
    function currentName(kind) {
        if (kind === 'subs') {
            if (cur.ext && cur.ext.r) return langName(cur.ext.r.lang) + ' \u00b7 synced';
            if (!cur.subsOn) return 'Off';
            var ti = current('TEXT'), tl = tracks('TEXT');
            for (var i = 0; i < tl.length; i++) if (tl[i].index === ti) return tl[i].name;
            return 'On';
        }
        var ai = current('AUDIO'), al = tracks('AUDIO');
        for (var j = 0; j < al.length; j++) if (al[j].index === ai) return al[j].name;
        return al.length ? al[0].name : '';
    }
    function epNow() {
        var c = cur && cur.epctx; if (!c) return null;
        var list = c.eps[c.seasons[c.s]] || [];
        return { list: list, e: list[c.e], n: c.e + 1, m: list.length };
    }
    function buttons() {
        var b = [{ id: 'back10', html: ICON.back10 }, { id: 'play', html: playing() ? ICON.pause : ICON.play }, { id: 'fwd10', html: ICON.fwd10 },
            { id: 'audio', pill: 1, html: pillHtml('audio', 'Audio', currentName('audio')) }, { id: 'subs', pill: 1, html: pillHtml('subs', 'Subtitles', currentName('subs')) }];
        var en = epNow();
        if (en) {
            if (cur.cue && cur.next) b.push({ id: 'next', pill: 1, right: 1, html: '<b>Next episode</b><span class="pi r">' + svg(PATH.next, 22) + '</span>' });
            b.push({ id: 'eps', pill: 1, right: 1, html: pillHtml('eps', 'Episodes', en.n + ' of ' + en.m) });
        }
        return b;
    }
    var btnPos = {};   // id -> left edge, so a popup can sit above its button
    function drawBar() {
        var bar = el.querySelector('.ctl');
        if (!vod()) { bar.innerHTML = ''; return; }
        var b = buttons(), h = '';
        for (var i = 0; i < b.length; i++)
            h += '<div class="pbtn ' + (b[i].pill ? 'lab' : 'rd') + (ctl && !menu && !onBar && !strip.inside && i === btn ? ' focus' : '') + '" id="pb' + i + '">' + b[i].html + '</div>';
        bar.innerHTML = h;
        var px = 112, rx = 1808;
        for (var j = 0; j < b.length; j++) if (!b[j].right) { var e = U.$('pb' + j); e.style.left = px + 'px'; btnPos[b[j].id] = px; px += e.offsetWidth + 14; }
        for (var k = b.length - 1; k >= 0; k--) if (b[k].right) { var f = U.$('pb' + k); rx -= f.offsetWidth; f.style.left = rx + 'px'; btnPos[b[k].id] = rx; rx -= 14; }
    }
    function btnId() { var b = buttons(); return b[btn] ? b[btn].id : ''; }
    var tuning = false;   // the bar is the loading state too: same name, logo and line, over black, until the picture plays
    function stripShown() { return !!(vod() && cur && cur.epctx && ctl && !menu && !onBar && btnId() === 'eps' && !strip.dis); }
    function setInfo(show, keep) {
        info.className = 'info' + (show ? ' show' : '') + (cur && cur.k === 'live' ? ' live' : ' vod') + (tuning ? ' tuning' : '') + (show && stripShown() ? ' strip' : '');
        clearTimeout(infoT);
        if (!show) { ctl = false; onBar = false; strip.inside = false; strip.dis = false; closeMenu(); }
        drawBar(); drawStrip();
        if (show && !keep && !menu && !stripShown()) infoT = setTimeout(function () { if (!menu && !stripShown()) setInfo(false); }, ctl ? 7000 : 4000);
    }
    function runtimeMin(e) { var m = e && e.info ? (e.info.duration_secs ? e.info.duration_secs / 60 : 0) : 0; return m ? Math.round(m) : 0; }
    function cleanEpTitle(t) { return t ? String(t).replace(/^.*?-\s*S\d+E\d+\s*-?\s*/i, '') : ''; }
    function render() {
        var en = epNow();
        if (en && en.e) {
            var c = cur.epctx;
            info.querySelector('.pk').textContent = (cur.epctx.ser.name || '') + ' \u00b7 Season ' + c.seasons[c.s];
            info.querySelector('.pt').textContent = 'E' + (en.e.episode_num || en.n) + ' \u00b7 ' + (cleanEpTitle(en.e.title) || cur.sub || '');
            info.querySelector('.ps').innerHTML = '<span class="tune"></span>';
        } else {
            info.querySelector('.pk').textContent = '';
            info.querySelector('.pt').textContent = cur.name || '';
            info.querySelector('.ps').innerHTML = (cur.k === 'live' ? '<span class="pill live">LIVE</span>&nbsp; ' : '') + U.esc(cur.sub || '') + '<span class="tune"></span>';
        }
        var logo = cur.k === 'live' ? U.logoFor(cur.name, cur.img || '') : '';
        info.querySelector('.pl').innerHTML = logo ? '<img src="' + U.esc(U.img(logo)) + '" onerror="this.parentNode.innerHTML=\'\'">' : '';
        info.querySelector('.prog').style.display = vod() ? 'block' : 'none';
        info.querySelector('.time').textContent = ''; info.querySelector('.tcur').textContent = '';
        info.querySelector('.prog i').style.width = '0';
        subEl.textContent = '';
    }
    function progress() {
        if (!vod() || !av()) return;
        var p = 0, d = 0;
        try { p = webapis.avplay.getCurrentTime(); d = webapis.avplay.getDuration(); } catch (e) { return; }
        if (seekAcc) p = Math.max(0, Math.min(d, p + seekAcc));
        if (!seekAcc && p > 0) { cur.pos = p; if (d > 0) cur.dur = d; }
        if (!seekAcc && p > 0) cueCheck(p, d);
        if (cur.resumeItem && p > 0 && Date.now() - (cur.saved || 0) > 15000) { cur.saved = Date.now(); U.setResume(cur.resumeItem, cur.pos, cur.dur || 0); }
        var thumb = info.querySelector('.prog b'), lab = info.querySelector('.scrubt');
        if (d > 0 && scrub !== null) {
            var f = scrub / d;
            thumb.style.display = 'block'; thumb.style.left = (100 * f).toFixed(2) + '%';
            var cx = Math.max(112, Math.min(1808 - 360, Math.round(112 + f * 1696 - 180)));
            lab.style.display = 'block'; U.setT(lab, cx, 0);
            var delta = scrub - p;
            lab.querySelector('.st').textContent = U.fmtTime(scrub);
            lab.querySelector('.sd').textContent = (delta >= 0 ? '+' : '\u2212') + U.fmtTime(Math.abs(delta));
        } else { thumb.style.display = onBar && d > 0 ? 'block' : 'none'; if (d > 0) thumb.style.left = (100 * p / d).toFixed(2) + '%'; lab.style.display = 'none'; }
        info.querySelector('.prog').className = 'prog' + (onBar ? ' focus' : '');
        info.className = info.className.replace(/ scrubbing/g, '') + (scrub !== null ? ' scrubbing' : '');
        drawBar();
        if (d > 0) {
            info.querySelector('.prog i').style.width = (100 * p / d).toFixed(2) + '%';
            var shown = scrub !== null ? scrub : p;
            info.querySelector('.tcur').textContent = U.fmtTime(shown);
            info.querySelector('.time').textContent = '\u2212' + U.fmtTime(Math.max(0, d - shown)) + (seekAcc ? '   (' + (seekAcc > 0 ? '+' : '-') + Math.abs(seekAcc / 1000) + ' s)' : '');
            if (!seekAcc) { cur.pos = p; cur.dur = d; }
        }
    }

    // ---------- audio and subtitle tracks ----------
    // Language: the file's tag (2 or 3 letters), else for subtitles the language named in the track title.
    // A discriminator is added only when the track title says what it is (Descriptive, Commentary, Original, SDH, Forced);
    // channels and codec ride on the right of the popup row, so two tracks of one language never read "English 1 / English 2".
    var LG = [['en', 'English', 'gb', 'eng'], ['fr', 'French', 'fr', 'fre fra'], ['nl', 'Dutch', 'nl', 'dut nld'], ['de', 'German', 'de', 'ger deu'], ['es', 'Spanish', 'es', 'spa'],
        ['it', 'Italian', 'it', 'ita'], ['pt', 'Portuguese', 'pt', 'por'], ['tr', 'Turkish', 'tr', 'tur'], ['ar', 'Arabic', 'sa', 'ara'], ['ru', 'Russian', 'ru', 'rus'], ['pl', 'Polish', 'pl', 'pol'],
        ['sv', 'Swedish', 'se', 'swe'], ['da', 'Danish', 'dk', 'dan'], ['no', 'Norwegian', 'no', 'nor nob nno nb nn'], ['fi', 'Finnish', 'fi', 'fin'], ['el', 'Greek', 'gr', 'gre ell'],
        ['cs', 'Czech', 'cz', 'cze ces'], ['hu', 'Hungarian', 'hu', 'hun'], ['ro', 'Romanian', 'ro', 'rum ron'], ['zh', 'Chinese', 'cn', 'chi zho cmn yue'], ['ko', 'Korean', 'kr', 'kor'],
        ['hi', 'Hindi', 'in', 'hin'], ['th', 'Thai', 'th', 'tha'], ['vi', 'Vietnamese', 'vn', 'vie'], ['id', 'Indonesian', 'id', 'ind'], ['he', 'Hebrew', 'il', 'heb iw'],
        ['uk', 'Ukrainian', 'ua', 'ukr'], ['ja', 'Japanese', 'jp', 'jpn']];
    var LGM = {};
    (function () { for (var i = 0; i < LG.length; i++) { var r = { name: LG[i][1], cc: LG[i][2] }; LGM[LG[i][0]] = r; var a = LG[i][3].split(' '); for (var j = 0; j < a.length; j++) LGM[a[j]] = r; } })();
    function langInfo(l) { l = String(l || '').toLowerCase().replace(/[-_].*$/, ''); return l && l !== 'und' && l !== 'unk' ? (LGM[l] || null) : null; }
    function langName(l) { var r = langInfo(l); l = String(l || '').toLowerCase(); return r ? r.name : (l && l !== 'und' ? l.toUpperCase() : ''); }
    function langFromTitle(t) { t = String(t || ''); for (var i = 0; i < LG.length; i++) if (new RegExp('\\b' + LG[i][1] + '\\b', 'i').test(t)) return LGM[LG[i][0]]; return null; }
    function kwOf(t) {
        t = String(t || '').toLowerCase();
        if (/descri|\baudio desc|\bad\b/.test(t)) return 'Descriptive';
        if (/commentar/.test(t)) return 'Commentary';
        if (/sdh|hearing|\bhi\b|\bcc\b/.test(t)) return 'SDH';
        if (/forced|signs/.test(t)) return 'Forced';
        if (/original|\bvo\b|v\.o\./.test(t)) return 'Original';
        return '';
    }
    function chText(x) {
        var n = parseInt(x.channels || x.channel || x.channel_num || x.num_channels || x.ch || 0, 10);
        return n === 1 ? 'mono' : n === 2 ? 'stereo' : n === 6 ? '5.1' : n === 8 ? '7.1' : n > 2 ? n + ' ch' : '';
    }
    var tcache = {};
    function tracks(type) {
        if (tcache[type] && tcache[type].length) return tcache[type];
        var out = [];
        try {
            var all = webapis.avplay.getTotalTrackInfo();
            for (var i = 0; i < all.length; i++) {
                if (all[i].type !== type) continue;
                var x = {}; try { x = JSON.parse(all[i].extra_info || '{}'); } catch (e) { /* plain text */ }
                var tag = x.language || x.track_lang || '', title = x.track_title || x.title || x.name || x.handler_name || x.label || '';
                var codec = String(x.fourCC || x.codec || x.codec_name || '').replace(/\s+$/, '').toUpperCase();
                var li = langInfo(tag) || (type === 'TEXT' ? langFromTitle(title) : null), kw = kwOf(title), pos = out.length;
                var label = li ? li.name + (kw ? ' · ' + kw : '') : 'Track ' + (pos + 1) + ' · unknown language';
                var detail = type === 'AUDIO' ? [chText(x), codec].filter(function (v) { return v; }).join(' · ') : (kw === 'Forced' ? 'signs only' : kw === 'SDH' ? 'hearing impaired' : '');
                out.push({ index: all[i].index, label: label, name: label, cc: li ? li.cc : '', detail: detail, codec: codec, pos: pos, extra: x });
            }
        } catch (e) { U.log({ ev: 'tracks.error', err: String(e && (e.name || e.message) || e) }); }
        if (out.length) tcache[type] = out;
        return out;
    }
    function current(type) { try { var c = webapis.avplay.getCurrentStreamInfo(); for (var i = 0; i < c.length; i++) if (c[i].type === type) return Number(c[i].index); } catch (e) { /* none */ } return -1; }
    function shortRel(n) {
        var a = /(WEB-?DL|WEB-?Rip|Blu-?Ray|BDRip|BRRip|HDTV|DVDRip|AMZN|NF|DSNP)/i.exec(n || ''), b = /(2160p|1080p|720p|480p)/i.exec(n || '');
        return (a ? a[1].replace(/webdl/i, 'WEB-DL') : '') + (a && b ? ' ' : '') + (b ? b[1].toLowerCase() : '');
    }
    function subsRows() {
        var l = menu.base.slice();
        if (menu.onl && menu.onl.length) l = l.concat([{ sect: 'ONLINE · OPENSUBTITLES' }], menu.onl);
        if (cur.ext) l.push({ timing: true });
        menu.list = l;
    }
    function openMenu(kind) {
        var raw = tracks(kind === 'audio' ? 'AUDIO' : 'TEXT'), list = raw.slice();
        var online = kind === 'subs' && vod() && cur.osub && Subs.ready();
        if (kind === 'subs') list.unshift({ index: -1, label: 'Off', off: true });
        if (!list.length || (kind === 'audio' && list.length < 2 && !list[0]) || (kind === 'subs' && list.length < 2 && !online && !cur.ext)) { U.toast(kind === 'audio' ? 'Only one audio track' : 'No subtitles in this file'); return; }
        var on = kind === 'audio' ? current('AUDIO') : (cur.ext ? cur.ext.idx : cur.subsOn ? current('TEXT') : -1);
        menu = { kind: kind, base: list, list: list, onl: online ? [{ index: -2, label: 'Searching online…', wait: true }] : [] };
        if (kind === 'subs') subsRows();
        if (online) {
            var it = cur;
            cur.osub.fps = videoFps(); cur.osub.url = cur.url;
            Subs.search(cur.osub, SUB_LANGS, function (e, res) {
                if (cur !== it || !menu || menu.kind !== 'subs') return;
                var o = [];
                if (e) o.push({ index: -2, label: 'Online search failed', wait: true });
                else if (!res.length) o.push({ index: -2, label: 'Nothing online', wait: true });
                res.forEach(function (r, i) {
                    var match = cur.osub.fps && r.fps && Math.abs(r.fps - cur.osub.fps) < 0.05, li = langInfo(r.lang), rel = shortRel(r.name);
                    o.push({ index: -10 - i, online: r, cc: li ? li.cc : '', label: langName(r.lang) + (r.hi ? ' · SDH' : '') + (rel ? ' · ' + rel : ''), detail: r.exact ? 'exact file' : match ? 'same frame rate' : '' });
                });
                menu.onl = o; subsRows();
                if (mSel >= menu.list.length) mSel = menu.list.length - 1;
                drawMenu();
                U.log({ ev: 'subs.online', n: res.length, err: e ? e.message : null });
            });
        }
        mSel = 0; mTop = 0; tSel = 1; for (var i = 0; i < menu.list.length; i++) if (menu.list[i].index === on && !menu.list[i].wait && !menu.list[i].online) mSel = i;
        drawMenu(); setInfo(true, true);
        U.log({ ev: 'tracks', kind: kind, labels: menu.list.map(function (t) { return (t.label || t.sect || 'timing') + '#' + t.index; }), on: on, item: cur && cur.resumeItem ? cur.resumeItem.k + ':' + cur.resumeItem.id : null });
    }
    var tSel = 1;   // chip of the TIMING row: 0 Earlier, 1 Auto, 2 Later
    function nextSel(d) { var i = mSel + d; while (i >= 0 && i < menu.list.length && menu.list[i].sect) i += d; if (i >= 0 && i < menu.list.length) mSel = i; }
    function flagHtml(cc) { return cc ? '<img class="fl" src="img/flags/' + cc + '.png" alt="">' : '<span class="fl none"></span>'; }
    var mTop = 0, MAXROWS = 8;
    function drawMenu() {
        if (!menu) { panel.className = 'tpanel'; panel.innerHTML = ''; return; }
        var on = menu.kind === 'audio' ? current('AUDIO') : (cur.subsOn ? current('TEXT') : -1), parts = [];
        for (var i = 0; i < menu.list.length; i++) {
            var t = menu.list[i];
            if (t.sect) { parts.push('<div class="tps">' + U.esc(t.sect) + '</div>'); continue; }
            if (t.timing) {
                var h2 = '<div class="tps">TIMING' + (cur.ext ? ' · now ' + fmtOff(cur.ext.off) : '') + '</div><div class="tch' + (i === mSel ? ' focus' : '') + '">', cn = ['Earlier −0.5 s', 'Auto', 'Later +0.5 s'];
                for (var c = 0; c < 3; c++) h2 += '<span class="' + (i === mSel && c === tSel ? 'on' : '') + '">' + cn[c] + '</span>';
                parts.push(h2 + '</div>'); continue;
            }
            parts.push('<div class="tpi' + (i === mSel ? ' focus' : '') + (t.wait ? ' wait' : '') + '">' + (t.off || t.wait ? '' : flagHtml(t.cc)) + '<span class="tn">' + U.esc(t.label) + (t.index === on && !t.wait ? ' &nbsp;&#10003;' : '') + '</span>' + (t.detail ? '<span class="td">' + U.esc(t.detail) + '</span>' : '') + '</div>');
        }
        // a long list shows a window of rows that follows the focus
        if (mSel < mTop) mTop = mSel; if (mSel >= mTop + MAXROWS) mTop = mSel - MAXROWS + 1;
        if (mTop > Math.max(0, parts.length - MAXROWS)) mTop = Math.max(0, parts.length - MAXROWS);
        panel.innerHTML = '<div class="tph">' + (menu.kind === 'audio' ? 'Audio' : 'Subtitles') + '</div>' + parts.slice(mTop, mTop + MAXROWS).join('');
        panel.className = 'tpanel show ' + menu.kind;
        var w = menu.kind === 'audio' ? 560 : 640, lx = btnPos[menu.kind] || 112;
        panel.style.left = Math.max(40, Math.min(1920 - w - 40, lx)) + 'px';
    }
    // Some files refuse an audio change while playing. Try it live, then paused, then reopen at the
    // same second and choose the track while the stream is READY (before play).
    // ---------- online subtitles (OpenSubtitles): shown on our own line, timed from the player clock ----------
    var SUB_LANGS = ['fr', 'en'], extT = null;
    function videoFps() {
        try { var c = webapis.avplay.getCurrentStreamInfo(); for (var i = 0; i < c.length; i++) if (c[i].type === 'VIDEO') { var x = JSON.parse(c[i].extra_info || '{}'); var f = +x.fps || 0; if (f > 1000) f = f / 1000; return f; } } catch (e) { /* unknown */ }
        return 0;
    }
    function fmtOff(o) { return (o > 0 ? '+' : o < 0 ? '\u2212' : '') + (Math.abs(o) / 1000).toFixed(1) + ' s'; }
    function loadOff(f) { try { return (JSON.parse(localStorage.getItem('nx_suboff') || '{}')[f]) || 0; } catch (e) { return 0; } }
    function saveOff(f, o) { try { var m = JSON.parse(localStorage.getItem('nx_suboff') || '{}'); m[f] = o; localStorage.setItem('nx_suboff', JSON.stringify(m)); } catch (e) { /* full */ } }
    function extOff(keepRef) { clearInterval(extT); extT = null; if (!keepRef && cur && cur.ext && cur.ext.ref) { try { webapis.avplay.setSilentSubtitle(true); } catch (e) { /* none */ } } if (cur) cur.ext = null; }
    // Auto sync: the file's own subtitle track (hidden) gives the real speech times. Each new cue start is matched to the
    // online cues around it; the offset most starts agree on wins. A sliding window keeps following a slow drift.
    function startAlign() {
        var emb = tracks('TEXT'); if (!emb.length || !cur.ext) return;
        var ref = emb[0]; for (var i = 0; i < emb.length; i++) if (/^en/.test(String(emb[i].extra.language || emb[i].extra.track_lang || ''))) { ref = emb[i]; break; }
        cur.ext.ref = { starts: [], last: '', n: 0, index: ref.index };
        afterPlay(cur, function () { webapis.avplay.setSelectTrack('TEXT', ref.index); webapis.avplay.setSilentSubtitle(false); }, null);
        U.log({ ev: 'subs.align.start', ref: ref.label });
    }
    // The TV reports a subtitle line a little before or after it is shown. That lead is measured on files whose
    // index was read (exact start times): the median gap between the reported time and the nearest real start.
    // It is kept across sessions and taken off the live path, which has only the reported times.
    function loadBias() { try { var b = JSON.parse(localStorage.getItem('nx_subbias') || 'null'); return b && b.n >= 6 ? b.ms : 0; } catch (e) { return 0; } }
    function calibrate(t) {
        var starts = window.SubSync ? SubSync.cached(SubSync.keyOf(cur)) : null;
        if (!starts || !starts.length) return;
        var lo = 0, hi = starts.length - 1;
        while (lo < hi) { var m = (lo + hi) >> 1; if (starts[m] < t - 3000) lo = m + 1; else hi = m; }
        var best = null;
        for (var j = Math.max(0, lo - 1); j < starts.length && starts[j] <= t + 3000; j++) { var d = t - starts[j]; if (best === null || Math.abs(d) < Math.abs(best)) best = d; }
        if (best === null || Math.abs(best) > 3000) return;
        try {
            var b = JSON.parse(localStorage.getItem('nx_subbias') || 'null') || { d: [], n: 0, ms: 0 };
            b.d.push(Math.round(best)); if (b.d.length > 60) b.d.shift();
            var sorted = b.d.slice().sort(function (x, y) { return x - y; });
            b.n = sorted.length; b.ms = sorted[sorted.length >> 1];
            localStorage.setItem('nx_subbias', JSON.stringify(b));
            if (b.n <= 3 || b.n % 10 === 0) U.log({ ev: 'subs.bias', n: b.n, ms: b.ms, last: Math.round(best) });
        } catch (e) { /* storage full */ }
    }
    function refCue(text) {
        var R = cur.ext.ref, t = 0;
        if (!text) { R.last = ''; return; }
        if (text === R.last) return; R.last = text;
        try { t = webapis.avplay.getCurrentTime(); } catch (e) { return; }
        calibrate(t);
        R.starts.push(t); if (R.starts.length > 40) R.starts.shift();
        if (R.n < 3 || R.n % 10 === 0) U.log({ ev: 'subs.ref', n: R.n + 1, at: t });
        if (++R.n % 4 === 0 && R.starts.length >= 6 && !cur.ext.fromIndex) align();
    }
    function align() {
        var E = cur.ext;
        // the TV did not say the video's frame rate: also try the usual 25 versus 23.976 rescales, keep the best
        if (!E.kFixed && E.r && E.r.fps && !videoFps()) {
            var ks = [1, 23.976 / 25, 25 / 23.976], bestK = E.k, bestS = -1;
            for (var q = 0; q < ks.length; q++) { E.k = ks[q]; var sc = alignScore(E).score; if (sc > bestS) { bestS = sc; bestK = ks[q]; } }
            E.k = bestK;
        }
        var res = alignScore(E), best = res.best, score = res.score, st = E.ref.starts;
        if (st.length >= 10 && score >= st.length * 0.4) E.kFixed = true;
        alignUse(E, best, score, st);
    }
    function alignScore(E) {
        var cues = E.cues, st = E.ref.starts, best = 0, score = 0, bins = {}, bias = loadBias();
        for (var i = 0; i < st.length; i++) {
            var te = (st[i] - bias) * E.k, lo = 0, hi = cues.length - 1;
            while (lo < hi) { var m = (lo + hi) >> 1; if (cues[m].a < te - 20000) lo = m + 1; else hi = m; }
            for (var j = lo; j < cues.length && cues[j].a <= te + 20000; j++) { var b = Math.round((te - cues[j].a) / 100); bins[b] = (bins[b] || 0) + 1; }
        }
        for (var key in bins) { var c = (bins[key - 2] || 0) + (bins[key - 1] || 0) + bins[key] + (bins[+key + 1] || 0) + (bins[+key + 2] || 0); if (c > score) { score = c; best = +key * 100; } }
        return { best: best, score: score };
    }
    function alignUse(E, best, score, st) {
        var ok = st.length >= 10 && score >= st.length * 0.4;
        if (ok) { E.off = best; E.auto = best; saveOff(E.file, best); }
        U.log({ ev: 'subs.align', off: best, score: score, n: st.length, used: ok, k: E.k, bias: loadBias(), file: E.file });
        // after a minute of dialogue with no agreement, this file is timed for another cut: try the next one
        if (!ok && st.length >= 16 && E.alts.length) {
            var nx = E.alts.shift(); nx.alts = E.alts; cur.ext0 = { ref: E.ref }; E.ref.starts = E.ref.starts.slice();
            U.log({ ev: 'subs.align.switch', to: nx.file, name: nx.name }); useOnline(nx, E.idx);
        }
    }
    // the online cue for the player clock; the offset is a constant per file, so a seek keeps it
    function extDraw(at) {
        if (!cur || !cur.ext) return;
        var t = at; if (t == null) { try { t = webapis.avplay.getCurrentTime(); } catch (e) { return; } }
        var x = Subs.at(cur.ext.cues, t * cur.ext.k - cur.ext.off);
        if (subEl.getAttribute('data-x') !== x) { subEl.setAttribute('data-x', x); subEl.innerHTML = U.esc(x).replace(/\n/g, '<br>'); }
    }
    function useOnline(r, idx) {
        var it = cur; U.toast('Loading subtitles\u2026');
        Subs.download(r.file, function (e, cues, left) {
            if (cur !== it) return;
            if (e || !cues || !cues.length) { U.toast('Could not load these subtitles (' + (e ? e.message : 'empty') + ')'); U.log({ ev: 'subs.dl.error', err: e ? e.message : 'empty' }); return; }
            if (!cur.ext0) { try { webapis.avplay.setSilentSubtitle(true); } catch (e2) { /* none */ } }
            cur.subsOn = false; extOff(!!cur.ext0);
            // a subtitle made for another frame rate drifts: rescale the clock (e.g. a 23.976 file against a 25 PAL copy)
            var vf = videoFps(), k = 1;
            if (vf && r.fps && Math.abs(vf - r.fps) > 0.05 && Math.abs(vf / r.fps - 1) < 0.06) k = vf / r.fps;
            var keepRef = cur.ext0 && cur.ext0.ref;
            cur.ext = { cues: cues, idx: idx, file: r.file, off: loadOff(r.file), k: k, r: r, alts: r.alts || [] };
            if (keepRef) { cur.ext.ref = keepRef; cur.ext0 = null; }
            extT = setInterval(function () { extDraw(); }, 200);
            // aligned at once from the file's own index when it was read before playback; else live, as cues play
            var refStarts = !r.exact && window.SubSync ? SubSync.cached(SubSync.keyOf(cur)) : null;
            if (refStarts && refStarts.length) {
                var ks = k !== 1 || (vf && r.fps) ? [k] : [1, 23.976 / 25, 25 / 23.976];
                var v = SubSync.vote(refStarts, cues, ks);
                U.log({ ev: 'subs.align', src: 'index', off: v.off, k: v.k, score: v.score, n: v.n, used: v.ok, file: r.file });
                if (v.ok) { cur.ext.off = v.off; cur.ext.auto = v.off; cur.ext.k = v.k; cur.ext.kFixed = true; cur.ext.fromIndex = true; saveOff(r.file, v.off); extDraw(); if (!cur.ext.ref) startAlign(); }   // the reference still listens, to measure the TV's report lead
                else if (!cur.ext.ref) startAlign();
            } else if (!r.exact && !cur.ext.ref) startAlign();
            U.toast(langName(r.lang) + ' subtitles on' + (left != null ? ' \u00b7 ' + left + ' downloads left today' : ''));
            U.log({ ev: 'subs.dl', n: cues.length, left: left, vfps: vf, sfps: r.fps, k: k });
        });
    }
    function closeMenu() { menu = null; if (panel) { panel.className = 'tpanel'; panel.innerHTML = ''; } }
    var audioFail = '';
    // Runs fn once playback runs: tries at 1.2 s, then 3 s. onFail gets the last error.
    function afterPlay(item, fn, onFail) {
        var tries = [1200, 1800, 3000, 5000];   // the TV accepts an audio change only once playback has settled (about 3 s on MKV with AC3)
        (function next() {
            setTimeout(function () {
                if (cur !== item) return;
                try { fn(); U.log({ ev: 'afterplay.ok' }); }
                catch (e) { U.log({ ev: 'afterplay.error', err: String(e && (e.name || e.message) || e) }); if (tries.length) next(); else if (onFail) onFail(e); }
            }, tries.shift());
        })();
    }
    // A mid-playback audio change on this TV can leave the sound out of step with the picture: jump to the
    // current time once, which flushes both and lines them up again (films and episodes only).
    // which audio track the TV is actually playing (its language), for the log
    function playingAudio() {
        try { var a = webapis.avplay.getCurrentStreamInfo(); for (var i = 0; i < a.length; i++) if (a[i].type === 'AUDIO') return a[i].index + ':' + (a[i].extra_info || '').slice(0, 80); } catch (e) { return 'err ' + String(e); }
        return 'none';
    }
    // One audio switch rule (research: Samsung AVPlay accepts an AUDIO change only in PLAYING, and this TV only
    // about 2 to 3 s after play; open-source Tizen players retry and then confirm). Retry every 500 ms for up
    // to 6 s, then read back the track that plays; never seek afterwards (a seek after the switch broke the sync
    // and once put the default track back). Subtitles are re-asserted once the audio has landed.
    var selT = null;
    function selectAudio(item, index, done) {
        clearTimeout(selT);
        var until = Date.now() + 6000, want = String(index);
        (function tryIt() {
            if (cur !== item) return;
            var ok = false;
            try { webapis.avplay.setSelectTrack('AUDIO', index); ok = true; } catch (e) { /* not accepted yet */ }
            selT = setTimeout(function () {
                if (cur !== item) return;
                var now = playingAudioIndex();
                if (ok && now === want) {
                    U.log({ ev: 'audio.set', index: want });
                    try {
                        if (cur.subsOn && cur.textIndex != null) { webapis.avplay.setSelectTrack('TEXT', cur.textIndex); webapis.avplay.setSilentSubtitle(false); }
                        else if (cur.ext && cur.ext.ref && cur.ext.ref.index != null) { webapis.avplay.setSelectTrack('TEXT', cur.ext.ref.index); webapis.avplay.setSilentSubtitle(false); }   // the realignment's reference
                    } catch (e) { /* subtitles stay as they are */ }
                    if (done) done(null);
                } else if (Date.now() < until) tryIt();
                else { U.log({ ev: 'audio.set.failed', index: want, playing: now }); if (done) done(new Error('not accepted')); }
            }, ok ? 600 : 500);
        })();
    }
    function playingAudioIndex() {
        try { var a = webapis.avplay.getCurrentStreamInfo(); for (var i = 0; i < a.length; i++) if (a[i].type === 'AUDIO') return String(a[i].index); } catch (e) { /* unknown */ }
        return '';
    }
    function switchAudio(index) {
        selectAudio(cur, index, function (err) { if (err) U.toast('This TV did not switch to that audio track'); });
    }
    function pick() {
        var t = menu.list[mSel];
        if (t.sect || t.wait) return;
        if (t.timing) {
            if (!cur.ext) return;
            if (tSel === 0) cur.ext.off -= 500; else if (tSel === 2) cur.ext.off += 500; else cur.ext.off = cur.ext.auto != null ? cur.ext.auto : 0;
            saveOff(cur.ext.file, cur.ext.off); U.log({ ev: 'subs.timing', chip: tSel, off: cur.ext.off }); drawMenu(); return;
        }
        try {
            if (menu.kind === 'audio') { audioFail = t.codec || ''; switchAudio(t.index); }
            else if (t.online) { useOnline(t.online, t.index); }
            else if (t.index === -1) { webapis.avplay.setSilentSubtitle(true); cur.subsOn = false; extOff(); subEl.textContent = ''; }
            else { extOff(); webapis.avplay.setSelectTrack('TEXT', t.index); webapis.avplay.setSilentSubtitle(false); cur.subsOn = true; cur.textIndex = t.index; }
            U.log({ ev: 'track.set', kind: menu.kind, index: t.index });
            if (cur.resumeItem) U.setTrackPref(cur.resumeItem, menu.kind, t.index === -1 ? { off: true } : t.online ? { online: true, lang: t.online.lang } : { lang: (t.extra && (t.extra.language || t.extra.track_lang)) || '', pos: t.pos });
        } catch (e) { U.log({ ev: 'track.error', err: String(e && (e.name || e.message) || e) }); U.toast('Could not switch'); }
        closeMenu(); setInfo(true);
    }

    // ---------- loading card ----------
    function tuneText(t) { var sp = info.querySelector('.ps .tune'); if (sp) sp.textContent = t ? (cur && cur.sub ? '  \u00b7  ' : '') + t : ''; }
    function showLoad(item) {
        var L = el.querySelector('.load');
        var pic = item.resumeItem && item.resumeItem.img ? U.img(item.resumeItem.img, 'w780') : '';
        L.querySelector('.lb').style.backgroundImage = pic ? 'url("' + pic + '")' : '';
        L.className = 'load on';
        tuning = true;
        info.querySelector('.prog').style.display = 'block';
        info.querySelector('.prog i').style.width = '4%';
        tuneText(item.k === 'live' ? 'Tuning in\u2026' : (item.pos ? 'Resuming at ' + U.fmtTime(item.pos) + '\u2026' : 'Loading\u2026'));
        setInfo(true, true);
    }
    function loadPct(p) {
        if (!tuning) return;
        info.querySelector('.prog i').style.width = Math.max(4, p) + '%';
        tuneText((cur && cur.k === 'live' ? 'Tuning in' : 'Loading') + '  ' + p + '%');
    }
    // the picture plays: the black fades away under the same bar, the status goes, the bar stays a moment
    function hideLoad() {
        var L = el.querySelector('.load'), was = tuning;
        L.className = 'load';
        if (!was) return;
        tuning = false; tuneText('');
        if (cur && cur.k === 'live') info.querySelector('.prog').style.display = 'none';
        else info.querySelector('.prog i').style.width = '0';
        if (cur) setInfo(true);
    }

    // ---------- reconnect ----------
    var stallT = null, retryT = null;
    // The account allows a set number of streams (often one). A refused stream with the account full shows
    // "in use on another device" and tries again every 5 s for 2 min, so the device used last gets the slot
    // as soon as the other one lets go.
    var busyT = null, busyN = 0;
    function busyRetry(item) {
        var L = el.querySelector('.load');
        busyN++;
        if (busyN > 24) { busyN = 0; hideLoad(); U.toast('Still in use on another device. Try again later.'); return; }
        try { showLoad(item); tuneText('Your account is in use on another device. Nexus TV starts as soon as it is free'); } catch (e) { /* no panel */ }
        U.log({ ev: 'account.busy', n: busyN });
        busyT = setTimeout(function () { if (cur === item) { item.tries = 0; start(item); } }, 5000);
    }
    function reconnect(why) {
        if (!cur) return;
        clearTimeout(stallT); clearTimeout(retryT); clearTimeout(busyT);
        if (why === 'error' || why === 'prepare') {
            var it0 = cur;
            try { stopAv(); } catch (e) { /* already closed */ }
            U.api({}, function (err, d) {
                if (cur !== it0) return;
                var ui = d && d.user_info, max = ui ? parseInt(ui.max_connections, 10) : 0, act = ui ? parseInt(ui.active_cons, 10) : 0;
                if (!err && max > 0 && act >= max) { busyRetry(it0); return; }
                busyN = 0; retry(why);
            });
            return;
        }
        retry(why);
    }
    function retry(why) {
        if (!cur) return;
        var n = (cur.tries || 0) + 1;
        U.log({ ev: 'reconnect', why: why, n: n });
        if (n > 5) { hideLoad(); busy.className = 'spinner busy'; U.toast('The stream stopped. Try again later.'); return; }
        var again = {}; for (var k in cur) again[k] = cur[k];
        again.tries = n; if (cur.src) again.url = cur.src;
        if (vod() && cur.pos) again.pos = cur.pos;
        var L = el.querySelector('.load');
        // The account allows one stream at a time: close this one now so the provider frees the slot, and give it
        // a few seconds before the next try (a try at 1 s is refused as a second connection).
        if (!vod()) { try { stopAv(); } catch (e) { /* already closed */ } }
        retryT = setTimeout(function () {
            start(again);
            tuneText('Reconnecting\u2026 (' + n + ')');
        }, vod() ? Math.min(8000, 1000 * Math.pow(2, n - 1)) : Math.min(12000, 3000 + 2000 * (n - 1)));
    }

    // Apply the saved audio/subtitle choice for this title, by language first, else by position.
    function applyPrefs() {
        var p = cur && cur.resumeItem ? U.getTrackPref(cur.resumeItem) : null;
        if (!p) return;
        var find = function (list, want) {
            if (!want) return null;
            for (var i = 0; i < list.length; i++) { var l = (list[i].extra && (list[i].extra.language || list[i].extra.track_lang)) || ''; if (want.lang && l === want.lang) return list[i]; }
            return want.pos >= 0 && list[want.pos] ? list[want.pos] : null;
        };
        var a = find(tracks('AUDIO'), p.audio);
        if (a && String(a.index) !== playingAudioIndex()) selectAudio(cur, a.index, null);   // applied once playing, then confirmed
        U.log({ ev: 'prefs.audio', want: p.audio || null, tracks: tracks('AUDIO').map(function (t) { return t.label; }), picked: a ? a.label : null });
        try {
            if (p.subs && p.subs.online) {
                if (cur.osub && Subs.ready()) { var it2 = cur; cur.osub.fps = videoFps(); cur.osub.url = cur.url; Subs.search(cur.osub, [p.subs.lang].concat(SUB_LANGS.filter(function (l) { return l !== p.subs.lang; })), function (e, res) {
                    if (cur !== it2 || e || !res.length || res[0].lang !== p.subs.lang) return; useOnline(res[0], -10);
                }); }
            }
            else if (p.subs && p.subs.off) { webapis.avplay.setSilentSubtitle(true); cur.subsOn = false; }
            else if (p.subs) { var s = find(tracks('TEXT'), p.subs); if (s) { webapis.avplay.setSelectTrack('TEXT', s.index); webapis.avplay.setSilentSubtitle(false); cur.subsOn = true; cur.textIndex = s.index; } }
            U.log({ ev: 'prefs.applied', audio: !!a, subs: cur.subsOn });
        } catch (e) { U.log({ ev: 'prefs.error', err: String(e && (e.name || e.message) || e) }); }
    }

    // ---------- play ----------
    function stopAv() {
        if (!av()) return;
        try { webapis.avplay.stop(); } catch (e) { /* idle */ }
        try { webapis.avplay.close(); } catch (e) { /* not open */ }
    }
    function start(item) {
        // A portal makes its play address on demand: resolve it first, keep the stored form for reconnects.
        if (item.url && item.url.indexOf('stalker:') === 0) {
            var orig = item.url; U.toast('Opening\u2026');
            Src.resolve(orig, function (u) {
                if (!u) { U.toast('The portal would not open this one'); return; }
                var real = {}; for (var k in item) real[k] = item[k];
                real.url = u; real.src = orig; start(real);
            });
            return;
        }
        // session memory: a chained episode carries whether the previous one reached its card without a seek; a fresh start is a key press
        if (!item.started) {
            item.started = true;
            if (sess.chainOk !== null) { item.prevOk = sess.chainOk; item.autoplayed = sess.chainAuto; if (sess.chainAuto) sess.autoplays++; else sess.autoplays = 0; sess.chainOk = null; }
            else if (!item.tries) { sess.autoplays = 0; sess.lastKey = Date.now(); }
        }
        stopAv();
        upHide(); stillHide(); extOff(); cur = item; ctl = false; btn = 1; closeMenu(); seekAcc = 0; tcache = {}; strip.inside = false; strip.dis = false;
        // while it tunes in, only the loading card shows (its own name, status and bar); the channel bar and the
        // spinner come once the picture plays or when a stall happens later
        render();
        busy.className = 'spinner busy';
        showLoad(item);
        document.documentElement.className = 'playing';
        U.log({ ev: 'play', k: item.k, name: item.name });
        if (vod() && item.resumeItem) U.setResume(item.resumeItem, item.pos || 0, 0);
        if (!av()) { U.toast('Player needs the TV'); busy.className = 'spinner busy'; return; }
        // the account allows one connection: the file's subtitle index is read before the stream opens (4 s at most)
        if (window.SubSync && vod() && SubSync.wants(item)) { SubSync.prefetch(item, function () { if (cur === item) start(item); }); return; }
        try {
            webapis.avplay.open(item.url);
            try {   // a playlist channel may ask for its own user agent or referrer
                var po = window.Src && Src.opts(item.src || item.url);
                if (po && po.ua) webapis.avplay.setStreamingProperty('USER_AGENT', po.ua);
                if (po && po.ref) webapis.avplay.setStreamingProperty('CUSTOM_MESSAGE_HEADER', 'Referer: ' + po.ref);
            } catch (e) { /* not supported on this TV */ }
            webapis.avplay.setDisplayRect(0, 0, 1920, 1080);
            webapis.avplay.setListener({
                onbufferingstart: function () { if (!tuning) busy.className = 'spinner busy on'; clearTimeout(stallT); stallT = setTimeout(function () { reconnect('stall'); }, 9000); },
                onbufferingcomplete: function () { busy.className = 'spinner busy'; hideLoad(); clearTimeout(stallT); if (cur) cur.tries = 0; },
                onbufferingprogress: function (pct) { loadPct(pct); },
                onstreamcompleted: function () {
                    U.log({ ev: 'ended' });
                    if (cur && cur.k === 'live') { reconnect('live-ended'); return; }   // a live channel never really ends
                    if (cur && cur.epctx) { endOfEpisode(); return; }   // an episode ends on its card: OK plays the next one, no timer
                    if (cur) cur.pos = 0;
                    if (cur && cur.next) advance(true); else exit();
                },
                onsubtitlechange: function (dur, text) {
                    noteCue(String(text || ''));
                    if (cur && cur.subsOn) subEl.innerHTML = U.esc(String(text || '')).replace(/\n/g, '<br>');
                    else if (cur && cur.ext && cur.ext.ref) refCue(String(text || ''));
                },
                onerror: function (e) { U.log({ ev: 'avplay.error', err: String(e) }); reconnect('error'); }
            });
            webapis.avplay.prepareAsync(function () {
                if (item.pos) { try { webapis.avplay.seekTo(item.pos); } catch (e) { /* live has no seek */ } }
                if (vod()) { try { webapis.avplay.setSilentSubtitle(true); } catch (e) { /* no subtitle support */ } cur.subsOn = false; applyPrefs(); }
                if (item.wantAudio != null) {
                    // the TV refuses an audio change before playback runs (PLAYER_ERROR_INVALID_OPERATION): wait for play
                    var want = item.wantAudio; item.wantAudio = null;
                    selectAudio(item, want, null);
                }
                webapis.avplay.play();
                busy.className = 'spinner busy';
                setTimeout(hideLoad, 400);
                drawBar(); stillMaybe(item);
                U.log({ ev: 'playing', k: item.k, audio: vod() ? tracks('AUDIO').length : null, subs: vod() ? tracks('TEXT').length : null });
                if (vod() && item.resumeItem) U.learnSubs(item.resumeItem, tracks('TEXT').length > 0);
            }, function (e) {
                busy.className = 'spinner busy';
                U.log({ ev: 'prepare.error', err: String(e && (e.name || e.message) || e) });
                reconnect('prepare');
            });
        } catch (e) {
            busy.className = 'spinner busy';
            U.log({ ev: 'play.exception', err: String(e && (e.name || e.message) || e) });
            U.toast('This could not be played');
        }
        clearInterval(tick); tick = setInterval(progress, 1000);
    }
    function exit(silent) {
        if (!cur) return;
        progress();
        if (cur.done && cur.dur) cur.pos = cur.dur;   // played past its credits: it is watched, not a resume point
        if (vod() && cur.resumeItem) U.setResume(cur.resumeItem, cur.pos || 0, cur.dur || 0);
        upHide(); stillHide(); clearInterval(tick); clearTimeout(stallT); clearTimeout(retryT); stopAv();
        document.documentElement.className = '';
        extOff(); cur = null; setInfo(false); subEl.textContent = ''; hideLoad();
        if (!silent) sess.chainOk = null;
        if (!silent && onExit) onExit();
    }
    function zap(d) {
        if (!cur || !cur.list || !cur.list.length) return;
        var i = (cur.idx + d + cur.list.length) % cur.list.length;
        var next = cur.list[i], onZap = cur.onZap;
        start({ k: 'live', url: U.liveUrl(next.sid), name: next.name, sub: next.sub, list: cur.list, idx: i, onZap: onZap });
        if (onZap) onZap(i);
    }
    // Repeated presses add up (+10, +20, +30 s...) and jump once the presses stop.
    function seek(ms) {
        if (!av() || !vod()) return;
        seekAcc += ms; cur.sought = true; setInfo(true); progress();
        clearTimeout(seekT);
        seekT = setTimeout(function () {
            var target;
            try { target = Math.max(0, webapis.avplay.getCurrentTime() + seekAcc); webapis.avplay.seekTo(target); extDraw(target); } catch (e) { U.log({ ev: 'seek.error', err: String(e) }); }
            seekAcc = 0; progress();
        }, 700);
    }
    // Live scrub: the film pauses and shows the real frame at the marker. A stop of 0.35 s loads that frame;
    // OK, or 1.8 s without a press, resumes playback from there.
    var previewT = null, seeking = false, wantPreview = null, wasPlaying = false, origin = 0;
    function scrubBy(dir) {
        if (!av() || !vod()) return;
        var d = 0, p = 0;
        try { d = webapis.avplay.getDuration(); p = webapis.avplay.getCurrentTime(); } catch (e) { return; }
        if (!d) { seek(dir * 10000); return; }
        var now = Date.now();
        streak = now - lastPress < 450 ? streak + 1 : 0; lastPress = now;
        var step = streak > 20 ? 120000 : streak > 10 ? 60000 : streak > 4 ? 30000 : 10000;
        if (scrub === null) { scrub = p; origin = p; wasPlaying = playing(); try { webapis.avplay.pause(); } catch (e) { /* idle */ } }
        scrub = Math.max(0, Math.min(d - 1000, scrub + dir * step));
        ctl = true; onBar = true; setInfo(true, true); progress();
        clearTimeout(previewT); previewT = setTimeout(function () { preview(scrub); }, 350);
        clearTimeout(scrubT); scrubT = setTimeout(commitScrub, 1800);
    }
    function preview(t) {
        if (t === null) return;
        if (seeking) { wantPreview = t; return; }
        seeking = true;
        try {
            webapis.avplay.seekTo(t, function () { seeking = false; if (wantPreview !== null && wantPreview !== t) { var w = wantPreview; wantPreview = null; preview(w); } else wantPreview = null; },
                function () { seeking = false; wantPreview = null; });
        } catch (e) { seeking = false; U.log({ ev: 'preview.error', err: String(e) }); }
    }
    function commitScrub() {
        clearTimeout(scrubT); clearTimeout(previewT);
        if (scrub === null) return;
        var t = scrub; scrub = null; streak = 0; cur.sought = true; cur.lastInter = t;
        var go = function () { try { webapis.avplay.play(); } catch (e) { /* idle */ } };
        try { webapis.avplay.seekTo(t, go, go); } catch (e) { U.log({ ev: 'seek.error', err: String(e) }); go(); }
        extDraw(t);
        U.log({ ev: 'scrub', to: Math.round(t / 1000) });
        progress(); setInfo(true);
    }
    function cancelScrub() {
        clearTimeout(scrubT); clearTimeout(previewT);
        scrub = null; streak = 0;
        var go = function () { if (wasPlaying) { try { webapis.avplay.play(); } catch (e) { /* idle */ } } };
        try { webapis.avplay.seekTo(origin, go, go); } catch (e) { go(); }
        progress(); setInfo(true);
    }
    // Paused for 2 minutes, or the app hidden: the stream is closed so another device can use the account;
    // play again reopens it (films and episodes where they were, live from now).
    var pauseT = null;
    function release(why) {
        if (!cur || cur.released) return;
        try { if (vod()) cur.pos = webapis.avplay.getCurrentTime(); } catch (e) { /* keep the last position */ }
        clearTimeout(stallT); clearTimeout(retryT); clearTimeout(busyT);
        try { stopAv(); } catch (e) { /* closed */ }
        cur.released = true; U.log({ ev: 'stream.released', why: why });
    }
    function reopen() {
        if (!cur || !cur.released) return;
        var again = {}; for (var k in cur) again[k] = cur[k];
        again.released = false; again.tries = 0; again.stillAsked = true; if (cur.src) again.url = cur.src;
        start(again);
    }
    function togglePause() {
        if (cur && cur.released) { reopen(); return; }
        if (!av()) return;
        clearTimeout(pauseT);
        try {
            if (playing()) { webapis.avplay.pause(); pauseT = setTimeout(function () { release('paused'); setInfo(true); }, 120000); }
            else webapis.avplay.play();
        } catch (e) { /* idle */ }
        setInfo(true);
    }
    function press(id) {
        if (id === 'back10') seek(-10000);
        else if (id === 'fwd10') seek(10000);
        else if (id === 'play') togglePause();
        else if (id === 'audio') openMenu('audio');
        else if (id === 'subs') openMenu('subs');
        else if (id === 'next' && cur.next) { recordSample('press'); advance(false); }
        else if (id === 'eps') { strip.dis = false; strip.inside = true; strip.sel = cur.epctx.e; setInfo(true, true); }
    }
    // ---------- episode strip (rule 3): focus on Episodes slides it up, Down enters it ----------
    var stripEl = null, STEP = 318, CARDW = 300;
    function stripCount() { var c = cur.epctx; return (c.eps[c.seasons[c.s]] || []).length + (c.s < c.seasons.length - 1 ? 1 : 0); }
    function drawStrip() {
        if (!stripEl) return;
        if (!(info.className.indexOf(' strip') > 0 && stripShown())) { stripEl.className = 'estrip'; if (stripEl.firstChild) stripEl.innerHTML = ''; return; }
        var c = cur.epctx, list = c.eps[c.seasons[c.s]] || [], n = list.length, total = stripCount(), sel = strip.inside ? strip.sel : c.e, h = '';
        for (var i = 0; i < total; i++) {
            var x = 112 + i * STEP;
            if (i >= n) {
                var nx = c.seasons[c.s + 1], cnt = (c.eps[nx] || []).length;
                h += '<div class="ec sn' + (sel === i ? ' ring' : '') + '" style="left:' + x + 'px"><div class="eth"></div><div class="ecap"><b>Season ' + U.esc(nx) + ' &#8250;</b><span>' + cnt + ' episodes</span></div></div>';
                continue;
            }
            var E = list[i], playing_ = i === c.e, rs = U.getResume({ k: 'ep', id: E.id }), pos = playing_ ? (cur.pos || 0) : (rs ? rs.pos : 0), dur = playing_ ? (cur.dur || 0) : (rs ? rs.dur : 0);
            var watched = !playing_ && U.isWatched({ k: 'ep', id: E.id }), mins = runtimeMin(E), still = E.info && E.info.movie_image ? E.info.movie_image : c.ser.img;
            var l2 = playing_ ? (dur ? U.fmtTime(pos) + ' of ' + U.fmtTime(dur) : (mins ? mins + ' min' : '')) : (mins ? mins + ' min' : '') + (i === c.e - 1 ? ' · Previous' : i === c.e + 1 ? ' · Next' : '');
            h += '<div class="ec' + (sel === i ? ' ring' : '') + '" style="left:' + x + 'px"><div class="eth">' + U.imgTag(still, 'w185') +
                (playing_ ? '<i class="eb">PLAYING</i>' : watched ? '<i class="eb">WATCHED</i>' : '') + (dur && pos > 0 ? '<s style="width:' + Math.min(100, Math.round(100 * pos / dur)) + '%"></s>' : '') + '</div>' +
                '<div class="ecap"><b>E' + (E.episode_num || i + 1) + ' · ' + U.esc(cleanEpTitle(E.title)) + '</b><span>' + U.esc(l2) + '</span></div></div>';
        }
        stripEl.innerHTML = '<div class="ein" id="ein">' + h + '</div>'; stripEl.className = 'estrip show';
        var max = Math.max(0, 112 + total * STEP - 18 + 112 - 1920), off = Math.max(0, Math.min(max, 112 + sel * STEP + CARDW / 2 - 960));
        var ein = U.$('ein'); ein.style.left = (-off) + 'px';
    }
    function stripKey(c) {
        var total = stripCount();
        if (c === 37 && strip.sel > 0) strip.sel--;
        else if (c === 39 && strip.sel < total - 1) strip.sel++;
        else if (c === 13) {
            var ec = cur.epctx, n = ec.eps[ec.seasons[ec.s]].length, to = strip.sel;
            if (to === ec.e) { strip.inside = false; strip.dis = true; setInfo(true); return true; }
            var f = ec.play; strip.inside = false;
            if (to >= n) { exit(true); f(ec.s + 1, 0); } else { exit(true); f(ec.s, to); }
            return true;
        }
        else if (c === 38 || c === 10009 || c === 8) { strip.inside = false; strip.dis = true; setInfo(true); return true; }
        setInfo(true, true); return true;
    }
    // Returns true when the key was used.
    function key(c) {
        if (!cur) return false;
        sess.lastKey = Date.now(); sess.autoplays = 0; cur.lastInter = cur.pos || 0;
        if (stillShown()) return stillKey(c);
        if (cardOn() && !ctl) {
            if (c === 13) { cardGo(); return true; }
            if (c === 10009 || c === 8) { cardDismiss(); return true; }
            ringStop();
        } else if (cardOn()) ringStop();
        if (c === 10009 || c === 8 || c === 413) {                       // Back, Stop
            if (scrub !== null) { cancelScrub(); return true; }
            if (menu) { closeMenu(); setInfo(true); return true; }
            if (strip.inside && c !== 413) { strip.inside = false; strip.dis = true; setInfo(true); return true; }
            if (ctl && c !== 413) { setInfo(false); return true; }
            exit(); return true;
        }
        if (c === 10252 || c === 415 || c === 19) { togglePause(); return true; }
        if (c === 412) { scrubBy(-1); return true; }
        if (c === 417) { scrubBy(1); return true; }
        if (!vod()) {
            if (c === 427 || c === 38) zap(-1);
            else if (c === 428 || c === 40) zap(1);
            else setInfo(true);
            return true;
        }
        if (menu) {
            var row = menu.list[mSel];
            if (c === 38) { nextSel(-1); drawMenu(); }
            else if (c === 40) { nextSel(1); drawMenu(); }
            else if (c === 13) pick();
            else if ((c === 37 || c === 39) && row && row.timing) { tSel = Math.max(0, Math.min(2, tSel + (c === 37 ? -1 : 1))); drawMenu(); }
            else if (c === 37 || c === 39) { closeMenu(); setInfo(true); }
            return true;
        }
        if (!ctl) {
            if (c === 37 || c === 39) { onBar = true; scrubBy(c === 37 ? -1 : 1); }
            else if (c === 13) { ctl = true; onBar = false; btn = 1; setInfo(true); }
            else if (c === 38 || c === 40) { ctl = true; onBar = true; setInfo(true); progress(); }
            return true;
        }
        if (strip.inside) return stripKey(c);
        if (onBar) {
            if (c === 37 || c === 39) scrubBy(c === 37 ? -1 : 1);
            else if (c === 13) { if (scrub !== null) commitScrub(); else togglePause(); }
            else if (c === 40) { commitScrub(); onBar = false; btn = 1; setInfo(true); progress(); }
            else if (c === 38) { commitScrub(); setInfo(false); }
            return true;
        }
        var n = buttons().length;
        if (c === 37 && btn > 0) { btn--; strip.dis = false; }
        else if (c === 39 && btn < n - 1) { btn++; strip.dis = false; }
        else if (c === 13) {
            if (btnId() === 'eps' && !strip.dis) { strip.inside = true; strip.sel = cur.epctx.e; setInfo(true, true); return true; }
            press(btnId()); return true;
        }
        else if (c === 38) { onBar = true; setInfo(true); progress(); return true; }
        else if (c === 40) { if (stripShown()) { strip.inside = true; strip.sel = cur.epctx.e; setInfo(true, true); return true; } setInfo(false); return true; }
        setInfo(true);
        return true;
    }

    // ---------- credits cue (rule 5) ----------
    // ONE function, in order of trust. creditsCue(p, d) says whether the credits have started at position p of d (ms).
    //  a. the show's memory: where its credits started, as seconds before the end (median of the last 5 samples, U.creditsMem)
    //  b. no memory: the subtitle cues go quiet for 45 s inside the last 6 minutes. The index of the file's own cues (SubSync)
    //     when it was read, else the cue times the TV reported live (onsubtitlechange)
    //  c. no subtitles at all: the last 2 % of the runtime, never under 20 s (also the backstop of b)
    function seriesKey() { var c = cur && cur.epctx; return c && c.ser ? String(c.ser.id) : (cur && cur.resumeItem && cur.resumeItem.series ? String(cur.resumeItem.series.id) : ''); }
    function cueStarts() {
        var idx = window.SubSync && cur ? SubSync.cached(SubSync.keyOf(cur)) : null;
        return idx && idx.length ? idx : ((cur && cur.cueTimes) || []);
    }
    function quietReached(st, p, d) {
        for (var i = 0; i < st.length; i++) {
            var s0 = st[i], nx = i + 1 < st.length ? st[i + 1] : Math.max(p, s0);
            if (s0 >= d - 360000 && nx - s0 >= 45000 && p >= s0 + 45000) return true;
        }
        return false;
    }
    function creditsCue(p, d) {
        var mem = U.creditsMem(seriesKey());
        if (mem) return p >= d - mem * 1000;
        var st = cueStarts();
        if (st.length && quietReached(st, p, d)) return true;
        return p >= d - Math.max(d * 0.02, 20000);
    }
    function noteCue(text) {
        if (!cur || !text || cur.lastCueText === text) { if (cur && !text) cur.lastCueText = ''; return; }
        cur.lastCueText = text;
        try { var t = webapis.avplay.getCurrentTime(); cur.cueTimes = cur.cueTimes || []; cur.cueTimes.push(t); if (cur.cueTimes.length > 600) cur.cueTimes.shift(); } catch (e) { /* no clock */ }
    }
    // A sample of where this show's credits start: Next episode / card OK with under 8 min left, or the file played to its end.
    function recordSample(kind) {
        var key = seriesKey(), d = cur && cur.dur, p = cur && cur.pos, secs = 0;
        if (!key || !d) return;
        if (kind === 'press') { if (d - p < 480000) secs = (d - p) / 1000; }
        else {
            var lp = cur.lastInter, st = cueStarts();
            if (lp != null && lp < d && d - lp <= 480000) secs = (d - lp) / 1000;
            else if (st.length && d - st[st.length - 1] <= 360000) secs = (d - st[st.length - 1]) / 1000;
        }
        if (secs >= 5) { U.creditsAdd(key, Math.round(secs)); U.log({ ev: 'credits.sample', kind: kind, secs: Math.round(secs) }); }
    }
    function cueCheck(p, d) {
        if (!cur || cur.k !== 'ep' || !cur.epctx || cur.cue || scrub !== null || !(d > 120000)) return;
        if (!creditsCue(p, d)) return;
        cur.cue = true; cur.cueAt = p; U.log({ ev: 'credits.cue', at: Math.round(p / 1000), of: Math.round(d / 1000) });
        cardShow(false); drawBar();
    }

    // ---------- end card (rule 4): compact row, bottom right ----------
    var CARD_SEC = 10, upEl = null, upLeft = 0, upT = null, upOn = false, upRing = false;
    function cardOn() { return upOn; }
    function advance(auto) {
        if (!cur || !cur.next) return;
        var ok = !!cur.cue && !cur.sought, n = cur.next;
        if (cur.cue) cur.done = true;
        upHide(); exit(true); sess.chainOk = ok; sess.chainAuto = !!auto; n();
    }
    function cardGo() {
        if (!cur) return;
        if (cur.next) { recordSample('press'); advance(false); }
        else { cur.done = true; exit(); }
    }
    function cardDismiss() { cur.cardDis = true; upHide(); }
    function endOfEpisode() {
        recordSample('end'); cur.done = true; cur.pos = cur.dur || cur.pos;
        if (cur.resumeItem) U.setResume(cur.resumeItem, cur.dur || 0, cur.dur || 0);
        cur.cue = true; cur.cardDis = false; cardShow(true); setInfo(true, true);
    }
    function cardShow(atEnd) {
        if (cur.cardDis && !atEnd) return;
        var ni = cur.nextInfo, last = !cur.next, newSeason = ni && ni.newSeason, ring = !last && !newSeason && !atEnd && !!cur.prevOk;
        var kick, title, sub = 'OK plays now · Back keeps the credits';
        if (last) { kick = 'LAST EPISODE'; title = 'Back to Home'; sub = 'OK goes Home · Back keeps the credits'; }
        else if (newSeason) { kick = 'NEXT SEASON · ' + ni.tag + (ni.mins ? ' · ' + ni.mins + ' MIN' : ''); title = ni.title || cur.nextName || ''; }
        else { kick = 'NEXT · ' + (ni ? ni.tag : '') + (ni && ni.mins ? ' · ' + ni.mins + ' MIN' : ''); title = ni && ni.title ? ni.title : (cur.nextName || ''); }
        var thumb = ni && ni.img ? U.imgTag(ni.img, 'w185') : '';
        upOn = true; upRing = ring; upLeft = ring ? CARD_SEC : 0;
        upEl.innerHTML = '<div class="ut">' + thumb + '</div><div class="ux"><div class="uh">' + U.esc(kick) + '</div><div class="un">' + U.esc(title) + '</div><div class="uk">' + sub + '</div></div>' +
            '<div class="ur' + (ring ? ' run' : '') + '"><svg width="52" height="52" viewBox="0 0 52 52"><circle cx="26" cy="26" r="22" class="rb"/><circle cx="26" cy="26" r="22" class="rf" id="rf"/></svg><b id="rn">' + (ring ? CARD_SEC : '&#9654;') + '</b></div>';
        upEl.className = 'upnext show';
        clearInterval(upT);
        if (ring) {
            upT = setInterval(function () {
                upLeft--; var rn = U.$('rn'), rf = U.$('rf');
                if (rn) rn.textContent = upLeft > 0 ? upLeft : '';
                if (rf) rf.style.strokeDashoffset = String(Math.round(138 * (1 - upLeft / CARD_SEC)));
                if (upLeft <= 0) { clearInterval(upT); upT = null; var a = true; advance(a); }
            }, 1000);
        }
    }
    // Any key press during the countdown stops the ring: the card stays and waits.
    function ringStop() {
        if (!upT) return;
        clearInterval(upT); upT = null; upRing = false;
        var rn = U.$('rn'); if (rn) rn.innerHTML = '&#9654;';
        if (upEl.firstChild) { var r = upEl.querySelector('.ur'); if (r) r.className = 'ur'; }
    }
    function upHide() { clearInterval(upT); upT = null; upLeft = 0; upOn = false; if (upEl) { upEl.className = 'upnext'; upEl.innerHTML = ''; } }

    // ---------- still watching (rule 6) ----------
    var STILL_SEC = 60, stillEl = null, stillT = null, stillLeft = 0, stillBtn = 0, stillAt = 0;
    function stillShown() { return stillT !== null; }
    function stillMaybe(item) {
        if (cur !== item || !item.autoplayed || item.stillAsked) return;
        var need = sess.next4 ? 4 : 2;
        if (sess.autoplays < need || Date.now() - sess.lastKey < 90 * 60000) return;
        item.stillAsked = true; sess.next4 = false;
        stillAt = Date.now(); stillLeft = STILL_SEC; stillBtn = 0; stillDraw();
        stillT = setInterval(function () {
            stillLeft--;
            if (stillLeft <= 0) { stillHide(); stillTimeout(); } else stillDraw();
        }, 1000);
        U.log({ ev: 'still.ask', autoplays: sess.autoplays, need: need });
    }
    function stillDraw() {
        if (!stillEl) return;
        var m = Math.floor(stillLeft / 60), s2 = stillLeft % 60;
        stillEl.innerHTML = '<div class="sh">Still watching?</div><div class="sx">No key press for ' + sess.autoplays + ' episodes. Playback pauses in 60 s and frees your account\'s stream for other devices.</div>' +
            '<div class="sb"><span class="' + (stillBtn === 0 ? 'on' : '') + '">Keep watching</span><span class="' + (stillBtn === 1 ? 'on' : '') + '">Back to Home</span><em>' + m + ':' + (s2 < 10 ? '0' : '') + s2 + '</em></div>';
        stillEl.className = 'still show';
    }
    function stillHide() { clearInterval(stillT); stillT = null; if (stillEl) { stillEl.className = 'still'; stillEl.innerHTML = ''; } }
    function stillTimeout() {
        if (!cur) return;
        try { if (playing()) webapis.avplay.pause(); } catch (e) { /* idle */ }
        release('still'); U.toast('Paused. Press OK to carry on.'); setInfo(true, true); U.log({ ev: 'still.timeout' });
    }
    function stillKey(c) {
        if (c === 37 || c === 39) { stillBtn = c === 37 ? 0 : 1; stillDraw(); return true; }
        if (c === 10009 || c === 8) { stillHide(); exit(); return true; }
        if (c === 13) {
            var quick = Date.now() - stillAt <= 10000;
            stillHide();
            if (stillBtn === 1) { exit(); return true; }
            sess.quick = quick ? sess.quick + 1 : 0;
            if (sess.quick >= 2) { sess.next4 = true; sess.quick = 0; }
            sess.autoplays = 0; sess.lastKey = Date.now();
            U.log({ ev: 'still.keep', quick: quick });
        }
        return true;
    }
    function init(exitCb) {
        el = U.$('player'); info = el.querySelector('.info'); busy = el.querySelector('.busy'); onExit = exitCb;
        subEl = U.$('subs'); panel = U.$('tpanel');
        upEl = document.createElement('div'); upEl.className = 'upnext'; el.appendChild(upEl);
        stillEl = document.createElement('div'); stillEl.className = 'still'; el.appendChild(stillEl);
        stripEl = document.createElement('div'); stripEl.className = 'estrip'; info.appendChild(stripEl);
        document.addEventListener('visibilitychange', function () {
            if (document.hidden && cur) exit();
        });
    }
    // The next episode and the episode list found after playback started (resume from Continue watching).
    function setNext(item, fn, name, ninfo) { if (cur !== item) return; cur.next = fn; cur.nextName = name || ''; cur.nextInfo = ninfo || null; drawBar(); }
    function setEps(item, ctx) { if (cur !== item) return; cur.epctx = ctx; render(); drawBar(); }
    function setSubsItem(item, o) { if (cur === item) cur.osub = o; }
    return { init: init, start: start, key: key, setNext: setNext, setEps: setEps, setSubsItem: setSubsItem, release: release, reopen: reopen, active: function () { return !!cur; } };
})();
