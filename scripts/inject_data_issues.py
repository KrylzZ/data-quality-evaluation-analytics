
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CANONICAL_DIR = ROOT / "data" / "canonical"
RAW_DIR = ROOT / "data" / "raw"

RAW_DIR.mkdir(parents=True, exist_ok=True)


def read_csv(filename):
    with open(
        CANONICAL_DIR / filename,
        "r",
        encoding="utf-8-sig",
        newline=""
    ) as file:
        reader = csv.DictReader(file)
        return list(reader), reader.fieldnames


def write_csv(filename, rows, columns):
    with open(
        RAW_DIR / filename,
        "w",
        encoding="utf-8-sig",
        newline=""
    ) as file:
        writer = csv.DictWriter(file, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


# 1. Read canonical data
requests, request_columns = read_csv("requests.csv")
evaluations, evaluation_columns = read_csv("evaluations.csv")


# 2. Inject issues into requests

# Inconsistent category: extra spaces
requests[9]["Category"] = " Classification "

# Inconsistent language casing
requests[24]["Language"] = "VI"

# Missing optional business attribute
requests[39]["Complexity"] = ""

# Duplicate a complete request row
requests.append(requests[59].copy())


# 3. Inject issues into evaluations

# Inconsistent error type casing
evaluations[14]["Error_Type"] = "none"

# Extra whitespace in reviewer ID
evaluations[29]["Reviewer_ID"] = " R02 "

# Missing reviewer notes
evaluations[44]["Reviewer_Notes"] = ""

# Duplicate an evaluation row
evaluations.append(evaluations[79].copy())


# 4. Export raw datasets
write_csv("requests_raw.csv", requests, request_columns)
write_csv("evaluations_raw.csv", evaluations, evaluation_columns)

print("Raw datasets generated.")
print(f"Requests: {len(requests)} rows")
print(f"Evaluations: {len(evaluations)} rows")
