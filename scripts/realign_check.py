"""Measures the true offset of an online subtitle against the film's own subtitle track, over the whole film, to check
what the app's live realignment found. Usage: realign_check.py <film id> <srt file>. Reads the login from
NXTV_ACCOUNT_FILE inside this script; prints only times. True offset = the shift (100 ms steps, -30..+30 s) that puts
the most online cue starts within 200 ms of a reference start (positive: the online file is early, show it later)."""
import os, re, sys, subprocess
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from mkvindex import reference_starts      # same track choice as the app
fid, srt = sys.argv[1], sys.argv[2]
ref = reference_starts(fid, 'mkv')
txt = open(srt, encoding='utf-8', errors='replace').read()
cues = sorted(((int(h) * 60 + int(m)) * 60 + int(s)) * 1000 + int(ms) for h, m, s, ms in re.findall(r'(\d+):(\d+):(\d+)[,.](\d+)\s*-->', txt))
import bisect
def score(off):
    n = 0
    for c in cues:
        t = c + off; i = bisect.bisect_left(ref, t - 200)
        if i < len(ref) and ref[i] <= t + 200: n += 1
    return n
best = max(range(-30000, 30001, 100), key=score)
print('reference starts %d, online cues %d, true offset %+d ms (%d of %d online cues within 200 ms), at 0: %d' % (len(ref), len(cues), best, score(best), len(cues), score(0)))
