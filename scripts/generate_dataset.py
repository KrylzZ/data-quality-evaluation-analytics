"""Generate reproducible synthetic request/evaluation datasets.

Run from any directory: python path/to/generate_dataset.py
No third-party packages required.
"""
from __future__ import annotations

import csv
import random
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

SEED = 20261116
REQUEST_COUNT = 400
REVIEWERS = ("R01", "R02", "R03", "R04")
START = datetime(2026, 7, 1, 0, 0)
END = datetime(2026, 10, 28, 23, 59)
CATEGORIES = (
    "Extraction", "Classification", "Summarization",
    "Guideline Review", "Data Validation",
)
COMPLEXITIES = ("Low", "Medium", "High")
PROCESSING_RANGES = {"Low": (2, 8), "Medium": (6, 18), "High": (15, 40)}
ERROR_BY_DIMENSION = {
    "Accuracy_Score": "Incorrect Information",
    "Completeness_Score": "Missing Information",
    "Guideline_Score": "Guideline Violation",
}
REQUEST_COLUMNS = (
    "Request_ID", "Created_At", "Completed_At", "Category", "Language",
    "Complexity", "Processing_Time_Min", "Processing_Status",
)
EVALUATION_COLUMNS = (
    "Evaluation_ID", "Request_ID", "Reviewer_ID", "Evaluated_At",
    "Accuracy_Score", "Completeness_Score", "Guideline_Score",
    "Error_Type", "Reviewer_Notes",
)
TIME_FORMAT = "%Y-%m-%d %H:%M:%S"
RNG = random.Random(SEED)


def weighted_choice(values, weights):
    return RNG.choices(values, weights=weights, k=1)[0]


def clamp(value, low=1, high=5):
    return max(low, min(high, value))


def generate_requests():
    requests = []
    # Spread requests across the period, without assuming equal daily volume.
    total_minutes = int((END - START).total_seconds() // 60)
    for index in range(1, REQUEST_COUNT + 1):
        category = weighted_choice(CATEGORIES, (24, 22, 18, 18, 18))
        language = weighted_choice(("vi", "en"), (70, 30))
        complexity = weighted_choice(COMPLEXITIES, (40, 40, 20))
        low, high = PROCESSING_RANGES[complexity]
        duration = RNG.randint(low, high)
        if RNG.random() < 0.05:
            duration += RNG.randint(15, 45)  # Occasional slow cases

        # Use whole minutes so timestamps and CSV duration match exactly.
        created = START + timedelta(minutes=RNG.randint(0, total_minutes))
        completed = created + timedelta(minutes=duration)
        requests.append({
            "Request_ID": f"REQ{index:04d}",
            "Created_At": created.strftime(TIME_FORMAT),
            "Completed_At": completed.strftime(TIME_FORMAT),
            "Category": category,
            "Language": language,
            "Complexity": complexity,
            "Processing_Time_Min": f"{duration:.2f}",
            "Processing_Status": "Completed",
        })
    requests.sort(key=lambda row: (row["Created_At"], row["Request_ID"]))
    return requests


def generate_evaluations(requests):
    evaluations = []
    for request in requests:
        # Shared latent quality makes two independent simulated reviews correlated.
        baseline = weighted_choice((2, 3, 4, 5), (8, 18, 43, 31))
        if request["Complexity"] == "High" and RNG.random() < 0.40:
            baseline -= 1
        if request["Category"] == "Guideline Review" and RNG.random() < 0.20:
            baseline -= 1
        baseline = clamp(baseline)

        selected_reviewers = RNG.sample(REVIEWERS, 2)
        completed = datetime.strptime(request["Completed_At"], TIME_FORMAT)
        for reviewer in selected_reviewers:
            # Each reviewer scores the same request with small random variation.
            scores = {}
            for dimension in ERROR_BY_DIMENSION:
                variation = weighted_choice((-1, 0, 1), (22, 58, 20))
                scores[dimension] = clamp(baseline + variation)

            failing = [name for name, score in scores.items() if score < 4]
            if not failing:
                error_type = "None"
                note = "Meets all three evaluation criteria."
            else:
                weakest = min(failing, key=lambda name: (scores[name], RNG.random()))
                error_type = ERROR_BY_DIMENSION[weakest]
                note = f"Review needed: {weakest.replace('_Score', '').lower()} below threshold."

            evaluated = completed + timedelta(minutes=RNG.randint(5, 2880))
            evaluations.append({
                "Evaluation_ID": f"EV{len(evaluations) + 1:05d}",
                "Request_ID": request["Request_ID"],
                "Reviewer_ID": reviewer,
                "Evaluated_At": evaluated.strftime(TIME_FORMAT),
                **scores,
                "Error_Type": error_type,
                "Reviewer_Notes": note,
            })
    return evaluations


def validate(requests, evaluations):
    errors = []
    if len(requests) != REQUEST_COUNT:
        errors.append(f"Expected {REQUEST_COUNT} requests; found {len(requests)}")
    if len(evaluations) != REQUEST_COUNT * 2:
        errors.append(f"Expected {REQUEST_COUNT * 2} evaluations; found {len(evaluations)}")

    request_ids = [r["Request_ID"] for r in requests]
    evaluation_ids = [e["Evaluation_ID"] for e in evaluations]
    if len(set(request_ids)) != len(request_ids):
        errors.append("Duplicate Request_ID")
    if len(set(evaluation_ids)) != len(evaluation_ids):
        errors.append("Duplicate Evaluation_ID")
    request_lookup = {r["Request_ID"]: r for r in requests}
    by_request = defaultdict(list)

    for r in requests:
        rid = r["Request_ID"]
        if set(r) != set(REQUEST_COLUMNS):
            errors.append(f"{rid}: incorrect request schema")
        if r["Category"] not in CATEGORIES or r["Language"] not in ("vi", "en"):
            errors.append(f"{rid}: invalid category/language")
        if r["Complexity"] not in COMPLEXITIES or r["Processing_Status"] != "Completed":
            errors.append(f"{rid}: invalid complexity/status")
        created = datetime.strptime(r["Created_At"], TIME_FORMAT)
        completed = datetime.strptime(r["Completed_At"], TIME_FORMAT)
        if not START <= created <= END:
            errors.append(f"{rid}: creation date outside range")
        if completed <= created:
            errors.append(f"{rid}: invalid completion time")
        duration = (completed - created).total_seconds() / 60
        if duration <= 0 or abs(duration - float(r["Processing_Time_Min"])) > 0.001:
            errors.append(f"{rid}: duration mismatch")

    for e in evaluations:
        eid, rid = e["Evaluation_ID"], e["Request_ID"]
        if set(e) != set(EVALUATION_COLUMNS):
            errors.append(f"{eid}: incorrect evaluation schema")
        if rid not in request_lookup:
            errors.append(f"{eid}: missing foreign key {rid}")
            continue
        by_request[rid].append(e)
        if e["Reviewer_ID"] not in REVIEWERS:
            errors.append(f"{eid}: invalid reviewer")
        if datetime.strptime(e["Evaluated_At"], TIME_FORMAT) < datetime.strptime(
            request_lookup[rid]["Completed_At"], TIME_FORMAT
        ):
            errors.append(f"{eid}: evaluated before completion")
        scores = [e[name] for name in ERROR_BY_DIMENSION]
        if any(type(score) is not int or not 1 <= score <= 5 for score in scores):
            errors.append(f"{eid}: score outside 1..5")
        failed = any(score < 4 for score in scores)
        if (e["Error_Type"] == "None") == failed:
            errors.append(f"{eid}: Error_Type inconsistent with scores")
        if e["Error_Type"] not in ("None", *ERROR_BY_DIMENSION.values()):
            errors.append(f"{eid}: invalid Error_Type")
        if not e["Reviewer_Notes"]:
            errors.append(f"{eid}: empty notes")

    for rid in request_ids:
        group = by_request[rid]
        if len(group) != 2 or len({e["Reviewer_ID"] for e in group}) != 2:
            errors.append(f"{rid}: must have exactly two distinct reviewers")

    if errors:
        raise ValueError("Validation failed:\n" + "\n".join(errors[:25]))
    print("Validation: PASS (counts, IDs, FK, dates, scores, reviewer pairs, rubric)")


def write_csv(path, columns, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


def main():
    project_root = Path(__file__).resolve().parent.parent
    output_dir = project_root / "data" / "canonical"
    requests = generate_requests()
    evaluations = generate_evaluations(requests)
    validate(requests, evaluations)
    write_csv(output_dir / "requests.csv", REQUEST_COLUMNS, requests)
    write_csv(output_dir / "evaluations.csv", EVALUATION_COLUMNS, evaluations)
    passes = sum(all(e[name] >= 4 for name in ERROR_BY_DIMENSION) for e in evaluations)
    print(f"Requests generated: {len(requests)}")
    print(f"Evaluations generated: {len(evaluations)}")
    print(f"Evaluation pass rate (synthetic): {passes / len(evaluations):.1%}")
    print(f"Category counts: {dict(Counter(r['Category'] for r in requests))}")
    print(f"Files saved in: {output_dir}")


if __name__ == "__main__":
    main()
