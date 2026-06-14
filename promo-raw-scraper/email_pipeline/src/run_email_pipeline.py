"""
run_email_pipeline.py — Orchestrate the full email promotion pipeline.

Steps:
  1. email_ingest.py          — Gmail promotions tab → email_text/
  2. list_email_candidates.py — Rank candidates    → logs/email_candidates.csv
  3. parse_email_candidates.py — LLM extraction   → structured_outputs/email/
                                                    logs/user_memberships.json
  4. normalize_email_promotions.py — Clean        → email_promotions.json
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SRC = Path(__file__).resolve().parent
ROOT = SRC.parent
PROJECT_ROOT = ROOT.parent          # promo-raw-scraper/ — where .env.email lives
LOGS_DIR = ROOT / "logs"


def run(cmd: list[str], label: str, log_fh) -> int:
    header = f"\n{'='*60}\n  {label}\n{'='*60}\n"
    print(header, end="")
    log_fh.write(header)
    log_fh.flush()
    process = subprocess.Popen(
        [sys.executable] + cmd,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
    )
    for line in process.stdout:
        print(line, end="")
        log_fh.write(line)
        log_fh.flush()
    process.wait()
    return process.returncode


def write_run_summary(log_path: Path, log_fh, elapsed_s: int) -> None:
    text = log_path.read_text(encoding="utf-8", errors="replace")

    # Ingest counts
    ingested   = len(re.findall(r"-> success\b", text))
    skipped    = len(re.findall(r"-> skipped_duplicate_hash\b", text))
    failed_ing = len(re.findall(r"-> failed\b", text))

    # Visibility breakdown from ingest
    private_ing = len(re.findall(r"visibility=private_user_offer", text))
    member_ing  = len(re.findall(r"visibility=member_offer", text))
    public_ing  = len(re.findall(r"visibility=public_general_offer", text))

    # Candidates
    m = re.search(r"Found (\d+) email candidates", text)
    candidates = int(m.group(1)) if m else 0

    # Parse counts
    llm_parsed   = len(re.findall(r"\[OK\].*\[LLM\]", text))
    rule_parsed  = len(re.findall(r"\[OK\].*\[rules\]", text))
    parse_failed = len(re.findall(r"^\[FAILED\]", text, re.MULTILINE))

    # Memberships detected
    m = re.search(r"Detected (\d+) membership signals", text)
    memberships = int(m.group(1)) if m else 0

    # Brand affinity
    affinity_file = ROOT / "logs" / "brand_affinity.json"
    brand_count = 0
    if affinity_file.exists():
        try:
            brand_count = len(json.loads(affinity_file.read_text()).get("brands", {}))
        except Exception:
            pass

    # Promotions output
    m = re.search(r"Wrote (\d+) email promotions from (\d+) brands", text)
    total_promos  = m.group(1) if m else "?"
    total_brands  = m.group(2) if m else "?"

    mins, secs = divmod(elapsed_s, 60)
    lines = [
        "",
        "=" * 60,
        "  EMAIL PIPELINE RUN SUMMARY",
        "=" * 60,
        f"  Ingest : {ingested} new  |  {skipped} unchanged  |  {failed_ing} failed",
        f"  Visibility : {private_ing} private  |  {member_ing} member  |  {public_ing} public",
        f"  Candidates : {candidates} passed signal filter",
        f"  Parse  : {llm_parsed} via Ollama  |  {rule_parsed} via rules  |  {parse_failed} failed",
        f"  Output : {total_promos} promotions from {total_brands} brands",
        f"  Memberships detected : {memberships}",
        f"  Brands in affinity   : {brand_count}",
        f"  Duration : {mins}m {secs}s",
        "=" * 60,
        "",
    ]
    block = "\n".join(lines)
    print(block)
    log_fh.write(block)
    log_fh.flush()


def check_ollama(host: str) -> bool:
    try:
        import requests as _req
        return _req.get(f"{host}/api/version", timeout=5).status_code == 200
    except Exception:
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the email promotion pipeline.")
    parser.add_argument("--email", type=str, default=None)
    parser.add_argument("--gmail-query", type=str, default="category:promotions newer_than:14d")
    parser.add_argument("--limit", type=int, default=200)
    parser.add_argument("--ollama-model", type=str, default="qwen2.5:14b")
    parser.add_argument("--ollama-host", type=str, default="http://localhost:11434")
    parser.add_argument("--ollama-timeout", type=int, default=3600)
    parser.add_argument("--skip-ingest", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--env-file", type=str, default=str(PROJECT_ROOT / ".env.email"))
    args = parser.parse_args()

    # Resolve env-file to absolute so subprocesses find it regardless of cwd
    if args.env_file:
        args.env_file = str(Path(args.env_file).resolve())

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_path = LOGS_DIR / f"email_pipeline_{ts}.log"

    existing = sorted(LOGS_DIR.glob("email_pipeline_*.log"))
    for old in existing[:-4]:
        old.unlink(missing_ok=True)

    start = time.time()

    with open(log_path, "w", encoding="utf-8") as log_fh:
        log_fh.write(f"Email pipeline started at {ts}\n")

        # Step 1: Ingest
        if not args.skip_ingest:
            ingest_cmd = [str(SRC / "email_ingest.py"), "--limit", str(args.limit),
                          "--gmail-query", args.gmail_query]
            if args.email:
                ingest_cmd += ["--email", args.email]
            if args.env_file:
                ingest_cmd += ["--env-file", args.env_file]
            rc = run(ingest_cmd, "Step 1/4 — Ingesting Gmail promotions", log_fh)
            if rc != 0:
                print(f"[ERROR] Ingest failed (rc={rc}). Aborting.")
                sys.exit(rc)

        # Step 2: List candidates
        rc = run([str(SRC / "list_email_candidates.py")], "Step 2/4 — Building candidate list", log_fh)
        if rc != 0:
            print(f"[ERROR] list_email_candidates failed (rc={rc}). Aborting.")
            sys.exit(rc)

        # Step 3: Parse with Ollama
        if not check_ollama(args.ollama_host):
            print(f"\n[WARN] Ollama not reachable at {args.ollama_host} — skipping Step 3.")
            print("       Start Ollama and re-run with --skip-ingest to parse without re-ingesting.")
        else:
            parse_cmd = [
                str(SRC / "parse_email_candidates.py"),
                "--ollama-model", args.ollama_model,
                "--ollama-host", args.ollama_host,
                "--ollama-timeout", str(args.ollama_timeout),
            ]
            if args.force:
                parse_cmd.append("--force")
            rc = run(parse_cmd, "Step 3/4 — Extracting promotions + memberships", log_fh)
            if rc != 0:
                print(f"[ERROR] parse_email_candidates failed (rc={rc}).")
                sys.exit(rc)

        # Step 4: Normalize
        rc = run([str(SRC / "normalize_email_promotions.py")], "Step 4/4 — Normalizing", log_fh)
        if rc != 0:
            print(f"[ERROR] normalize_email_promotions failed (rc={rc}).")
            sys.exit(rc)

        elapsed = int(time.time() - start)
        write_run_summary(log_path, log_fh, elapsed)

        m, s = divmod(elapsed, 60)
        summary = (
            f"\n{'='*60}\n"
            f"  Email pipeline complete in {m}m {s}s\n"
            f"  Promotions  -> {ROOT.parent / 'email_promotions.json'}\n"
            f"  Memberships -> {LOGS_DIR / 'user_memberships.json'}\n"
            f"  Affinity    -> {LOGS_DIR / 'brand_affinity.json'}\n"
            f"  Log         -> {log_path.name}\n"
            f"{'='*60}\n"
        )
        print(summary)
        log_fh.write(summary)


if __name__ == "__main__":
    main()
