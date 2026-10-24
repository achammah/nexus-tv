"""Brand assets for both apps from the approved files in logo/final/ (rendered first with svg2png.swift):
  build/icon1024.png  app-icon.svg at 1024 (black rounded tile + mark)
  build/mark1024.png  the same SVG without the tile, 2048 px (the mark alone, transparent)
  lockup.png          the opening's last frame (lockup on black)
Writes: tvOS layered app icon + top shelf, the macOS AppIcon set, and the header lockup (transparent) for both.
Usage: python3 -I scripts/art/make_brand.py <path to logo/final>
"""
import json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FINAL = sys.argv[1]
INFO = {'author': 'xcode', 'version': 1}
TV = os.path.join(ROOT, 'NexusTV/Assets.xcassets')
MAC = os.path.join(ROOT, 'MacApp/Assets.xcassets')
icon = Image.open(os.path.join(ROOT, 'build/icon1024.png')).convert('RGBA')
mark = Image.open(os.path.join(ROOT, 'build/mark1024.png')).convert('RGBA')
mark = mark.crop(mark.getbbox())


def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        json.dump(obj, f, indent=2)


# header lockup: crop the last frame to the lockup, black becomes transparent (alpha = brightness, colour un-premultiplied)
src = Image.open(os.path.join(FINAL, 'lockup.png')).convert('RGB')
bx = src.point(lambda v: 255 if v > 12 else 0).convert('L').getbbox()
pad = 8
src = src.crop((max(0, bx[0] - pad), max(0, bx[1] - pad), min(src.width, bx[2] + pad), min(src.height, bx[3] + pad)))
px = src.load()
lock = Image.new('RGBA', src.size)
lp = lock.load()
for y in range(src.height):
    for x in range(src.width):
        r, g, b = px[x, y]
        a = max(r, g, b)
        lp[x, y] = (0, 0, 0, 0) if a == 0 else (min(255, r * 255 // a), min(255, g * 255 // a), min(255, b * 255 // a), a)
for xc in (TV, MAC):
    d = os.path.join(xc, 'Lockup.imageset')
    os.makedirs(d, exist_ok=True)
    lock.save(os.path.join(d, 'lockup.png'))
    write(os.path.join(d, 'Contents.json'), {'images': [{'idiom': 'universal', 'filename': 'lockup.png', 'scale': '1x'}], 'info': INFO,
                                             'properties': {'preserves-vector-representation': False}})


def layer_set(stack, w, h, scales, front_scale):
    """A tvOS image stack: Back = black, Front = the mark centred."""
    for layer in ('Back', 'Front'):
        d = os.path.join(stack, layer + '.imagestacklayer', 'Content.imageset')
        os.makedirs(d, exist_ok=True)
        imgs = []
        for s in scales:
            W, H = w * s, h * s
            if layer == 'Back':
                im = Image.new('RGBA', (W, H), (0, 0, 0, 255))
            else:
                im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                mh = int(H * front_scale)
                m = mark.resize((int(mark.width * mh / mark.height), mh), Image.LANCZOS)
                im.alpha_composite(m, ((W - m.width) // 2, (H - m.height) // 2))
            n = '%s%s.png' % (layer.lower(), '' if s == 1 else '@%dx' % s)
            im.save(os.path.join(d, n))
            imgs.append({'idiom': 'tv', 'filename': n, 'scale': '%dx' % s})
        write(os.path.join(d, 'Contents.json'), {'images': imgs, 'info': INFO})
        write(os.path.join(stack, layer + '.imagestacklayer', 'Contents.json'), {'info': INFO})
    write(os.path.join(stack, 'Contents.json'), {'info': INFO, 'layers': [{'filename': 'Front.imagestacklayer'}, {'filename': 'Back.imagestacklayer'}]})


BA = os.path.join(TV, 'App Icon & Top Shelf Image.brandassets')
layer_set(os.path.join(BA, 'App Icon.imagestack'), 400, 240, [1, 2], 0.62)
layer_set(os.path.join(BA, 'App Icon - App Store.imagestack'), 1280, 768, [1], 0.62)


def shelf(name, w, h):
    d = os.path.join(BA, name + '.imageset')
    imgs = []
    for s in (1, 2):
        W, H = w * s, h * s
        im = Image.new('RGBA', (W, H), (0, 0, 0, 255))
        lh = int(H * 0.30)
        l = lock.resize((int(lock.width * lh / lock.height), lh), Image.LANCZOS)
        im.alpha_composite(l, ((W - l.width) // 2, (H - l.height) // 2))
        n = 'shelf%s.png' % ('' if s == 1 else '@2x')
        im.convert('RGB').save(os.path.join(d, n))
        imgs.append({'idiom': 'tv', 'filename': n, 'scale': '%dx' % s})
    write(os.path.join(d, 'Contents.json'), {'images': imgs, 'info': INFO})


shelf('Top Shelf Image', 1920, 720)
shelf('Top Shelf Image Wide', 2320, 720)

# macOS: the tile on Apple's icon grid (824 of 1024, centred), every size
d = os.path.join(MAC, 'AppIcon.appiconset')
tile = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
t = icon.resize((824, 824), Image.LANCZOS)
tile.alpha_composite(t, (100, 100))
imgs = []
for s in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        n = 'icon_%dx%d%s.png' % (s, s, '@2x' if sc == 2 else '')
        tile.resize((s * sc, s * sc), Image.LANCZOS).save(os.path.join(d, n))
        imgs.append({'idiom': 'mac', 'size': '%dx%d' % (s, s), 'scale': '%dx' % sc, 'filename': n})
write(os.path.join(d, 'Contents.json'), {'images': imgs, 'info': INFO})
print('lockup', lock.size)
