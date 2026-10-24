// Full-screen player on Samsung's native AVPlay (the web <video> on Tizen 3 buffers these streams forever).
// Films and episodes get a control bar: back 10 s, play/pause, forward 10 s, audio language, subtitles,
// and next episode when there is one. Live channels zap with up/down.
var Player = (function () {
    'use strict';
    var cur = null, infoT = null, tick = null, el, info, busy, subEl, panel, onExit = null;
    var ctl = false, btn = 1, menu = null, mSel = 0, seekAcc = 0, seekT = null;
    // Timeline scrubbing, Apple style: Left/Right move a marker on the bar (faster when held), OK or a pause jumps there.
    var onNext = false, onBar = false, scrub = null, scrubT = null, lastPress = 0, streak = 0;

    function av() { return window.webapis && webapis.avplay; }
    function vod() { return cur && cur.k !== 'live'; }
    function playing() { try { return webapis.avplay.getState() === 'PLAYING'; } catch (e) { return false; } }

    // ---------- control bar: icon buttons ----------
    function svg(d) { return '<svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + d + '</svg>'; }
    var ICON = {
        play: svg('<path d="M7 4.5v15l12-7.5z" fill="currentColor" stroke="none"/>'),
        pause: svg('<rect x="6" y="4.5" width="4" height="15" rx="1" fill="currentColor" stroke="none"/><rect x="14" y="4.5" width="4" height="15" rx="1" fill="currentColor" stroke="none"/>'),
        back10: svg('<path d="M4 12a8 8 0 1 0 2.3-5.6"/><path d="M4 4v4h4"/><text x="12" y="15.5" font-size="7.5" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="Arial">10</text>'),
        fwd10: svg('<path d="M20 12a8 8 0 1 1-2.3-5.6"/><path d="M20 4v4h-4"/><text x="12" y="15.5" font-size="7.5" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="Arial">10</text>'),
        audio: svg('<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor" stroke="none"/><path d="M15.5 9a4 4 0 0 1 0 6"/><path d="M18 6.5a7.5 7.5 0 0 1 0 11"/>'),
        subs: svg('<rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="M10.5 10.3a2.2 2.2 0 1 0 0 3.4"/><path d="M17 10.3a2.2 2.2 0 1 0 0 3.4"/>'),
        next: svg('<path d="M5 5v14l10-7z" fill="currentColor" stroke="none"/><rect x="16.5" y="5" width="2.6" height="14" rx="1" fill="currentColor" stroke="none"/>')
    };
    function buttons() {
        var b = [{ id: 'back10', label: ICON.back10 }, { id: 'play', label: playing() ? ICON.pause : ICON.play }, { id: 'fwd10', label: ICON.fwd10 },
            { id: 'audio', label: ICON.audio }, { id: 'subs', label: ICON.subs }];
        return b;
    }
    function drawBar() {
        var bar = el.querySelector('.ctl');
        if (!vod()) { bar.innerHTML = ''; return; }
        var b = buttons(), h = '', x = 112;
        for (var i = 0; i < b.length; i++) {
            h += '<div class="pbtn' + (ctl && !menu && !onBar && !onNext && i === btn ? ' focus' : '') + '" id="pb' + i + '" style="left:' + x + 'px">' + b[i].label + '</div>';
            x += 0;
        }
        bar.innerHTML = h;
        var px = 112;
        for (var j = 0; j < b.length; j++) { var e = U.$('pb' + j); e.style.left = px + 'px'; px += e.offsetWidth + 14; }
    }
    // Next episode: a labelled button on the right, just above the timeline. Up from the timeline reaches it.
    function drawNext() {
        var nb = info.querySelector('.nextb');
        if (!vod() || !cur || !cur.next) { nb.className = 'nextb'; nb.innerHTML = ''; return; }
        nb.className = 'nextb show' + (onNext ? ' focus' : '');
        nb.innerHTML = ICON.next;
    }
    function setInfo(show, keep) {
        info.className = 'info' + (show ? ' show' : '');
        clearTimeout(infoT);
        if (!show) { ctl = false; onBar = false; onNext = false; closeMenu(); }
        drawBar(); drawNext();
        if (show && !keep && !menu) infoT = setTimeout(function () { if (!menu) setInfo(false); }, ctl ? 7000 : 4000);
    }
    function render() {
        info.querySelector('.pt').textContent = cur.name || '';
        info.querySelector('.ps').innerHTML = cur.k === 'live' ? '<span class="pill live">LIVE</span>&nbsp; ' + U.esc(cur.sub || '') : U.esc(cur.sub || '');
        info.querySelector('.prog').style.display = vod() ? 'block' : 'none';
        info.querySelector('.time').textContent = '';
        info.querySelector('.prog i').style.width = '0';
        subEl.textContent = '';
    }
    function progress() {
        if (!vod() || !av()) return;
        var p = 0, d = 0;
        try { p = webapis.avplay.getCurrentTime(); d = webapis.avplay.getDuration(); } catch (e) { return; }
        if (seekAcc) p = Math.max(0, Math.min(d, p + seekAcc));
        if (!seekAcc && p > 0) { cur.pos = p; if (d > 0) cur.dur = d; }
        if (!seekAcc && p > 0) upCheck(p, d);
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
            info.querySelector('.time').textContent = U.fmtTime(p) + ' / ' + U.fmtTime(d) + (seekAcc ? '   (' + (seekAcc > 0 ? '+' : '-') + Math.abs(seekAcc / 1000) + ' s)' : '');
            if (!seekAcc) { cur.pos = p; cur.dur = d; }
        }
    }

    // ---------- audio and subtitle tracks ----------
    function tracks(type) {
        var out = [];
        try {
            var all = webapis.avplay.getTotalTrackInfo();
            for (var i = 0; i < all.length; i++) {
                if (all[i].type !== type) continue;
                var x = {}; try { x = JSON.parse(all[i].extra_info || '{}'); } catch (e) { /* plain text */ }
                var lang = x.language || x.track_lang || '';
                var codec = String(x.fourCC || x.codec || x.codec_name || '').replace(/\s+$/, '').toUpperCase();
                var name = langName(lang) || (type === 'AUDIO' ? 'Audio ' : 'Subtitles ') + (out.length + 1);
                out.push({ index: all[i].index, label: name + (type === 'AUDIO' && codec ? ' \u00b7 ' + codec : ''), codec: codec, extra: x });
            }
        } catch (e) { U.log({ ev: 'tracks.error', err: String(e && (e.name || e.message) || e) }); }
        return out;
    }
    var LANGS = { en: 'English', eng: 'English', fr: 'French', fre: 'French', fra: 'French', nl: 'Dutch', dut: 'Dutch', nld: 'Dutch', de: 'German', ger: 'German', deu: 'German',
        es: 'Spanish', spa: 'Spanish', it: 'Italian', ita: 'Italian', pt: 'Portuguese', por: 'Portuguese', ar: 'Arabic', ara: 'Arabic', tr: 'Turkish', tur: 'Turkish', ja: 'Japanese', jpn: 'Japanese' };
    function langName(l) { l = String(l || '').toLowerCase(); return LANGS[l] || (l && l !== 'und' ? l.toUpperCase() : ''); }
    function current(type) { try { var c = webapis.avplay.getCurrentStreamInfo(); for (var i = 0; i < c.length; i++) if (c[i].type === type) return Number(c[i].index); } catch (e) { /* none */ } return -1; }
    function openMenu(kind) {
        var list = tracks(kind === 'audio' ? 'AUDIO' : 'TEXT');
        var online = kind === 'subs' && vod() && cur.osub && Subs.ready();
        if (kind === 'subs') list.unshift({ index: -1, label: 'Off' });
        if (kind === 'subs' && cur.ext) { list.unshift({ index: -4, sync: 500, label: 'Later \u00b7 +0.5 s' }); list.unshift({ index: -3, sync: -500, label: 'Earlier \u00b7 \u22120.5 s  (now ' + fmtOff(cur.ext.off) + ')' }); }
        if (online) list.push({ index: -2, label: 'Searching online\u2026', wait: true });
        if (!list.length || (kind === 'audio' && list.length < 2 && !list[0]) || (kind === 'subs' && list.length < 2)) { U.toast(kind === 'audio' ? 'Only one audio track' : 'No subtitles in this file'); return; }
        var on = kind === 'audio' ? current('AUDIO') : (cur.ext ? cur.ext.idx : cur.subsOn ? current('TEXT') : -1);
        if (online) {
            var it = cur, m0 = null;
            cur.osub.fps = videoFps(); cur.osub.url = cur.url;
            Subs.search(cur.osub, SUB_LANGS, function (e, res) {
                if (cur !== it || !menu || menu.kind !== 'subs') return;
                var l = menu.list.filter(function (x) { return !x.wait; });
                if (e) l.push({ index: -2, label: 'Online search failed', wait: true });
                else if (!res.length) l.push({ index: -2, label: 'Nothing online', wait: true });
                res.forEach(function (r, i) {
                    var match = cur.osub.fps && r.fps && Math.abs(r.fps - cur.osub.fps) < 0.05;
                    l.push({ index: -10 - i, online: r, label: langName(r.lang) + ' \u00b7 online' + (r.exact ? ' \u00b7 made for this file' : match ? ' \u00b7 same frame rate' : '') + (r.hi ? ' (SDH)' : '') });
                });
                menu.list = l; if (mSel >= l.length) mSel = l.length - 1; drawMenu();
                U.log({ ev: 'subs.online', n: res.length, err: e ? e.message : null });
            });
        }
        menu = { kind: kind, list: list };
        mSel = 0; for (var i = 0; i < list.length; i++) if (list[i].index === on) mSel = i;
        drawMenu(); setInfo(true, true);
        U.log({ ev: 'tracks', kind: kind, labels: list.map(function (t) { return t.label + '#' + t.index; }), on: on, item: cur && cur.resumeItem ? cur.resumeItem.k + ':' + cur.resumeItem.id : null });
    }
    function drawMenu() {
        if (!menu) { panel.className = 'tpanel'; panel.innerHTML = ''; return; }
        var on = menu.kind === 'audio' ? current('AUDIO') : (cur.subsOn ? current('TEXT') : -1);
        var h = '<div class="tph">' + (menu.kind === 'audio' ? 'Audio' : 'Subtitles') + '</div>';
        for (var i = 0; i < menu.list.length; i++)
            h += '<div class="tpi' + (i === mSel ? ' focus' : '') + '">' + (menu.list[i].index === on ? '&#10003;&nbsp; ' : '<span style="display:inline-block;width:34px"></span>') + U.esc(menu.list[i].label) + '</div>';
        panel.innerHTML = h; panel.className = 'tpanel show';
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
        cur.ext.ref = { starts: [], last: '', n: 0 };
        afterPlay(cur, function () { webapis.avplay.setSelectTrack('TEXT', ref.index); webapis.avplay.setSilentSubtitle(false); }, null);
        U.log({ ev: 'subs.align.start', ref: ref.label });
    }
    function refCue(text) {
        var R = cur.ext.ref, t = 0;
        if (!text) { R.last = ''; return; }
        if (text === R.last) return; R.last = text;
        try { t = webapis.avplay.getCurrentTime(); } catch (e) { return; }
        R.starts.push(t); if (R.starts.length > 40) R.starts.shift();
        if (++R.n % 4 === 0 && R.starts.length >= 6) align();
    }
    function align() {
        var E = cur.ext, cues = E.cues, st = E.ref.starts, best = 0, score = 0, bins = {};
        for (var i = 0; i < st.length; i++) {
            var te = st[i] * E.k, lo = 0, hi = cues.length - 1;
            while (lo < hi) { var m = (lo + hi) >> 1; if (cues[m].a < te - 20000) lo = m + 1; else hi = m; }
            for (var j = lo; j < cues.length && cues[j].a <= te + 20000; j++) { var b = Math.round((te - cues[j].a) / 100); bins[b] = (bins[b] || 0) + 1; }
        }
        for (var key in bins) { var c = (bins[key - 2] || 0) + (bins[key - 1] || 0) + bins[key] + (bins[+key + 1] || 0) + (bins[+key + 2] || 0); if (c > score) { score = c; best = +key * 100; } }
        var ok = st.length >= 10 && score >= st.length * 0.4;
        if (ok) { E.off = best; saveOff(E.file, best); }
        U.log({ ev: 'subs.align', off: best, score: score, n: st.length, used: ok, file: E.file });
        // after a minute of dialogue with no agreement, this file is timed for another cut: try the next one
        if (!ok && st.length >= 16 && E.alts.length) {
            var nx = E.alts.shift(); nx.alts = E.alts; cur.ext0 = { ref: E.ref }; E.ref.starts = E.ref.starts.slice();
            U.log({ ev: 'subs.align.switch', to: nx.file, name: nx.name }); useOnline(nx, E.idx);
        }
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
            extT = setInterval(function () {
                if (!cur || !cur.ext) return;
                var t = 0; try { t = webapis.avplay.getCurrentTime(); } catch (e3) { return; }
                var x = Subs.at(cur.ext.cues, t * cur.ext.k - cur.ext.off); if (subEl.getAttribute('data-x') !== x) { subEl.setAttribute('data-x', x); subEl.innerHTML = U.esc(x).replace(/\n/g, '<br>'); }
            }, 200);
            if (!r.exact && !cur.ext.ref) startAlign();
            U.toast(langName(r.lang) + ' subtitles on' + (left != null ? ' \u00b7 ' + left + ' downloads left today' : ''));
            U.log({ ev: 'subs.dl', n: cues.length, left: left, vfps: vf, sfps: r.fps, k: k });
        });
    }
    var audioFail = '';
    // Runs fn once playback runs: tries at 1.2 s, then 3 s. onFail gets the last error.
    function afterPlay(item, fn, onFail) {
        var tries = [1200, 1800];
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
    function resync(item) {
        if (!vod()) return;
        setTimeout(function () {
            if (cur !== item) return;
            try { var t = webapis.avplay.getCurrentTime(); webapis.avplay.seekTo(t, function () { U.log({ ev: 'av.resync', at: t }); }, function (e) { U.log({ ev: 'av.resync.error', err: String(e) }); }); }
            catch (e) { U.log({ ev: 'av.resync.error', err: String(e && (e.name || e.message) || e) }); }
        }, 400);
    }
    function switchAudio(index) {
        try { webapis.avplay.setSelectTrack('AUDIO', index); resync(cur); return; } catch (e) { U.log({ ev: 'audio.live.error', err: String(e && (e.name || e.message) || e) }); }
        try { webapis.avplay.pause(); webapis.avplay.setSelectTrack('AUDIO', index); webapis.avplay.play(); resync(cur); return; }
        catch (e) { U.log({ ev: 'audio.paused.error', err: String(e && (e.name || e.message) || e) }); try { webapis.avplay.play(); } catch (e2) { /* reopened below */ } }
        var it = cur;
        try { it.pos = vod() ? webapis.avplay.getCurrentTime() : 0; } catch (e) { /* keep the last known position */ }
        it.wantAudio = index;
        start(it);
    }
    function closeMenu() { menu = null; if (panel) { panel.className = 'tpanel'; panel.innerHTML = ''; } }
    function pick() {
        var t = menu.list[mSel];
        try {
            if (menu.kind === 'audio') { audioFail = t.codec || ''; switchAudio(t.index); }
            else if (t.wait) { return; }
            else if (t.sync) { cur.ext.off += t.sync; saveOff(cur.ext.file, cur.ext.off); menu.list[0].label = 'Earlier \u00b7 \u22120.5 s  (now ' + fmtOff(cur.ext.off) + ')'; drawMenu(); return; }
            else if (t.online) { useOnline(t.online, t.index); }
            else if (t.index === -1) { webapis.avplay.setSilentSubtitle(true); cur.subsOn = false; extOff(); subEl.textContent = ''; }
            else { extOff(); webapis.avplay.setSelectTrack('TEXT', t.index); webapis.avplay.setSilentSubtitle(false); cur.subsOn = true; }
            U.log({ ev: 'track.set', kind: menu.kind, index: t.index });
            if (cur.resumeItem) {
                var pos = 0; for (var i = 0; i < menu.list.length; i++) if (menu.list[i] === t) pos = i;
                U.setTrackPref(cur.resumeItem, menu.kind, t.index === -1 ? { off: true } : t.online ? { online: true, lang: t.online.lang } : { lang: (t.extra && (t.extra.language || t.extra.track_lang)) || '', pos: menu.kind === 'subs' ? pos - 1 : pos });
            }
        } catch (e) { U.log({ ev: 'track.error', err: String(e && (e.name || e.message) || e) }); U.toast('Could not switch'); }
        closeMenu(); setInfo(true);
    }

    // ---------- loading card ----------
    function showLoad(item) {
        var L = el.querySelector('.load');
        var pic = item.resumeItem && item.resumeItem.img ? U.img(item.resumeItem.img, 'w780') : '';
        L.querySelector('.lb').style.backgroundImage = pic ? 'url("' + pic + '")' : '';
        L.querySelector('.lt').textContent = item.name || '';
        L.querySelector('.ls').textContent = item.k === 'live' ? 'Tuning in…' : (item.pos ? 'Resuming at ' + U.fmtTime(item.pos) + '…' : 'Loading…');
        L.querySelector('.lp i').style.width = '4%';
        L.className = 'load on';
    }
    function loadPct(p) { var L = el.querySelector('.load'); if (L.className.indexOf('on') > 0) { L.querySelector('.lp i').style.width = Math.max(4, p) + '%'; L.querySelector('.ls').textContent = (cur && cur.k === 'live' ? 'Tuning in' : 'Loading') + '  ' + p + '%'; } }
    function hideLoad() { el.querySelector('.load').className = 'load'; }

    // ---------- reconnect ----------
    var stallT = null, retryT = null;
    function reconnect(why) {
        if (!cur) return;
        clearTimeout(stallT); clearTimeout(retryT);
        var n = (cur.tries || 0) + 1;
        U.log({ ev: 'reconnect', why: why, n: n });
        if (n > 5) { hideLoad(); busy.className = 'spinner busy'; U.toast('The stream stopped. Try again later.'); return; }
        var again = {}; for (var k in cur) again[k] = cur[k];
        again.tries = n; if (cur.src) again.url = cur.src;
        if (vod() && cur.pos) again.pos = cur.pos;
        var L = el.querySelector('.load');
        retryT = setTimeout(function () {
            start(again);
            L.querySelector('.ls').textContent = 'Reconnecting… (' + n + ')';
        }, Math.min(8000, 1000 * Math.pow(2, n - 1)));
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
        try { if (a) webapis.avplay.setSelectTrack('AUDIO', a.index); }
        catch (e) {
            U.log({ ev: 'prefs.audio.error', err: String(e && (e.name || e.message) || e), codec: a.codec });
            // the TV refuses an audio change before playback runs: apply it once playing
            var it1 = cur;
            afterPlay(cur, function () { webapis.avplay.setSelectTrack('AUDIO', a.index); resync(it1); }, null);
        }
        U.log({ ev: 'prefs.audio', want: p.audio || null, tracks: tracks('AUDIO').map(function (t) { return t.label; }), picked: a ? a.label : null });
        try {
            if (p.subs && p.subs.online) {
                if (cur.osub && Subs.ready()) { var it2 = cur; cur.osub.fps = videoFps(); cur.osub.url = cur.url; Subs.search(cur.osub, [p.subs.lang].concat(SUB_LANGS.filter(function (l) { return l !== p.subs.lang; })), function (e, res) {
                    if (cur !== it2 || e || !res.length || res[0].lang !== p.subs.lang) return; useOnline(res[0], -10);
                }); }
            }
            else if (p.subs && p.subs.off) { webapis.avplay.setSilentSubtitle(true); cur.subsOn = false; }
            else if (p.subs) { var s = find(tracks('TEXT'), p.subs); if (s) { webapis.avplay.setSelectTrack('TEXT', s.index); webapis.avplay.setSilentSubtitle(false); cur.subsOn = true; } }
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
        stopAv();
        upHide(); extOff(); cur = item; ctl = false; btn = 1; closeMenu(); seekAcc = 0;
        render(); setInfo(true);
        busy.className = 'spinner busy on';
        showLoad(item);
        document.documentElement.className = 'playing';
        U.log({ ev: 'play', k: item.k, name: item.name });
        if (vod() && item.resumeItem) U.setResume(item.resumeItem, item.pos || 0, 0);
        if (!av()) { U.toast('Player needs the TV'); busy.className = 'spinner busy'; return; }
        try {
            webapis.avplay.open(item.url);
            try {   // a playlist channel may ask for its own user agent or referrer
                var po = window.Src && Src.opts(item.src || item.url);
                if (po && po.ua) webapis.avplay.setStreamingProperty('USER_AGENT', po.ua);
                if (po && po.ref) webapis.avplay.setStreamingProperty('CUSTOM_MESSAGE_HEADER', 'Referer: ' + po.ref);
            } catch (e) { /* not supported on this TV */ }
            webapis.avplay.setDisplayRect(0, 0, 1920, 1080);
            webapis.avplay.setListener({
                onbufferingstart: function () { busy.className = 'spinner busy on'; clearTimeout(stallT); stallT = setTimeout(function () { reconnect('stall'); }, 9000); },
                onbufferingcomplete: function () { busy.className = 'spinner busy'; hideLoad(); clearTimeout(stallT); if (cur) cur.tries = 0; },
                onbufferingprogress: function (pct) { loadPct(pct); },
                onstreamcompleted: function () {
                    U.log({ ev: 'ended' });
                    if (cur && cur.k === 'live') { reconnect('live-ended'); return; }   // a live channel never really ends
                    if (cur) cur.pos = 0;
                    if (cur && cur.next) { var n = cur.next; exit(true); n(); } else exit();
                },
                onsubtitlechange: function (dur, text) {
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
                    afterPlay(item, function () { webapis.avplay.setSelectTrack('AUDIO', want); resync(item); }, function (e) {
                        U.toast('Could not switch to this track (' + (audioFail ? audioFail + ', ' : '') + String(e && (e.name || e.message) || e) + ')');
                    });
                }
                webapis.avplay.play();
                busy.className = 'spinner busy';
                setTimeout(hideLoad, 400);
                drawBar();
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
        if (vod() && cur.resumeItem) U.setResume(cur.resumeItem, cur.pos || 0, cur.dur || 0);
        upHide(); clearInterval(tick); clearTimeout(stallT); clearTimeout(retryT); stopAv();
        document.documentElement.className = '';
        extOff(); cur = null; setInfo(false); subEl.textContent = ''; hideLoad();
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
        seekAcc += ms; setInfo(true); progress();
        clearTimeout(seekT);
        seekT = setTimeout(function () {
            var target;
            try { target = Math.max(0, webapis.avplay.getCurrentTime() + seekAcc); webapis.avplay.seekTo(target); } catch (e) { U.log({ ev: 'seek.error', err: String(e) }); }
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
        var t = scrub; scrub = null; streak = 0;
        var go = function () { try { webapis.avplay.play(); } catch (e) { /* idle */ } };
        try { webapis.avplay.seekTo(t, go, go); } catch (e) { U.log({ ev: 'seek.error', err: String(e) }); go(); }
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
    function togglePause() {
        if (!av()) return;
        try { if (playing()) webapis.avplay.pause(); else webapis.avplay.play(); } catch (e) { /* idle */ }
        setInfo(true);
    }
    function press(id) {
        if (id === 'back10') seek(-10000);
        else if (id === 'fwd10') seek(10000);
        else if (id === 'play') togglePause();
        else if (id === 'audio') openMenu('audio');
        else if (id === 'subs') openMenu('subs');
        else if (id === 'next' && cur.next) { var n = cur.next; exit(true); n(); }
    }
    // Returns true when the key was used.
    function key(c) {
        if (!cur) return false;
        if (upShown()) {
            if (c === 13) { upGo(); return true; }
            if (c === 10009 || c === 8) { upHide(); return true; }
        }
        if (c === 10009 || c === 8 || c === 413) {                       // Back, Stop
            if (scrub !== null) { cancelScrub(); return true; }
            if (menu) { closeMenu(); setInfo(true); return true; }
            if (onNext) { onNext = false; onBar = true; setInfo(true); return true; }
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
            if (c === 38 && mSel > 0) { mSel--; drawMenu(); }
            else if (c === 40 && mSel < menu.list.length - 1) { mSel++; drawMenu(); }
            else if (c === 13) pick();
            else if (c === 37 || c === 39) { closeMenu(); setInfo(true); }
            return true;
        }
        if (!ctl) {
            if (c === 37 || c === 39) { onBar = true; scrubBy(c === 37 ? -1 : 1); }
            else if (c === 13) { ctl = true; onBar = false; btn = 1; setInfo(true); }
            else if (c === 38 || c === 40) { ctl = true; onBar = true; setInfo(true); progress(); }
            return true;
        }
        if (onNext) {
            if (c === 13) { press('next'); return true; }
            if (c === 40) { onNext = false; onBar = true; setInfo(true); progress(); return true; }
            return true;
        }
        if (onBar) {
            if (c === 37 || c === 39) scrubBy(c === 37 ? -1 : 1);
            else if (c === 13) { if (scrub !== null) commitScrub(); else togglePause(); }
            else if (c === 40) { commitScrub(); onBar = false; btn = 1; setInfo(true); progress(); }
            else if (c === 38) { commitScrub(); if (cur.next) { onBar = false; onNext = true; ctl = true; setInfo(true, true); } else setInfo(false); }
            return true;
        }
        var n = buttons().length;
        if (c === 37 && btn > 0) btn--;
        else if (c === 39 && btn < n - 1) btn++;
        else if (c === 13) { press(buttons()[btn].id); return true; }
        else if (c === 38) { onBar = true; setInfo(true); progress(); return true; }
        else if (c === 40) { setInfo(false); return true; }
        setInfo(true);
        return true;
    }
    // ---------- next episode card, Netflix style: shows UP_AT before the end, plays the next one after UP_COUNT s ----------
    var UP_AT = 40000, UP_COUNT = 10, upEl = null, upLeft = 0, upT = null;
    function upShown() { return upLeft > 0; }
    function upCheck(p, d) {
        if (upShown() || !cur || !cur.next || cur.upDone || !(d > UP_AT * 2) || d - p > UP_AT || scrub !== null) return;
        cur.upDone = true; upLeft = UP_COUNT; upDraw();
        upT = setInterval(function () { upLeft--; if (upLeft <= 0) upGo(); else upDraw(); }, 1000);
    }
    function upDraw() {
        upEl.innerHTML = '<div class="uh">Next episode</div><div class="un">' + U.esc(cur.nextName || '') + '</div>' +
            '<div class="ub focus">&#9654;&nbsp; Play now &middot; ' + upLeft + '</div><div class="uk">Back to keep watching</div>';
        upEl.className = 'upnext show';
    }
    function upHide() { clearInterval(upT); upT = null; upLeft = 0; if (upEl) { upEl.className = 'upnext'; upEl.innerHTML = ''; } }
    function upGo() { upHide(); if (cur && cur.next) { var n = cur.next; exit(true); n(); } }
    function init(exitCb) {
        el = U.$('player'); info = el.querySelector('.info'); busy = el.querySelector('.busy'); onExit = exitCb;
        subEl = U.$('subs'); panel = U.$('tpanel');
        upEl = document.createElement('div'); upEl.className = 'upnext'; el.appendChild(upEl);
        document.addEventListener('visibilitychange', function () {
            if (document.hidden && cur) exit();
        });
    }
    // The next episode found after playback started (resume from Continue watching).
    function setNext(item, fn, name) { if (cur !== item) return; cur.next = fn; cur.nextName = name || ''; drawNext(); }
    function setSubsItem(item, o) { if (cur === item) cur.osub = o; }
    return { init: init, start: start, key: key, setNext: setNext, setSubsItem: setSubsItem, active: function () { return !!cur; } };
})();
