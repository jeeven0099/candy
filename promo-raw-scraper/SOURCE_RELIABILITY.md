# Captured Source Reliability

The existing scraper and normalization steps now attach `source_evidence` to
public deals. No new scheduler, network service, Supabase table, or build step is
required. Production data files are not rewritten by the tests or audit below.

## Eligibility

For You and Near Me apply this gate before rule scoring or CatBoost, including
all replacement candidates. A deal needs a known public HTTP(S) source on the
configured brand domain, a concrete offer, redemption instructions, required
code/membership details, and source evidence captured within 14 days. Missing
expiry is allowed when source evidence is recent; an expiry is never invented.
Start/expiry dates are rechecked at runtime. Date-only expiry includes the whole
last day in the offer's timezone. Unknown or malformed dates require review.
Birthday rewards additionally require the user's birthday month.

Evidence is matched conservatively against a nearby passage in the captured
text. Values, codes, minimum spend, declared dates, and title anchors must match;
obvious omitted first-order, membership, purchase, or app-only conditions fail.
Evidence from separate pages/passages is not combined. Synthesized discounts
require review. The evidence snapshot is tied to the extracted offer fields.
This is deterministic grounding, not a guarantee that checkout will succeed.
It does not detect every semantic ambiguity, inventory change, or hidden term.

Normalization does not set a fresh date just because it ran. Identical successful
scrapes refresh evidence only when the content hash and captured source match.
A failed source check quarantines previously supported deals as unverified, not
as proven false. Normalization cannot revive them from an older capture.
Deal-link backfill never overwrites the captured source URL. Evidence-bearing
offers only accept a backfilled link when its literal marker is in the captured
offer passage and the URL stays on the configured brand domain.

Unsupported deals stay in normalized review output with reason codes. Existing
active-only merging keeps them out of the public feed/notification dataset.
The app also rejects legacy rows without evidence. Historical saved/notification
details remain inspectable but show a verification warning. Source dates come
from the capture, not the day the user opens the detail screen.

Feedback includes eligibility/version/reason codes, never source excerpts or
private links. New unreliable-offer interactions do not teach preferences.

## Audit And Rollout

Run a local audit without changing published datasets:

```powershell
.venv/Scripts/python.exe promo-raw-scraper/src/normalize_promotions.py --output-dir .env.reliability-normalized
```

From `promo_viewer`, validate that copy with the app's parser and runtime gate:

```powershell
dart run tool/audit_deal_reliability.dart ../.env.reliability-normalized
```

The audit reports aggregate reasons without printing offer text or private data.
An empty catalog, malformed records, or evidence/offer format mismatch returns a
nonzero exit code. Reliability eligibility is not a promise of top-10 placement:
quality, birthday eligibility, and user preferences are applied separately.

Publish the validated scraper changes and refresh the catalog before releasing
the strict app gate. Older remote/bundled catalogs without `source_evidence` will
otherwise produce empty feeds. Do not deploy only the app changes.

Build 73 disables Gmail UI, consent launch, connection restore, and private-deal
loading through `kGmailDealsEnabled`. Normal Google sign-in remains available.
The Gmail automation remains paused and is not enabled by this change. Legacy
private email offers without this evidence are held back as well. They need a
corresponding private ingestion validator before returning to the feed.

See `BETA_RELEASE.md` at the repository root for the release order and device
smoke test. Do not infer TestFlight or production-database readiness from local
unit tests alone.
