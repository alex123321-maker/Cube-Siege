"""
tests/unit/test_build_issue_43_gif.py - Regression test for sequential frame sorting and boundary preservation.
"""
import unittest
from pathlib import Path
from tools.build_issue_43_gif import extract_frame_index, sort_and_select_frames

class TestBuildIssue43Gif(unittest.TestCase):
    def test_legacy_lexicographical_sorting_fails_above_100_frames(self):
        """Reproduce the bug of the legacy lexicographical sorting on 135 frames (0..134)
        formatted with dyn_seq_%02d.png where 100-134 sort before 11, causing backwards jumps
        like 118 -> 12 and selecting 99 as the final frame instead of 134.
        """
        # Given 135 frames formatted as dyn_seq_%02d.png
        files = [Path(f"dyn_seq_{i:02d}.png") for i in range(135)]
        
        # Legacy algorithm: sorted(files) -> lexicographical order
        legacy_sorted = sorted(files)
        legacy_selected = legacy_sorted[::2]
        if legacy_sorted[-1] not in legacy_selected:
            legacy_selected.append(legacy_sorted[-1])
        
        legacy_indices = [extract_frame_index(f) for f in legacy_selected]
        
        # 1. The legacy order fails to maintain strictly ascending order:
        has_inversion = any(legacy_indices[i] >= legacy_indices[i + 1] for i in range(len(legacy_indices) - 1))
        self.assertTrue(has_inversion, "Legacy sorting should have inversions when crossing index 99")
        
        # 2. Specifically, jumps backward like 118 -> 12 or 134 -> 15 occur
        self.assertIn(118, legacy_indices)
        idx_118 = legacy_indices.index(118)
        self.assertEqual(legacy_indices[idx_118 + 1], 12)
        
        # 3. The last element in legacy selection is 99, NOT the final frame 134
        self.assertEqual(legacy_indices[-1], 99)
        self.assertNotEqual(legacy_indices[-1], 134)

    def test_numerical_sorting_strictly_ascending_and_preserves_boundaries(self):
        """Verify that sort_and_select_frames produces strictly increasing indices,
        starts at 0, and ends at exactly 134 for range 0..134.
        """
        files = [Path(f"dyn_seq_{i:02d}.png") for i in range(135)]
        
        selected = sort_and_select_frames(files, step=2)
        indices = [extract_frame_index(f) for f in selected]
        
        # Check boundary conditions
        self.assertEqual(indices[0], 0, "First frame index must be 0")
        self.assertEqual(indices[-1], 134, "Last frame index must be 134")
        
        # Check strictly increasing order (no inversions or backwards jumps)
        for i in range(len(indices) - 1):
            self.assertLess(
                indices[i],
                indices[i + 1],
                f"Indices must be strictly increasing, but found {indices[i]} >= {indices[i + 1]} at step {i}"
            )
            
        # Verify stepping (for step=2, difference between consecutive indices should be 2)
        self.assertEqual(indices, list(range(0, 135, 2)))
        self.assertEqual(len(indices), 68)

    def test_numerical_sorting_handles_non_aligned_lengths(self):
        """Verify that when range length is odd (e.g. 0..133, 134 frames total),
        the last element 133 is still strictly preserved at the end and indices strictly increase.
        """
        files = [Path(f"dyn_seq_{i:02d}.png") for i in range(134)]
        selected = sort_and_select_frames(files, step=2)
        indices = [extract_frame_index(f) for f in selected]
        
        self.assertEqual(indices[0], 0)
        self.assertEqual(indices[-1], 133)
        for i in range(len(indices) - 1):
            self.assertLess(indices[i], indices[i + 1])

if __name__ == "__main__":
    unittest.main()
