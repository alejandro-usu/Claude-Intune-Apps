#!/usr/bin/env python3
"""Create and verify Intune Win32 app packages (.intunewin) without IntuneWinAppUtil.exe.

The output has the same layout as Microsoft's Win32 Content Prep Tool:

    <setup>.intunewin                      (zip, stored)
      IntuneWinPackage/Contents/IntunePackage.intunewin
          HMAC-SHA256 (32 bytes) | IV (16 bytes) | AES-256-CBC/PKCS7 ciphertext
          The plaintext is a zip of the source folder. The HMAC covers IV + ciphertext.
      IntuneWinPackage/Metadata/Detection.xml
          Keys, IV, MAC and the SHA-256 digest of the plaintext zip, all base64.

Usage:
    intunewin.py pack   <source_dir> <setup_file> <output_dir>
    intunewin.py verify <package.intunewin>
"""
import argparse
import base64
import hashlib
import hmac
import os
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

TOOL_VERSION = "1.8.6.0"
CONTENTS = "IntuneWinPackage/Contents/IntunePackage.intunewin"
METADATA = "IntuneWinPackage/Metadata/Detection.xml"
CHUNK = 4 * 1024 * 1024


def b64(data):
    return base64.b64encode(data).decode("ascii")


def zip_folder(source_dir, dest):
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
        for root, dirs, files in os.walk(source_dir):
            dirs.sort()
            for name in sorted(files):
                path = os.path.join(root, name)
                zf.write(path, os.path.relpath(path, source_dir))


def encrypt_file(plain_path, enc_path):
    """Encrypt plain_path into enc_path. Returns (key, mac_key, iv, mac, sha256 of plaintext)."""
    key, mac_key, iv = os.urandom(32), os.urandom(32), os.urandom(16)
    encryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    padder = padding.PKCS7(128).padder()
    mac = hmac.new(mac_key, iv, hashlib.sha256)
    digest = hashlib.sha256()

    with open(plain_path, "rb") as src, open(enc_path, "wb") as dst:
        dst.write(b"\0" * 32)  # HMAC placeholder
        dst.write(iv)
        while True:
            block = src.read(CHUNK)
            if not block:
                break
            digest.update(block)
            data = encryptor.update(padder.update(block))
            mac.update(data)
            dst.write(data)
        data = encryptor.update(padder.finalize()) + encryptor.finalize()
        mac.update(data)
        dst.write(data)
        dst.seek(0)
        dst.write(mac.digest())
    return key, mac_key, iv, mac.digest(), digest.digest()


def detection_xml(setup_file, plain_size, key, mac_key, iv, mac, file_digest):
    info = ET.Element("ApplicationInfo", {
        "xmlns:xsd": "http://www.w3.org/2001/XMLSchema",
        "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
        "ToolVersion": TOOL_VERSION,
    })
    for tag, value in (("Name", setup_file), ("UnencryptedContentSize", str(plain_size)),
                       ("FileName", "IntunePackage.intunewin"), ("SetupFile", setup_file)):
        ET.SubElement(info, tag).text = value
    enc = ET.SubElement(info, "EncryptionInfo")
    for tag, value in (("EncryptionKey", b64(key)), ("MacKey", b64(mac_key)),
                       ("InitializationVector", b64(iv)), ("Mac", b64(mac)),
                       ("ProfileIdentifier", "ProfileVersion1"), ("FileDigest", b64(file_digest)),
                       ("FileDigestAlgorithm", "SHA256")):
        ET.SubElement(enc, tag).text = value
    ET.indent(info)
    return ET.tostring(info, encoding="utf-8", xml_declaration=True)


def pack(source_dir, setup_file, output_dir):
    if not os.path.isfile(os.path.join(source_dir, setup_file)):
        sys.exit(f"Setup file '{setup_file}' not found in '{source_dir}'")
    os.makedirs(output_dir, exist_ok=True)
    output = os.path.join(output_dir, os.path.splitext(setup_file)[0] + ".intunewin")

    with tempfile.TemporaryDirectory(dir=output_dir) as tmp:
        plain = os.path.join(tmp, "content.zip")
        encrypted = os.path.join(tmp, "IntunePackage.intunewin")
        print(f"Compressing {source_dir} ...")
        zip_folder(source_dir, plain)
        print("Encrypting ...")
        key, mac_key, iv, mac, file_digest = encrypt_file(plain, encrypted)
        xml = detection_xml(setup_file, os.path.getsize(plain), key, mac_key, iv, mac, file_digest)
        with zipfile.ZipFile(output, "w", zipfile.ZIP_STORED, allowZip64=True) as zf:
            zf.write(encrypted, CONTENTS)
            zf.writestr(METADATA, xml)
    print(f"Wrote {output} ({os.path.getsize(output):,} bytes)")
    return output


def verify(package):
    """Check the MAC, decrypt, check the digest and list the content. Exits non-zero on failure."""
    with zipfile.ZipFile(package) as outer, tempfile.TemporaryDirectory() as tmp:
        root = ET.fromstring(outer.read(METADATA))
        enc = root.find("EncryptionInfo")
        field = lambda tag: base64.b64decode(enc.find(tag).text)
        key, mac_key, iv, expected_mac = (field("EncryptionKey"), field("MacKey"),
                                          field("InitializationVector"), field("Mac"))
        expected_digest = field("FileDigest")

        plain = os.path.join(tmp, "content.zip")
        with outer.open(CONTENTS) as src, open(plain, "wb") as dst:
            stored_mac, stored_iv = src.read(32), src.read(16)
            if stored_mac != expected_mac or stored_iv != iv:
                sys.exit("FAIL: header MAC/IV do not match Detection.xml")
            mac = hmac.new(mac_key, iv, hashlib.sha256)
            decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
            unpadder = padding.PKCS7(128).unpadder()
            digest = hashlib.sha256()
            while True:
                block = src.read(CHUNK)
                if not block:
                    break
                mac.update(block)
                data = unpadder.update(decryptor.update(block))
                digest.update(data)
                dst.write(data)
            data = unpadder.update(decryptor.finalize()) + unpadder.finalize()
            digest.update(data)
            dst.write(data)

        if not hmac.compare_digest(mac.digest(), expected_mac):
            sys.exit("FAIL: HMAC mismatch")
        if digest.digest() != expected_digest:
            sys.exit("FAIL: file digest mismatch")
        if os.path.getsize(plain) != int(root.findtext("UnencryptedContentSize")):
            sys.exit("FAIL: UnencryptedContentSize mismatch")
        with zipfile.ZipFile(plain) as inner:
            if inner.testzip() is not None:
                sys.exit("FAIL: corrupt content zip")
            names = inner.namelist()
        if root.findtext("SetupFile") not in names:
            sys.exit("FAIL: setup file missing from content")

    print(f"OK: {package}  setup file: {root.findtext('SetupFile')}")
    for name in names:
        print(f"  {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("pack", help="create a .intunewin package")
    p.add_argument("source_dir")
    p.add_argument("setup_file", help="file name, relative to source_dir, that Intune runs")
    p.add_argument("output_dir")
    v = sub.add_parser("verify", help="check a .intunewin package")
    v.add_argument("package")
    args = parser.parse_args()
    if args.command == "pack":
        pack(args.source_dir, args.setup_file, args.output_dir)
    else:
        verify(args.package)


if __name__ == "__main__":
    main()
