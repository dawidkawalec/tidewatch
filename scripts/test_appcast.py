"""Tests for scripts/appcast.py: python3 -m unittest discover -s scripts -p 'test_*.py'"""

import os
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import appcast  # noqa: E402

NS = appcast.SPARKLE_NS
WHEN = datetime(2026, 10, 10, 10, 0, 0, tzinfo=timezone(timedelta(hours=2)))
BASE = "https://kawalec.pl/tidewatch"


def item_args(version="0.3.0", build=12, signature="c2lnbmF0dXJl", length=1100000):
    return dict(
        version=version,
        build=build,
        url=f"{BASE}/download/Tidewatch-{version}.dmg",
        length=length,
        signature=signature,
        notes_url=f"{BASE}/updates/notes/{version}.html",
        min_os="14.4",
        pub_date=WHEN,
    )


def builds(root):
    return [int(item.findtext(f"{{{NS}}}version")) for item in root.iter("item")]


class ItemTests(unittest.TestCase):
    def test_item_has_the_sparkle_fields(self):
        item = appcast.make_item(**item_args())
        self.assertEqual(item.findtext("title"), "Tidewatch 0.3.0")
        self.assertEqual(item.findtext("pubDate"), "Sat, 10 Oct 2026 10:00:00 +0200")
        self.assertEqual(item.findtext(f"{{{NS}}}version"), "12")
        self.assertEqual(item.findtext(f"{{{NS}}}shortVersionString"), "0.3.0")
        self.assertEqual(item.findtext(f"{{{NS}}}minimumSystemVersion"), "14.4")
        self.assertEqual(item.findtext(f"{{{NS}}}releaseNotesLink"), f"{BASE}/updates/notes/0.3.0.html")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), f"{BASE}/download/Tidewatch-0.3.0.dmg")
        self.assertEqual(enclosure.get("length"), "1100000")
        self.assertEqual(enclosure.get("type"), "application/octet-stream")
        self.assertEqual(enclosure.get(f"{{{NS}}}edSignature"), "c2lnbmF0dXJl")

    def test_rejects_bad_input(self):
        for bad in (dict(version="0.3"), dict(build=0), dict(length=0), dict(signature="")):
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    appcast.make_item(**{**item_args(), **bad})
        with self.assertRaises(ValueError):
            appcast.make_item(**{**item_args(), "url": "http://kawalec.pl/tidewatch/x.dmg"})


class FeedTests(unittest.TestCase):
    def test_new_feed_has_a_channel_and_no_items(self):
        root = appcast.new_feed()
        self.assertEqual(root.tag, "rss")
        self.assertEqual(root.findtext("channel/title"), "Tidewatch")
        self.assertEqual(root.findtext("channel/link"), f"{BASE}/")
        self.assertEqual(builds(root), [])

    def test_upsert_keeps_other_items_and_sorts_newest_first(self):
        root = appcast.new_feed()
        appcast.upsert_item(root, appcast.make_item(**item_args("0.3.0", 12)))
        appcast.upsert_item(root, appcast.make_item(**item_args("0.3.2", 20)))
        appcast.upsert_item(root, appcast.make_item(**item_args("0.3.1", 15)))
        self.assertEqual(builds(root), [20, 15, 12])

    def test_upsert_replaces_the_item_with_the_same_build(self):
        root = appcast.new_feed()
        appcast.upsert_item(root, appcast.make_item(**item_args("0.3.0", 12, signature="old")))
        appcast.upsert_item(root, appcast.make_item(**item_args("0.3.0", 12, signature="new")))
        self.assertEqual(builds(root), [12])
        self.assertEqual(root.find("channel/item/enclosure").get(f"{{{NS}}}edSignature"), "new")

    def test_upsert_replaces_an_older_build_of_the_same_version(self):
        root = appcast.new_feed()
        appcast.upsert_item(root, appcast.make_item(**item_args("0.3.0", 10)))
        appcast.upsert_item(root, appcast.make_item(**item_args("0.3.1", 14)))
        appcast.upsert_item(root, appcast.make_item(**item_args("0.3.0", 12)))
        self.assertEqual(builds(root), [14, 12])

    def test_round_trip_keeps_the_sparkle_namespace(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "appcast.xml")
            root = appcast.load_feed(path)
            appcast.upsert_item(root, appcast.make_item(**item_args("0.3.0", 12)))
            appcast.write_feed(root, path)
            root = appcast.load_feed(path)
            appcast.upsert_item(root, appcast.make_item(**item_args("0.3.1", 15)))
            appcast.write_feed(root, path)
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            self.assertIn('xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"', text)
            self.assertNotIn("ns0:", text)
            self.assertTrue(text.startswith("<?xml"))
            self.assertEqual(builds(ET.parse(path).getroot()), [15, 12])


class SignUpdateTests(unittest.TestCase):
    def test_parses_the_sign_update_output(self):
        signature, length = appcast.parse_sign_update('sparkle:edSignature="AbC+/12==" length="1100000"\n')
        self.assertEqual((signature, length), ("AbC+/12==", 1100000))

    def test_rejects_output_without_a_signature(self):
        with self.assertRaises(ValueError):
            appcast.parse_sign_update("ERROR! Unable to find a private key")


class NotesTests(unittest.TestCase):
    MD = "## New\n\n- **Updates** in the app\n- shortcut `x` and <tag>\n- [Page](https://kawalec.pl/tidewatch/)\n"

    def test_renders_headings_lists_and_links(self):
        html = appcast.render_notes(self.MD, "0.3.0")
        self.assertIn("<title>Tidewatch 0.3.0</title>", html)
        self.assertIn("<h1>Tidewatch 0.3.0</h1>", html)
        self.assertIn("<h2>New</h2>", html)
        self.assertIn("<li><strong>Updates</strong> in the app</li>", html)
        self.assertIn("<li>shortcut <code>x</code> and &lt;tag&gt;</li>", html)
        self.assertIn('<li><a href="https://kawalec.pl/tidewatch/">Page</a></li>', html)

    def test_uses_the_download_page_stylesheet(self):
        # notes live at /tidewatch/updates/notes/<version>.html, the page CSS at /tidewatch/assets/
        self.assertIn('href="../../assets/site.css', appcast.render_notes("x\n", "0.3.0"))

    def test_refuses_empty_notes(self):
        with self.assertRaises(ValueError):
            appcast.render_notes("  \n\n", "0.3.0")


class CheckReleaseTests(unittest.TestCase):
    def feed(self, **overrides):
        root = appcast.new_feed()
        appcast.upsert_item(root, appcast.make_item(**item_args("0.3.0", 12)))
        appcast.upsert_item(root, appcast.make_item(**item_args(**{"version": "0.3.1", "build": 15, **overrides})))
        return root

    def test_a_published_release_passes(self):
        self.assertEqual(appcast.check_release(self.feed(), "0.3.1", 15, 1100000), [])

    def test_dry_run_signature_is_refused(self):
        problems = appcast.check_release(self.feed(signature="DRY-RUN-UNSIGNED"), "0.3.1", 15, 1100000)
        self.assertTrue(any("dry run" in p for p in problems), problems)

    def test_length_version_url_and_newest(self):
        self.assertTrue(any("1234" in p for p in appcast.check_release(self.feed(), "0.3.1", 15, 1234)))
        problems = appcast.check_release(self.feed(), "0.3.3", 15, 1100000)
        self.assertTrue(any("Tidewatch-0.3.3.dmg" in p for p in problems), problems)
        self.assertTrue(any("newest" in p for p in appcast.check_release(self.feed(), "0.3.0", 12, 1100000)))


if __name__ == "__main__":
    unittest.main()
