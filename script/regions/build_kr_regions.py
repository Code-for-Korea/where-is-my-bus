#!/usr/bin/env python3
"""법정동코드 CSV(+ VWorld 법정구역 SHP)에서 Rails 지역 적재용 CSV를 만든다.

사용법과 CSV 계약은 README.md 참고.
"""
import argparse
import csv
import sys
from collections import Counter

HEADER = ["code", "parent_code", "level", "kind", "name", "south", "west", "north", "east"]
KINDS = {1: "시도", 2: "시군구", 3: "읍면동", 4: "리"}
DECIMALS = 6


def parse_codes(path):
    """법정동코드 CSV에서 `존재` 행만 [(코드, 이름)]으로 읽는다. 기본 인코딩 cp949, 실패 시 utf-8."""
    for encoding in ("cp949", "utf-8-sig"):
        try:
            with open(path, "r", encoding=encoding, newline="") as f:
                return _read_live_rows(f)
        except UnicodeDecodeError:
            continue
    raise ValueError(f"{path}: cp949/utf-8로 읽을 수 없습니다")


def _read_live_rows(f):
    reader = csv.reader(f)
    header = [h.strip() for h in next(reader)]
    code_i, name_i, status_i = (header.index(h) for h in ("법정동코드", "법정동명", "폐지여부"))
    rows = []
    for values in reader:
        if not values or values[status_i].strip() != "존재":
            continue
        rows.append((values[code_i].strip(), values[name_i].strip()))
    return rows


def _pattern_level(code):
    if code[2:] == "0" * 8:
        return 1
    if code[5:] == "0" * 5:
        return 2
    if code[8:] == "00":
        return 3
    return 4


def _sido_code(code):
    return code[:2] + "0" * 8


def classify(code, live_codes=None):
    """(레벨, 종류). 시도가 없는 시군구 자리 코드(세종)는 최상위 시도로 본다."""
    level = _pattern_level(code)
    if level == 2 and live_codes is not None and _sido_code(code) not in live_codes:
        level = 1
    return level, KINDS[level]


def parent_code(code, live_codes=None):
    """상위 지역 코드. 최상위면 None. 이름이 아니라 코드로만 구한다."""
    level, _ = classify(code, live_codes)
    if level == 1:
        return None
    if level == 2:
        return _sido_code(code)
    if level == 3:
        return code[:5] + "0" * 5
    return code[:8] + "00"


def region_name(full_name, parent_full_name):
    """전체 이름에서 상위 지역의 전체 이름을 뺀 나머지. 상위가 없으면 전체 이름."""
    full = full_name.strip()
    if parent_full_name is None:
        return full
    prefix = parent_full_name.strip() + " "
    if not full.startswith(prefix):
        raise ValueError(f"'{full}'은(는) 상위 이름 '{parent_full_name.strip()}'으로 시작하지 않습니다")
    return full[len(prefix):].strip()


def build_hierarchy(codes):
    """[(코드, 전체 이름)] -> 레벨, 코드 순 행 목록(bbox 제외). 상위가 없으면 오류."""
    full_names = {code: name.strip() for code, name in codes}
    live = set(full_names)
    rows = []
    for code, full in full_names.items():
        level, kind = classify(code, live)
        parent = parent_code(code, live)
        if parent is not None and parent not in live:
            raise ValueError(f"상위 지역이 없습니다: {code} {full} (상위 코드 {parent})")
        name = region_name(full, full_names[parent] if parent else None)
        if not name:
            raise ValueError(f"이름이 비어 있습니다: {code} {full}")
        rows.append({"code": code, "parent_code": parent or "", "level": level, "kind": kind, "name": name})
    rows.sort(key=lambda r: (r["level"], r["code"]))
    return rows


def bounds_from_shapefile(path, valid_codes):
    """SHP -> ({10자리 코드: (남, 서, 북, 동)}, 매칭 실패 코드 수).

    코드는 뒤를 0으로 채워 10자리로 맞춘 뒤 매칭한다(5/8/10자리 모두 대응).
    같은 코드의 조각이 여럿이면(다중 폴리곤, 여러 레코드) 원본 투영 좌표계 기준 가장 큰 조각만 쓴다.
    """
    import shapefile
    from pyproj import Transformer
    from shapely.geometry import shape

    reader = _open_shapefile(shapefile, path)
    transformer = Transformer.from_crs("EPSG:5186", "EPSG:4326", always_xy=True)
    largest = {}
    unmatched = set()
    with reader:
        field_names = [f[0] for f in reader.fields[1:]]
        code_i = field_names.index("A1")
        for shape_record in reader.iterShapeRecords():
            raw = str(shape_record.record[code_i]).strip()
            code = raw.ljust(10, "0")
            if code not in valid_codes:
                unmatched.add(raw)
                continue
            geometry = shape(shape_record.shape.__geo_interface__)
            for part in getattr(geometry, "geoms", [geometry]):
                if part.is_empty:
                    continue
                if code not in largest or part.area > largest[code].area:
                    largest[code] = part
    bounds = {}
    for code, part in largest.items():
        xs, ys = zip(*part.exterior.coords)
        lons, lats = transformer.transform(xs, ys)
        bounds[code] = (round(min(lats), DECIMALS), round(min(lons), DECIMALS),
                        round(max(lats), DECIMALS), round(max(lons), DECIMALS))
    return bounds, len(unmatched)


def _open_shapefile(shapefile, path):
    try:
        with shapefile.Reader(path, encoding="cp949") as probe:
            for _ in probe.iterRecords():  # 디코딩 실패는 레코드를 읽을 때 드러난다
                pass
        return shapefile.Reader(path, encoding="cp949")
    except UnicodeDecodeError:
        return shapefile.Reader(path, encoding="utf-8")


def derive_missing_bounds(rows, bounds):
    """도형이 없는 지역에 하위 지역 bbox의 합집합을 채운다(깊은 레벨부터).

    포함 관계: 자식(parent_code) + 같은 앞 4자리의 다른 시군구(시 아래 일반구).
    형제 합산은 5번째 자리가 0인 시군구(= 시 본체)만 한다. 일반구가 형제의 영역을 빌리면 틀리기 때문이다.
    반환값은 원본 bounds에 파생값을 더한 새 dict. 아무것도 없으면 채우지 않는다.
    """
    result = dict(bounds)
    children = {}
    gu_by_prefix = {}
    for r in rows:
        if r["parent_code"]:
            children.setdefault(r["parent_code"], []).append(r["code"])
        if r["level"] == 2:
            gu_by_prefix.setdefault(r["code"][:4], []).append(r["code"])
    for level in sorted({r["level"] for r in rows}, reverse=True):
        # 같은 레벨에서는 코드 내림차순: 일반구(5번째 자리 != 0)가 시 본체보다 먼저 계산된다.
        for r in sorted((r for r in rows if r["level"] == level), key=lambda r: r["code"], reverse=True):
            code = r["code"]
            if code in result:
                continue
            contained = list(children.get(code, []))
            if level == 2 and code[4] == "0":
                contained += [c for c in gu_by_prefix.get(code[:4], []) if c != code]
            boxes = [result[c] for c in contained if c in result]
            if boxes:
                result[code] = (min(b[0] for b in boxes), min(b[1] for b in boxes),
                                max(b[2] for b in boxes), max(b[3] for b in boxes))
    return result


def write_csv(path, rows, bounds):
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(HEADER)
        for r in sorted(rows, key=lambda r: (r["level"], r["code"])):
            box = bounds.get(r["code"])
            cells = [f"{v:.{DECIMALS}f}" for v in box] if box else [""] * 4
            writer.writerow([r["code"], r["parent_code"], r["level"], r["kind"], r["name"], *cells])


def main(argv=None):
    parser = argparse.ArgumentParser(description="한국 법정구역 지역 CSV 생성")
    parser.add_argument("--codes", required=True, help="법정동코드 CSV(cp949)")
    parser.add_argument("--out", required=True, help="출력 CSV")
    parser.add_argument("--sig", help="시군구 SHP")
    parser.add_argument("--emd", help="읍면동 SHP")
    parser.add_argument("--li", help="리 SHP")
    args = parser.parse_args(argv)

    rows = build_hierarchy(parse_codes(args.codes))
    valid = {r["code"] for r in rows}
    own = {}
    unmatched = 0
    for layer, path in (("SIG", args.sig), ("EMD", args.emd), ("LIG", args.li)):
        if not path:
            continue
        layer_bounds, layer_unmatched = bounds_from_shapefile(path, valid)
        print(f"{layer}: 도형 {len(layer_bounds)}개 매칭, 매칭 실패 코드 {layer_unmatched}개", file=sys.stderr)
        own.update(layer_bounds)
        unmatched += layer_unmatched
    all_bounds = derive_missing_bounds(rows, own)
    write_csv(args.out, rows, all_bounds)

    per_level = Counter(r["level"] for r in rows)
    for level in sorted(per_level):
        print(f"레벨 {level} ({KINDS[level]}): {per_level[level]}", file=sys.stderr)
    derived = sum(1 for r in rows if r["code"] in all_bounds and r["code"] not in own)
    blank = sum(1 for r in rows if r["code"] not in all_bounds)
    print(f"합계 {len(rows)}행: 자체 bbox {len(own)}, 파생 bbox {derived}, 없음 {blank}, "
          f"매칭 실패 SHP 코드 {unmatched}", file=sys.stderr)


if __name__ == "__main__":
    main()
