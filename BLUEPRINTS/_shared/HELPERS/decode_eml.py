#!/usr/bin/env python3
"""
decode_eml.py
Usage: python HELPERS/decode_eml.py <path-to-eml-file> [output-directory]

Decodes base64-encoded parts from an .eml file. Text parts are printed as UTF-8.
Binary parts (e.g. PDF) are written to output-directory when given; otherwise a
short notice is printed.
"""
from __future__ import annotations

import base64
import re
import sys
from pathlib import Path

_DEFAULT_REL = (
    Path(__file__).resolve().parent.parent
    / "INPUTS"
    / "Re_ Olive Grove_ AI Calling & Data Automation Project.eml"
)

# Terminate before any MIME subpart boundary line (-- followed by token). Outlook
# uses both --_000_... and --_004_... etc.; older regex only matched --_000.
_B64_BLOCK = re.compile(
    r"Content-Transfer-Encoding:\s*base64[\r\n\s]+([\s\S]*?)(?=\r?\n--[^\r\n]+)",
    re.MULTILINE | re.IGNORECASE,
)


def main() -> None:
    eml_path = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else _DEFAULT_REL
    out_dir = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
    content = eml_path.read_text(encoding="utf-8", errors="replace")

    section_num = 0
    for match in _B64_BLOCK.finditer(content):
        section_num += 1
        raw_b64 = re.sub(r"[\r\n\s]", "", match.group(1))
        try:
            raw = base64.b64decode(raw_b64, validate=False)
            if raw.startswith(b"%PDF"):
                if out_dir:
                    out_dir.mkdir(parents=True, exist_ok=True)
                    out_path = out_dir / f"{eml_path.stem}_attachment_{section_num}.pdf"
                    out_path.write_bytes(raw)
                    print(f"Wrote PDF ({len(raw)} bytes): {out_path}")
                else:
                    print(
                        f"=== BINARY PDF SECTION {section_num} ({len(raw)} bytes): "
                        "pass output directory as second argument to save ===\n"
                    )
                continue
            decoded = raw.decode("utf-8", errors="replace")
            print(f"=== DECODED SECTION {section_num} ===")
            print(decoded)
            print(f"=== END SECTION {section_num} ===\n")
        except Exception as e:  # noqa: BLE001 — mirror JS try/catch
            print(f"Error decoding section {section_num}: {e}", file=sys.stderr)

    if section_num == 0:
        print("No base64 sections found.")


if __name__ == "__main__":
    main()
