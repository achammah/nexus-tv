#!/usr/bin/env python3
"""Copy a country's provider-hosted channel logos into the app (img/logos/<cc>/) and point data/live-<cc>.json at them,
so the Frame shows them even when the provider's logo server does not answer. Usage: tools/bundle_logos.py be"""
import json, os, re, sys, urllib.request, concurrent.futures as cf
cc = sys.argv[1]; root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, 'data', 'live-%s.json' % cc); out = os.path.join(root, 'img', 'logos', cc); os.makedirs(out, exist_ok=True)
d = json.load(open(path))
def local(u): return re.sub(r'[^A-Za-z0-9._-]', '_', u.split('/')[-1]) or 'x.png'
icons = sorted({c[1] for c in d['c'] if c[1] and re.match(r'^https?://', c[1])})
def get(u):
    f = os.path.join(out, local(u))
    if os.path.exists(f) and os.path.getsize(f) > 0: return u, True
    try:
        b = urllib.request.urlopen(u, timeout=10).read()
        if len(b) < 64 or not (b[:4] == b'\x89PNG' or b[:3] == b'\xff\xd8\xff'): return u, False
        open(f, 'wb').write(b); return u, True
    except Exception: return u, False
ok = {}
with cf.ThreadPoolExecutor(8) as ex:
    for u, good in ex.map(get, icons): ok[u] = good
n = 0
for c in d['c']:
    if c[1] in ok and ok[c[1]]: c[1] = 'img/logos/%s/%s' % (cc, local(c[1])); n += 1
json.dump(d, open(path, 'w'), separators=(',', ':'), ensure_ascii=False)
print('icons', len(icons), 'saved', sum(ok.values()), 'channels pointed local', n)

# Home's own data (data/home.json) carries the same channels: point its logos at the bundled copies too
hp = os.path.join(root, 'data', 'home.json')
if os.path.exists(hp):
    files = set(os.listdir(out)); h = json.load(open(hp)); moved = [0]
    def walk(o):
        if isinstance(o, list):
            for i, v in enumerate(o):
                if isinstance(v, str) and v.startswith('http') and local(v) in files and v in ok: o[i] = 'img/logos/%s/%s' % (cc, local(v)); moved[0] += 1
                else: walk(v)
        elif isinstance(o, dict):
            for v in o.values(): walk(v)
    walk(h); json.dump(h, open(hp, 'w'), separators=(',', ':'), ensure_ascii=False); print('home.json logos pointed local', moved[0])

# img/logos/<cc>/index.js: the bundled file names, so a saved remote logo (favourites) maps to its local copy
names = sorted(f for f in os.listdir(out) if f.lower().endswith(('.png', '.jpg')))
open(os.path.join(out, 'index.js'), 'w').write('// bundled %s logos by file name (tools/bundle_logos.py)\nwindow.LOGOS_LOCAL=window.LOGOS_LOCAL||{};(function(){var a=%s;for(var i=0;i<a.length;i++)window.LOGOS_LOCAL[a[i]]="img/logos/%s/"+a[i];})();\n' % (cc, json.dumps(names), cc))
