import unittest

import numpy as np

import demo_phase


class CutFromFlags(unittest.TestCase):
    def test_cut_starts_just_after_the_cycle_start(self):
        # Expansion seen 2.0 s after the skip: the cycle started at skip + 2.0 - 4.0.
        flags = [False] * 40 + [True] * 90 + [False] * 130
        cut = demo_phase.cut_from_flags(flags, fps=20, skip=3, period=12, expand_at=4.0)
        self.assertAlmostEqual(cut, 3 + (2.0 - 4.0 + 0.3) % 12)

    def test_the_first_rising_edge_counts_even_when_the_clip_starts_expanded(self):
        flags = [True] * 30 + [False] * 120 + [True] * 50
        cut = demo_phase.cut_from_flags(flags, fps=20, skip=3, period=12, expand_at=4.0)
        self.assertAlmostEqual(cut, 3 + (150 / 20 - 4.0 + 0.3) % 12)

    def test_no_expansion_is_an_error(self):
        with self.assertRaises(ValueError):
            demo_phase.cut_from_flags([False] * 100, fps=20, skip=3, period=12, expand_at=4.0)


class ExpandedFlags(unittest.TestCase):
    def test_a_bright_panel_on_the_left_is_detected(self):
        frames = np.zeros((20, 30, 40), dtype=np.uint8)
        frames[8:12, :, :20] = 200
        flags = demo_phase.expanded_flags(frames)
        self.assertEqual(list(np.nonzero(flags)[0]), [8, 9, 10, 11])


if __name__ == "__main__":
    unittest.main()
