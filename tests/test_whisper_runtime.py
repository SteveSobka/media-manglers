from __future__ import annotations

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from media_manglers.core.whisper_runtime import build_runtime_plan


class WhisperRuntimePlanTests(unittest.TestCase):
    def test_longer_media_gets_a_higher_adaptive_timeout(self) -> None:
        short_plan = build_runtime_plan(
            source_duration_seconds=15 * 60,
            model_name="large",
            gpu_capable=False,
        )
        long_plan = build_runtime_plan(
            source_duration_seconds=90 * 60,
            model_name="large",
            gpu_capable=False,
        )

        self.assertGreater(
            long_plan["resolved_timeout_seconds"],
            short_plan["resolved_timeout_seconds"],
        )

    def test_larger_model_gets_a_higher_adaptive_timeout(self) -> None:
        small_plan = build_runtime_plan(
            source_duration_seconds=60 * 60,
            model_name="small",
            gpu_capable=False,
        )
        large_plan = build_runtime_plan(
            source_duration_seconds=60 * 60,
            model_name="large",
            gpu_capable=False,
        )

        self.assertGreater(
            large_plan["resolved_timeout_seconds"],
            small_plan["resolved_timeout_seconds"],
        )

    def test_explicit_timeout_override_wins(self) -> None:
        plan = build_runtime_plan(
            source_duration_seconds=60 * 60,
            model_name="large",
            gpu_capable=False,
            explicit_timeout_seconds=7777,
        )

        self.assertEqual(plan["resolved_timeout_seconds"], 7777)
        self.assertEqual(plan["timeout_source"], "explicit_override")

    def test_stall_watchdog_is_separate_from_runtime_budget(self) -> None:
        plan = build_runtime_plan(
            source_duration_seconds=90 * 60,
            model_name="large",
            gpu_capable=False,
            heartbeat_seconds=10,
        )

        self.assertIn("stall_timeout_seconds", plan)
        self.assertIn("resolved_timeout_seconds", plan)
        self.assertLess(plan["stall_timeout_seconds"], plan["resolved_timeout_seconds"])
        self.assertGreaterEqual(plan["stall_timeout_seconds"], 30)


if __name__ == "__main__":
    unittest.main()
