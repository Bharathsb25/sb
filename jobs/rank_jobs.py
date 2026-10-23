"""Dedupe and rank scraped job listings against Bharath's CV profile.

Usage: python jobs/rank_jobs.py [raw.json] [--today YYYY-MM-DD]
Writes jobs/ranked_jobs.csv and jobs/RANKED_JOBS.md.
"""
import csv
import json
import re
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Title keywords -> points, weighted by how closely they match the CV
# (CRM/HRMS/SaaS implementation, onboarding, product/business analysis).
TITLE_WEIGHTS = [
    (r"implementation|implementaion", 40),
    (r"onboarding", 30),
    (r"product specialist", 25),
    (r"\bcrm\b", 20),
    (r"hrms|hris|payroll|\bhcm\b|\bhrsd\b", 20),
    (r"functional (consultant|analyst)", 20),
    (r"customer success|client engagement|technical success", 25),
    (r"solutions? (consultant|engineer)|presales|product value", 15),
    (r"business (analyst|solutions analyst)|\bba\b", 15),
    (r"product (analyst|support|operations|enablement|owner)", 15),
    (r"delivery|configuration", 10),
    (r"project (coordinator|manager|management)|\bpmo\b", 10),
    (r"zoho|\berp\b|odoo|erpnext", 10),
    (r"\bqa\b|test", 8),
    (r"servicenow|salesforce|dynamics|netsuite|oracle|workday|business central|blackline|zendesk", 5),
]

# Tools and domains named on the CV.
COMPANY_BOOST = [
    (r"leadsquared", 20),
    (r"freshworks", 10),
    (r"keka", 20),
    (r"zoho", 10),
    (r"jewel", 20),
    (r"bayzat|rippling", 8),
]

LOCATION_POINTS = [
    (r"chennai", 15),
    (r"remote", 12),
    (r"coimbatore", 10),
    (r"bengaluru|bangalore|karnataka|hyderabad", 8),
    (r"pune", 4),
]

# About 3.5 years of experience, so senior/lead/manager titles are a stretch.
SENIOR = r"\b(senior|sr\.?|lead|manager|principal)\b"
JUNIOR = r"\b(associate|junior|ii)\b"


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def first_match(text, table):
    for pattern, pts in table:
        if re.search(pattern, text):
            return pts
    return 0


def score(job, today):
    title = job["title"].lower()
    reasons = []

    title_pts = sum(pts for pattern, pts in TITLE_WEIGHTS if re.search(pattern, title))
    title_pts = min(title_pts, 70)
    reasons.append(f"title +{title_pts}")
    total = title_pts

    co = first_match(job["company"].lower() + " " + title, COMPANY_BOOST)
    if co:
        total += co
        reasons.append(f"tool/domain match +{co}")

    loc = first_match(job["location"].lower(), LOCATION_POINTS)
    total += loc
    reasons.append(f"location +{loc}")

    # "Customer Success Manager" is a role name, not a seniority level.
    if re.search(SENIOR, title.replace("success manager", "")):
        total -= 10
        reasons.append("seniority -10")
    elif re.search(JUNIOR, title):
        total += 5
        reasons.append("level fit +5")

    if "intern" in job.get("type", "").lower():
        total -= 20
        reasons.append("internship -20")
    if re.search(r"part-time|contract|temporary", job.get("type", "").lower()):
        total -= 5
        reasons.append("non-permanent -5")

    age = (today - date.fromisoformat(job["posted"])).days
    if age <= 30:
        rec = 10
    elif age <= 90:
        rec = 5
    elif age <= 180:
        rec = 0
    elif age <= 365:
        rec = -10
    else:
        rec = -25
    total += rec
    reasons.append(f"posted {age}d ago {rec:+d}")

    return total, age, "; ".join(reasons)


def tier(s):
    if s >= 75:
        return "A"
    if s >= 50:
        return "B"
    return "C"


def main():
    args = sys.argv[1:]
    today = date.today()
    if "--today" in args:
        i = args.index("--today")
        today = date.fromisoformat(args[i + 1])
        del args[i : i + 2]
    raw_path = Path(args[0]) if args else HERE / "data" / "indeed_raw.json"

    jobs = json.loads(raw_path.read_text())

    # The same posting shows up under several short URLs; keep the newest.
    deduped = {}
    for job in jobs:
        key = (norm(job["title"]), norm(job["company"]))
        if key not in deduped or job["posted"] > deduped[key]["posted"]:
            deduped[key] = job

    ranked = []
    for job in deduped.values():
        s, age, why = score(job, today)
        ranked.append({**job, "score": s, "tier": tier(s), "age_days": age, "why": why})
    ranked.sort(key=lambda j: (-j["score"], j["age_days"]))
    for i, job in enumerate(ranked, 1):
        job["rank"] = i

    fields = ["rank", "tier", "score", "title", "company", "location", "posted", "age_days", "type", "url", "why"]
    with open(HERE / "ranked_jobs.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(ranked)

    lines = [
        "# Ranked jobs",
        "",
        f"{len(ranked)} unique jobs from {len(jobs)} Indeed results, ranked on {today.isoformat()}.",
        "Tier A = apply first, B = good fit, C = stretch or weak match.",
        "",
        "| # | Tier | Score | Job | Company | Location | Posted |",
        "|---|---|---|---|---|---|---|",
    ]
    for j in ranked:
        title = j["title"].replace("|", "/")
        lines.append(
            f"| {j['rank']} | {j['tier']} | {j['score']} | [{title}]({j['url']}) "
            f"| {j['company']} | {j['location']} | {j['posted']} |"
        )
    (HERE / "RANKED_JOBS.md").write_text("\n".join(lines) + "\n")

    counts = {t: sum(1 for j in ranked if j["tier"] == t) for t in "ABC"}
    print(f"{len(jobs)} raw -> {len(ranked)} unique. Tiers: {counts}")
    for j in ranked[:25]:
        print(f"{j['rank']:>3} {j['tier']} {j['score']:>3}  {j['title']} | {j['company']} | {j['location']}")


if __name__ == "__main__":
    main()
