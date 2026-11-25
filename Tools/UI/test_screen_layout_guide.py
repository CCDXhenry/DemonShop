"""Geometry checks for the offline layout guide generator."""
import unittest
from build_screen_layout_guide import area, build, clip, coverage, preview, project, rectangle_union


class GuideGeometryTests(unittest.TestCase):
    def test_projection_with_letterbox_origin(self):
        self.assertEqual(project([150, 100, 250, 150], [50, 100], .5), [200, 0, 400, 100])

    def test_outside_canvas_is_excluded_before_padding(self):
        self.assertIsNone(clip([-100, 0, -1, 1080]))
        self.assertIsNone(clip([0, 0, 0, 1080]))
        self.assertEqual(clip([-20, 0, 100, 50]), [0, 0, 100, 50])

    def test_union_preserves_top_center_and_disconnected_jump(self):
        inputs = [[0, 0, 200, 100], [0, 0, 300, 60], [1700, 800, 1850, 1000]]
        result = rectangle_union(inputs)
        self.assertEqual(sum(map(area, result)), 56000)
        for rect in inputs:
            self.assertEqual(coverage(rect, result), area(rect))
        self.assertEqual(coverage([400, 0, 1600, 100], result), 0)
        self.assertEqual(coverage([0, 800, 300, 1080], result), 0)

    def test_union_keeps_hole(self):
        result = rectangle_union([[0, 0, 30, 10], [0, 20, 30, 30], [0, 10, 10, 20], [20, 10, 30, 20]])
        self.assertEqual(sum(map(area, result)), 800)
        self.assertEqual(coverage([10, 10, 20, 20], result), 0)

    def test_build_defaults_to_top_left_only_and_supports_optional_jump(self):
        def make_data(included=None):
            payload = {
                "padding": 24,
                "samples": [
                    {
                        "logicalSize": [1920, 1080],
                        "screenSize": [1920, 1080],
                        "origin": [0, 0],
                        "scale": 1.0,
                        "movementExcluded": True,
                        "modal": {"size": [1920, 1080]},
                        "reserved": [
                            {"name": "TopLeftCore", "screenRect": [0, 0, 200, 80]},
                            {"name": "JumpButton", "screenRect": [1700, 800, 1850, 950]},
                        ],
                    }
                ],
            }
            if included is not None:
                payload["includedRegionNames"] = included
            return payload

        default_result = build(make_data())
        self.assertEqual(default_result["includedRegionNames"], ["TopLeftCore"])
        self.assertEqual(default_result["rectangles"], [[0, 0, 224, 104]])
        self.assertIn("Reserved: TopLeftCore", preview(default_result))

        opt_in_result = build(make_data(["TopLeftCore", "JumpButton"]))
        self.assertEqual(opt_in_result["includedRegionNames"], ["TopLeftCore", "JumpButton"])
        self.assertEqual(opt_in_result["rectangles"], [[0, 0, 224, 104], [1676, 776, 1874, 974]])
        self.assertIn("Reserved: TopLeftCore + JumpButton", preview(opt_in_result))


if __name__ == "__main__":
    unittest.main()
