#!/usr/bin/env python3
"""Copy the chosen review sample to a clean filename ready for upload."""

import shutil
from pathlib import Path

SOURCE = Path(__file__).parent.parent / "assets" / "sample" / "sample.wav"
DEST = Path(__file__).parent.parent / "_tmp" / "bandcut_review_sample.wav"


def main() -> None:
    if not SOURCE.exists():
        raise FileNotFoundError(f"Source file not found: {SOURCE}")

    DEST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE, DEST)
    print(f"Copied review sample to: {DEST}")
    print(f"Size: {DEST.stat().st_size / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
