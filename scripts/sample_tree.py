"""Print the heavy branches of the main thread from a macOS `sample` report (counts in ms)."""
import re
import sys

lines = open(sys.argv[1]).read().splitlines()
start = next(i for i, l in enumerate(lines) if 'Main Thread' in l)
nodes = []
for l in lines[start + 1:]:
    m = re.match(r'^(\s*[+!:| ]*)(\d+) (.*)$', l)
    if not m or not l.startswith('    +'):
        if nodes and re.match(r'^\s+\d+ Thread_', l):
            break
        continue
    depth = len(m.group(1)) // 2
    nodes.append((depth, int(m.group(2)), m.group(3)))
minimum = int(sys.argv[2]) if len(sys.argv) > 2 else 80
skip = ('__CFRunLoopServiceMachPort', 'mach_msg')
for d, n, s in nodes:
    if n < minimum or any(x in s for x in skip):
        continue
    name = re.sub(r'\s+\[0x[0-9a-f,]+\].*$', '', s)
    name = re.sub(r'\(in ([^)]+)\) \+ \d+', r'(\1)', name)
    print('%s%d %s' % ('  ' * min(d, 40), n, name[:150]))
