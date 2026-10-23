"""Write the git-ignored Config/Signing.xcconfig from the first "Apple Development" identity in your keychain.

Prints nothing but whether a team was found. Without a signing identity, copy Config/Signing.example.xcconfig
to Config/Signing.xcconfig and fill in your team id (Xcode > Settings > Accounts), or pick the team in Xcode.
Usage: python3 -I scripts/make_signing.py
"""
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.umask(0o077)

team = None
out = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'], capture_output=True, text=True).stdout
if any('Apple Development' in line for line in out.splitlines()):
    pem = subprocess.run(['security', 'find-certificate', '-a', '-Z', '-p', '-c', 'Apple Development'], capture_output=True, text=True).stdout
    first = pem.split('-----END CERTIFICATE-----')[0] + '-----END CERTIFICATE-----\n'
    subj = subprocess.run(['openssl', 'x509', '-noout', '-subject', '-nameopt', 'multiline'], input=first, capture_output=True, text=True).stdout
    m = re.search(r'organizationalUnitName\s*=\s*(\w+)', subj)
    if m:
        team = m.group(1)
path = os.path.join(ROOT, 'Config/Signing.xcconfig')
if team:
    with open(path, 'w') as f:
        f.write('DEVELOPMENT_TEAM = %s\nCODE_SIGN_STYLE = Automatic\n' % team)
    print('Config/Signing.xcconfig written (team found)')
elif not os.path.exists(path):
    print('No "Apple Development" identity found: copy Config/Signing.example.xcconfig to Config/Signing.xcconfig and set your team id')
