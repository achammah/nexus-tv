"""Build the Live TV app's data files from the provider API.

Reads the login from ~/.nexus-secrets/tvapp-iptv.key (3 lines: server URL, username, password).
Writes data/*.json (no login inside) and data/config.js (login, git-ignored).
Usage: python3 -I tools/build_data.py [--refresh]
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(APP, '.cache')
DATA = os.path.join(APP, 'data')
COUNTRIES = ['BE', 'FR', 'UK', 'US']
FILM_TAGS = ('EN', 'FR', 'MULTI', None)      # None = untagged groups (Netflix, Disney+, Top IMDB)
SERIES_TAGS = ('EN', 'FR', 'MULTI', None)
TMDB = 'https://image.tmdb.org/t/p/'

os.umask(0o077)
key = [l.strip() for l in open(os.path.expanduser('~/.nexus-secrets/tvapp-iptv.key')).read().splitlines() if l.strip()]
BASE, USER, PASS = key[0].rstrip('/'), key[1], key[2]


def api(action):
    path = os.path.join(CACHE, action + '.json')
    if os.path.exists(path) and '--refresh' not in sys.argv:
        return json.load(open(path))
    url = BASE + '/player_api.php?' + urllib.parse.urlencode({'username': USER, 'password': PASS, 'action': action})
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    body = json.load(urllib.request.urlopen(req, timeout=300))
    os.makedirs(CACHE, exist_ok=True)
    json.dump(body, open(path, 'w'))
    return body


def tag(cat_name):
    m = re.match(r'\s*\|\s*([A-Z]+)\s*\|', cat_name or '')
    return m.group(1) if m else None


def clean_cat(name):
    name = re.sub(r'^\s*\|\s*[A-Z]+\s*\|\s*', '', name or '')
    name = re.sub(r'^\s*[A-Z]{2}\s*\|\s*', '', name)
    name = re.sub(r'[ᴀ-ᶿ⁰-₟ʰ-˿]+', '', name)   # superscript decorations
    return re.sub(r'\s+', ' ', name).strip()


def clean_title(name):
    name = re.sub(r'^\s*[A-Z]{2,3}\s*-\s*', '', name or '')        # "EN - ", "NF - "
    name = re.sub(r'^\s*[A-Z]{2}\s*\|\s*', '', name)               # "BE| "
    name = re.sub(r'[ᴀ-ᶿ⁰-₟ʰ-˿]+', '', name)
    name = re.sub(r'\s+-\s+UNCUT\b|\s+4K\b|\s+\([A-Z]{2}\)$', '', name)
    return re.sub(r'\s+', ' ', name).strip()


def short_img(url):
    """Shorten TMDB URLs to 'T:<file>' (the app picks the size); keep others as they are."""
    if not url:
        return ''
    m = re.match(r'https?://image\.tmdb\.org/t/p/[^/]+/(.+)$', url)
    if m:
        return 'T:' + m.group(1)
    return '' if 'image.tmdb.org' in url else url     # a bare TMDB base has no picture


def year_of(name):
    m = re.search(r'\((\d{4})\)', name or '')
    return m.group(1) if m else ''


def dump(name, obj):
    path = os.path.join(DATA, name)
    with open(path, 'w') as f:
        json.dump(obj, f, ensure_ascii=False, separators=(',', ':'))
    return os.path.getsize(path)


def main():
    os.makedirs(DATA, exist_ok=True)
    sizes = {}

    # ---- channel logos: verified map from work/frame-tv/logos (url + dark flag) ----
    meta_path = os.path.join(os.path.dirname(APP), 'logos', 'logos_meta.json')
    logos = json.load(open(meta_path)) if os.path.exists(meta_path) else {}

    # ---- live channels, one file per country ----
    live_cats = {c['category_id']: c['category_name'] for c in api('get_live_categories')}
    streams = sorted(api('get_live_streams'), key=lambda s: s.get('num') or 0)
    for cc in COUNTRIES:
        groups, gidx, rows = [], {}, []
        for s in streams:
            if str(s.get('is_adult')) == '1':
                continue
            cname = live_cats.get(s.get('category_id'), '')
            if not re.match(r'\s*%s\s*\|' % cc, cname):
                continue
            g = clean_cat(cname)
            if re.search(r'REPLAY', g, re.I):
                continue
            nm = clean_title(s.get('name'))
            if not nm or re.match(r'^[#=*\-_~|]{3,}', nm):
                continue
            if g not in gidx:
                gidx[g] = len(groups)
                groups.append(g)
            lm = logos.get(str(s['stream_id']))
            rows.append([nm, lm['url'] if lm else '', gidx[g], s['stream_id'], 1 if lm and lm.get('dark') else 0])
        # everyday channels first, pay-per-view and event feeds last (stable order otherwise)
        late = lambda g: 1 if re.search(r'PPV|VIP|EVENT|24/7|RAW|PLAY\b|PRIME|MAX|DAZN|ESPN|PACKAGE|NETWORK HULU', g) else 0
        order = sorted(range(len(groups)), key=lambda i: (late(groups[i]), i))
        remap = {old: new for new, old in enumerate(order)}
        groups = [groups[i] for i in order]
        rows = [[r[0], r[1], remap[r[2]], r[3], r[4]] for r in rows]
        sizes['live-%s.json' % cc.lower()] = (dump('live-%s.json' % cc.lower(), {'g': groups, 'c': rows}), len(rows))

    # ---- logos for channels the verified map does not cover: twins, then iptv-org (tools/fill_logos.py) ----
    import importlib.util
    spec = importlib.util.spec_from_file_location('fill_logos', os.path.join(APP, 'tools', 'fill_logos.py'))
    fl = importlib.util.module_from_spec(spec); spec.loader.exec_module(fl)
    for cc, (n, before, t, o, left) in fl.apply(DATA, '--refresh' in sys.argv).items():
        print('logos %s: %d without, twin %d, iptv-org %d, wordmark %d' % (cc.upper(), before, t, o, left))

    # ---- films and series categories + search index ----
    out = {'films': [], 'series': []}
    search = {'f': [], 's': []}
    for kind, ck, sk, idk, tags in [('films', 'get_vod_categories', 'get_vod_streams', 'stream_id', FILM_TAGS),
                                    ('series', 'get_series_categories', 'get_series', 'series_id', SERIES_TAGS)]:
        cats = api(ck)
        keep = {c['category_id']: c['category_name'] for c in cats if tag(c['category_name']) in tags}
        counts, art = {}, {}      # art: the first 4 pictures of each list, for its browse card
        for s in api(sk):
            cid = s.get('category_id')
            if cid not in keep or str(s.get('is_adult')) == '1':
                continue
            counts[cid] = counts.get(cid, 0) + 1
            img = short_img(s.get('stream_icon') if kind == 'films' else s.get('cover'))
            if img and len(art.setdefault(cid, [])) < 4:
                art[cid].append(img)
            title = clean_title(s.get('name'))
            if kind == 'films':
                search['f'].append([s[idk], title, img, cid, s.get('container_extension') or 'mp4'])
            else:
                search['s'].append([s[idk], title, img, cid])
        for c in cats:
            if c['category_id'] in keep and counts.get(c['category_id']):
                lang = tag(c['category_name']) or ''
                out[kind].append([c['category_id'], clean_cat(c['category_name']), counts[c['category_id']], lang, art.get(c['category_id'], [])])
    sizes['library.json'] = (dump('library.json', out), len(out['films']) + len(out['series']))
    sizes['search.json'] = (dump('search.json', search), len(search['f']) + len(search['s']))

    # every other language too (names only, no pictures): searched after the main index
    more, li = {'f': [], 's': [], 'langs': []}, {}
    for kind, ck, sk, idk, key in [('films', 'get_vod_categories', 'get_vod_streams', 'stream_id', 'f'),
                                   ('series', 'get_series_categories', 'get_series', 'series_id', 's')]:
        cats = {c['category_id']: c['category_name'] for c in api(ck)}
        for x in api(sk):
            if str(x.get('is_adult')) == '1':
                continue
            t = tag(cats.get(x.get('category_id'), ''))
            if t in FILM_TAGS:
                continue
            if t not in li:
                li[t] = len(more['langs'])
                more['langs'].append(t)
            row = [x[idk], clean_title(x.get('name')), li[t]]
            if key == 'f':
                row.append(x.get('container_extension') or 'mp4')
            more[key].append(row)
    # live channels of every country without its own bundled list
    more['c'] = []
    live_cats = {c['category_id']: c['category_name'] for c in api('get_live_categories')}
    for x in api('get_live_streams'):
        if str(x.get('is_adult')) == '1':
            continue
        m = re.match(r'\s*([A-Z0-9]{2,5})\s*\|', live_cats.get(x.get('category_id'), '') or '')
        code = m.group(1) if m else ''
        if code in COUNTRIES:
            continue
        nm = clean_title(x.get('name'))
        if not nm or re.match(r'^[#=*\-_~|]{3,}', nm):
            continue
        if code not in li:
            li[code] = len(more['langs'])
            more['langs'].append(code)
        more['c'].append([x['stream_id'], nm, li[code]])
    sizes['search-more.json'] = (dump('search-more.json', more), len(more['f']) + len(more['s']) + len(more['c']))

    # ---- home: featured hero + rows ----
    vod_cats = {c['category_name']: c['category_id'] for c in api('get_vod_categories')}
    ser_cats = {c['category_name']: c['category_id'] for c in api('get_series_categories')}
    def first_cat(names, table):
        for n in names:
            if n in table:
                return table[n]
    new_cid = first_cat(['|EN| NEW RELEASED'], vod_cats)
    top_cid = first_cat(['|EN| TOP SERIES'], ser_cats)
    seen, new_films = set(), []
    for s in api('get_vod_streams'):
        t = clean_title(s.get('name'))
        if s.get('category_id') == new_cid and s.get('stream_icon') and t not in seen:
            seen.add(t)
            new_films.append([s['stream_id'], t, short_img(s['stream_icon']), s.get('container_extension') or 'mp4'])
    top_series = [[s['series_id'], clean_title(s.get('name')), short_img(s.get('cover'))]
                  for s in api('get_series') if s.get('category_id') == top_cid and s.get('cover')]
    hero = []
    for s in api('get_series'):
        back = (s.get('backdrop_path') or [None])[0] or ''
        if s.get('category_id') in keep_series_ids(api) and 'tmdb' in back and s.get('plot') and str(s.get('rating') or '0')[:1] in '789':
            hero.append({'kind': 'series', 'id': s['series_id'], 't': clean_title(re.sub(r'\s*\(.*$', '', s['name'])),
                         'year': (s.get('releaseDate') or s.get('release_date') or '')[:4],
                         'genre': (s.get('genre') or '').split('/')[0].split(',')[0].strip(),
                         'rating': str(s.get('rating') or ''), 'plot': s.get('plot'), 'back': short_img(back),
                         'img': short_img(s.get('cover'))})
        if len(hero) >= 5:
            break
    live_rows = {}
    for cc in COUNTRIES:
        d = json.load(open(os.path.join(DATA, 'live-%s.json' % cc.lower())))
        seen, items = set(), []
        for gi in range(len(d['g'])):
            for c in d['c']:
                if c[2] != gi or len(items) >= 24:
                    continue
                k = re.sub(r'\s+(fhd|uhd|hd|sd|hevc|4k|raw|vip)\b', '', c[0].lower()).strip()
                if k in seen:
                    continue
                seen.add(k)
                items.append([c[0], c[1], d['g'][gi], c[3], c[4]])
            if len(items) >= 24:
                break
        live_rows[cc.lower()] = {'n': len(d['c']), 'c': items}
    sizes['home.json'] = (dump('home.json', {'hero': hero, 'newFilms': new_films[:30], 'topSeries': top_series[:30], 'live': live_rows}), len(hero))

    # ---- login for the app (git-ignored) ----
    with open(os.path.join(DATA, 'config.js'), 'w') as f:
        f.write('window.IPTV=%s;\n' % json.dumps({'base': BASE, 'user': USER, 'pass': PASS}))
        osk = os.path.expanduser('~/.nexus-secrets/opensubtitles.key')   # key, username, password (optional)
        if os.path.exists(osk):
            k = [l.strip() for l in open(osk).read().splitlines() if l.strip()] + ['', '']
            f.write('window.OSUB=%s;\n' % json.dumps({'key': k[0], 'user': k[1], 'pass': k[2]}))
    for k, (b, n) in sizes.items():
        print('%-16s %8d KB  %6d entries' % (k, b // 1024, n))


_series_keep = None
def keep_series_ids(api_fn):
    global _series_keep
    if _series_keep is None:
        _series_keep = {c['category_id'] for c in api_fn('get_series_categories') if tag(c['category_name']) in SERIES_TAGS}
    return _series_keep


if __name__ == '__main__':
    main()
