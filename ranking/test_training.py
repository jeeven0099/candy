import json
import math
import tempfile
import unittest
from pathlib import Path

from train_preferences import (
    FEATURE_NAMES, SCHEMA, auc, compile_model, examples_from_events,
    log_loss, portable_probability, readiness, train,
)


def event(kind, sequence, user="u", deal="d", valid=True):
    return {
        "user_id": user, "promotion_id": deal, "event_type": kind,
        "created_at": "2026-10-07T20:00:00Z",
        "metadata": {"event_sequence": sequence, "feature_schema": SCHEMA["version"],
                     "preference_features": {name: 0.0 for name in FEATURE_NAMES} if valid else None},
    }


class TrainingTests(unittest.TestCase):
    def test_undo_and_unsave_cancel_labels(self):
        self.assertEqual(examples_from_events([event("not_interested", 1), event("not_interested_undone", 2)]), [])
        self.assertEqual(examples_from_events([event("deal_saved", 1), event("deal_unsaved", 2)]), [])

    def test_undo_restores_earlier_save_without_future_feature_leakage(self):
        saved = event("deal_saved", 1)
        saved["metadata"]["preference_features"]["quality"] = 0.7
        examples = examples_from_events([saved, event("not_interested", 2), event("not_interested_undone", 3)])
        self.assertEqual(examples[0]["label"], 1)
        self.assertEqual(examples[0]["sequence"], 1)
        self.assertEqual(examples[0]["features"]["quality"], 0.7)

    def test_repeated_swipes_are_not_multiple_training_examples(self):
        rows = examples_from_events([event("not_interested", 2), event("not_interested", 1)])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["sequence"], 2)

    def test_users_are_not_merged_and_no_action_is_not_negative(self):
        rows = examples_from_events([event("deal_saved", 1, user="a"), event("not_interested", 2, user="b"), event("feed_impression", 3, deal="unacted")])
        self.assertEqual(len(rows), 2)
        self.assertEqual(sum(e["label"] for e in rows), 1)

    def test_missing_or_invalid_snapshots_are_not_fabricated(self):
        bad = event("deal_saved", 1)
        bad["metadata"]["preference_features"]["confidence"] = math.nan
        unknown = event("deal_saved", 2, deal="unknown")
        unknown["metadata"]["feature_schema"] = 99
        self.assertEqual(examples_from_events([bad, unknown, event("not_interested", 3, valid=False)]), [])

    def test_sparse_data_and_single_class_do_not_publish(self):
        artifact, report = train(examples_from_events([event("not_interested", 1)]))
        self.assertIsNone(artifact)
        self.assertEqual(report["status"], "collecting_feedback")
        rows = [{"label": 1, "user_id": str(i % 10)} for i in range(200)]
        self.assertFalse(readiness(rows)["ready"])

    def test_temporal_split_requires_both_classes(self):
        rows = [{"label": int(i < 100), "user_id": str(i % 10), "sequence": i,
                 "features": {f: 0 for f in FEATURE_NAMES}} for i in range(200)]
        artifact, report = train(rows)
        self.assertIsNone(artifact)
        self.assertEqual(report["status"], "insufficient_temporal_validation")

    def test_metrics_have_expected_behavior(self):
        self.assertEqual(auc([0, 1], [0.1, 0.9]), 1)
        self.assertEqual(auc([0, 1], [0.5, 0.5]), 0.5)
        self.assertLess(log_loss([0, 1], [0.1, 0.9]), log_loss([0, 1], [0.5, 0.5]))

    def test_actual_catboost_export_matches_native_inference(self):
        from catboost import CatBoostClassifier, Pool
        x = [[0.0 for _ in FEATURE_NAMES] for _ in range(60)]
        y = [int(i % 2 == 0) for i in range(60)]
        for i, row in enumerate(x):
            row[0] = 0.8 if y[i] else 0.3
            row[15] = 0.4 if y[i] else -0.4
        model = CatBoostClassifier(iterations=6, depth=2, verbose=False, allow_writing_files=False, thread_count=2, random_seed=67)
        model.fit(Pool(x, y, feature_names=FEATURE_NAMES))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "model.json"
            model.save_model(str(path), format="json")
            artifact = compile_model(json.loads(path.read_text()), 0.5, "test_only")
        for row, p in zip(x, model.predict_proba(x)[:, 1]):
            self.assertAlmostEqual(portable_probability(artifact, row), p, places=6)

    def test_training_gate_accepts_only_a_validated_predictive_candidate(self):
        rows = []
        for i in range(200):
            label = i % 2
            features = {f: 0.0 for f in FEATURE_NAMES}
            features["brand_preference"] = 0.4 if label else -0.4
            features["total_evidence"] = 0.5
            rows.append({"label": label, "features": features, "user_id": str(i % 10), "sequence": i})
        artifact, report = train(rows)
        self.assertTrue(artifact["validated"])
        self.assertEqual(report["status"], "candidate_validated")
        self.assertGreater(report["auc"], 0.9)

    def test_uninformative_data_is_not_published(self):
        rows = [{"label": i % 2, "features": {f: (i % 3) / 3 for f in FEATURE_NAMES},
                 "user_id": str(i % 10), "sequence": i} for i in range(200)]
        artifact, report = train(rows)
        self.assertIsNone(artifact)
        self.assertEqual(report["status"], "validation_failed")


if __name__ == "__main__":
    unittest.main()
