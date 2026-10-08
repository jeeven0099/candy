# Beta Learned Preferences

The public scraper, nightly runner, Gmail extractor, and Codemagic workflow are
unchanged. This is a separate training tool for the 30-user beta.

## Serving

The existing quality/eligibility gates run first. The app then adds a numeric
CatBoost adjustment to the existing rule score, bounded to +/-6 points and
shrunk toward zero for users with sparse feedback. The top 10 and next 30 remain
in app memory. Missing, invalid, incompatible, or unavailable models produce a
zero adjustment. New users start on the existing rules.

The app loads at most 1,000 recent feedback events for the authenticated account
from the previous 90 days. Its in-memory profile summarizes brand, category,
promotion/discount type, and membership-requirement outcomes. Evidence decays
with a 30-day half-life; repeated actions on one deal are not extra evidence.
Undo cancels a dismissal, and unsave cancels a save, without guessing a new
negative preference. Profiles are cleared on sign-out/account changes.
Recent server-recorded dismissals are also excluded from candidates. Local skip
keys are now account-scoped; unscoped legacy keys are not assigned to another
account. Online dismissals from older builds are recovered from feedback history.

No new per-user score table is created. Existing `user_preferences` remain the
explicit settings and `user_interactions` are the feedback source of truth.
The single `learned_ranking_model` row is authenticated-readable and only
server-writable. It contains trees, not private training examples.

## Feedback Features

Each promotion event records `feature_schema`, `offer_features`, and the numeric
`preference_features` used before the action. These exclude titles, email
contents, sender addresses, links, tokens, and coupon codes. The current deal
is excluded from its own history features. `learned_model_version` and
`learned_adjustment` distinguish fallback from model-assisted ranking.

Brand/category/type are represented by the user's smoothed prior reactions,
not arbitrary numeric IDs or memorized email text. Explicit favorites, deal
value, discount kind, app/purchase/membership requirements and the app's
existing membership context are additional features. That membership context
comes from the existing membership loader, not a new verified user-membership
system. Feature names/order are shared with `feature_schema.json` and tested.

Save events are emitted once by `SavedDealsService`, including context from a
feed when available. Unsave emits `deal_unsaved`. These follow the existing
best-effort online Supabase writes; there is no new offline delivery guarantee.

## Training

Use Python 3.11+ in a separate environment, then install `ranking/requirements.txt`.
From the repository root, with the existing Supabase CLI login/project link:

```powershell
python ranking/train_preferences.py --linked --supabase-cli <path-to-supabase>
```

This reads a minimal private feedback export through the CLI and prints only
aggregate readiness/validation metrics. It does not change the database.
No historical feature snapshots are invented for earlier app versions.

The first model is a `CatBoostClassifier` of saved versus dismissed *among
explicit feedback*, not a calibrated purchase probability or a full pairwise
ranker. It is used only as a preference adjustment. Training initially requires
100 effective user/deal examples, 20 of each class, and 5 users. Those are
conservative beta gates, not universal sufficiency guarantees. Both classes
must also appear in a chronological 80/20 train/validation split.

The held-out AUC must be >=0.60 and log loss must improve on a constant training
class-prior baseline by at least 2%. Exported numeric trees are checked against
native CatBoost predictions. Poor/insufficient runs leave the active model
untouched. Generated model files use ignored `.env.*` names.

After reviewing a candidate, explicitly publish it:

```powershell
python ranking/train_preferences.py --linked --supabase-cli <path-to-supabase> --publish
```

Apply `supabase/migrations/004_learned_ranking_model.sql` first. Publication
replaces only the beta model row. Apps fetch that row on startup/pull-to-refresh,
so a later validated model does not require another iOS binary.

Feedback updates the app's input profile immediately, but CatBoost trees do not
train on the phone after each swipe. Rerun the training command periodically,
or schedule it as its own job. No scheduled job is installed and no existing
nightly task is changed. These validation gates do not establish improved
top-10 recommendations: compare save/dismissal rates against the rule baseline
with beta users, controlling for position and source before increasing impact.

## Tests

```powershell
python -m unittest discover -s ranking -p test_training.py
python ranking/generate_test_fixture.py
```

The fixture is synthetic and lives only under Flutter tests, not app assets.
Flutter tests verify feature parity, inference parity, bounded adjustments,
cold-start/offline fallback, account isolation, reversal handling, and the
existing feed eligibility/replacement behavior.
