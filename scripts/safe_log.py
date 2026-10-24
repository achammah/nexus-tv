"""Print the test result lines of an xcodebuild log, with any login value from the key files masked."""
import os
import re
import sys

key = [l.strip() for l in open(os.path.expanduser(os.environ['NXTV_ACCOUNT_FILE'])).read().splitlines() if l.strip()]
host = key[0].split('://')[-1].split('/')[0].split(':')[0]
secrets = [s for s in (key[0], host, key[1], key[2]) if s]
# the OpenSubtitles test account (OSUB_ACCOUNT_FILE: API key, username, password), when the run has one
if os.environ.get('OSUB_ACCOUNT_FILE'):
    secrets += [l.strip() for l in open(os.path.expanduser(os.environ['OSUB_ACCOUNT_FILE'])).read().splitlines() if l.strip()]
hits = 0
for line in open(sys.argv[1], errors='replace'):
    if not re.search(r"error:|Test Case .*(passed|failed)|\*\* TEST", line):
        continue
    for s in secrets:
        if s in line:
            hits += 1
            line = line.replace(s, '<masked>')
    print(line.rstrip()[:300])
print('login values masked in output lines: %d' % hits)
