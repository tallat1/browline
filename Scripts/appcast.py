#!/usr/bin/env python3
"""Sparkle appcast'ine bir sürüm ekler ya da aynı derleme numaralı sürümü günceller (en yeni en üstte).

  Scripts/appcast.py --appcast appcast.xml --version 0.9.1 --build 2 \\
      --url https://github.com/tallat1/browline/releases/download/v0.9.1/Browline-0.9.1.dmg \\
      --signature 'sparkle:edSignature="…" length="…"' \\
      --notes https://github.com/tallat1/browline/releases/tag/v0.9.1 [--min-system 14.0]

`--signature` Sparkle'ın `sign_update` aracının çıktısıdır (özel anahtar Anahtar Zinciri'nde, betik görmez).
"""
import argparse
import email.utils
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def q(tag):
    return f"{{{SPARKLE}}}{tag}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--appcast", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True)
    ap.add_argument("--url", required=True)
    ap.add_argument("--signature", required=True)
    ap.add_argument("--notes", required=True)
    ap.add_argument("--min-system", default="14.0")
    ap.add_argument("--feed-url", default="https://raw.githubusercontent.com/tallat1/browline/main/appcast.xml")
    a = ap.parse_args()

    attrs = dict(re.findall(r'(sparkle:edSignature|length)="([^"]+)"', a.signature))
    if set(attrs) != {"sparkle:edSignature", "length"}:
        sys.exit(f"sign_update çıktısı anlaşılamadı: {a.signature!r}")
    if not a.build.isdigit():
        sys.exit("derleme numarası tam sayı olmalı (Sparkle sürümleri CFBundleVersion ile karşılaştırır)")

    path = pathlib.Path(a.appcast)
    if path.exists():
        tree = ET.parse(path)
        rss = tree.getroot()
    else:
        rss = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "Browline"
        ET.SubElement(channel, "link").text = a.feed_url
        ET.SubElement(channel, "description").text = "Browline updates"
        ET.SubElement(channel, "language").text = "en"
        tree = ET.ElementTree(rss)
    channel = rss.find("channel")

    builds = []
    for item in channel.findall("item"):
        version = item.find(q("version"))
        if version is not None and version.text == a.build:
            channel.remove(item)
        elif version is not None and version.text.isdigit():
            builds.append(int(version.text))
    if builds and int(a.build) <= max(builds):
        sys.exit(f"derleme {a.build} en yeni sürümden ({max(builds)}) büyük olmalı")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = a.version
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, q("version")).text = a.build
    ET.SubElement(item, q("shortVersionString")).text = a.version
    ET.SubElement(item, q("minimumSystemVersion")).text = a.min_system
    ET.SubElement(item, q("releaseNotesLink")).text = a.notes
    ET.SubElement(item, "enclosure", {"url": a.url, q("edSignature"): attrs["sparkle:edSignature"],
                                      "length": attrs["length"], "type": "application/octet-stream"})
    first_item = next((i for i, child in enumerate(channel) if child.tag == "item"), len(channel))
    channel.insert(first_item, item)

    ET.indent(tree, space="  ")
    tree.write(path, encoding="utf-8", xml_declaration=True)
    print(f"  appcast: {path} ← {a.version} ({a.build})")


if __name__ == "__main__":
    main()
