#!/usr/bin/env python3
"""Download the installers into source/, check their SHA-256, and build output/Install.intunewin.

Hashes are pinned to the values the vendors publish:
  PyCharm: https://download.jetbrains.com/python/pycharm-2026.2.3.exe.sha256
  Python:  sha256_sum at https://www.python.org/api/v2/downloads/release_file/?release=1116
"""
import hashlib
import os
import shutil
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import intunewin  # noqa: E402

SOURCE = os.path.join(HERE, "source")
OUTPUT = os.path.join(HERE, "output")

DOWNLOADS = [
    ("https://www.python.org/ftp/python/3.14.7/python-3.14.7-amd64.exe",
     "9d9eb2709ef81bf5cd30db3c2096bdbc4ea10087c22e62f27d356b36f6ae9649"),
    ("https://download.jetbrains.com/python/pycharm-2026.2.3.exe",
     "f47b0e48ce06a903b94245bbe8a312f2196205a12264ee47b0cf1595a1443362"),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def fetch(url, expected):
    path = os.path.join(SOURCE, url.rsplit("/", 1)[1])
    if os.path.exists(path) and sha256(path) == expected:
        print(f"Have {os.path.basename(path)} (hash OK)")
        return
    print(f"Downloading {url} ...")
    with urllib.request.urlopen(url) as response, open(path + ".part", "wb") as f:
        shutil.copyfileobj(response, f, 4 * 1024 * 1024)
    actual = sha256(path + ".part")
    if actual != expected:
        os.remove(path + ".part")
        sys.exit(f"SHA-256 mismatch for {url}: got {actual}, expected {expected}")
    os.replace(path + ".part", path)
    print(f"Downloaded {os.path.basename(path)} (hash OK)")


def main():
    for url, expected in DOWNLOADS:
        fetch(url, expected)
    package = intunewin.pack(SOURCE, "Install.ps1", OUTPUT)
    intunewin.verify(package)


if __name__ == "__main__":
    main()
