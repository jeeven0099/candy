from __future__ import annotations

import difflib
import hashlib
from pathlib import Path

# Pages whose visible text differs by less than this fraction are treated as
# unchanged — avoids re-parsing when only timestamps or counters updated.
SIMILARITY_THRESHOLD = 0.995


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def hash_exists_for_brand(brand_slug: str, content_hash: str, raw_text_dir: str | Path = 'raw_text') -> bool:
    raw_text_path = Path(raw_text_dir)
    for meta_file in raw_text_path.glob(f'{brand_slug}_*.meta.json'):
        try:
            if f'"content_hash": "{content_hash}"' in meta_file.read_text(encoding='utf-8'):
                return True
        except OSError:
            continue
    return False


def is_similar_to_last(
    brand_slug: str,
    new_text: str,
    raw_text_dir: str | Path = 'raw_text',
    threshold: float = SIMILARITY_THRESHOLD,
) -> tuple[bool, float]:
    """Compare new_text against the most recent saved text for this brand.

    Returns (is_similar, ratio). is_similar is True when the pages are so
    close that re-parsing would almost certainly produce identical output.
    """
    files = sorted(Path(raw_text_dir).glob(f'{brand_slug}_*.txt'))
    if not files:
        return False, 0.0
    try:
        prev = files[-1].read_text(encoding='utf-8')
    except OSError:
        return False, 0.0
    ratio = difflib.SequenceMatcher(None, prev, new_text).ratio()
    return ratio >= threshold, round(ratio, 6)
