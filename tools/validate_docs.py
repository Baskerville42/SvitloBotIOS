#!/usr/bin/env python3
"""Check local links, fragments, page metadata, and image alt text in the Pages site."""

from __future__ import annotations

import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.links: list[tuple[str, str]] = []
        self.errors: list[str] = []
        self.has_title = False
        self.has_viewport = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        element_id = values.get("id")
        if element_id:
            if element_id in self.ids:
                self.errors.append(f"duplicate id #{element_id}")
            self.ids.add(element_id)

        if tag == "title":
            self.has_title = True
        if tag == "meta" and (values.get("name") or "").lower() == "viewport":
            self.has_viewport = True
        if tag == "img" and "alt" not in values:
            self.errors.append("image is missing an alt attribute")

        for attribute in ("href", "src"):
            value = values.get(attribute)
            if value:
                self.links.append((attribute, value))

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <docs-directory>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    pages = sorted(root.rglob("*.html"))
    if not pages:
        print(f"No HTML pages found under {root}", file=sys.stderr)
        return 1

    parsed: dict[Path, PageParser] = {}
    failed = False
    for page in pages:
        parser = PageParser()
        try:
            parser.feed(page.read_text(encoding="utf-8"))
            parser.close()
        except (OSError, UnicodeError) as error:
            print(f"{page.relative_to(root)}: cannot read page: {error}", file=sys.stderr)
            failed = True
            continue
        parsed[page] = parser
        if not parser.has_title:
            print(f"{page.relative_to(root)}: missing <title>", file=sys.stderr)
            failed = True
        if not parser.has_viewport:
            print(f"{page.relative_to(root)}: missing viewport metadata", file=sys.stderr)
            failed = True
        for error in parser.errors:
            print(f"{page.relative_to(root)}: {error}", file=sys.stderr)
            failed = True

    for page, parser in parsed.items():
        for attribute, value in parser.links:
            target_url = urlsplit(value)
            if target_url.scheme or target_url.netloc:
                continue

            relative_target = unquote(target_url.path)
            destination = page if not relative_target else page.parent / relative_target
            destination = destination.resolve()
            try:
                destination.relative_to(root)
            except ValueError:
                print(f"{page.relative_to(root)}: {attribute} escapes docs/: {value}", file=sys.stderr)
                failed = True
                continue

            if destination.is_dir():
                destination = destination / "index.html"
            if not destination.is_file():
                print(f"{page.relative_to(root)}: missing {attribute} target: {value}", file=sys.stderr)
                failed = True
                continue

            if target_url.fragment and destination.suffix.lower() == ".html":
                target_parser = parsed.get(destination)
                if target_parser is None:
                    target_parser = PageParser()
                    target_parser.feed(destination.read_text(encoding="utf-8"))
                fragment = unquote(target_url.fragment)
                if fragment not in target_parser.ids:
                    print(f"{page.relative_to(root)}: missing fragment #{fragment} in {value}", file=sys.stderr)
                    failed = True

    if failed:
        return 1
    print(f"Validated {len(parsed)} HTML pages and their local links and assets.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
