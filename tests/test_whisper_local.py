from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace
import json
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from media_manglers.providers import whisper_local


class _FakeCuda:
    @staticmethod
    def is_available() -> bool:
        return True

    @staticmethod
    def device_count() -> int:
        return 2

    @staticmethod
    def get_device_name(index: int) -> str:
        return f"Fake RTX {index}"


class _FakeTorchModule:
    __version__ = "9.9.9+cu999"
    version = SimpleNamespace(cuda="99.9")
    cuda = _FakeCuda()


class _FakeCpuCuda:
    @staticmethod
    def is_available() -> bool:
        return False

    @staticmethod
    def device_count() -> int:
        return 0


class _FakeCpuTorchModule:
    __version__ = "2.11.0+cpu"
    version = SimpleNamespace(cuda="")
    cuda = _FakeCpuCuda()


class _FakeModel:
    def __init__(self, device_name: str) -> None:
        self._device_name = device_name

    def transcribe(
        self,
        audio_path: str,
        *,
        language: str | None,
        task: str,
        verbose: bool,
        fp16: bool,
    ) -> dict[str, object]:
        if self._device_name == "cuda":
            raise RuntimeError("simulated CUDA failure")
        return {
            "language": language or "en",
            "segments": [
                {"start": 0.0, "end": 1.0, "text": "hello world"},
            ],
        }


class _FakeWhisperModule:
    @staticmethod
    def load_model(model_name: str, device: str) -> _FakeModel:
        return _FakeModel(device)


class WhisperLocalProviderTests(unittest.TestCase):
    def test_probe_environment_reports_gpu_capable_runtime_details(self) -> None:
        with mock.patch.dict(
            sys.modules,
            {
                "whisper": _FakeWhisperModule(),
                "torch": _FakeTorchModule(),
            },
            clear=False,
        ):
            result = whisper_local.probe_environment(emit_logs=False)

        self.assertTrue(result["whisper_import_ok"])
        self.assertTrue(result["torch_import_ok"])
        self.assertTrue(result["cuda_available"])
        self.assertEqual(result["device"], "cuda")
        self.assertEqual(result["selected_device"], "cuda")
        self.assertEqual(result["cuda_device_count"], 2)
        self.assertEqual(result["cuda_device_names"], ["Fake RTX 0", "Fake RTX 1"])
        self.assertEqual(result["selected_device_name"], "Fake RTX 0")
        self.assertEqual(result["classification_code"], "gpu_capable_for_whisper")
        self.assertTrue(result["can_run_local_whisper"])
        self.assertTrue(str(result["python_path"]).lower().endswith("python.exe") or "python" in str(result["python_path"]).lower())
        self.assertTrue(result["python_version"])

    def test_probe_environment_reports_cpu_only_runtime_details(self) -> None:
        with mock.patch.dict(
            sys.modules,
            {
                "whisper": _FakeWhisperModule(),
                "torch": _FakeCpuTorchModule(),
            },
            clear=False,
        ):
            result = whisper_local.probe_environment(emit_logs=False)

        self.assertTrue(result["whisper_import_ok"])
        self.assertTrue(result["torch_import_ok"])
        self.assertFalse(result["cuda_available"])
        self.assertEqual(result["selected_device"], "cpu")
        self.assertEqual(result["cuda_device_count"], 0)
        self.assertEqual(result["cuda_device_names"], [])
        self.assertEqual(result["classification_code"], "cpu_only_for_whisper")
        self.assertEqual(result["classification_label"], "CPU-only for Local Whisper")
        self.assertTrue(result["can_run_local_whisper"])

    def test_transcribe_from_request_records_gpu_fallback_progress(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            audio_path = temp_root / "input.mp3"
            output_dir = temp_root / "output"
            progress_file = temp_root / "progress.json"
            audio_path.write_bytes(b"fake-audio")

            payload = {
                "audio_path": str(audio_path),
                "output_dir": str(output_dir),
                "model_name": "large",
                "language_code": "en",
                "prefer_gpu": True,
                "task_name": "transcribe",
                "progress_file": str(progress_file),
                "heartbeat_interval_seconds": 15,
            }

            with mock.patch.dict(
                sys.modules,
                {
                    "whisper": _FakeWhisperModule(),
                    "torch": _FakeTorchModule(),
                },
                clear=False,
            ):
                result = whisper_local.transcribe_from_request(payload)

            progress_state = json.loads(progress_file.read_text(encoding="utf-8"))

            self.assertEqual(result["device"], "cpu")
            self.assertEqual(result["gpu_error"], "simulated CUDA failure")
            self.assertEqual(result["requested_device"], "cuda")
            self.assertEqual(result["selected_device"], "cpu")
            self.assertEqual(result["device_switch_count"], 1)
            self.assertEqual(result["classification_code"], "gpu_capable_for_whisper")
            self.assertEqual(result["cuda_device_names"], ["Fake RTX 0", "Fake RTX 1"])
            self.assertEqual(progress_state["device"], "cpu")
            self.assertEqual(progress_state["selected_device"], "cpu")
            self.assertEqual(progress_state["requested_device"], "cuda")
            self.assertEqual(progress_state["device_switch_count"], 1)
            self.assertEqual(progress_state["gpu_error"], "simulated CUDA failure")
            self.assertEqual(progress_state["stage"], "complete")
            self.assertTrue((output_dir / "transcript.json").exists())
            self.assertTrue((output_dir / "transcript.srt").exists())
            self.assertTrue((output_dir / "transcript.txt").exists())


if __name__ == "__main__":
    unittest.main()
