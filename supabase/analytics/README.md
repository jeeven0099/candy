# Beta Deal Feedback

Supabase remains the source of truth. No additional analytics service or schema
migration is required: feedback goes into the existing `user_interactions` table
with its existing user-scoped RLS policies.

Each deal event carries `deal_source`, `source_group`, `ranking_version`, and
the feed/one-based position when available. Metadata contains scores and offer
characteristics, not mailbox tokens, email subjects, sender addresses, or bodies.
`source_group=email` includes legacy `source=both`; `deal_source` preserves that
distinction for further segmentation.

Both feeds show up to 10 qualified deals with up to 30 additional ranked deals
cached in memory per feed. Swiping in either direction means not interested;
the next qualified cached deal replaces the rejected card. Menu dismissals use
the same replacement path. Undo restores the deal and reverses its feedback.
The reserve resets when the account, preferences, dataset, or Near Me radius
changes. It is never stored as a shared public email dataset.

Feed impressions require at least 50% of the card to be visible for one second
on the active tab while the app is resumed. Opening, saving, selecting a menu
action, or tapping redeem also qualifies as an exposure. An account/session/feed/source/deal is recorded once per app launch;
cached and off-screen cards are not exposures. Inserts are best-effort online
writes, not an offline delivery guarantee.

Existing actions include `deal_card_opened`, `deal_card_clicked`, `deal_saved`,
`not_interested`, and the new `not_interested_undone`. Undo cancels the latest
dismissal in the comparison query. `fast_redeem_clicked` and `redeem_clicked`
represent intent only, never a confirmed purchase or redemption.
Dismissal metadata includes `feedback_method` (`swipe` or `menu`), plus the
logical swipe direction when applicable. Client event sequences preserve action/undo order even if requests reach
Supabase out of order.

Run `deal_source_metrics.sql` in the Supabase SQL editor to inspect views,
opens, saves, effective dismissals, and redemption intent by source, feed,
ranking version, and position band. Rates count distinct exposed deals per
session, not raw tap totals. Old events without a source tag are excluded rather
than guessed from promotion IDs. Detail actions without a feed are attributed
to the most recent matching exposure in the same account/session.

The second query reports current pipeline yield and connected-user coverage.
An eligible email deal can still lose to public offers in the top-10 ranker.

Compare the same beta-user cohort and similar positions before drawing
conclusions. These are observational metrics: different candidate pools,
ranking, and the visible Email badge can influence results. They do not prove
that the pipeline caused higher engagement. The reserve is populated only from
the existing quality-filtered ranker; email offers are not forced into the feed
to make the Email badge appear.
