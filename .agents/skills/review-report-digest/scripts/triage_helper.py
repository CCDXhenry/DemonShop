#!/usr/bin/env python3
"""Helper script for review-report-digest skill.

Collects latest weekly/daily reports, current git workspace status, and manages
local ignore/defer triage state stored in `.cache/report-triage.json`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


REPO_ROOT = Path(__file__).resolve().parents[4]
DAILY_DIR = REPO_ROOT / "每日代码分析报告"
WEEKLY_DIR = REPO_ROOT / "每周架构分析报告"
TRIAGE_PATH = REPO_ROOT / ".cache" / "report-triage.json"

DAILY_FILE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})(?:.*)\.md$")
WEEKLY_FILE_RE = re.compile(r"^(\d{4})-W(\d{2})(?:.*)\.md$")
HEAD_HASH_RE = re.compile(r"HEAD(?:\s*Commit)?\*{0,2}\s*[\|：:]\s*\*{0,2}`?([0-9a-fA-F]{7,40})`?")
WINDOW_END_RE = re.compile(r"[～~\-至]\s*(\d{4}-\d{2}-\d{2})")
HEAD_DATE_RE = re.compile(r"HEAD\s*Commit.*?(\d{4}-\d{2}-\d{2})")


def run_git(args: list[str], strip: bool = True) -> str:
    try:
        proc = subprocess.run(
            ["git", *args],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        return proc.stdout.strip() if strip else proc.stdout.rstrip("\r\n")
    except OSError:
        return ""


def parse_report_meta(path: Path) -> dict[str, Any]:
    try:
        head_text = path.read_text(encoding="utf-8", errors="replace")[:4000]
    except OSError:
        head_text = ""

    head_match = HEAD_HASH_RE.search(head_text)
    head_hash = head_match.group(1) if head_match else None

    window_end = None
    m_win = WINDOW_END_RE.search(head_text)
    if m_win:
        window_end = m_win.group(1)
    else:
        m_hd = HEAD_DATE_RE.search(head_text)
        if m_hd:
            window_end = m_hd.group(1)

    return {
        "name": path.name,
        "path": str(path),
        "head": head_hash,
        "window_end": window_end,
    }


def list_weekly_reports() -> list[tuple[tuple[int, int, str], Path]]:
    if not WEEKLY_DIR.is_dir():
        return []
    found: list[tuple[tuple[int, int, str], Path]] = []
    for p in WEEKLY_DIR.glob("*.md"):
        m = WEEKLY_FILE_RE.match(p.name)
        if m:
            found.append(((int(m.group(1)), int(m.group(2)), p.name), p))
    found.sort(key=lambda item: item[0])
    return found


def list_daily_reports() -> list[tuple[str, Path]]:
    if not DAILY_DIR.is_dir():
        return []
    found: list[tuple[str, Path]] = []
    for p in DAILY_DIR.glob("*.md"):
        m = DAILY_FILE_RE.match(p.name)
        if m:
            found.append((m.group(1), p))
    found.sort(key=lambda item: (item[0], item[1].name))
    return found


def load_triage() -> dict[str, Any]:
    if not TRIAGE_PATH.is_file():
        return {"version": 1, "items": []}
    try:
        data = json.loads(TRIAGE_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("items"), list):
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return {"version": 1, "items": []}


def save_triage(data: dict[str, Any]) -> None:
    TRIAGE_PATH.parent.mkdir(parents=True, exist_ok=True)
    TRIAGE_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def enrich_triage(data: dict[str, Any]) -> dict[str, Any]:
    today = dt.date.today().isoformat()
    active: list[dict[str, Any]] = []
    expired: list[dict[str, Any]] = []
    for item in data.get("items", []):
        entry = dict(item)
        defer_until = entry.get("defer_until")
        if entry.get("status") == "deferred" and defer_until and defer_until <= today:
            entry["expired"] = True
            expired.append(entry)
        else:
            entry["expired"] = False
            active.append(entry)
    return {
        "triage_file": str(TRIAGE_PATH),
        "today": today,
        "active": active,
        "expired_deferred": expired,
    }


def cmd_scan(args: argparse.Namespace) -> None:
    branch = run_git(["rev-parse", "--abbrev-ref", "HEAD"])
    head_full = run_git(["rev-parse", "HEAD"])
    head_short = head_full[:8] if head_full else ""
    head_subject = run_git(["log", "-1", "--format=%s"])
    head_date = run_git(["log", "-1", "--format=%ci"])
    status_raw = run_git(["status", "--short"], strip=False)
    dirty_files = [line for line in status_raw.splitlines() if line.strip()]

    weekly_list = list_weekly_reports()
    daily_list = list_daily_reports()

    selected_weekly: list[dict[str, Any]] = []
    selected_daily: list[dict[str, Any]] = []
    skipped_daily: list[dict[str, Any]] = []

    if args.all:
        selected_weekly = [parse_report_meta(p) for _, p in weekly_list]
        selected_daily = [parse_report_meta(p) for _, p in daily_list]
    elif args.days is not None:
        if weekly_list:
            selected_weekly = [parse_report_meta(weekly_list[-1][1])]
        cutoff = (dt.date.today() - dt.timedelta(days=args.days)).isoformat()
        for date_str, p in daily_list:
            meta = parse_report_meta(p)
            meta["date"] = date_str
            if date_str >= cutoff:
                selected_daily.append(meta)
            else:
                skipped_daily.append(meta)
    else:
        latest_weekly_meta: dict[str, Any] | None = None
        if weekly_list:
            latest_weekly_meta = parse_report_meta(weekly_list[-1][1])
            selected_weekly.append(latest_weekly_meta)

        if latest_weekly_meta:
            w_head = (latest_weekly_meta.get("head") or "").lower()
            w_end = latest_weekly_meta.get("window_end") or ""
            for date_str, p in daily_list:
                meta = parse_report_meta(p)
                meta["date"] = date_str
                d_head = (meta.get("head") or "").lower()
                same_head = bool(w_head and d_head and (w_head.startswith(d_head) or d_head.startswith(w_head)))
                if same_head or (w_end and date_str < w_end):
                    meta["skip_reason"] = "covered_by_latest_weekly"
                    skipped_daily.append(meta)
                else:
                    selected_daily.append(meta)
        else:
            for date_str, p in daily_list[-7:]:
                meta = parse_report_meta(p)
                meta["date"] = date_str
                selected_daily.append(meta)

    triage_info = enrich_triage(load_triage())

    output = {
        "repo_root": str(REPO_ROOT),
        "git": {
            "branch": branch,
            "head": head_full,
            "head_short": head_short,
            "head_subject": head_subject,
            "head_date": head_date,
            "dirty_count": len(dirty_files),
            "dirty_files": dirty_files,
        },
        "reports": {
            "selected_weekly": selected_weekly,
            "selected_daily": selected_daily,
            "skipped_daily": skipped_daily,
        },
        "triage": triage_info,
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


def upsert_triage(
    key: str,
    ids: list[str],
    title: str,
    status: str,
    reason: str,
    defer_until: str | None,
) -> dict[str, Any]:
    data = load_triage()
    items: list[dict[str, Any]] = data.get("items", [])
    today = dt.date.today().isoformat()
    norm_ids = [x.strip() for x in ids if x.strip()]

    updated = False
    for entry in items:
        if entry.get("key") == key:
            merged_ids = sorted(set(entry.get("ids", [])) | set(norm_ids))
            entry.update(
                {
                    "ids": merged_ids,
                    "title": title or entry.get("title", ""),
                    "status": status,
                    "reason": reason,
                    "defer_until": defer_until,
                    "updated_at": today,
                }
            )
            updated = True
            break

    if not updated:
        items.append(
            {
                "key": key,
                "ids": norm_ids,
                "title": title,
                "status": status,
                "reason": reason,
                "defer_until": defer_until,
                "updated_at": today,
            }
        )

    data["items"] = items
    save_triage(data)
    return data


def cmd_ignore(args: argparse.Namespace) -> None:
    ids = args.ids.split(",") if args.ids else []
    upsert_triage(args.key, ids, args.title, "ignored", args.reason, None)
    print(json.dumps({"ok": True, "action": "ignored", "key": args.key, "file": str(TRIAGE_PATH)}, ensure_ascii=False))


def cmd_defer(args: argparse.Namespace) -> None:
    ids = args.ids.split(",") if args.ids else []
    upsert_triage(args.key, ids, args.title, "deferred", args.reason, args.until)
    print(
        json.dumps(
            {"ok": True, "action": "deferred", "key": args.key, "until": args.until, "file": str(TRIAGE_PATH)},
            ensure_ascii=False,
        )
    )


def cmd_restore(args: argparse.Namespace) -> None:
    data = load_triage()
    target = args.key.strip()
    before = len(data.get("items", []))
    kept = [
        item
        for item in data.get("items", [])
        if item.get("key") != target and target not in item.get("ids", [])
    ]
    data["items"] = kept
    save_triage(data)
    print(
        json.dumps(
            {"ok": True, "action": "restored", "removed": before - len(kept), "target": target},
            ensure_ascii=False,
        )
    )


def cmd_list(_args: argparse.Namespace) -> None:
    print(json.dumps(enrich_triage(load_triage()), ensure_ascii=False, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description="DemonShop report digest & triage helper")
    sub = parser.add_subparsers(dest="command", required=True)

    p_scan = sub.add_parser("scan", help="Scan latest weekly + subsequent daily reports and triage state")
    p_scan.add_argument("--all", action="store_true", help="Include all historical reports")
    p_scan.add_argument("--days", type=int, default=None, help="Include daily reports within last N days")
    p_scan.set_defaults(func=cmd_scan)

    p_ign = sub.add_parser("ignore", help="Mark an issue/optimization as ignored in .cache/report-triage.json")
    p_ign.add_argument("--key", required=True, help="Stable fingerprint key")
    p_ign.add_argument("--ids", default="", help="Comma-separated report issue IDs")
    p_ign.add_argument("--title", required=True, help="Short human-readable title")
    p_ign.add_argument("--reason", required=True, help="Why it is ignored")
    p_ign.set_defaults(func=cmd_ignore)

    p_def = sub.add_parser("defer", help="Mark an issue/optimization as deferred until a date")
    p_def.add_argument("--key", required=True, help="Stable fingerprint key")
    p_def.add_argument("--ids", default="", help="Comma-separated report issue IDs")
    p_def.add_argument("--title", required=True, help="Short human-readable title")
    p_def.add_argument("--until", required=True, help="Defer until YYYY-MM-DD")
    p_def.add_argument("--reason", required=True, help="Why it is deferred")
    p_def.set_defaults(func=cmd_defer)

    p_res = sub.add_parser("restore", help="Remove an entry from ignore/defer list by key or ID")
    p_res.add_argument("--key", required=True, help="Fingerprint key or issue ID")
    p_res.set_defaults(func=cmd_restore)

    p_list = sub.add_parser("list", help="List current triage entries")
    p_list.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
