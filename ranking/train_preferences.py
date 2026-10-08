"""Train a small, numeric CatBoost adjustment independently of the scraper."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import subprocess
import tempfile
from datetime import datetime, timezone
from typing import Any

SCHEMA = json.loads(Path(__file__).with_name("feature_schema.json").read_text(encoding="utf-8"))
FEATURE_NAMES = SCHEMA["features"]
MIN_EXAMPLES = 100
MIN_PER_CLASS = 20
MIN_USERS = 5


def event_sequence(event: dict) -> int:
    value = event.get("metadata", {}).get("event_sequence")
    if value is not None:
        return int(value)
    return int(datetime.fromisoformat(event["created_at"].replace("Z", "+00:00")).timestamp() * 1_000_000)


def valid_features(event: dict) -> bool:
    meta = event.get("metadata") or {}
    values = meta.get("preference_features")
    return (
        meta.get("feature_schema") == SCHEMA["version"]
        and isinstance(values, dict)
        and set(values) == set(FEATURE_NAMES)
        and all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
                and (-1 <= v <= 1 if k.endswith("_preference") else 0 <= v <= 1)
                for k, v in values.items())
    )


def examples_from_events(events: list[dict]) -> list[dict]:
    """One effective label per user/deal; Undo and unsave cancel their channel."""
    states: dict[tuple[str, str], dict[str, dict | None]] = {}
    for event in sorted(events, key=event_sequence):
        user, deal = event.get("user_id"), event.get("promotion_id")
        if not user or not deal:
            continue
        state = states.setdefault((user, deal), {"save": None, "dismiss": None})
        kind = event.get("event_type")
        if kind == "deal_saved":
            state["save"] = event
        elif kind == "deal_unsaved":
            state["save"] = None
        elif kind == "not_interested":
            state["dismiss"] = event
        elif kind == "not_interested_undone":
            state["dismiss"] = None
    examples = []
    for state in states.values():
        active = [e for e in state.values() if e is not None]
        if not active:
            continue
        latest = max(active, key=event_sequence)
        # Never backfill missing historical model inputs using today's deal.
        if valid_features(latest):
            examples.append({
                "user_id": latest["user_id"],
                "sequence": event_sequence(latest),
                "label": int(latest["event_type"] == "deal_saved"),
                "features": latest["metadata"]["preference_features"],
            })
    return sorted(examples, key=lambda e: e["sequence"])


def readiness(examples: list[dict]) -> dict:
    positives = sum(e["label"] for e in examples)
    negatives = len(examples) - positives
    users = len({e["user_id"] for e in examples})
    ready = len(examples) >= MIN_EXAMPLES and min(positives, negatives) >= MIN_PER_CLASS and users >= MIN_USERS
    return {"examples": len(examples), "saves": positives, "dismissals": negatives,
            "users": users, "ready": ready,
            "required": {"examples": MIN_EXAMPLES, "each_class": MIN_PER_CLASS, "users": MIN_USERS}}


def log_loss(labels: list[int], probabilities: list[float]) -> float:
    return -sum(y * math.log(max(1e-7, min(1 - 1e-7, p))) +
                (1 - y) * math.log(max(1e-7, min(1 - 1e-7, 1 - p)))
                for y, p in zip(labels, probabilities)) / len(labels)


def auc(labels: list[int], scores: list[float]) -> float:
    positives = [s for y, s in zip(labels, scores) if y]
    negatives = [s for y, s in zip(labels, scores) if not y]
    return sum((p > n) + 0.5 * (p == n) for p in positives for n in negatives) / (len(positives) * len(negatives))


def compile_model(raw: dict, prior: float, version: str) -> dict:
    """Compile only CatBoost FloatFeature oblivious trees; reject other models."""
    info = raw["features_info"]
    if info.get("categorical_features") or info.get("ctrs"):
        raise ValueError("Only numeric CatBoost models are supported")
    indices = {}
    for feature in info["float_features"]:
        flat = feature["flat_feature_index"]
        if feature["feature_id"] != FEATURE_NAMES[flat]:
            raise ValueError("Feature order mismatch")
        indices[feature["feature_index"]] = flat
    scale, biases = raw["scale_and_bias"]
    if len(biases) != 1:
        raise ValueError("Only binary classification is supported")
    trees = [{"splits": [], "leaves": [float(biases[0])]}]
    for tree in raw["oblivious_trees"]:
        splits = []
        for split in tree.get("splits") or []:
            if split["split_type"] != "FloatFeature":
                raise ValueError("Unsupported CatBoost split")
            splits.append({"feature": indices[split["float_feature_index"]], "border": split["border"]})
        if len(splits) > 6 or len(tree["leaf_values"]) != 1 << len(splits):
            raise ValueError("Unsupported tree shape")
        trees.append({"splits": splits, "leaves": [float(v * scale) for v in tree["leaf_values"]]})
    artifact = {"schema_version": SCHEMA["version"], "format": "catboost_numeric_v1",
                "version": version, "feature_names": FEATURE_NAMES, "prior": prior,
                "validated": False, "trees": trees}
    if len(trees) > 300 or len(json.dumps(artifact).encode()) > 1_000_000:
        raise ValueError("Model exceeds beta size limit")
    return artifact


def portable_probability(artifact: dict, row: list[float]) -> float:
    import struct
    # Match CatBoost's float32 numeric inputs, including values near a border.
    values = [struct.unpack("f", struct.pack("f", value))[0] for value in row]
    score = 0.0
    for tree in artifact["trees"]:
        leaf = sum(1 << bit for bit, split in enumerate(tree["splits"])
                   if values[split["feature"]] > split["border"])
        score += tree["leaves"][leaf]
    return 1 / (1 + math.exp(-max(-40, min(40, score))))


def train(examples: list[dict]) -> tuple[dict | None, dict]:
    report = readiness(examples)
    if not report["ready"]:
        return None, {**report, "status": "collecting_feedback"}
    cut = int(len(examples) * 0.8)
    earlier, later = examples[:cut], examples[cut:]
    # Split by time, never random events from the same deal into both sets.
    if min(sum(e["label"] == label for e in earlier) for label in (0, 1)) < 10 or min(
        sum(e["label"] == label for e in later) for label in (0, 1)
    ) < 5:
        return None, {**report, "status": "insufficient_temporal_validation"}
    from catboost import CatBoostClassifier, Pool
    x = [[e["features"][f] for f in FEATURE_NAMES] for e in earlier]
    y = [e["label"] for e in earlier]
    test_x = [[e["features"][f] for f in FEATURE_NAMES] for e in later]
    test_y = [e["label"] for e in later]
    model = CatBoostClassifier(iterations=120, depth=3, learning_rate=0.04,
                               l2_leaf_reg=8, loss_function="Logloss", random_seed=67,
                               thread_count=2, verbose=False, allow_writing_files=False)
    model.fit(Pool(x, y, feature_names=FEATURE_NAMES))
    probabilities = model.predict_proba(test_x)[:, 1].tolist()
    prior = sum(y) / len(y)
    loss, baseline = log_loss(test_y, probabilities), log_loss(test_y, [prior] * len(test_y))
    area = auc(test_y, probabilities)
    metrics = {"validation_examples": len(later), "auc": area, "log_loss": loss,
               "constant_baseline_log_loss": baseline}
    # A first deployment gate, not evidence that top-10 quality is improved.
    if area < 0.60 or loss >= baseline * 0.98:
        return None, {**report, **metrics, "status": "validation_failed"}
    version = "catboost_beta_" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "model.json"
        model.save_model(str(path), format="json")
        artifact = compile_model(json.loads(path.read_text(encoding="utf-8")), prior, version)
    # Verify the portable representation against CatBoost before publication.
    for row, prediction in zip(test_x + x, probabilities + model.predict_proba(x)[:, 1].tolist()):
        if abs(portable_probability(artifact, row) - prediction) > 1e-6:
            raise ValueError("Portable CatBoost inference differs from native inference")
    artifact["validated"] = True
    return artifact, {**report, **metrics, "status": "candidate_validated", "version": version}


def linked_query(cli: str, sql_file: Path) -> dict:
    process = subprocess.run([cli, "db", "query", "--linked", "--file", str(sql_file)],
                             check=True, capture_output=True, text=True, encoding="utf-8",
                             cwd=Path(__file__).resolve().parent.parent)
    return json.loads(process.stdout)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--events-file", type=Path)
    source.add_argument("--linked", action="store_true")
    parser.add_argument("--supabase-cli", default="supabase")
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / ".env.preference-model.json")
    parser.add_argument("--publish", action="store_true", help="Explicitly publish a validated candidate to the beta slot")
    args = parser.parse_args()
    if args.publish and not args.linked:
        parser.error("Publication requires --linked; never publish fixture data")
    data = linked_query(args.supabase_cli, Path(__file__).with_name("export_feedback.sql")) if args.linked else json.loads(args.events_file.read_text(encoding="utf-8-sig"))
    events = data["rows"] if isinstance(data, dict) else data
    artifact, report = train(examples_from_events(events))
    print(json.dumps({"events_checked": len(events), **report}, indent=2))
    if artifact is None:
        # Do not replace a working model or reuse a stale local file.
        return
    args.output.write_text(json.dumps(artifact, separators=(",", ":")), encoding="utf-8")
    if args.publish:
        text = json.dumps(artifact, separators=(",", ":")).replace("'", "''")
        version = artifact["version"].replace("'", "''")
        sql = ("insert into public.learned_ranking_model (id,version,artifact) values "
               f"('beta','{version}','{text}'::jsonb) on conflict (id) do update "
               "set version=excluded.version, artifact=excluded.artifact, updated_at=now() returning version;")
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "publish.sql"
            path.write_text(sql, encoding="utf-8")
            result = linked_query(args.supabase_cli, path)
        print(json.dumps({"published": result["rows"][0]["version"]}))


if __name__ == "__main__":
    main()
