from __future__ import annotations

import hashlib
from pathlib import Path


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
