#!/usr/bin/env python3
"""Sparkle appcast and release notes for Tidewatch releases (stdlib only, from Captylo's appcast.py).

  scripts/appcast.py item <appcast.xml> --version 0.3.0 --build 12
      --url https://kawalec.pl/tidewatch/download/Tidewatch-0.3.0.dmg
      (--signature <edSig> --length <bytes> | --sign-update '<sign_update output>')
      --notes https://kawalec.pl/tidewatch/updates/notes/0.3.0.html [--min-os 14.4]
  scripts/appcast.py notes <notes.md> <out.html> --version 0.3.0
  scripts/appcast.py check <appcast.xml> --version 0.3.0 --build 12 --length <DMG bytes>

`item` creates the feed when it does not exist, keeps every other item, replaces the item with
the same build or version and keeps the items newest first. `notes` turns a short Markdown file
(headings, paragraphs, "- " lists, **bold**, `code`, [links](https://...)) into the page Sparkle
shows next to the update. `check` is the publish guard (the item exists, is newest, matches the
DMG size and carries a real signature).
Tests: python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import argparse
import html
import os
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime
from email.utils import format_datetime

APP = "Tidewatch"
PAGE = "https://kawalec.pl/tidewatch/"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
SIGN_UPDATE_RE = re.compile(r'sparkle:edSignature="([^"]+)"\s+length="(\d+)"')


def _sparkle(tag):
    return f"{{{SPARKLE_NS}}}{tag}"


def _require_https(url, what):
    if not url.startswith("https://"):
        raise ValueError(f"{what} must be an https URL: {url}")


def new_feed():
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = APP
    ET.SubElement(channel, "link").text = PAGE
    ET.SubElement(channel, "description").text = f"{APP} updates"
    ET.SubElement(channel, "language").text = "en"
    return root


def load_feed(path):
    if not os.path.exists(path):
        return new_feed()
    root = ET.parse(path).getroot()
    if root.tag != "rss" or root.find("channel") is None:
        raise ValueError(f"{path} is not an RSS feed with a channel")
    return root


def make_item(version, build, url, length, signature, notes_url, min_os, pub_date=None):
    if not VERSION_RE.match(version):
        raise ValueError(f"version must look like 1.2.3: {version}")
    if int(build) <= 0:
        raise ValueError(f"build must be a positive number: {build}")
    if int(length) <= 0:
        raise ValueError(f"length must be a positive number of bytes: {length}")
    if not signature:
        raise ValueError("the EdDSA signature is empty")
    _require_https(url, "the download URL")
    _require_https(notes_url, "the release notes URL")
    when = pub_date or datetime.now().astimezone()

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"{APP} {version}"
    ET.SubElement(item, "pubDate").text = format_datetime(when)
    ET.SubElement(item, _sparkle("version")).text = str(int(build))
    ET.SubElement(item, _sparkle("shortVersionString")).text = version
    ET.SubElement(item, _sparkle("minimumSystemVersion")).text = min_os
    ET.SubElement(item, _sparkle("releaseNotesLink")).text = notes_url
    ET.SubElement(
        item,
        "enclosure",
        {"url": url, "length": str(int(length)), "type": "application/octet-stream", _sparkle("edSignature"): signature},
    )
    return item


def _build_of(item):
    try:
        return int(item.findtext(_sparkle("version")) or 0)
    except ValueError:
        return 0


def _version_of(item):
    return (item.findtext(_sparkle("shortVersionString")) or "").strip()


def upsert_item(root, item):
    """Adds the item, dropping any item with the same build or the same version: a rerun of
    make dist for one version replaces the DMG at the same URL, so an older item would carry a
    length and signature that no longer match it."""
    channel = root.find("channel")
    build = _build_of(item)
    version = _version_of(item)
    items = [old for old in channel.findall("item") if _build_of(old) != build and (not version or _version_of(old) != version)]
    for old in channel.findall("item"):
        channel.remove(old)
    items.append(item)
    items.sort(key=_build_of, reverse=True)
    channel.extend(items)
    return root


def write_feed(root, path):
    ET.indent(root, space="  ")
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
    with open(path, "a", encoding="utf-8") as handle:
        handle.write("\n")


def parse_sign_update(text):
    match = SIGN_UPDATE_RE.search(text or "")
    if not match:
        raise ValueError(f"no sparkle:edSignature in the sign_update output: {(text or '').strip()}")
    return match.group(1), int(match.group(2))


# Release notes

def _inline(text):
    out = []
    for part in re.split(r"(`[^`]+`)", text):
        if len(part) >= 2 and part.startswith("`") and part.endswith("`"):
            out.append(f"<code>{html.escape(part[1:-1], quote=False)}</code>")
            continue
        escaped = html.escape(part, quote=False)
        escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
        escaped = re.sub(
            r"\[([^\]]+)\]\((https?://[^\s)]+)\)",
            lambda m: f'<a href="{m.group(2).replace(chr(34), "&quot;")}">{m.group(1)}</a>',
            escaped,
        )
        out.append(escaped)
    return "".join(out)


def _blocks(markdown):
    body = []
    paragraph = []
    in_list = False

    def flush_paragraph():
        if paragraph:
            body.append(f"<p>{_inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def close_list():
        nonlocal in_list
        if in_list:
            body.append("</ul>")
            in_list = False

    for raw in markdown.splitlines():
        line = raw.strip()
        heading = re.match(r"^(#{1,3})\s+(.*)$", line)
        bullet = re.match(r"^[-*]\s+(.*)$", line)
        if not line:
            flush_paragraph()
            close_list()
        elif heading:
            flush_paragraph()
            close_list()
            level = len(heading.group(1))
            body.append(f"<h{level}>{_inline(heading.group(2))}</h{level}>")
        elif bullet:
            flush_paragraph()
            if not in_list:
                body.append("<ul>")
                in_list = True
            body.append(f"<li>{_inline(bullet.group(1))}</li>")
        else:
            close_list()
            paragraph.append(line)
    flush_paragraph()
    close_list()
    return body


# Shown inside Sparkle's update window and on the web: the download page's fonts and colors.
NOTES_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="stylesheet" href="../../assets/site.css">
<style>
body{{background:var(--bg);padding:0 20px}}
.notes{{max-width:640px;margin:0 auto;padding:28px 0 40px}}
.notes h1{{font-size:clamp(28px,4.4vw,40px);line-height:1.08;letter-spacing:-.03em}}
.notes h2{{margin-top:28px;font-size:21px}}
.notes h3{{margin-top:20px;font-size:17px}}
.notes p{{margin-top:12px;color:var(--fg-2)}}
.notes ul{{margin-top:10px;padding-left:22px;list-style:disc;display:grid;gap:6px;color:var(--fg-2)}}
.notes a{{text-decoration:underline;text-underline-offset:3px}}
</style>
</head>
<body>
<main class="notes">
{body}
</main>
</body>
</html>
"""


def render_notes(markdown, version):
    if not VERSION_RE.match(version):
        raise ValueError(f"version must look like 1.2.3: {version}")
    if not markdown.strip():
        raise ValueError("the release notes are empty")
    title = f"{APP} {version}"
    body = _blocks(markdown)
    if not body[0].startswith("<h1>"):
        body.insert(0, f"<h1>{html.escape(title)}</h1>")
    return NOTES_TEMPLATE.format(title=html.escape(title), body="\n".join(body))


# Checks before publishing

def check_release(root, version, build, length):
    """Problems that should stop a publish, as sentences; empty when the feed is ready."""
    problems = []
    items = root.find("channel").findall("item")
    matching = [item for item in items if _build_of(item) == int(build)]
    if not matching:
        return [f"the appcast has no item for build {build}"]
    item = matching[0]
    if items[0] is not item:
        problems.append(f"build {build} is not the newest item in the appcast")
    shown = item.findtext(_sparkle("shortVersionString"))
    if shown != version:
        problems.append(f"build {build} is version {shown} in the appcast, not {version}")
    enclosure = item.find("enclosure")
    if enclosure is None:
        return problems + [f"build {build} has no enclosure"]
    url = enclosure.get("url", "")
    if not url.endswith(f"/{APP}-{version}.dmg"):
        problems.append(f"the enclosure points at {url}, not at {APP}-{version}.dmg")
    signature = enclosure.get(_sparkle("edSignature"), "")
    if not signature or signature == "DRY-RUN-UNSIGNED":
        problems.append("the item carries no EdDSA signature (a dry run item?)")
    if enclosure.get("length") != str(int(length)):
        problems.append(f"the enclosure says {enclosure.get('length')} bytes, the DMG has {length}")
    return problems


# Command line

def _cmd_item(args):
    if args.sign_update:
        signature, length = parse_sign_update(args.sign_update)
    else:
        if not args.signature or args.length is None:
            raise ValueError("give --signature and --length, or --sign-update")
        signature, length = args.signature, args.length
    root = load_feed(args.appcast)
    item = make_item(args.version, args.build, args.url, length, signature, args.notes, args.min_os)
    upsert_item(root, item)
    write_feed(root, args.appcast)
    print(f"{args.appcast}: {APP} {args.version} (build {args.build}), {length} bytes")


def _cmd_notes(args):
    with open(args.markdown, encoding="utf-8") as handle:
        page = render_notes(handle.read(), args.version)
    directory = os.path.dirname(args.out)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(page)
    print(f"{args.out}: release notes for {APP} {args.version}")


def _cmd_check(args):
    problems = check_release(load_feed(args.appcast), args.version, args.build, args.length)
    if problems:
        raise ValueError(f"{args.appcast} is not ready: " + "; ".join(problems))
    print(f"{args.appcast}: {APP} {args.version} (build {args.build}) is signed and newest")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)

    item = commands.add_parser("item", help="add or replace one release in the appcast")
    item.add_argument("appcast")
    item.add_argument("--version", required=True)
    item.add_argument("--build", required=True, type=int)
    item.add_argument("--url", required=True)
    item.add_argument("--length", type=int)
    item.add_argument("--signature")
    item.add_argument("--sign-update", help="the line sign_update printed (signature and length)")
    item.add_argument("--notes", required=True, help="release notes URL")
    item.add_argument("--min-os", default="14.4")
    item.set_defaults(run=_cmd_item)

    notes = commands.add_parser("notes", help="render the release notes page")
    notes.add_argument("markdown")
    notes.add_argument("out")
    notes.add_argument("--version", required=True)
    notes.set_defaults(run=_cmd_notes)

    check = commands.add_parser("check", help="is this release in the appcast, signed and newest?")
    check.add_argument("appcast")
    check.add_argument("--version", required=True)
    check.add_argument("--build", required=True, type=int)
    check.add_argument("--length", required=True, type=int, help="size of the DMG in bytes")
    check.set_defaults(run=_cmd_check)

    args = parser.parse_args(argv)
    try:
        args.run(args)
    except (ValueError, OSError, ET.ParseError) as error:
        print(f"appcast.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
