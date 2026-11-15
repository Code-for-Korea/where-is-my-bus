import csv
import importlib.util
import os
import tempfile
import unittest

import shapefile
from pyproj import Transformer

_spec = importlib.util.spec_from_file_location(
    "build_kr_regions", os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_kr_regions.py")
)
brk = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(brk)

TO_5186 = Transformer.from_crs("EPSG:4326", "EPSG:5186", always_xy=True)


def write_codes_csv(path, rows):
    with open(path, "w", encoding="cp949", newline="") as f:
        f.write("법정동코드,법정동명,폐지여부\n")
        for code, name, status in rows:
            f.write(f"{code},{name},{status}\n")


def box_5186(west, south, east, north):
    """lon/lat 사각형을 EPSG:5186 좌표의 닫힌 링으로 만든다(시계 방향 = 바깥 링)."""
    corners = [(west, south), (west, north), (east, north), (east, south), (west, south)]
    return [list(TO_5186.transform(lon, lat)) for lon, lat in corners]


def write_polygon_shp(path, records, encoding="cp949"):
    """records: [(code, [ring, ...])]; 레코드 하나가 여러 링(조각)을 가질 수 있다."""
    with shapefile.Writer(path, shapeType=shapefile.POLYGON, encoding=encoding) as w:
        w.field("A1", "C", size=10)
        w.field("A2", "C", size=40)
        for code, rings in records:
            w.poly(rings)
            w.record(code, "이름")


SAMPLE = [
    ("1100000000", "서울특별시", "존재"),
    ("1111000000", "서울특별시 종로구", "존재"),
    ("1111010100", "서울특별시 종로구 청운동", "존재"),
    ("4100000000", "경기도", "존재"),
    ("4111000000", "경기도 수원시", "존재"),
    ("4111100000", "경기도 수원시 장안구", "존재"),
    ("4111112900", "경기도 수원시 장안구 파장동", "존재"),
    ("4119900000", "경기도 폐지시", "폐지"),
    ("4719000000", "경상북도 가상군 ", "존재"),
    ("4700000000", "경상북도", "존재"),
    ("4794000000", "경상북도 울릉군", "존재"),
    ("4794025000", "경상북도 울릉군 울릉읍", "존재"),
    ("4794025027", "경상북도 울릉군 울릉읍 독도리", "존재"),
    ("3611000000", "세종특별자치시", "존재"),
    ("3611010100", "세종특별자치시 반곡동", "존재"),
]


class ClassifyTest(unittest.TestCase):
    LIVE = {code for code, _, status in SAMPLE if status == "존재"}

    def test_levels(self):
        cases = {
            "1100000000": (1, "시도"),
            "1111000000": (2, "시군구"),
            "4111100000": (2, "시군구"),
            "1111010100": (3, "읍면동"),
            "4794025000": (3, "읍면동"),
            "4794025027": (4, "리"),
        }
        for code, expected in cases.items():
            self.assertEqual(expected, brk.classify(code, self.LIVE), code)

    def test_sejong_is_root_sido(self):
        self.assertEqual((1, "시도"), brk.classify("3611000000", self.LIVE))
        self.assertIsNone(brk.parent_code("3611000000", self.LIVE))
        self.assertEqual((3, "읍면동"), brk.classify("3611010100", self.LIVE))
        self.assertEqual("3611000000", brk.parent_code("3611010100", self.LIVE))

    def test_parent_codes(self):
        cases = {
            "1100000000": None,
            "1111000000": "1100000000",
            "1111010100": "1111000000",
            "4111000000": "4100000000",
            "4111100000": "4100000000",
            "4111112900": "4111100000",
            "4794025000": "4794000000",
            "4794025027": "4794025000",
        }
        for code, expected in cases.items():
            self.assertEqual(expected, brk.parent_code(code, self.LIVE), code)

    def test_region_name(self):
        self.assertEqual("서울특별시", brk.region_name("서울특별시", None))
        self.assertEqual("종로구", brk.region_name("서울특별시 종로구", "서울특별시"))
        self.assertEqual("수원시 장안구", brk.region_name("경기도 수원시 장안구", "경기도"))
        self.assertEqual("울릉군", brk.region_name("경상북도 울릉군", "경상북도"))
        self.assertEqual("독도리", brk.region_name("경상북도 울릉군 울릉읍 독도리", "경상북도 울릉군 울릉읍"))
        self.assertEqual("파장동", brk.region_name("경기도 수원시 장안구 파장동", "경기도 수원시 장안구"))
        self.assertEqual("부천시 원미구", brk.region_name("경기도 부천시 원미구 ", "경기도"))

    def test_region_name_requires_prefix(self):
        with self.assertRaises(ValueError):
            brk.region_name("충청북도 청주시", "경기도")


class HierarchyTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "codes.csv")

    def test_parse_codes_skips_abolished(self):
        write_codes_csv(self.path, SAMPLE)
        codes = dict(brk.parse_codes(self.path))
        self.assertNotIn("4119900000", codes)
        self.assertEqual("경상북도 가상군", codes["4719000000"])
        self.assertEqual(14, len(codes))

    def test_build_hierarchy(self):
        write_codes_csv(self.path, SAMPLE)
        rows = {r["code"]: r for r in brk.build_hierarchy(brk.parse_codes(self.path))}
        self.assertEqual(14, len(rows))
        ulleung = rows["4794025027"]
        self.assertEqual(("4794025000", 4, "리", "독도리"),
                         (ulleung["parent_code"], ulleung["level"], ulleung["kind"], ulleung["name"]))
        jangan = rows["4111100000"]
        self.assertEqual(("4100000000", 2, "수원시 장안구"), (jangan["parent_code"], jangan["level"], jangan["name"]))
        self.assertEqual("4111100000", rows["4111112900"]["parent_code"])
        self.assertEqual("", rows["3611000000"]["parent_code"])
        self.assertEqual(1, rows["3611000000"]["level"])
        self.assertEqual(3, rows["3611010100"]["level"])
        self.assertEqual("가상군", rows["4719000000"]["name"])
        keys = [(r["level"], r["code"]) for r in brk.build_hierarchy(brk.parse_codes(self.path))]
        self.assertEqual(sorted(keys), keys)

    def test_missing_parent_raises(self):
        write_codes_csv(self.path, [("1100000000", "서울특별시", "존재"), ("1111010100", "서울특별시 종로구 청운동", "존재")])
        with self.assertRaises(ValueError) as ctx:
            brk.build_hierarchy(brk.parse_codes(self.path))
        self.assertIn("1111010100", str(ctx.exception))


class BoundsFromShapefileTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.shp = os.path.join(self.dir.name, "test.shp")
        self.valid = {"4794000000", "4111100000", "1111000000"}

    def test_bbox_in_lonlat(self):
        write_polygon_shp(self.shp, [("4111100000", [box_5186(127.0, 37.2, 127.1, 37.3)])])
        bounds, unmatched = brk.bounds_from_shapefile(self.shp, self.valid)
        south, west, north, east = bounds["4111100000"]
        for actual, expected in zip((south, west, north, east), (37.2, 127.0, 37.3, 127.1)):
            self.assertAlmostEqual(expected, actual, delta=1e-5)
        self.assertEqual(0, unmatched)

    def test_largest_part_only(self):
        big = box_5186(130.80, 37.40, 130.95, 37.55)
        tiny_far = box_5186(131.86, 37.24, 131.87, 37.25)  # 독도처럼 멀리 떨어진 작은 조각
        write_polygon_shp(self.shp, [("4794000000", [tiny_far, big])])
        bounds, _ = brk.bounds_from_shapefile(self.shp, self.valid)
        south, west, north, east = bounds["4794000000"]
        for actual, expected in zip((south, west, north, east), (37.40, 130.80, 37.55, 130.95)):
            self.assertAlmostEqual(expected, actual, delta=1e-5)

    def test_largest_part_across_records_with_same_code(self):
        small = box_5186(126.0, 36.0, 126.01, 36.01)
        big = box_5186(126.5, 36.5, 126.7, 36.7)
        write_polygon_shp(self.shp, [("1111000000", [small]), ("1111000000", [big])])
        bounds, _ = brk.bounds_from_shapefile(self.shp, self.valid)
        self.assertAlmostEqual(36.5, bounds["1111000000"][0], delta=1e-5)

    def test_short_code_is_right_padded(self):
        write_polygon_shp(self.shp, [("41111", [box_5186(127.0, 37.2, 127.1, 37.3)])])
        valid = {"4111100000", "4111000000"}
        bounds, unmatched = brk.bounds_from_shapefile(self.shp, valid)
        self.assertEqual({"4111100000"}, set(bounds))
        self.assertEqual(0, unmatched)

    def test_unknown_code_counted(self):
        write_polygon_shp(self.shp, [("9999900000", [box_5186(127.0, 37.2, 127.1, 37.3)]),
                                      ("4111100000", [box_5186(127.0, 37.2, 127.1, 37.3)])])
        bounds, unmatched = brk.bounds_from_shapefile(self.shp, self.valid)
        self.assertEqual({"4111100000"}, set(bounds))
        self.assertEqual(1, unmatched)


def row(code, parent, level, kind="x"):
    return {"code": code, "parent_code": parent, "level": level, "kind": kind, "name": code}


class DeriveMissingBoundsTest(unittest.TestCase):
    def test_sido_union_of_children(self):
        rows = [row("1100000000", "", 1), row("1111000000", "1100000000", 2), row("1114000000", "1100000000", 2)]
        out = brk.derive_missing_bounds(rows, {"1111000000": (37.0, 126.0, 37.5, 126.5),
                                               "1114000000": (37.2, 126.2, 37.8, 127.0)})
        self.assertEqual((37.0, 126.0, 37.8, 127.0), out["1100000000"])

    def test_si_without_geometry_uses_gu(self):
        rows = [row("4100000000", "", 1), row("4111000000", "4100000000", 2),
                row("4111100000", "4100000000", 2), row("4111300000", "4100000000", 2),
                row("4113000000", "4100000000", 2)]
        own = {"4111100000": (37.2, 127.0, 37.3, 127.1), "4111300000": (37.1, 126.9, 37.25, 127.05),
               "4113000000": (37.4, 127.1, 37.5, 127.2)}
        out = brk.derive_missing_bounds(rows, own)
        self.assertEqual((37.1, 126.9, 37.3, 127.1), out["4111000000"])
        self.assertEqual((37.1, 126.9, 37.5, 127.2), out["4100000000"])

    def test_gu_does_not_borrow_from_siblings(self):
        rows = [row("4100000000", "", 1), row("4111000000", "4100000000", 2),
                row("4111100000", "4100000000", 2), row("4111300000", "4100000000", 2)]
        out = brk.derive_missing_bounds(rows, {"4111300000": (37.1, 126.9, 37.25, 127.05)})
        self.assertNotIn("4111100000", out)

    def test_deepest_first_propagation(self):
        rows = [row("1100000000", "", 1), row("1111000000", "1100000000", 2),
                row("1111010100", "1111000000", 3), row("1111010101", "1111010100", 4)]
        out = brk.derive_missing_bounds(rows, {"1111010101": (37.5, 127.0, 37.6, 127.1)})
        for code in ("1111010100", "1111000000", "1100000000"):
            self.assertEqual((37.5, 127.0, 37.6, 127.1), out[code], code)

    def test_nothing_available_stays_blank(self):
        rows = [row("1100000000", "", 1), row("1111000000", "1100000000", 2)]
        self.assertEqual({}, brk.derive_missing_bounds(rows, {}))

    def test_own_bounds_not_overwritten(self):
        rows = [row("1100000000", "", 1), row("1111000000", "1100000000", 2)]
        own = {"1100000000": (30.0, 120.0, 40.0, 130.0), "1111000000": (37.0, 126.0, 37.5, 126.5)}
        self.assertEqual(own, brk.derive_missing_bounds(rows, own))


class WriteCsvTest(unittest.TestCase):
    def test_format(self):
        rows = [row("1111000000", "1100000000", 2, "시군구"), row("1100000000", "", 1, "시도")]
        bounds = {"1111000000": (37.5, 126.9, 37.7, 127.1)}
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "out.csv")
            brk.write_csv(path, rows, bounds)
            with open(path, "rb") as f:
                raw = f.read()
            self.assertFalse(raw.startswith(b"\xef\xbb\xbf"))
            lines = raw.decode("utf-8").splitlines()
            self.assertEqual("code,parent_code,level,kind,name,south,west,north,east", lines[0])
            parsed = list(csv.reader(lines[1:]))
            self.assertEqual(["1100000000", "", "1", "시도", "1100000000", "", "", "", ""], parsed[0])
            self.assertEqual(["1111000000", "1100000000", "2", "시군구", "1111000000",
                              "37.500000", "126.900000", "37.700000", "127.100000"], parsed[1])


if __name__ == "__main__":
    unittest.main()
