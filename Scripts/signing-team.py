#!/usr/bin/env python3
"""Geçerli Apple Development sertifikalarının herkese açık OU alanını okur."""
import re
import subprocess
import sys

result = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True, check=True)
names = re.findall(r'"(Apple Development:[^"\n]+)"', result.stdout)
teams = set()
for name in names:
    certificate = subprocess.run(["security", "find-certificate", "-c", name, "-p"], capture_output=True, check=True)
    subject = subprocess.run(["openssl", "x509", "-noout", "-subject"], input=certificate.stdout, capture_output=True, check=True)
    match = re.search(r"\bOU\s*=\s*([A-Z0-9]{10})\b", subject.stdout.decode())
    if match:
        teams.add(match.group(1))
if len(teams) != 1:
    sys.exit("Tek imzalama takımı seçilemedi. Xcode'a Apple hesabını ekle ve --team TEAM_ID kullan.")
print(next(iter(teams)))
