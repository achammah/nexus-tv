"""Build tvOS/Assets.xcassets: the in-app logo (SVG) and the tvOS app icon + top shelf images.

The logo PNG comes from svg2png.swift (AppKit draws the SVG). Run from the repo root:
  swift scripts/art/svg2png.swift scripts/art/nexus-logo-white.svg /tmp/logo.png 1400
  python3 -I scripts/art/make_assets.py /tmp/logo.png
"""
import json
import os
import shutil
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
XC = os.path.join(ROOT, 'tvOS/Assets.xcassets')
LOGO = Image.open(sys.argv[1]).convert('RGBA')
INFO = {'author': 'xcode', 'version': 1}
FONT = '/System/Library/Fonts/HelveticaNeue.ttc'


def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        json.dump(obj, f, indent=2)


def lockup(height, color=(255, 255, 255)):
    """'[logo] | TV' in `color` on transparent, `height` = logo height."""
    lw = int(LOGO.width * height / LOGO.height)
    logo = LOGO.resize((lw, height), Image.LANCZOS)
    if color != (255, 255, 255):
        tinted = Image.new('RGBA', logo.size, color + (255,))
        tinted.putalpha(logo.getchannel('A'))
        logo = tinted
    font = ImageFont.truetype(FONT, int(height * 0.95), index=7)  # Light
    tv = ImageDraw.Draw(Image.new('RGBA', (1, 1))).textbbox((0, 0), 'TV', font=font)
    gap, bar = int(height * 0.42), max(2, height // 20)
    w = lw + gap * 2 + bar + (tv[2] - tv[0])
    img = Image.new('RGBA', (w, int(height * 1.2)), (0, 0, 0, 0))
    img.alpha_composite(logo, (0, int(height * 0.1)))
    d = ImageDraw.Draw(img)
    d.rectangle([lw + gap, int(height * 0.22), lw + gap + bar, int(height * 0.98)], fill=color + (110,))
    d.text((lw + gap * 2 + bar - tv[0], int(height * 0.1) - tv[1] + int(height * 0.05)), 'TV', font=font, fill=color + (255,))
    return img


def back(w, h):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    for y in range(h):   # #2A2D36 top-left glow fading to black
        t = y / h
        c = tuple(int(v * (1 - t) ** 1.6) for v in (0x2A, 0x2D, 0x36))
        d.line([(0, y), (w, y)], fill=c + (255,))
    return img


def front(w, h, scale=0.55):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    lk = lockup(int(h * 0.22))
    if lk.width > w * scale:
        lk = lk.resize((int(w * scale), int(lk.height * w * scale / lk.width)), Image.LANCZOS)
    img.alpha_composite(lk, ((w - lk.width) // 2, (h - lk.height) // 2))
    return img


def stack(name, size, scales, idiom='tv'):
    base = os.path.join(XC, 'App Icon & Top Shelf Image.brandassets', name + '.imagestack')
    write(os.path.join(base, 'Contents.json'), {'info': INFO, 'layers': [{'filename': 'Front.imagestacklayer'}, {'filename': 'Back.imagestacklayer'}]})
    for layer, fn in (('Front', front), ('Back', back)):
        d = os.path.join(base, layer + '.imagestacklayer')
        write(os.path.join(d, 'Contents.json'), {'info': INFO})
        imgs = []
        for s in scales:
            f = '%s%s.png' % (layer.lower(), '' if s == 1 else '@%dx' % s)
            im = fn(size[0] * s, size[1] * s)
            if layer == 'Back':
                im = im.convert('RGB')
            os.makedirs(os.path.join(d, 'Content.imageset'), exist_ok=True)
            im.save(os.path.join(d, 'Content.imageset', f))
            imgs.append({'filename': f, 'idiom': idiom, 'scale': '%dx' % s})
        write(os.path.join(d, 'Content.imageset', 'Contents.json'), {'images': imgs, 'info': INFO})


def shelf(name, size):
    d = os.path.join(XC, 'App Icon & Top Shelf Image.brandassets', name + '.imageset')
    imgs = []
    for s in (1, 2):
        w, h = size[0] * s, size[1] * s
        im = back(w, h)
        lk = lockup(int(h * 0.16))
        im.alpha_composite(lk, (int(h * 0.16), int(h * 0.16)))
        font = ImageFont.truetype(FONT, int(h * 0.06), index=0)
        ImageDraw.Draw(im).text((int(h * 0.16), int(h * 0.16) + lk.height + int(h * 0.06)), 'Live TV  ·  Films  ·  Series', font=font, fill=(255, 255, 255, 150))
        f = 'shelf%s.png' % ('' if s == 1 else '@2x')
        os.makedirs(d, exist_ok=True)
        im.convert('RGB').save(os.path.join(d, f))
        imgs.append({'filename': f, 'idiom': 'tv', 'scale': '%dx' % s})
    write(os.path.join(d, 'Contents.json'), {'images': imgs, 'info': INFO})


if os.path.exists(XC):
    shutil.rmtree(XC)
write(os.path.join(XC, 'Contents.json'), {'info': INFO})
lg = os.path.join(XC, 'NexusLogo.imageset')
os.makedirs(lg)
shutil.copy(os.path.join(ROOT, 'scripts/art/nexus-logo-white.svg'), lg)
write(os.path.join(lg, 'Contents.json'), {'images': [{'filename': 'nexus-logo-white.svg', 'idiom': 'universal'}], 'info': INFO,
                                          'properties': {'preserves-vector-representation': True}})
write(os.path.join(XC, 'App Icon & Top Shelf Image.brandassets', 'Contents.json'), {'info': INFO, 'assets': [
    {'filename': 'App Icon - App Store.imagestack', 'idiom': 'tv', 'role': 'primary-app-icon', 'size': '1280x768'},
    {'filename': 'App Icon.imagestack', 'idiom': 'tv', 'role': 'primary-app-icon', 'size': '400x240'},
    {'filename': 'Top Shelf Image Wide.imageset', 'idiom': 'tv', 'role': 'top-shelf-image-wide', 'size': '2320x720'},
    {'filename': 'Top Shelf Image.imageset', 'idiom': 'tv', 'role': 'top-shelf-image', 'size': '1920x720'}]})
# launch screen: the icon art, black lockup on white
ls = os.path.join(XC, 'LaunchLogo.imageset')
os.makedirs(ls)
imgs = []
for sc in (1, 2):
    lockup(110 * sc, (0, 0, 0)).save(os.path.join(ls, 'launch%s.png' % ('' if sc == 1 else '@2x')))
    imgs.append({'filename': 'launch%s.png' % ('' if sc == 1 else '@2x'), 'idiom': 'tv', 'scale': '%dx' % sc})
write(os.path.join(ls, 'Contents.json'), {'images': imgs, 'info': INFO})
write(os.path.join(XC, 'LaunchBackground.colorset', 'Contents.json'), {'info': INFO, 'colors': [{'idiom': 'universal', 'color': {
    'color-space': 'srgb', 'components': {'red': '1.000', 'green': '1.000', 'blue': '1.000', 'alpha': '1.000'}}}]})
stack('App Icon', (400, 240), (1, 2))
stack('App Icon - App Store', (1280, 768), (1,))
shelf('Top Shelf Image', (1920, 720))
shelf('Top Shelf Image Wide', (2320, 720))
print('assets written')
