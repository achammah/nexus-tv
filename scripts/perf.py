"""Join the app's metrics log with the test's phase times and print the speed numbers.
Usage: python3 -I scripts/perf.py <metrics.log> <perf-phases.txt>"""
import re
import sys

ev = []      # (t, text)
for l in open(sys.argv[1]):
    t, _, rest = l.strip().partition(' ')
    ev.append((float(t), rest))
ph = []
for l in open(sys.argv[2]):
    t, _, rest = l.strip().partition(' ')
    ph.append((float(t), rest))

bodies = {}
def frames(a, b):
    bodies.clear()
    f = h = 0; w = 0; busy = 0; lng = 0
    for t, s in ev:
        m = re.match(r'frames (\d+) hitches (\d+) worst (\d+)ms busy (\d+)ms longest (\d+)ms(?: bodies (\S+))?', s)
        if m and a < t <= b + 1:
            f += int(m.group(1)); h += int(m.group(2)); w = max(w, int(m.group(3))); busy += int(m.group(4)); lng = max(lng, int(m.group(5)))
            for kv in (m.group(6) or '').split(','):
                if '=' in kv:
                    k, v = kv.split('='); bodies[k] = bodies.get(k, 0) + int(v)
    frames.busy, frames.longest = busy, lng
    return f, h, w

marks = [(t, s) for t, s in ev if not s.startswith('frames')]
for t, s in marks:
    if s.startswith('ready:home') or s == 'launch':
        print('%-28s %s' % ('launch mark', s))
times = dict((s, t) for t, s in ph)
for name in ['home-focus', 'guide-focus']:
    a, b = times.get(name + ' start'), times.get(name + ' end')
    if a and b:
        f, h, w = frames(a, b)
        n = 41 if name == 'home-focus' else 20
        print('%-28s %.1f s, %.0f fps, %d hitches, worst frame %d ms | main thread busy %d ms = %.1f ms per move, longest stretch %d ms' % (
            name, b - a, f / max(b - a, 0.1), h, w, frames.busy, frames.busy / n, frames.longest))
        print('%-28s view bodies per move: %s' % ('', ', '.join('%s %.0f' % (k, v / n) for k, v in sorted(bodies.items(), key=lambda x: -x[1]))))
for (t, s) in ph:
    if s.startswith('switch'):
        _, rnd, tab = s.split()
        tabm = next((mt for mt, ms in marks if ms.startswith('tab:' + tab) and mt >= t - 0.2), None)
        ready = next((mt for mt, ms in marks if ms.startswith('ready:' + tab) and mt >= t - 0.2 and mt < t + 4), None)
        f, h, w = frames(t, t + 2)
        print('%-28s tab mark %s, content ready %s | main thread busy %d ms in 3 s, longest stretch %d ms, worst frame %d ms' % (
            'switch round %s %s' % (rnd, tab),
            ('+%.0f ms' % ((tabm - t) * 1000)) if tabm else '-',
            ('+%.0f ms' % ((ready - t) * 1000)) if ready else '-', frames.busy, frames.longest, w))
