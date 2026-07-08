"""
Full web discount extraction pipeline.

Steps:
  1.  run_scraper.py                  -fetch brand pages, save raw text (1 file per brand)
  2.  inspect_raw_data.py             -scan raw text, build summary CSV
  3.  list_text_candidates.py         -deduplicate and rank candidates
  4.  parse_candidates.py             -LLM extraction -> structured_outputs/{brand}.json
  5.  normalize_promotions.py         -clean + deduplicate -> normalized_outputs/{brand}.json
  6.  generate_review_csv.py          -human-readable review -> logs/promotion_review.csv
  7.  generate_merged_json.py         -single merged JSON -> merged_promotions.json
  8.  merge_all_promotions.py         -web + email -> all_promotions.json
  9.  generate_fast_redemption.py     -add fast_redemption to all_promotions.json
 10.  generate_scores.py              -add rank_base_score to all_promotions.json
 11.  generate_notifications.py       -notification_candidates.json -> Flutter assets
 12.  copy to promo_viewer/assets/all_promotions.json

All output is written to logs/pipeline_<timestamp>.log in addition to the terminal.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SRC = Path(__file__).resolve().parent / "src"
LOGS_DIR = Path(__file__).resolve().parent / "logs"


def run(cmd: list[str], label: str, log_fh) -> int:
    header = f"\n{'='*60}\n  {label}\n{'='*60}\n"
    print(header, end="")
    log_fh.write(header)
    log_fh.flush()

    process = subprocess.Popen(
        [sys.executable, "-u"] + cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    for line in process.stdout:
        print(line, end="")
        log_fh.write(line)
        log_fh.flush()
    process.wait()
    return process.returncode


def check_ollama(host: str) -> bool:
    try:
        import requests as _req
        r = _req.get(f"{host}/api/version", timeout=5)
        return r.status_code == 200
    except Exception:
        return False


def log_print(msg: str, log_fh) -> None:
    print(msg)
    log_fh.write(msg + "\n")
    log_fh.flush()


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the full promotion extraction pipeline.")
    parser.add_argument("--brand", type=str, default=None, help="Filter by brand substring")
    parser.add_argument("--category", type=str, default=None, help="Filter by category")
    parser.add_argument("--scrape-limit", type=int, default=None, help="Max brands to scrape")
    parser.add_argument("--parse-limit", type=int, default=999, help="Max brands to parse. Default: 999 (all)")
    parser.add_argument("--ollama-model", type=str, default="qwen2.5:14b")
    parser.add_argument("--ollama-host", type=str, default="http://localhost:11434")
    parser.add_argument("--ollama-timeout", type=int, default=3600)
    parser.add_argument("--skip-scrape", action="store_true", help="Skip step 1 (use existing raw text)")
    parser.add_argument("--force", action="store_true", help="Re-parse all brands even if content is unchanged")
    parser.add_argument("--from-step", type=int, default=1, metavar="N",
                        help="Resume from step N, skipping steps 1..N-1 (use after a crash). Default: 1")
    parser.add_argument("--failed-only", action="store_true",
                        help="In step 4, skip brands already attempted (success or failure); only process brands with no output at all")
    parser.add_argument("--gc-interval", type=int, default=10,
                        help="gc.collect() every N LLM-processed brands in step 4 (0 = off). Default: 10")
    parser.add_argument("--ollama-restart-interval", type=int, default=25,
                        help="Unload Ollama model every N brands to free VRAM (0 = off). Default: 25")
    args = parser.parse_args()

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_path = LOGS_DIR / f"pipeline_{ts}.log"

    # Keep only the 14 most recent pipeline logs
    existing_logs = sorted(LOGS_DIR.glob("pipeline_*.log"))
    for old in existing_logs[:-14]:
        old.unlink(missing_ok=True)

    start = time.time()

    with open(log_path, "w", encoding="utf-8") as log_fh:
        log_print(f"Pipeline started at {ts}", log_fh)
        log_print(f"Log: {log_path}", log_fh)

        # Step 1: Scrape
        if args.from_step <= 1 and not args.skip_scrape:
            scrape_cmd = [str(SRC / "run_scraper.py"), "--keep-raw", "1"]
            if args.brand:
                scrape_cmd += ["--brand", args.brand]
            if args.category:
                scrape_cmd += ["--category", args.category]
            if args.scrape_limit:
                scrape_cmd += ["--limit", str(args.scrape_limit)]

            rc = run(scrape_cmd, "Step 1/13 -Scraping brand pages", log_fh)
            if rc != 0:
                log_print(f"\n[ERROR] Scraper exited with code {rc}. Aborting.", log_fh)
                sys.exit(rc)

        # Step 2: Inspect
        if args.from_step <= 2:
            rc = run([str(SRC / "inspect_raw_data.py")], "Step 2/13 -Inspecting raw text files", log_fh)
            if rc != 0:
                log_print(f"\n[ERROR] inspect_raw_data exited with code {rc}. Aborting.", log_fh)
                sys.exit(rc)

        # Step 3: List candidates
        if args.from_step <= 3:
            rc = run([str(SRC / "list_text_candidates.py")], "Step 3/13 -Building candidate list", log_fh)
            if rc != 0:
                log_print(f"\n[ERROR] list_text_candidates exited with code {rc}. Aborting.", log_fh)
                sys.exit(rc)

        # Step 4: Parse (skipped if Ollama is not running or --from-step > 4)
        if args.from_step <= 4:
            if not check_ollama(args.ollama_host):
                log_print(f"\n[WARN] Ollama not reachable at {args.ollama_host} -skipping Step 4 (parse).", log_fh)
                log_print(f"       Start Ollama and re-run with --skip-scrape to parse without re-scraping.", log_fh)
            else:
                parse_cmd = [
                    str(SRC / "parse_candidates.py"),
                    "--model", "ollama",
                    "--limit", str(args.parse_limit),
                    "--ollama-model", args.ollama_model,
                    "--ollama-host", args.ollama_host,
                    "--ollama-timeout", str(args.ollama_timeout),
                    "--gc-interval", str(args.gc_interval),
                    "--ollama-restart-interval", str(args.ollama_restart_interval),
                ]
                if args.force:
                    parse_cmd.append("--force")
                if args.failed_only:
                    parse_cmd.append("--failed-only")
                if args.brand:
                    parse_cmd += ["--brand", args.brand]
                rc = run(parse_cmd, "Step 4/13 -Extracting promotions", log_fh)
                if rc != 0:
                    log_print(f"\n[WARN] parse_candidates exited with code {rc} (partial extraction). Continuing with whatever was extracted.", log_fh)

        # Step 5: Normalize
        normalize_cmd = [str(SRC / "normalize_promotions.py")]
        if args.brand:
            normalize_cmd += ["--brand", args.brand]
        rc = run(normalize_cmd, "Step 5/13 -Normalizing promotions", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] normalize_promotions exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 6: Review CSV
        review_cmd = [str(SRC / "generate_review_csv.py")]
        if args.brand:
            review_cmd += ["--brand", args.brand]
        rc = run(review_cmd, "Step 6/13 -Generating promotion review CSV", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] generate_review_csv exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 7: Merged JSON
        rc = run([str(SRC / "generate_merged_json.py")], "Step 7/13 -Generating merged promotions JSON", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] generate_merged_json exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 8: Merge web + email into all_promotions.json
        rc = run([str(SRC / "merge_all_promotions.py")], "Step 8/13 -Merging promotions", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] merge_all_promotions exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 9: Add fast_redemption to all_promotions.json
        rc = run([str(SRC / "generate_fast_redemption.py")], "Step 9/13 -Generating fast redemption data", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] generate_fast_redemption exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 10: Add rank_base_score to all_promotions.json
        rc = run([str(SRC / "generate_scores.py")], "Step 10/13 -Computing rank scores", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] generate_scores exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 11: Compute notification candidates
        rc = run([str(SRC / "generate_notifications.py")], "Step 11/13 -Computing notification candidates", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] generate_notifications exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 12: Copy to Flutter app assets
        import shutil
        assets_dest = Path(__file__).resolve().parents[1] / "promo_viewer" / "assets" / "all_promotions.json"
        src_file = Path(__file__).resolve().parent / "all_promotions.json"
        if src_file.exists():
            shutil.copy2(src_file, assets_dest)
            size_kb = assets_dest.stat().st_size // 1024
            log_print(f"\n[Step 12/13] Copied all_promotions.json to app assets ({size_kb} KB)", log_fh)
        else:
            log_print(f"\n[ERROR] all_promotions.json not found at {src_file}", log_fh)
            sys.exit(1)

        write_run_summary(log_path, log_fh)

        # Step 13: Publish updated assets to GitHub — also triggers deploy_web.yml
        # which rebuilds the Flutter web app with fresh bundled data.
        repo_root = Path(__file__).resolve().parents[1]
        assets_to_push = [
            "promo_viewer/assets/all_promotions.json",
            "promo_viewer/assets/notification_candidates.json",
        ]
        try:
            subprocess.run(["git", "add"] + assets_to_push, cwd=repo_root, check=True)
            commit_result = subprocess.run(
                ["git", "commit", "-m", f"chore: update promotions {ts}"],
                cwd=repo_root, capture_output=True, text=True,
            )
            if commit_result.returncode == 0:
                subprocess.run(["git", "push", "origin", "master"], cwd=repo_root, check=True)
                log_print(f"\n[Step 13/13] Assets pushed to GitHub.", log_fh)
            else:
                log_print(f"\n[Step 13/13] No asset changes to push.", log_fh)
        except Exception as e:
            log_print(f"\n[Step 15/15] Git push failed (non-fatal): {e}", log_fh)

        elapsed = int(time.time() - start)
        minutes, seconds = divmod(elapsed, 60)
        summary = (
            f"\n{'='*60}\n"
            f"  Pipeline complete in {minutes}m {seconds}s\n"
            f"  Raw outputs      -> structured_outputs/\n"
            f"  Clean outputs    -> normalized_outputs/\n"
            f"  Review sheet     -> logs/promotion_review.csv\n"
            f"  Merged JSON      -> merged_promotions.json\n"
            f"  App JSON         -> promo_viewer/assets/all_promotions.json\n"
            f"  Notifications    -> promo_viewer/assets/notification_candidates.json\n"
            f"  Log              -> {log_path.name}\n"
            f"{'='*60}\n"
        )
        log_print(summary, log_fh)


def write_run_summary(log_path: Path, log_fh) -> None:
    """Parse the completed log and append a human-readable stats block."""
    text = log_path.read_text(encoding="utf-8", errors="replace")

    # Scraper stats
    scrape_new     = len(re.findall(r"-> success\b", text))
    scrape_skip    = len(re.findall(r"-> skipped_duplicate_hash\b", text))
    scrape_fail    = len(re.findall(r"-> failed\b", text))

    # Changed brand names (lines ending with -> success)
    changed_brands = re.findall(r"Processing (.+?): https?://.*\n\s*-> success", text)

    # Parser stats
    parse_ok     = len(re.findall(r"^\[OK\]", text, re.MULTILINE))
    parse_skip   = len(re.findall(r"^\[SKIP\]", text, re.MULTILINE))
    parse_failed = len(re.findall(r"^\[FAILED\]", text, re.MULTILINE))

    # Failed brand names
    failed_brands = re.findall(r"^\[FAILED\] (.+?):", text, re.MULTILINE)

    # Merged output
    m = re.search(r"Merged (\d+) promotions from (\d+) brands", text)
    total_promos = m.group(1) if m else "?"
    total_brands = m.group(2) if m else "?"

    lines = [
        "",
        "=" * 60,
        "  RUN SUMMARY",
        "=" * 60,
        f"  Scrape : {scrape_new} new  |  {scrape_skip} unchanged  |  {scrape_fail} failed",
        f"  Parse  : {parse_ok} re-parsed  |  {parse_skip} skipped  |  {parse_failed} failed",
        f"  Output : {total_promos} promotions from {total_brands} brands",
    ]

    if changed_brands:
        lines.append(f"\n  Brands with new content ({len(changed_brands)}):")
        for b in sorted(changed_brands):
            lines.append(f"    + {b}")

    if failed_brands:
        lines.append(f"\n  Failed to parse ({len(failed_brands)}):")
        for b in failed_brands:
            lines.append(f"    x {b}")

    lines.append("=" * 60)
    lines.append("")

    block = "\n".join(lines)
    print(block)
    log_fh.write(block)
    log_fh.flush()


if __name__ == "__main__":
    main()
