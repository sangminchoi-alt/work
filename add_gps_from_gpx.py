#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import json
import math
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import List, Optional, Tuple

try:
    from zoneinfo import ZoneInfo
except ImportError:
    print("Python 3.9+ 가 필요합니다. (zoneinfo 미지원)", file=sys.stderr)
    sys.exit(1)


SUPPORTED_EXTENSIONS = {".jpg", ".jpeg", ".heic", ".heif"}


@dataclass
class TrackPoint:
    dt_utc: datetime
    lat: float
    lon: float
    ele: Optional[float] = None


@dataclass
class PhotoMeta:
    path: str
    dt_local: Optional[datetime]
    dt_utc: Optional[datetime]


def run_cmd(cmd: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def check_exiftool() -> None:
    result = run_cmd(["which", "exiftool"])
    if result.returncode != 0 or not result.stdout.strip():
        print("exiftool 이 설치되어 있지 않습니다.", file=sys.stderr)
        print('macOS 설치 예: brew install exiftool', file=sys.stderr)
        sys.exit(1)


def parse_gpx_time(value: str) -> datetime:
    # 예: 2026-03-21T04:15:23Z
    value = value.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value).astimezone(timezone.utc)


def parse_gpx(gpx_path: str) -> List[TrackPoint]:
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
    except Exception as e:
        print(f"GPX 파싱 실패: {gpx_path} / {e}", file=sys.stderr)
        sys.exit(1)

    ns = {}
    if root.tag.startswith("{"):
        uri = root.tag.split("}")[0].strip("{")
        ns["gpx"] = uri
        trkpt_xpath = ".//gpx:trkpt"
        time_xpath = "gpx:time"
        ele_xpath = "gpx:ele"
    else:
        trkpt_xpath = ".//trkpt"
        time_xpath = "time"
        ele_xpath = "ele"

    points: List[TrackPoint] = []

    for trkpt in root.findall(trkpt_xpath, ns):
        lat = trkpt.attrib.get("lat")
        lon = trkpt.attrib.get("lon")
        if lat is None or lon is None:
            continue

        time_node = trkpt.find(time_xpath, ns)
        if time_node is None or not time_node.text:
            continue

        ele_node = trkpt.find(ele_xpath, ns)
        ele = None
        if ele_node is not None and ele_node.text:
            try:
                ele = float(ele_node.text)
            except ValueError:
                ele = None

        try:
            dt_utc = parse_gpx_time(time_node.text)
            points.append(
                TrackPoint(
                    dt_utc=dt_utc,
                    lat=float(lat),
                    lon=float(lon),
                    ele=ele,
                )
            )
        except Exception:
            continue

    points.sort(key=lambda p: p.dt_utc)

    if not points:
        print("유효한 GPX track point 가 없습니다.", file=sys.stderr)
        sys.exit(1)

    return points


def list_photo_files(photo_dir: str) -> List[str]:
    files = []
    for root, _, filenames in os.walk(photo_dir):
        for name in filenames:
            ext = os.path.splitext(name)[1].lower()
            if ext in SUPPORTED_EXTENSIONS:
                files.append(os.path.join(root, name))
    files.sort()
    return files


def exiftool_read_datetime(paths: List[str], dt_tag: str) -> List[PhotoMeta]:
    if not paths:
        return []

    cmd = [
        "exiftool",
        "-json",
        "-n",
        f"-{dt_tag}",
        *paths,
    ]
    result = run_cmd(cmd)
    if result.returncode != 0:
        print("exiftool 읽기 실패", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        print(f"exiftool JSON 파싱 실패: {e}", file=sys.stderr)
        sys.exit(1)

    metas: List[PhotoMeta] = []
    for item in data:
        path = item.get("SourceFile")
        raw_dt = item.get(dt_tag)

        metas.append(PhotoMeta(path=path, dt_local=None, dt_utc=None))
        if not raw_dt:
            continue

        # exiftool DateTimeOriginal 예: 2026:03:21 14:15:23
        try:
            dt_local_naive = datetime.strptime(raw_dt, "%Y:%m:%d %H:%M:%S")
            metas[-1].dt_local = dt_local_naive
        except ValueError:
            continue

    return metas


def attach_timezone(photo_metas: List[PhotoMeta], tz_name: str) -> None:
    tz = ZoneInfo(tz_name)
    for meta in photo_metas:
        if meta.dt_local is None:
            continue
        local_aware = meta.dt_local.replace(tzinfo=tz)
        meta.dt_utc = local_aware.astimezone(timezone.utc)


def find_surrounding_points(points: List[TrackPoint], target_utc: datetime) -> Tuple[Optional[TrackPoint], Optional[TrackPoint]]:
    if target_utc <= points[0].dt_utc:
        return None, points[0]
    if target_utc >= points[-1].dt_utc:
        return points[-1], None

    lo = 0
    hi = len(points) - 1

    while lo <= hi:
        mid = (lo + hi) // 2
        if points[mid].dt_utc < target_utc:
            lo = mid + 1
        else:
            hi = mid - 1

    prev_pt = points[lo - 1] if lo - 1 >= 0 else None
    next_pt = points[lo] if lo < len(points) else None
    return prev_pt, next_pt


def interpolate_point(prev_pt: TrackPoint, next_pt: TrackPoint, target_utc: datetime) -> Tuple[float, float, Optional[float], float]:
    total_sec = (next_pt.dt_utc - prev_pt.dt_utc).total_seconds()
    if total_sec <= 0:
        return prev_pt.lat, prev_pt.lon, prev_pt.ele, 0.0

    elapsed_sec = (target_utc - prev_pt.dt_utc).total_seconds()
    ratio = elapsed_sec / total_sec

    lat = prev_pt.lat + (next_pt.lat - prev_pt.lat) * ratio
    lon = prev_pt.lon + (next_pt.lon - prev_pt.lon) * ratio

    ele = None
    if prev_pt.ele is not None and next_pt.ele is not None:
        ele = prev_pt.ele + (next_pt.ele - prev_pt.ele) * ratio

    nearest_gap = min(
        abs((target_utc - prev_pt.dt_utc).total_seconds()),
        abs((next_pt.dt_utc - target_utc).total_seconds()),
    )
    return lat, lon, ele, nearest_gap


def nearest_point(prev_pt: Optional[TrackPoint], next_pt: Optional[TrackPoint], target_utc: datetime) -> Tuple[float, float, Optional[float], float]:
    candidates = []
    if prev_pt is not None:
        candidates.append(prev_pt)
    if next_pt is not None:
        candidates.append(next_pt)

    if not candidates:
        raise ValueError("No GPX point candidates")

    best = min(candidates, key=lambda p: abs((p.dt_utc - target_utc).total_seconds()))
    gap = abs((best.dt_utc - target_utc).total_seconds())
    return best.lat, best.lon, best.ele, gap


def build_exiftool_write_cmd(
    path: str,
    lat: float,
    lon: float,
    ele: Optional[float],
    overwrite_original: bool,
) -> List[str]:
    lat_ref = "N" if lat >= 0 else "S"
    lon_ref = "E" if lon >= 0 else "W"

    cmd = [
        "exiftool",
        "-P",
    ]

    if overwrite_original:
        cmd.append("-overwrite_original")
    # overwrite_original=False 이면 exiftool 이 *_original 백업 생성

    cmd.extend([
        f"-GPSLatitude={abs(lat):.8f}",
        f"-GPSLatitudeRef={lat_ref}",
        f"-GPSLongitude={abs(lon):.8f}",
        f"-GPSLongitudeRef={lon_ref}",
    ])

    if ele is not None:
        alt_ref = 0 if ele >= 0 else 1
        cmd.extend([
            f"-GPSAltitude={abs(ele):.2f}",
            f"-GPSAltitudeRef={alt_ref}",
        ])

    cmd.append(path)
    return cmd


def confidence_from_gap(seconds_gap: float) -> str:
    if seconds_gap <= 5:
        return "high"
    if seconds_gap <= 15:
        return "medium"
    if seconds_gap <= 30:
        return "low"
    return "very_low"


def process(
    gpx_path: str,
    photo_dir: str,
    timezone_name: str,
    dt_tag: str,
    mode: str,
    max_gap_sec: float,
    overwrite_original: bool,
    dry_run: bool,
) -> int:
    check_exiftool()

    print(f"[1/4] GPX 읽는 중: {gpx_path}")
    points = parse_gpx(gpx_path)
    print(f"  - GPX 포인트 수: {len(points)}")
    print(f"  - GPX 시작: {points[0].dt_utc.isoformat()}")
    print(f"  - GPX 종료: {points[-1].dt_utc.isoformat()}")

    print(f"[2/4] 사진 검색 중: {photo_dir}")
    files = list_photo_files(photo_dir)
    print(f"  - 대상 사진 수: {len(files)}")

    if not files:
        print("사진이 없습니다.")
        return 0

    print(f"[3/4] EXIF 촬영시간 읽는 중: {dt_tag}")
    metas = exiftool_read_datetime(files, dt_tag)
    attach_timezone(metas, timezone_name)

    success = 0
    skipped_no_dt = 0
    skipped_outside = 0
    skipped_gap = 0
    failed_write = 0

    print("[4/4] GPS 업데이트 중")
    total = len(metas)

    for idx, meta in enumerate(metas, start=1):
        rel_path = os.path.relpath(meta.path, photo_dir)

        if meta.dt_utc is None:
            skipped_no_dt += 1
            print(f"[{idx}/{total}] SKIP no datetime: {rel_path}")
            continue

        prev_pt, next_pt = find_surrounding_points(points, meta.dt_utc)

        if prev_pt is None and next_pt is not None:
            gap = abs((next_pt.dt_utc - meta.dt_utc).total_seconds())
            if gap > max_gap_sec:
                skipped_outside += 1
                print(f"[{idx}/{total}] SKIP before GPX range: {rel_path} (gap={gap:.1f}s)")
                continue

        if prev_pt is not None and next_pt is None:
            gap = abs((meta.dt_utc - prev_pt.dt_utc).total_seconds())
            if gap > max_gap_sec:
                skipped_outside += 1
                print(f"[{idx}/{total}] SKIP after GPX range: {rel_path} (gap={gap:.1f}s)")
                continue

        try:
            if mode == "interpolate" and prev_pt is not None and next_pt is not None:
                lat, lon, ele, gap = interpolate_point(prev_pt, next_pt, meta.dt_utc)
                source = "interpolated"
            else:
                lat, lon, ele, gap = nearest_point(prev_pt, next_pt, meta.dt_utc)
                source = "nearest"
        except Exception as e:
            failed_write += 1
            print(f"[{idx}/{total}] FAIL match: {rel_path} ({e})")
            continue

        if gap > max_gap_sec:
            skipped_gap += 1
            print(f"[{idx}/{total}] SKIP gap too large: {rel_path} (gap={gap:.1f}s)")
            continue

        conf = confidence_from_gap(gap)

        if dry_run:
            print(
                f"[{idx}/{total}] DRY  {rel_path} -> "
                f"lat={lat:.8f}, lon={lon:.8f}, ele={ele}, "
                f"gap={gap:.1f}s, mode={source}, conf={conf}"
            )
            success += 1
            continue

        cmd = build_exiftool_write_cmd(
            path=meta.path,
            lat=lat,
            lon=lon,
            ele=ele,
            overwrite_original=overwrite_original,
        )
        result = run_cmd(cmd)
        if result.returncode == 0:
            success += 1
            print(
                f"[{idx}/{total}] OK   {rel_path} -> "
                f"lat={lat:.8f}, lon={lon:.8f}, gap={gap:.1f}s, mode={source}, conf={conf}"
            )
        else:
            failed_write += 1
            print(f"[{idx}/{total}] FAIL write: {rel_path}")
            if result.stderr.strip():
                print(f"           {result.stderr.strip()}")

    print("\n=== 결과 요약 ===")
    print(f"성공                : {success}")
    print(f"촬영시간 없음       : {skipped_no_dt}")
    print(f"GPX 범위 밖         : {skipped_outside}")
    print(f"허용 시간차 초과    : {skipped_gap}")
    print(f"쓰기 실패           : {failed_write}")

    return 0 if failed_write == 0 else 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="GPX 시간 기준으로 사진 EXIF GPS 좌표를 업데이트합니다."
    )
    parser.add_argument("gpx", help="GPX 파일 경로")
    parser.add_argument("photo_dir", help="사진 폴더 경로")
    parser.add_argument(
        "--timezone",
        default="Asia/Seoul",
        help="사진 EXIF 시간이 해석될 로컬 타임존 (기본: Asia/Seoul)",
    )
    parser.add_argument(
        "--datetime-tag",
        default="DateTimeOriginal",
        choices=["DateTimeOriginal", "CreateDate"],
        help="촬영시간으로 사용할 EXIF 태그 (기본: DateTimeOriginal)",
    )
    parser.add_argument(
        "--mode",
        default="interpolate",
        choices=["interpolate", "nearest"],
        help="좌표 계산 방식 (기본: interpolate)",
    )
    parser.add_argument(
        "--max-gap",
        type=float,
        default=30.0,
        help="사진 시간과 GPX 시간의 최대 허용 오차(초), 기본: 30",
    )
    parser.add_argument(
        "--overwrite-original",
        action="store_true",
        help="원본 파일을 직접 덮어씀. 없으면 exiftool 이 *_original 백업 생성",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="실제 파일 수정 없이 매칭 결과만 출력",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not os.path.isfile(args.gpx):
        print(f"GPX 파일이 없습니다: {args.gpx}", file=sys.stderr)
        return 1

    if not os.path.isdir(args.photo_dir):
        print(f"사진 폴더가 없습니다: {args.photo_dir}", file=sys.stderr)
        return 1

    return process(
        gpx_path=args.gpx,
        photo_dir=args.photo_dir,
        timezone_name=args.timezone,
        dt_tag=args.datetime_tag,
        mode=args.mode,
        max_gap_sec=args.max_gap,
        overwrite_original=args.overwrite_original,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    sys.exit(main())

