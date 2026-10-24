"""Fill missing channel logos in data/live-*.json.

1. Twin reuse: the same cleaned name in the same country borrows the logo of its twin that has one.
2. iptv-org match: https://iptv-org.github.io/api/channels.json + logos.json. Exact cleaned name or alt name,
   same country first (a name that exists in one country only may match across countries), widest logo.
Whatever stays empty gets the wordmark tile at runtime (js/util.js wordmark).
Usage: python3 tools/fill_logos.py [--refresh]      (build_data.py calls apply() after writing the live files)
"""
import json
import os
import re
import sys
import urllib.request

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(APP, 'data')
CACHE = os.path.join(APP, '.cache')
ORG = {'be': 'BE', 'fr': 'FR', 'uk': 'GB', 'us': 'US'}      # iptv-org uses GB for the UK
API = 'https://iptv-org.github.io/api/'


def clean(name):
    n = re.sub(r'^\s*[A-Za-z]{2,3}\s*\([^)]*\)\s*', '', name or '')           # "US (P+) "
    n = re.sub(r'\[[^\]]*\]|\([^)]*\)', ' ', n)
    n = re.sub(r'^\s*[A-Za-z]{2,4}\s*[:|]\s*', '', n)                       # "US:", "ENF|"
    n = re.sub(r'\b(FHD|UHD|HD|SD|HEVC|4K|LQ|RAW|VIP)\b', ' ', n, flags=re.I)
    return re.sub(r'\s+', ' ', n).strip()


def key(name):
    return re.sub(r'[^a-z0-9]+', '', clean(name).lower())


def fetch(name, refresh):
    path = os.path.join(CACHE, 'iptv-org-' + name)
    if refresh or not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        req = urllib.request.Request(API + name, headers={'User-Agent': 'Mozilla/5.0'})
        open(path, 'wb').write(urllib.request.urlopen(req, timeout=120).read())
    return json.load(open(path))


def widest(logos):
    best = None
    for l in logos:
        if not l.get('in_use', True) or not l.get('url'):
            continue
        if best is None or (l.get('width') or 0) > (best.get('width') or 0):
            best = l
    return best


def apply(data_dir=DATA, refresh=False):
    channels, logos = fetch('channels.json', refresh), fetch('logos.json', refresh)
    by_ch = {}
    for l in logos:
        by_ch.setdefault(l['channel'], []).append(l)
    index = {}                       # cleaned key -> [channel]
    for c in channels:
        if not by_ch.get(c['id']):
            continue
        for nm in [c['name']] + (c.get('alt_names') or []):
            k = key(nm)
            if len(k) >= 3 and c not in index.setdefault(k, []):
                index[k].append(c)
    report = {}
    for cc, org in ORG.items():
        path = os.path.join(data_dir, 'live-%s.json' % cc)
        d = json.load(open(path))
        rows = d['c']
        before = sum(1 for r in rows if not r[1])
        twin = {}
        for r in rows:
            if r[1] and len(key(r[0])) >= 3:
                twin.setdefault(key(r[0]), r)
        n_twin = n_org = 0
        for r in rows:
            if r[1]:
                continue
            k = key(r[0])
            if len(k) < 3:
                continue
            if k in twin:
                r[1], r[4] = twin[k][1], twin[k][4]; n_twin += 1; continue
            cands = index.get(k, [])
            same = [c for c in cands if c['country'] == org]
            pick = same[0] if same else (cands[0] if len(cands) == 1 else None)
            if not pick:
                continue
            best = widest(by_ch[pick['id']])
            if not best:
                continue
            r[1] = best['url']
            r[4] = 1 if set(best.get('tags') or []) & {'black', 'dark'} else 0     # dark logo: the tile turns light
            twin[k] = r; n_org += 1
        json.dump(d, open(path, 'w'), ensure_ascii=False, separators=(',', ':'))
        report[cc] = (len(rows), before, n_twin, n_org, sum(1 for r in rows if not r[1]))
    return report


def patch_home(data_dir=DATA):
    """home.json carries copies of the first live rows: refresh their logos from the live files."""
    hp = os.path.join(data_dir, 'home.json')
    if not os.path.exists(hp):
        return
    h = json.load(open(hp))
    for cc in ORG:
        d = json.load(open(os.path.join(data_dir, 'live-%s.json' % cc)))
        by = {r[3]: r for r in d['c']}
        for it in h.get('live', {}).get(cc, {}).get('c', []):
            r = by.get(it[3])
            if r and r[1] and not it[1]:
                it[1], it[4] = r[1], r[4]
    json.dump(h, open(hp, 'w'), ensure_ascii=False, separators=(',', ':'))


# ---------- stage 3: online lookups for what is still empty (build time, cached) ----------
import time
import urllib.parse
UA = 'NexusTVLogoBuild/0.1 (https://github.com/achammah/nexus-tv)'
LOOKUPS = os.path.join(CACHE, 'logo-lookups.json')
ESPN_PLUS = 'https://raw.githubusercontent.com/tv-logo/tv-logos/main/misc/media/espn-plus.png'
SPORT_OF = [(r'FORMULA 1|MOTOGP|SUPERCROSS|TT RACE', ('Motorsport',)), (r'PDC|DARTS', ('Darts',)), (r'BOXING|UFC|PAY PER VIEW', ('Fighting', 'Boxing')),
            (r'SERIE A|LIGUE 1|CUP GAMES|EPL|VIAPLAY|FA PLAYER|MOLA|EUROSPORT', ('Soccer',)), (r'GAA', ('Gaelic Football', 'Hurling', 'Gaelic Games')), (r'SUPER LEAGUE', ('Rugby',))]
_last = {}


def http(url, gap):
    host = urllib.parse.urlparse(url).netloc
    w = _last.get(host, 0) + gap - time.time()
    if w > 0:
        time.sleep(w)
    _last[host] = time.time()
    try:
        return json.load(urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=25))
    except Exception:
        return None


def norm(s):
    return re.sub(r'[^a-z0-9]', '', (s or '').lower())


def sdb_badge(team, sports):
    d = http('https://www.thesportsdb.com/api/v1/json/123/searchteams.php?t=' + urllib.parse.quote(team), 2.5)
    for t in (d or {}).get('teams') or []:
        if norm(t.get('strTeam')) != norm(team):                 # exact team name only
            continue
        if sports and t.get('strSport') not in sports:           # reject sport mismatches
            continue
        return t.get('strBadge') or t.get('strLogo') or ''
    return ''


def wiki_thumb(q):
    s = http('https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=1&srsearch=' + urllib.parse.quote(q), 1.05)
    try:
        title = s['query']['search'][0]['title']
    except Exception:
        return ''
    if norm(q) not in norm(title):                                # the page title must contain the cleaned name
        return ''
    d = http('https://en.wikipedia.org/api/rest_v1/page/summary/' + urllib.parse.quote(title.replace(' ', '_')), 1.05)
    if not d or d.get('type') == 'disambiguation':
        return ''
    return (d.get('thumbnail') or {}).get('source') or ''


def plan(name, group):
    """-> (stage, [queries]) for a channel the first two stages left empty; None keeps the wordmark."""
    n, g = name or '', (group or '').upper()
    if re.match(r'\s*ESPN\s*(PLUS|\+)', n, re.I):
        return ('espn', [])
    sports = ()
    for pat, sp in SPORT_OF:
        if re.search(pat, g):
            sports = sp; break
    if g.startswith('24/7'):
        q = re.sub(r'^24/7\s+', '', clean(n))
        q = re.sub(r'^(THE)\s+', '', q, flags=re.I).title()
        return ('wiki', [q]) if len(norm(q)) >= 4 and not re.match(r'(NETFLIX|DISNEY\+|AMAZON|APPLE)', q, re.I) else None
    if sports or re.search(r'\bvs\.?\b', n, re.I):
        m = re.search(r'(?:[-|]\s*)?([^|\-:]+?)\s+vs\.?\s+([^|\-:\d]+?)(?:\s+\d{1,2}[:.]\d\d.*)?$', clean(n), re.I)
        if m:
            teams = [m.group(1).strip(), m.group(2).strip()]
        else:
            m = re.match(r'[A-Z0-9 ]+\|\s*([A-Za-z][^|]+?)\s*$', clean(n))
            teams = [m.group(1).strip().title()] if m else []
        teams = [t for t in teams if len(norm(t)) >= 4]
        return ('team', teams, sports) if teams else None
    return None


_idx = None
CF = {'uk': 'united-kingdom', 'us': 'united-states', 'be': 'belgium', 'fr': 'france'}


def n2(s):
    return re.sub(r'[^a-z0-9+]', '', (s or '').lower().replace('&', 'and').replace('+', 'plus'))


def exact_index():
    """jaruba/channel-logos (name -> TMDB path) and tv-logo/tv-logos (file stem); exact normalised names only."""
    global _idx
    if _idx:
        return _idx
    jp, tp = os.path.join(CACHE, 'jaruba-logo_paths.json'), os.path.join(CACHE, 'tvlogos-tree.json')
    os.makedirs(CACHE, exist_ok=True)
    if not os.path.exists(jp):
        open(jp, 'w').write(json.dumps(http('https://jaruba.github.io/channel-logos/logo_paths.json', 1) or {}))
    if not os.path.exists(tp):
        open(tp, 'w').write(json.dumps(http('https://api.github.com/repos/tv-logo/tv-logos/git/trees/main?recursive=1', 1) or {}))
    j = {n2(k): v for k, v in json.load(open(jp)).items()}
    tv = {}
    for x in json.load(open(tp)).get('tree', []):
        p = x['path']
        if not p.endswith('.png'):
            continue
        parts = p.split('/')
        stem = re.sub(r'-(hd|4k|sd)$', '', re.sub(r'-(uk|us|ie|de|fr|ca|au|it|es|nl|be|tr|pl|gr)$', '', parts[-1].rsplit('.', 1)[0]))
        folder = parts[1] if parts[0] == 'countries' and len(parts) > 2 else ''
        tv.setdefault(n2(stem), []).append((folder, p))
    _idx = (j, tv)
    return _idx


def exact_logo(name, cc):
    j, tv = exact_index()
    q = re.sub(r'\s*\d+\s*:?\s*$', '', clean(name))
    if re.match(r'ESPN\s*(PLUS|\+)', q, re.I):
        q = 'ESPN+'
    k = n2(q)
    if len(k) < 4:
        return ''
    if k in j:
        return 'https://jaruba.github.io/channel-logos/export/transparent-color' + j[k]
    if k in tv:
        c = sorted(tv[k], key=lambda t: t[0] != CF.get(cc))[0]
        return 'https://raw.githubusercontent.com/tv-logo/tv-logos/main/' + urllib.parse.quote(c[1])
    return ''


_snp = None
PICONS = 'https://raw.githubusercontent.com/picons/picons/master/build-source/'


def picon(name, group):
    """picons build-source/snp.index: normalised name -> logo stem. Exact only; brand-only rows (F1 drivers, event feeds) are skipped.
    The image is linked at runtime from picons (GPL-3.0), never copied here."""
    global _snp
    if re.search(r'FORMULA 1|EVENT|KETOP', (group or '').upper() + ' ' + (name or '').upper()):
        return ''
    if _snp is None:
        p = os.path.join(CACHE, 'picons-snp.index')
        if not os.path.exists(p):
            os.makedirs(CACHE, exist_ok=True)
            open(p, 'wb').write(urllib.request.urlopen(urllib.request.Request(PICONS + 'snp.index', headers={'User-Agent': UA}), timeout=60).read())
        _snp = {}
        for ln in open(p, encoding='utf-8', errors='ignore'):
            if '=' in ln:
                a, b = ln.strip().split('=', 1); _snp.setdefault(a, b)
    k = re.sub(r'[^a-z0-9]', '', clean(name).lower())
    stem = _snp.get(k) if len(k) >= 5 else None
    if not stem:
        return ''
    lk = LOOKUPS + '.picons'
    c = json.load(open(lk)) if os.path.exists(lk) else {}
    if stem not in c:
        c[stem] = ''
        for ext in ('default.svg', 'default.png', 'default.jpg'):
            try:
                urllib.request.urlopen(urllib.request.Request(PICONS + 'logos/%s.%s' % (stem, ext), method='HEAD', headers={'User-Agent': UA}), timeout=20)
                c[stem] = PICONS + 'logos/%s.%s' % (stem, ext); break
            except Exception:
                pass
        json.dump(c, open(lk, 'w'))
    return c[stem]


LEAGUES = ('afcchampionsleague', 'premierleague', 'uefachampionsleague')


def logopedia(cc, name):
    """Logopedia, linked at runtime. Exact page title = the cleaned channel name; a league logo only when the feed name contains the league name."""
    global _lp
    try:
        _lp
    except NameError:
        _lp = json.load(open(os.path.join(APP, 'tools', 'logo-map-logopedia.json')))
    e = _lp.get(cc, {}).get(name)
    if not e:
        return ''
    q = re.sub(r'^24/7\s+', '', clean(name))
    q = re.sub(r'\s*\d+\s*$', '', re.sub(r'\b4k\b', '', q, flags=re.I)).strip()
    page = norm(e['page'])
    if norm(q) == page:
        return e['url']
    for lg in LEAGUES:
        if lg in norm(q) and page.startswith(lg):
            return e['url']
    return ''


def mapped(cc, name):
    """Exact raw name -> URL from tools/logo-map.json (measured matches in picons, mediaportal-uk-logos, IPTV-Logos; linked, never copied)."""
    global _map
    try:
        _map
    except NameError:
        _map = json.load(open(os.path.join(APP, 'tools', 'logo-map.json')))
    return _map.get(cc, {}).get(name, '')


def online(data_dir=DATA, budget=600):
    cache = json.load(open(LOOKUPS)) if os.path.exists(LOOKUPS) else {}
    t0 = time.time()
    found = {}; ex_n = {}
    for cc in ORG:
        path = os.path.join(data_dir, 'live-%s.json' % cc)
        d = json.load(open(path)); n = 0; examples = []
        for r in d['c']:
            if r[1]:
                continue
            url = mapped(cc, r[0]) or exact_logo(r[0], cc) or picon(r[0], d['g'][r[2]]) or logopedia(cc, r[0])
            if url:
                r[1] = url; n += 1; ex_n[cc] = ex_n.get(cc, 0) + 1
                if len(examples) < 40: examples.append((r[0], url))
                continue
            p = plan(r[0], d['g'][r[2]])
            if not p:
                continue
            url = ''
            if p[0] == 'espn':
                url = ESPN_PLUS
            else:
                for q in p[1]:
                    key = p[0] + ':' + q + ':' + ','.join(p[2] if len(p) > 2 else ())
                    if key not in cache:
                        if time.time() - t0 > budget:
                            break
                        cache[key] = (sdb_badge(q, p[2]) or wiki_thumb(q)) if p[0] == 'team' else wiki_thumb(q)
                        json.dump(cache, open(LOOKUPS, 'w'))
                    if cache[key]:
                        url = cache[key]; break
            if url:
                r[1] = url; n += 1
                if len(examples) < 40:
                    examples.append((r[0], url))
        json.dump(d, open(path, 'w'), ensure_ascii=False, separators=(',', ':'))
        found[cc] = (n, examples)
    print('exact (jaruba, tv-logos):', ex_n)
    return found


if __name__ == '__main__':
    rep = apply(refresh='--refresh' in sys.argv)
    if '--online' in sys.argv:
        on = online()
        for cc, (n, ex) in on.items():
            print('online %s: %d found' % (cc.upper(), n))
            for e in ex[:6]: print('   ', e[0][:60], '->', e[1][:80])
    patch_home()
    for cc, (n, before, t, o, left) in rep.items():
        print('%s: %d channels, %d without logo, twin %d, iptv-org %d, wordmark %d' % (cc.upper(), n, before, t, o, left))
