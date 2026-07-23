#!/usr/bin/env python3
"""CSV에서 모델 컬럼/날짜 컬럼을 찾아 전체 날짜범위와 등장 모델 목록을 출력한다.
쿼트/임베디드 콤마/개행이 있는 CSV도 안전하게 처리한다 (csv 모듈 사용).

출력 (stdout):
  1번째 줄: <최소날짜(YYYYMMDD)>\t<최대날짜(YYYYMMDD)>
  이후 줄: 파일에 등장하는 모델명 (한 줄에 하나)
"""
import csv
import re
import sys

MODEL_CANDIDATES = ["MODEL_NAME", "CUSTOMER_MODEL_NAME"]
DATE_CANDIDATES = ["@cnsl_timestamp per hour", "MANUFACTURING_DATE"]

SUFFIX_RE = re.compile(r"\s*:\s*(Descending|Ascending)\s*$", re.IGNORECASE)
DIGITS_RE = re.compile(r"\d")


def normalize_header(cell):
    cell = cell.strip()
    cell = SUFFIX_RE.sub("", cell)
    return cell.strip()


def find_col(header, candidates):
    normalized = [normalize_header(c) for c in header]
    for cand in candidates:
        for i, h in enumerate(normalized):
            if h.lower() == cand.lower():
                return i
    return None


def main():
    if len(sys.argv) != 2:
        print("usage: voc_csv_info.py <csv_file>", file=sys.stderr)
        sys.exit(2)

    path = sys.argv[1]
    with open(path, encoding="utf-8-sig", errors="replace", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            print("empty csv", file=sys.stderr)
            sys.exit(1)

        model_idx = find_col(header, MODEL_CANDIDATES)
        date_idx = find_col(header, DATE_CANDIDATES)

        if model_idx is None or date_idx is None:
            missing = []
            if model_idx is None:
                missing.append("model(" + "/".join(MODEL_CANDIDATES) + ")")
            if date_idx is None:
                missing.append("date(" + "/".join(DATE_CANDIDATES) + ")")
            print("컬럼을 찾을 수 없습니다: " + ", ".join(missing), file=sys.stderr)
            print("헤더: " + ", ".join(header), file=sys.stderr)
            sys.exit(1)

        min_date = None
        max_date = None
        models = set()

        for row in reader:
            if len(row) <= max(model_idx, date_idx):
                continue

            digits = "".join(DIGITS_RE.findall(row[date_idx]))[:8]
            if len(digits) == 8:
                if min_date is None or digits < min_date:
                    min_date = digits
                if max_date is None or digits > max_date:
                    max_date = digits

            model = row[model_idx].strip()
            if model:
                models.add(model)

    if min_date is None or max_date is None:
        print("유효한 날짜 값을 찾지 못했습니다.", file=sys.stderr)
        sys.exit(1)

    print(f"{min_date}\t{max_date}")
    for m in sorted(models):
        print(m)


if __name__ == "__main__":
    main()
