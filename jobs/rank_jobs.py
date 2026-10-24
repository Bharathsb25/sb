"""Dedupe and rank scraped job listings against Bharath's CV profile.

Usage: python jobs/rank_jobs.py [raw.json] [--today YYYY-MM-DD] [--max-age DAYS]
Only postings at most --max-age days old (default 30) are kept.
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
    if age <= 7:
        rec = 10
    elif age <= 14:
        rec = 7
    elif age <= 30:
        rec = 4
    elif age <= 90:
        rec = 0
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


CITIES = [
    (r"chennai", "Chennai"),
    (r"bengaluru|bangalore|karnataka", "Bengaluru"),
    (r"hyderabad", "Hyderabad"),
    (r"coimbatore", "Coimbatore"),
    (r"pune", "Pune"),
    (r"remote", "Remote"),
]

# First match wins, so the closest fit to the CV comes first.
FAMILIES = [
    (r"implementation|implementaion|onboarding|configuration", "Implementation"),
    (r"customer success|client engagement|technical success|account manager|enablement", "Customer success"),
    (r"functional|\berp|zoho|odoo|netsuite|dynamics|servicenow|salesforce|oracle|\bhcm\b|hris|hrsd|workday|business central", "Functional / ERP"),
    (r"analyst|product owner|\bba\b", "Business / product analyst"),
    (r"solution|presales|value consultant|consultant", "Solution consulting"),
    (r"project|delivery|\bpmo\b|coordinat", "Project / delivery"),
    (r"\bqa\b|test", "QA"),
]


def label(text, table, default):
    for pattern, name in table:
        if re.search(pattern, text.lower()):
            return name
    return default


def plan_week(job):
    # Week 1 takes the top 15, week 2 the rest of tiers A and B.
    if job["rank"] <= 15:
        return "Week 1"
    if job["tier"] in "AB":
        return "Week 2"
    return "Backlog"


def main():
    args = sys.argv[1:]
    today = date.today()
    if "--today" in args:
        i = args.index("--today")
        today = date.fromisoformat(args[i + 1])
        del args[i : i + 2]
    max_age = 30
    if "--max-age" in args:
        i = args.index("--max-age")
        max_age = int(args[i + 1])
        del args[i : i + 2]
    raw_path = Path(args[0]) if args else HERE / "data" / "indeed_raw.json"

    jobs = json.loads(raw_path.read_text())
    scraped = len(jobs)
    jobs = [j for j in jobs if (today - date.fromisoformat(j["posted"])).days <= max_age]

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
        job["city"] = label(job["location"], CITIES, "Other")
        job["family"] = label(job["title"], FAMILIES, "Other")
        job["plan"] = plan_week(job)

    fields = ["rank", "tier", "score", "title", "company", "location", "city", "family",
              "plan", "posted", "age_days", "type", "url", "why"]
    (HERE / "ranked_jobs.json").write_text(
        json.dumps([{k: j.get(k, "") for k in fields} for j in ranked], indent=1, ensure_ascii=False) + "\n"
    )
    with open(HERE / "ranked_jobs.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(ranked)

    lines = [
        "# Ranked jobs",
        "",
        f"{len(ranked)} unique jobs posted in the last {max_age} days ({len(jobs)} of {scraped} Indeed results), ranked on {today.isoformat()}.",
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
    print(f"{scraped} raw -> {len(jobs)} within {max_age} days -> {len(ranked)} unique. Tiers: {counts}")
    for j in ranked[:25]:
        print(f"{j['rank']:>3} {j['tier']} {j['score']:>3}  {j['title']} | {j['company']} | {j['location']}")


if __name__ == "__main__":
    main()
