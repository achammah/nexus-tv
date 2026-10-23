"""Summarise a Time Profiler export: main-thread samples per second and the heaviest app frames on the main thread."""
import collections
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
ids = {}
for el in root.iter():
    if 'id' in el.attrib:
        ids[el.attrib['id']] = el
def ref(el):
    return ids.get(el.attrib['ref'], el) if el is not None and 'ref' in el.attrib else el

main = total = 0
per_sec = collections.Counter()
top = collections.Counter()
for row in root.iter('row'):
    th = ref(row.find('thread'))
    t = ref(row.find('sample-time'))
    if th is None or t is None:
        continue
    total += 1
    name = th.attrib.get('fmt', '')
    if 'Main Thread' not in name and 'main' not in name.lower():
        continue
    main += 1
    per_sec[int(int(t.text) / 1e9)] += 1
    bt = ref(row.find('backtrace'))
    if bt is None:
        continue
    frames = [ref(f).attrib.get('name', '') for f in bt.findall('frame')]
    for f in frames:
        if 'NexusTV' in f or 'Nexus' in f or f.startswith('$s7NexusTV'):
            top[f[:120]] += 1
            break
print('samples: %d total, %d on the main thread (1 sample = 1 ms)' % (total, main))
busy = sorted(per_sec.items())
print('main-thread ms per second (first 75 s):', ' '.join(str(v) for _, v in busy))
print('heaviest app frames on the main thread:')
for f, n in top.most_common(15):
    print('  %5d ms  %s' % (n, f))
