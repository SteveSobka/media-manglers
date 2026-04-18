"""Tracked local Whisper helpers for the phased migration."""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timezone
import json
import os
import sys
import threading
import time
from typing import Any

from media_manglers.core.transcripts import write_transcript_files
from media_manglers.core.whisper_runtime import build_runtime_plan


def _log(message: str) -> None:
    print(message, flush=True)


def _configure_stdio() -> None:
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            try:
                reconfigure(encoding="utf-8", errors="replace")
            except Exception:
                pass


def _write_progress(
    progress_file: str,
    *,
    stage: str,
    message: str,
    started_at: float,
    extra: dict[str, Any] | None = None,
) -> None:
    if not progress_file:
        return

    payload: dict[str, Any] = {
        "stage": stage,
        "message": message,
        "elapsed_seconds": round(max(0.0, time.time() - started_at), 1),
        "updated_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    if extra:
        payload.update(extra)

    temp_path = progress_file + ".tmp"
    try:
        with open(temp_path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
        os.replace(temp_path, progress_file)
    except Exception:
        try:
            if os.path.exists(temp_path):
                os.remove(temp_path)
        except OSError:
            pass


def _collect_cuda_device_names(torch_module: Any, device_count: int) -> list[str]:
    device_names: list[str] = []
    device_name_getter = getattr(getattr(torch_module, "cuda", None), "get_device_name", None)
    if not callable(device_name_getter):
        return device_names

    for index in range(max(0, device_count)):
        try:
            device_name = str(device_name_getter(index) or "").strip()
        except Exception:
            continue
        if device_name:
            device_names.append(device_name)

    return device_names


def _classify_probe_environment(result: dict[str, Any]) -> None:
    whisper_import_ok = bool(result.get("whisper_import_ok"))
    torch_import_ok = bool(result.get("torch_import_ok"))
    cuda_available = bool(result.get("cuda_available"))
    cuda_device_count = int(result.get("cuda_device_count") or 0)
    cuda_device_names = [
        str(name).strip()
        for name in (result.get("cuda_device_names") or [])
        if str(name).strip()
    ]

    classification_code = "misconfigured_or_uncertain"
    classification_label = "Local Whisper runtime misconfigured or uncertain"
    classification_summary = (
        "The selected Python runtime is not ready for a trustworthy Local Whisper run yet."
    )
    classification_action = (
        "Fix the selected Python runtime before starting a long Local Whisper run."
    )
    can_run_local_whisper = False

    if whisper_import_ok and torch_import_ok and cuda_available:
        if cuda_device_count > 0 or cuda_device_names:
            classification_code = "gpu_capable_for_whisper"
            classification_label = "GPU-capable for Local Whisper"
            classification_summary = (
                "This machine can run Local Whisper on CUDA in the selected Python runtime."
            )
            classification_action = (
                "You can use this box for real CUDA Local Whisper runs."
            )
            can_run_local_whisper = True
        else:
            classification_summary = (
                "PyTorch reported CUDA available, but no CUDA devices were reported by "
                "the selected Python runtime."
            )
            classification_action = (
                "Treat this machine as uncertain and repair the Python/CUDA runtime "
                "before a long Local Whisper run."
            )
    elif whisper_import_ok and torch_import_ok:
        classification_code = "cpu_only_for_whisper"
        classification_label = "CPU-only for Local Whisper"
        classification_summary = (
            "This machine can run Local Whisper on CPU, but CUDA is not available in "
            "the selected Python runtime."
        )
        classification_action = (
            "CPU-only validation is fine here. Use a GPU-capable box when you need "
            "CUDA-backed Local Whisper runs."
        )
        can_run_local_whisper = True
    elif whisper_import_ok and not torch_import_ok:
        classification_summary = (
            "Whisper imported, but PyTorch did not import cleanly in the selected "
            "Python runtime."
        )
        classification_action = (
            "Repair the PyTorch install or pick a different Python interpreter before "
            "starting Local Whisper."
        )
    elif torch_import_ok and not whisper_import_ok:
        classification_summary = (
            "PyTorch imported, but whisper did not import cleanly in the selected "
            "Python runtime."
        )
        classification_action = (
            "Install or repair openai-whisper before starting Local Whisper."
        )
    else:
        classification_summary = (
            "The selected Python runtime could not import whisper or PyTorch cleanly."
        )
        classification_action = (
            "Repair the Local Whisper Python runtime before starting a long run."
        )

    result["classification_code"] = classification_code
    result["classification_label"] = classification_label
    result["classification_summary"] = classification_summary
    result["classification_action"] = classification_action
    result["can_run_local_whisper"] = can_run_local_whisper


def probe_environment(*, emit_logs: bool = True) -> dict[str, Any]:
    _configure_stdio()
    result: dict[str, Any] = {
        "python_path": sys.executable,
        "python_version": sys.version.split()[0],
        "whisper_import_ok": False,
        "torch_import_ok": False,
        "cuda_available": False,
        "device": "cpu",
        "selected_device": "cpu",
        "selected_device_name": "",
        "cuda_device_count": 0,
        "cuda_device_names": [],
        "torch_version": "",
        "cuda_version": "",
        "error": "",
    }

    try:
        if emit_logs:
            _log("[PY-PROBE] Importing whisper...")
        __import__("whisper")
        result["whisper_import_ok"] = True
    except Exception as exc:
        result["error"] = f"whisper import failed: {exc}"

    try:
        if emit_logs:
            _log("[PY-PROBE] Importing torch...")
        import torch

        result["torch_import_ok"] = True
        result["torch_version"] = str(getattr(torch, "__version__", "") or "")
        result["cuda_version"] = str(getattr(torch.version, "cuda", "") or "")
        result["cuda_available"] = bool(torch.cuda.is_available())
        result["selected_device"] = "cuda" if result["cuda_available"] else "cpu"
        result["device"] = result["selected_device"]
        device_count_getter = getattr(getattr(torch, "cuda", None), "device_count", None)
        if callable(device_count_getter):
            try:
                result["cuda_device_count"] = max(0, int(device_count_getter()))
            except Exception:
                result["cuda_device_count"] = 0
        if result["cuda_available"] and result["cuda_device_count"] > 0:
            result["cuda_device_names"] = _collect_cuda_device_names(
                torch,
                result["cuda_device_count"],
            )
            if result["cuda_device_names"]:
                result["selected_device_name"] = result["cuda_device_names"][0]
    except Exception as exc:
        if result["error"]:
            result["error"] += f" | torch import failed: {exc}"
        else:
            result["error"] = f"torch import failed: {exc}"

    _classify_probe_environment(result)
    return result


def _run_transcription(
    audio_path: str,
    model_name: str,
    language_code: str,
    task_name: str,
    prefer_gpu: bool,
    progress_callback: Callable[[str, str, str, dict[str, Any] | None], None] | None = None,
) -> tuple[dict[str, Any], str, bool, str]:
    import whisper

    torch = None
    gpu_error = ""
    requested_device = "cuda" if prefer_gpu else "cpu"
    if prefer_gpu:
        try:
            import torch as imported_torch

            torch = imported_torch
        except Exception as exc:
            _log(f"[PY] Torch import failed. GPU path disabled. {exc}")

    def run(device_name: str) -> tuple[dict[str, Any], bool]:
        fp16 = device_name == "cuda"
        if progress_callback:
            progress_callback(
                "loading_model",
                f"Loading Whisper model '{model_name}' on {device_name}",
                device_name,
                {"requested_device": requested_device},
            )
        _log(f"[PY] Loading model '{model_name}' on device '{device_name}'...")
        model = whisper.load_model(model_name, device=device_name)
        if progress_callback:
            progress_callback(
                "transcribing",
                f"Running Whisper {task_name} on {device_name}",
                device_name,
                {"requested_device": requested_device},
            )
        _log(f"[PY] Starting {task_name} on {device_name}...")
        result = model.transcribe(
            audio_path,
            language=language_code or None,
            task=task_name,
            verbose=False,
            fp16=fp16,
        )
        return result, fp16

    if prefer_gpu and torch is not None and torch.cuda.is_available():
        try:
            result, fp16 = run("cuda")
            return result, "cuda", fp16, gpu_error
        except Exception as exc:
            gpu_error = str(exc)
            _log(f"[PY] GPU transcription failed. Retrying on CPU. {exc}")
            if progress_callback:
                progress_callback(
                    "fallback_to_cpu",
                    f"GPU failed. Retrying on CPU. {gpu_error}",
                    "cpu",
                    {
                        "requested_device": requested_device,
                        "device_event": "gpu_to_cpu_fallback",
                        "device_switch_count": 1,
                        "gpu_error": gpu_error,
                        "selected_device": "cpu",
                    },
                )

    result, fp16 = run("cpu")
    return result, "cpu", fp16, gpu_error


def transcribe_from_request(payload: dict[str, Any]) -> dict[str, Any]:
    _configure_stdio()
    audio_path = str(payload.get("audio_path") or "")
    output_dir = str(payload.get("output_dir") or "")
    model_name = str(payload.get("model_name") or "")
    language_code = str(payload.get("language_code") or "")
    ffmpeg_dir = str(payload.get("ffmpeg_dir") or "")
    prefer_gpu = bool(payload.get("prefer_gpu", False))
    task_name = str(payload.get("task_name") or "transcribe")
    json_name = str(payload.get("json_name") or "transcript.json")
    srt_name = str(payload.get("srt_name") or "transcript.srt")
    text_name = str(payload.get("text_name") or "transcript.txt")
    progress_file = str(payload.get("progress_file") or "")
    heartbeat_interval_seconds = max(10, int(payload.get("heartbeat_interval_seconds") or 15))

    if not audio_path:
        raise ValueError("audio_path is required.")
    if not model_name:
        raise ValueError("model_name is required.")

    if ffmpeg_dir:
        os.environ["PATH"] = ffmpeg_dir + os.pathsep + os.environ.get("PATH", "")

    heartbeat_stop = threading.Event()
    started_at = time.time()
    requested_device = "cuda" if prefer_gpu else "cpu"
    progress_state: dict[str, Any] = {
        "stage": "starting",
        "message": "Preparing Whisper helper",
        "device": "pending",
        "selected_device": "pending",
        "requested_device": requested_device,
        "device_event": "starting",
        "device_switch_count": 0,
        "gpu_error": "",
    }

    def set_progress(
        stage: str,
        message: str,
        device: str | None = None,
        extra: dict[str, Any] | None = None,
    ) -> None:
        progress_state["stage"] = stage
        progress_state["message"] = message
        if device:
            progress_state["device"] = device
            progress_state["selected_device"] = device
        if extra:
            progress_state.update(extra)
        _write_progress(
            progress_file,
            stage=progress_state["stage"],
            message=progress_state["message"],
            started_at=started_at,
            extra={
                "device": progress_state["device"],
                "selected_device": progress_state["selected_device"],
                "requested_device": progress_state["requested_device"],
                "device_event": progress_state["device_event"],
                "device_switch_count": progress_state["device_switch_count"],
                "gpu_error": progress_state["gpu_error"],
                "model_name": model_name,
                "task_name": task_name,
                "audio_path": audio_path,
            },
        )

    def heartbeat() -> None:
        while not heartbeat_stop.wait(heartbeat_interval_seconds):
            elapsed = time.time() - started_at
            _log(
                f"[PY] heartbeat: transcription process alive, "
                f"elapsed={elapsed:.0f}s, stage={progress_state['stage']}"
            )
            set_progress(progress_state["stage"], progress_state["message"], progress_state["device"])

    heartbeat_thread = threading.Thread(target=heartbeat, daemon=True)
    heartbeat_thread.start()

    try:
        set_progress("starting", "Preparing Whisper transcription helper")
        _log(f"[PY] Audio input: {audio_path}")
        _log(f"[PY] Output dir: {output_dir}")
        runtime_probe = probe_environment(emit_logs=False)
        _log(f"[PY] Python executable: {runtime_probe['python_path']}")
        _log(f"[PY] Python version: {runtime_probe['python_version']}")
        _log(f"[PY] Torch version: {runtime_probe['torch_version'] or 'unavailable'}")
        _log(f"[PY] Torch CUDA version: {runtime_probe['cuda_version'] or 'unavailable'}")
        _log(f"[PY] CUDA available: {runtime_probe['cuda_available']}")
        _log(f"[PY] CUDA device count: {runtime_probe['cuda_device_count']}")
        if runtime_probe["cuda_device_names"]:
            _log(f"[PY] CUDA devices: {', '.join(runtime_probe['cuda_device_names'])}")
        _log(f"[PY] Requested device: {requested_device}")
        _log(f"[PY] Selected device before run: {runtime_probe['selected_device']}")
        _log(f"[PY] Whisper runtime health: {runtime_probe['classification_label']}")
        _log(f"[PY] Whisper runtime summary: {runtime_probe['classification_summary']}")
        if runtime_probe["error"]:
            _log(f"[PY] Runtime probe notes: {runtime_probe['error']}")
        set_progress("importing_whisper", "Importing Whisper runtime")
        result, device, fp16, gpu_error = _run_transcription(
            audio_path=audio_path,
            model_name=model_name,
            language_code=language_code,
            task_name=task_name,
            prefer_gpu=prefer_gpu,
            progress_callback=set_progress,
        )
        if gpu_error:
            progress_state["gpu_error"] = gpu_error
        set_progress("writing_outputs", "Writing transcript files", device)
        _log("[PY] Writing transcript files...")
        json_path, srt_path, text_path = write_transcript_files(
            output_dir=output_dir,
            json_name=json_name,
            srt_name=srt_name,
            text_name=text_name,
            result=result,
        )
        _log("[PY] Transcript files written successfully.")
        set_progress("complete", "Transcript files written successfully", device)
        return {
            "device": device,
            "fp16": fp16,
            "json_path": str(json_path),
            "srt_path": str(srt_path),
            "text_path": str(text_path),
            "language": str(result.get("language", "") or ""),
            "segments_count": len(result.get("segments") or []),
            "gpu_error": gpu_error,
            "requested_device": requested_device,
            "selected_device": progress_state["selected_device"],
            "device_switch_count": int(progress_state["device_switch_count"] or 0),
            "python_path": runtime_probe["python_path"],
            "python_version": runtime_probe["python_version"],
            "torch_version": runtime_probe["torch_version"],
            "cuda_version": runtime_probe["cuda_version"],
            "cuda_available": runtime_probe["cuda_available"],
            "cuda_device_count": int(runtime_probe["cuda_device_count"] or 0),
            "cuda_device_names": list(runtime_probe["cuda_device_names"] or []),
            "classification_code": runtime_probe["classification_code"],
            "classification_label": runtime_probe["classification_label"],
        }
    finally:
        heartbeat_stop.set()


def build_runtime_plan_from_request(payload: dict[str, Any]) -> dict[str, Any]:
    calibration_payload = payload.get("calibration")
    calibration = calibration_payload if isinstance(calibration_payload, dict) else None

    return build_runtime_plan(
        source_duration_seconds=payload.get("source_duration_seconds", 0),
        model_name=str(payload.get("model_name") or ""),
        gpu_capable=bool(payload.get("gpu_capable", False)),
        heartbeat_seconds=int(payload.get("heartbeat_seconds") or 10),
        explicit_timeout_seconds=int(payload.get("explicit_timeout_seconds") or 0),
        task_name=str(payload.get("task_name") or "transcribe"),
        calibration=calibration,
    )
