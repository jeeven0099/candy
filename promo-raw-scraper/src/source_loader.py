from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class Source:
    brand: str
    category: str
    url: str
    source_type: str
    allowed_to_fetch: bool = False
    online_only: bool = False

    @property
    def slug(self) -> str:
        safe = ''.join(ch.lower() if ch.isalnum() else '_' for ch in self.brand)
        while '__' in safe:
            safe = safe.replace('__', '_')
        return safe.strip('_')


def load_sources(path: str | Path = 'sources/urls.json') -> list[Source]:
    p = Path(path)
    data = json.loads(p.read_text(encoding='utf-8-sig'))
    sources: list[Source] = []
    for item in data:
        sources.append(
            Source(
                brand=item['brand'],
                category=item.get('category', 'other'),
                url=item['url'],
                source_type=item.get('source_type', 'unknown'),
                allowed_to_fetch=bool(item.get('allowed_to_fetch', False)),
                online_only=bool(item.get('online_only', False)),
            )
        )
    return sources


def filter_sources(
    sources: Iterable[Source],
    brand: str | None = None,
    category: str | None = None,
    limit: int | None = None,
    allowed_only: bool = True,
) -> list[Source]:
    result = []
    for source in sources:
        if allowed_only and not source.allowed_to_fetch:
            continue
        if brand and brand.lower() not in source.brand.lower():
            continue
        if category and category.lower() != source.category.lower():
            continue
        result.append(source)
        if limit is not None and len(result) >= limit:
            break
    return result
