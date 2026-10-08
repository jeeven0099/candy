"""Generate a synthetic native-CatBoost parity fixture, never a deployment model."""
import json
import tempfile
from pathlib import Path

from catboost import CatBoostClassifier, Pool
from train_preferences import FEATURE_NAMES, compile_model

rows = []
labels = []
for i in range(60):
    row = [0.0 for _ in FEATURE_NAMES]
    row[0] = (i % 10) / 10
    row[15] = 0.4 if i % 2 else -0.4
    row[23] = 0.5
    rows.append(row)
    labels.append(int(i % 2 != 0))
model = CatBoostClassifier(iterations=6, depth=2, verbose=False, allow_writing_files=False,
                           thread_count=2, random_seed=67)
model.fit(Pool(rows, labels, feature_names=FEATURE_NAMES))
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / "model.json"
    model.save_model(str(path), format="json")
    artifact = compile_model(json.loads(path.read_text()), 0.5, "test_fixture_never_publish")
artifact["validated"] = True
fixture = {
    "artifact": artifact,
    "samples": [{"features": dict(zip(FEATURE_NAMES, row)), "probability": float(p)}
                for row, p in zip(rows[:4], model.predict_proba(rows[:4])[:, 1])],
}
target = Path(__file__).resolve().parent.parent / "promo_viewer/test/fixtures/catboost_numeric.json"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(fixture, indent=2) + "\n", encoding="utf-8")
print("Generated synthetic CatBoost parity fixture")
