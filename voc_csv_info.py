#!/usr/bin/env python3
"""CSV/XLSX에서 모델 컬럼/날짜 컬럼을 찾아 전체 날짜범위와 등장 모델 목록을 출력한다.
쿼트/임베디드 콤마/개행이 있는 CSV도 안전하게 처리한다 (csv 모듈 사용).
XLSX는 표준 라이브러리(zipfile + xml)로 첫 번째 시트만 읽는다 (openpyxl 불필요).

사용법:
  voc_csv_info.py <csv_or_xlsx_file>
  voc_csv_info.py --to-csv <out.csv> <xlsx_file>   # XLSX 첫 시트를 UTF-8 CSV로 변환

출력 (stdout):
  1번째 줄: <최소날짜(YYYYMMDD)>\t<최대날짜(YYYYMMDD)>
  이후 줄: 파일에 등장하는 모델명 (한 줄에 하나)
"""
import csv
import datetime
import posixpath
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

MODEL_CANDIDATES = ["MODEL_NAME", "CUSTOMER_MODEL_NAME"]
# "@cnsl_timestamp per hour", "per 3 hours", "per day" 등 Kibana 집계 간격과 무관하게 매칭
DATE_CANDIDATES = [re.compile(r"^@cnsl_timestamp(\s+per\s+.+)?$", re.IGNORECASE), "MANUFACTURING_DATE"]

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
            if isinstance(cand, re.Pattern):
                if cand.match(h):
                    return i
            elif h.lower() == cand.lower():
                return i
    return None


# ---------------------------------------------------------------- XLSX 읽기
NS_MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
NS_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
NS_PKG_REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"
# Excel 내장 날짜/시간 numFmtId
BUILTIN_DATE_FMTS = set(range(14, 23)) | {45, 46, 47}
COL_RE = re.compile(r"^([A-Z]+)")


def _col_index(ref):
    m = COL_RE.match(ref or "")
    if not m:
        return None
    n = 0
    for ch in m.group(1):
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def _text_of(elem):
    # <si>/<is> 안의 모든 <t> (리치 텍스트 run 포함)를 이어붙임
    return "".join(t.text or "" for t in elem.iter(NS_MAIN + "t"))


def _first_sheet_path(zf):
    wb = ET.fromstring(zf.read("xl/workbook.xml"))
    sheet = wb.find(f"{NS_MAIN}sheets/{NS_MAIN}sheet")
    rid = sheet.get(NS_REL + "id") if sheet is not None else None
    if rid:
        rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
        for rel in rels.iter(NS_PKG_REL + "Relationship"):
            if rel.get("Id") == rid:
                target = rel.get("Target")
                if target.startswith("/"):
                    return target.lstrip("/")
                return posixpath.normpath(posixpath.join("xl", target))
    return "xl/worksheets/sheet1.xml"


def _date_styles(zf):
    """날짜 서식이 적용된 cellXfs 인덱스 집합."""
    try:
        st = ET.fromstring(zf.read("xl/styles.xml"))
    except KeyError:
        return set()
    custom_date = set()
    numfmts = st.find(NS_MAIN + "numFmts")
    if numfmts is not None:
        for nf in numfmts:
            code = re.sub(r'"[^"]*"|\[[^\]]*\]', "", nf.get("formatCode", "")).lower()
            if re.search(r"[ymdhs]", code):
                custom_date.add(int(nf.get("numFmtId")))
    result = set()
    xfs = st.find(NS_MAIN + "cellXfs")
    if xfs is not None:
        for i, xf in enumerate(xfs):
            fid = int(xf.get("numFmtId", "0"))
            if fid in BUILTIN_DATE_FMTS or fid in custom_date:
                result.add(i)
    return result


def _serial_to_str(v):
    dt = datetime.datetime(1899, 12, 30) + datetime.timedelta(days=float(v))
    return dt.strftime("%Y-%m-%d %H:%M")


def iter_xlsx_rows(path):
    with zipfile.ZipFile(path) as zf:
        shared = []
        if "xl/sharedStrings.xml" in zf.namelist():
            sst = ET.fromstring(zf.read("xl/sharedStrings.xml"))
            shared = [_text_of(si) for si in sst.iter(NS_MAIN + "si")]
        date_styles = _date_styles(zf)
        sheet = ET.fromstring(zf.read(_first_sheet_path(zf)))

    for row in sheet.iter(NS_MAIN + "row"):
        cells = {}
        next_idx = 0
        for c in row.iter(NS_MAIN + "c"):
            idx = _col_index(c.get("r"))
            if idx is None:
                idx = next_idx
            next_idx = idx + 1
            t = c.get("t", "n")
            v = c.find(NS_MAIN + "v")
            if t == "inlineStr":
                is_ = c.find(NS_MAIN + "is")
                val = _text_of(is_) if is_ is not None else ""
            elif v is None or v.text is None:
                val = ""
            elif t == "s":
                val = shared[int(v.text)]
            elif t == "b":
                val = "TRUE" if v.text == "1" else "FALSE"
            elif t == "n" and int(c.get("s", "0")) in date_styles:
                val = _serial_to_str(v.text)
            elif t == "n":
                num = float(v.text)
                val = str(int(num)) if num.is_integer() else v.text
            else:  # str, e 등
                val = v.text
            cells[idx] = val
        width = max(cells) + 1 if cells else 0
        yield [cells.get(i, "") for i in range(width)]


def is_xlsx(path):
    return path.lower().endswith((".xlsx", ".xlsm"))


def iter_rows(path):
    if is_xlsx(path):
        yield from iter_xlsx_rows(path)
        return
    with open(path, encoding="utf-8-sig", errors="replace", newline="") as f:
        yield from csv.reader(f)


def to_csv(xlsx_path, out_path):
    with open(out_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        for row in iter_xlsx_rows(xlsx_path):
            w.writerow(row)


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--to-csv":
        to_csv(sys.argv[3], sys.argv[2])
        return

    if len(sys.argv) != 2:
        print("usage: voc_csv_info.py <csv_or_xlsx_file>", file=sys.stderr)
        print("       voc_csv_info.py --to-csv <out.csv> <xlsx_file>", file=sys.stderr)
        sys.exit(2)

    path = sys.argv[1]
    reader = iter_rows(path)
    try:
        header = next(reader)
    except StopIteration:
        print("빈 파일입니다.", file=sys.stderr)
        sys.exit(1)

    model_idx = find_col(header, MODEL_CANDIDATES)
    date_idx = find_col(header, DATE_CANDIDATES)

    if model_idx is None or date_idx is None:
        missing = []
        if model_idx is None:
            missing.append("model(" + "/".join(MODEL_CANDIDATES) + ")")
        if date_idx is None:
            missing.append("date(@cnsl_timestamp per .../MANUFACTURING_DATE)")
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
