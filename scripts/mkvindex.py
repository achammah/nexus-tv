"""Reference subtitle starts of a provider film from its Matroska index (Cues), like Shared/Core/SubAutoSync.swift."""
import os, urllib.request
def _acct():
    k = [l.strip() for l in open(os.path.expanduser(os.environ['NXTV_ACCOUNT_FILE'])) if l.strip()]
    b = k[0].rstrip('/'); b = b if '://' in b else 'http://' + b
    return b, k[1], k[2]
def _rng(u, a, n):
    r = urllib.request.Request(u, headers={'Range': 'bytes=%d-%d' % (a, a + n - 1), 'User-Agent': 'VLC/3.0'})
    with urllib.request.urlopen(r, timeout=30) as f: return f.read()
def _vint(b, i, keep):
    x = b[i]; n = 1
    while n <= 8 and not (x & (0x80 >> (n - 1))): n += 1
    v = x if keep else x & (0xFF >> n)
    for j in range(1, n): v = (v << 8) | b[i + j]
    return v, n
def _kids(b, i, end):
    while i < min(end, len(b)):
        e, l1 = _vint(b, i, True); s, l2 = _vint(b, i + l1, False)
        unk = s == (1 << (7 * l2)) - 1
        yield e, i + l1 + l2, (None if unk else s)
        if unk: return
        i += l1 + l2 + s
def _num(b): 
    v = 0
    for x in b: v = (v << 8) | x
    return v
def reference_starts(fid, ext):
    base, user, pw = _acct()
    u = '%s/movie/%s/%s/%s.%s' % (base, user, pw, fid, ext)
    h = _rng(u, 0, 256 * 1024)
    seg = next(p for e, p, s in _kids(h, 0, len(h)) if e == 0x18538067)
    seek, tracks, scale = {}, [], 1000000
    for e, p, s in _kids(h, seg, len(h)):
        if s is None: break
        if e == 0x114D9B74:
            for e2, p2, s2 in _kids(h, p, p + s):
                if e2 == 0x4DBB:
                    d = {e3: _num(h[p3:p3 + s3]) for e3, p3, s3 in _kids(h, p2, p2 + s2)}
                    seek[d.get(0x53AB)] = d.get(0x53AC)
        if e == 0x1549A966:
            for e2, p2, s2 in _kids(h, p, p + s):
                if e2 == 0x2AD7B1: scale = _num(h[p2:p2 + s2])
        if e == 0x1654AE6B:
            for e2, p2, s2 in _kids(h, p, p + s):
                if e2 != 0xAE: continue
                t = {'lang': 'eng'}
                for e3, p3, s3 in _kids(h, p2, p2 + s2):
                    if e3 == 0xD7: t['n'] = _num(h[p3:p3 + s3])
                    if e3 == 0x83: t['type'] = _num(h[p3:p3 + s3])
                    if e3 == 0x22B59C: t['lang'] = h[p3:p3 + s3].decode(errors='replace').strip('\x00')
                    if e3 == 0x86: t['codec'] = h[p3:p3 + s3].decode(errors='replace')
                if t.get('type') == 0x11 and t.get('codec', '').startswith(('S_TEXT', 'S_ASS', 'S_SSA')): tracks.append(t)
        if e == 0x1F43B675: break
    c = seek[0x1C53BB6B]
    top = _rng(u, seg + c, 16); _, l1 = _vint(top, 0, True); size, l2 = _vint(top, l1, False)
    body = _rng(u, seg + c + l1 + l2, size)
    by = {}
    want = {t['n'] for t in tracks}
    for e, p, s in _kids(body, 0, len(body)):
        if e != 0xBB: continue
        ct, trs = 0, []
        for e2, p2, s2 in _kids(body, p, p + s):
            if e2 == 0xB3: ct = _num(body[p2:p2 + s2])
            if e2 == 0xB7: trs += [_num(body[p3:p3 + s3]) for e3, p3, s3 in _kids(body, p2, p2 + s2) if e3 == 0xF7]
        for t in trs:
            if t in want: by.setdefault(t, []).append(ct * scale // 1000000)
    full = [t for t in tracks if len(by.get(t['n'], [])) >= 100] or tracks
    pick = next((t for t in full if t['lang'].startswith('en')), full[0])
    return sorted(set(by[pick['n']]))
