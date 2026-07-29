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
  9.  run_keyword_backfill.py         -generate keywords for brands missing them
 10.  apply_keyword_store.py          -re-apply stored keywords overwritten by merge
 11.  generate_fast_redemption.py     -add fast_redemption to all_promotions.json
 12.  generate_scores.py              -add rank_base_score to all_promotions.json
 13.  generate_notifications.py       -notification_candidates.json -> Flutter assets
 14.  copy to promo_viewer/assets/all_promotions.json
 15.  git commit + push

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

import os as _os

def _load_env_file(env_path: Path) -> None:
    if not env_path.exists():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        _os.environ.setdefault(k.strip(), v.strip())

# Load API keys from .env file if present (overrides nothing already set in the environment)
try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).resolve().parent / ".env")
except ImportError:
    _load_env_file(Path(__file__).resolve().parent / ".env")

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
        sys.stdout.buffer.write(line.encode("utf-8", errors="replace"))
        sys.stdout.buffer.flush()
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
    parser.add_argument("--model", choices=["ollama", "groq", "openrouter"], default="ollama",
                        help="Extraction backend for step 4. Default: ollama")
    parser.add_argument("--ollama-model", type=str, default="qwen2.5:14b")
    parser.add_argument("--ollama-host", type=str, default="http://localhost:11434")
    parser.add_argument("--ollama-timeout", type=int, default=3600)
    parser.add_argument("--groq-model", type=str, default="llama-3.3-70b-versatile",
                        help="Groq model name (used when --model groq)")
    parser.add_argument("--groq-api-key", type=str, default=None,
                        help="Groq API key (falls back to GROQ_API_KEY env var)")
    parser.add_argument("--openrouter-model", type=str, default="openai/gpt-4o-mini",
                        help="OpenRouter model name (used when --model openrouter)")
    parser.add_argument("--openrouter-api-key", type=str, default=None,
                        help="OpenRouter API key (falls back to OPENROUTER_API_KEY env var)")
    parser.add_argument("--cloud-timeout", type=int, default=120,
                        help="Seconds before a cloud model request times out. Default: 120")
    parser.add_argument("--parallel", action="store_true",
                        help="Run Groq and Ollama concurrently in step 4, each on a designated brand slice")
    parser.add_argument("--groq-brands", type=int, default=25,
                        help="In --parallel mode: top N brands assigned to Groq. Default: 25")
    parser.add_argument("--skip-scrape", action="store_true", help="Skip step 1 (use existing raw text)")
    parser.add_argument("--force", action="store_true", help="Re-parse all brands even if content is unchanged")
    parser.add_argument("--from-step", type=int, default=1, metavar="N",
                        help="Resume from step N, skipping steps 1..N-1 (use after a crash). Default: 1")
    parser.add_argument("--failed-only", action="store_true",
                        help="In step 4, skip brands already attempted (success or failure); only process brands with no output at all")
    parser.add_argument("--clean-only", action="store_true",
                        help="In step 4, only parse brands with no prior FAILED/RETRY history. Faster for benchmarking clean LLM timing.")
    parser.add_argument("--never-extracted", action="store_true",
                        help="In step 4, only process brands that have never produced a structured output")
    parser.add_argument("--gc-interval", type=int, default=10,
                        help="gc.collect() every N LLM-processed brands in step 4 (0 = off). Default: 10")
    parser.add_argument("--ollama-restart-interval", type=int, default=0,
                        help="Unload Ollama model every N brands to free VRAM (0 = off). Default: 0 (disabled)")
    args = parser.parse_args()

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_path = LOGS_DIR / f"pipeline_{ts}.log"

    # Keep only the 45 most recent pipeline logs
    existing_logs = sorted(LOGS_DIR.glob("pipeline_*.log"))
    for old in existing_logs[:-45]:
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

        # Step 4: Parse
        if args.from_step <= 4:
            needs_ollama = args.model == "ollama" or args.parallel
            skip_step4 = False
            if needs_ollama and not check_ollama(args.ollama_host):
                log_print(f"\n[WARN] Ollama not reachable at {args.ollama_host} -skipping Step 4 (parse).", log_fh)
                log_print(f"       Start Ollama and re-run with --skip-scrape to parse without re-scraping.", log_fh)
                skip_step4 = True

            if not skip_step4:
                parse_cmd = [
                    str(SRC / "parse_candidates.py"),
                    "--limit", str(args.parse_limit),
                    "--gc-interval", str(args.gc_interval),
                    "--ollama-model", args.ollama_model,
                    "--ollama-host", args.ollama_host,
                    "--ollama-timeout", str(args.ollama_timeout),
                    "--ollama-restart-interval", str(args.ollama_restart_interval),
                    "--groq-model", args.groq_model,
                    "--openrouter-model", args.openrouter_model,
                    "--cloud-timeout", str(args.cloud_timeout),
                ]
                if args.parallel:
                    parse_cmd += [
                        "--parallel",
                        "--groq-brands", str(args.groq_brands),
                    ]
                    if args.groq_api_key:
                        parse_cmd += ["--groq-api-key", args.groq_api_key]
                else:
                    parse_cmd += ["--model", args.model]
                    if args.model == "groq" and args.groq_api_key:
                        parse_cmd += ["--groq-api-key", args.groq_api_key]
                    if args.model == "openrouter" and args.openrouter_api_key:
                        parse_cmd += ["--openrouter-api-key", args.openrouter_api_key]
                if args.force:
                    parse_cmd.append("--force")
                if args.failed_only:
                    parse_cmd.append("--failed-only")
                if args.clean_only:
                    parse_cmd.append("--clean-only")
                if args.never_extracted:
                    parse_cmd.append("--never-extracted")
                if args.brand:
                    parse_cmd += ["--brand", args.brand]
                rc = run(parse_cmd, "Step 4/13 -Extracting promotions", log_fh)
                if rc != 0:
                    log_print(f"\n[WARN] parse_candidates exited with code {rc} (partial extraction). Continuing with whatever was extracted.", log_fh)

        # Step 5: Normalize
        if args.from_step <= 5:
            normalize_cmd = [str(SRC / "normalize_promotions.py")]
            if args.brand:
                normalize_cmd += ["--brand", args.brand]
            rc = run(normalize_cmd, "Step 5/13 -Normalizing promotions", log_fh)
            if rc != 0:
                log_print(f"\n[ERROR] normalize_promotions exited with code {rc}.", log_fh)
                sys.exit(rc)

        # Step 5b: Backfill deal URLs from raw text markers (no LLM needed)
        if args.from_step <= 6:
            backfill_cmd = [str(SRC.parent / "backfill_deal_urls.py")]
            rc = run(backfill_cmd, "Step 5b/13 -Backfilling deal URLs from raw text", log_fh)
            if rc != 0:
                log_print(f"\n[WARN] backfill_deal_urls exited with code {rc} (non-fatal).", log_fh)

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
        rc = run([str(SRC / "merge_all_promotions.py")], "Step 8/15 -Merging promotions", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] merge_all_promotions exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 9: Generate keywords for any brand in all_promotions.json that is missing them.
        # Rebuilds the queue each run so newly-added brands are always picked up.
        # Non-fatal: a keyword failure should not abort the rest of the pipeline.
        if args.model == "openrouter":
            kw_cmd = [
                str(SRC / "run_keyword_backfill.py"),
                "--rebuild-queue", "--batch", "999",
                "--openrouter", "--openrouter-model", args.openrouter_model,
            ]
        else:
            kw_cmd = [
                str(SRC / "run_keyword_backfill.py"),
                "--rebuild-queue", "--batch", "999",
                "--ollama", "--ollama-model", args.ollama_model,
            ]
        rc = run(kw_cmd, "Step 9/15 -Generating missing keywords", log_fh)
        if rc != 0:
            log_print(f"\n[WARN] run_keyword_backfill exited with code {rc} (non-fatal).", log_fh)

        # Step 10: Re-apply keyword store so stored keywords survive the merge step rewrite.
        rc = run([str(SRC / "apply_keyword_store.py")], "Step 10/15 -Applying keyword store", log_fh)
        if rc != 0:
            log_print(f"\n[WARN] apply_keyword_store exited with code {rc} (non-fatal).", log_fh)

        # Step 11: Add fast_redemption to all_promotions.json
        rc = run([str(SRC / "generate_fast_redemption.py")], "Step 11/15 -Generating fast redemption data", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] generate_fast_redemption exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 12: Add rank_base_score to all_promotions.json
        rc = run([str(SRC / "generate_scores.py")], "Step 12/15 -Computing rank scores", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] generate_scores exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 13: Compute notification candidates
        rc = run([str(SRC / "generate_notifications.py")], "Step 13/15 -Computing notification candidates", log_fh)
        if rc != 0:
            log_print(f"\n[ERROR] generate_notifications exited with code {rc}.", log_fh)
            sys.exit(rc)

        # Step 13b: Send push notifications via Supabase Edge Function (non-fatal)
        _send_push_notifications(log_fh)

        # Step 14: Copy to Flutter app assets
        import shutil
        assets_dest = Path(__file__).resolve().parents[1] / "promo_viewer" / "assets" / "all_promotions.json"
        src_file = Path(__file__).resolve().parent / "all_promotions.json"
        if src_file.exists():
            shutil.copy2(src_file, assets_dest)
            size_kb = assets_dest.stat().st_size // 1024
            log_print(f"\n[Step 14/15] Copied all_promotions.json to app assets ({size_kb} KB)", log_fh)
        else:
            log_print(f"\n[ERROR] all_promotions.json not found at {src_file}", log_fh)
            sys.exit(1)

        write_run_summary(log_path, log_fh)

        # Step 15: Publish updated assets to GitHub — also triggers deploy_web.yml
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
                log_print(f"\n[Step 15/15] Assets pushed to GitHub.", log_fh)
            else:
                log_print(f"\n[Step 15/15] No asset changes to push.", log_fh)
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


def _send_push_notifications(log_fh) -> None:
    """POST notification candidates to the Supabase Edge Function. Non-fatal."""
    try:
        import json
        import urllib.request

        assets_dir = Path(__file__).resolve().parents[1] / "promo_viewer" / "assets"
        candidates_path = assets_dir / "notification_candidates.json"
        if not candidates_path.exists():
            log_print("[Push] notification_candidates.json not found - skipping push.", log_fh)
            return

        supabase_url     = _os.environ.get("SUPABASE_URL", "").rstrip("/")
        service_role_key = _os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not supabase_url or not service_role_key:
            log_print("[Push] SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set - skipping push.", log_fh)
            return

        data = json.loads(candidates_path.read_text(encoding="utf-8"))
        candidates = data.get("candidates", [])
        payload = json.dumps({"candidates": candidates}).encode()

        url = f"{supabase_url}/functions/v1/send-push"
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {service_role_key}",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            log_print(
                f"[Push] Sent {result.get('sent', 0)} push(es) to "
                f"{result.get('users', 0)} user(s) from "
                f"{result.get('candidates', 0)} candidate(s).",
                log_fh,
            )
    except Exception as exc:
        log_print(f"[Push] Edge Function call failed (non-fatal): {exc}", log_fh)


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
