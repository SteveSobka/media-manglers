from __future__ import annotations

from pathlib import Path
import unittest


class ReleaseGuidanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[1]
        revoked_video_id = "".join(["APOq", "EiXEC4g"])
        self.revoked_french = f"https://www.youtube.com/watch?v={revoked_video_id}"
        self.approved_french_id = "XRka52Y3kyA"

    def _read_text(self, relative_path: str) -> str:
        return (self.repo_root / relative_path).read_text(encoding="utf-8")

    def test_revoked_french_source_is_removed_from_tracked_guidance(self) -> None:
        tracked_guidance = [
            "README.md",
            "docs/guides/README.txt",
            "docs/guides/VIDEO_MANGLER.txt",
            "tools/smoke/Run-AudioSmokeTest.ps1",
        ]

        for relative_path in tracked_guidance:
            with self.subTest(path=relative_path):
                text = self._read_text(relative_path)
                self.assertNotIn(self.revoked_french, text)
                self.assertIn(self.approved_french_id, text)

    def test_current_version_has_matching_release_notes_and_readme_link(self) -> None:
        version = (self.repo_root / "VERSION").read_text(encoding="utf-8").strip()

        self.assertEqual(version, "0.7.6")
        self.assertTrue(
            (self.repo_root / "docs" / "release-notes" / f"RELEASE_NOTES_v{version}.txt").exists()
        )
        self.assertIn(
            f"[v{version} release notes](docs/release-notes/RELEASE_NOTES_v{version}.txt)",
            self._read_text("README.md"),
        )

    def test_packaged_validation_watchdog_scripts_are_tracked(self) -> None:
        self.assertTrue((self.repo_root / "tools" / "validation" / "PackagedRunWatchdog.ps1").exists())
        self.assertTrue(
            (self.repo_root / "tools" / "validation" / "Run-PackagedVideoRemoteValidation.ps1").exists()
        )


if __name__ == "__main__":
    unittest.main()
