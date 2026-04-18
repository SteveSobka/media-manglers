"""Tracked local Whisper helpers for the phased migration."""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timezone
import json
import os
import threading
import time
from typing import Any

from media_manglers.core.transcripts import write_transcript_files
from media_manglers.core.whisper_runtime import build_runtime_plan


def _log(message: str) -> None:
    print(message, flush=True)


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


def probe_environment() -> dict[str, Any]:
    result: dict[str, Any] = {
        "whisper_import_ok": False,
        "torch_import_ok": False,
        "cuda_available": False,
        "device": "cpu",
        "torch_version": "",
        "cuda_version": "",
        "error": "",
    }

    try:
        _log("[PY-PROBE] Importing whisper...")
        __import__("whisper")
        result["whisper_import_ok"] = True
    except Exception as exc:
        result["error"] = f"whisper import failed: {exc}"

    try:
        _log("[PY-PROBE] Importing torch...")
        import torch

        result["torch_import_ok"] = True
        result["torch_version"] = str(getattr(torch, "__version__", "") or "")
        result["cuda_version"] = str(getattr(torch.version, "cuda", "") or "")
        result["cuda_available"] = bool(torch.cuda.is_available())
        result["device"] = "cuda" if result["cuda_available"] else "cpu"
    except Exception as exc:
        if result["error"]:
            result["error"] += f" | torch import failed: {exc}"
        else:
            result["error"] = f"torch import failed: {exc}"

    return result


def _run_transcription(
    audio_path: str,
    model_name: str,
    language_code: str,
    task_name: str,
    prefer_gpu: bool,
    progress_callback: Callable[[str, str, str], None] | None = None,
) -> tuple[dict[str, Any], str, bool, str]:
    import whisper

    torch = None
    gpu_error = ""
    if prefer_gpu:
        try:
            import torch as imported_torch

            torch = imported_torch
        except Exception as exc:
            _log(f"[PY] Torch import failed. GPU path disabled. {exc}")

    def run(device_name: str) -> tuple[dict[str, Any], bool]:
        fp16 = device_name == "cuda"
        if progress_callback:
            progress_callback("loading_model", f"Loading Whisper model '{model_name}' on {device_name}", device_name)
        _log(f"[PY] Loading model '{model_name}' on device '{device_name}'...")
        model = whisper.load_model(model_name, device=device_name)
        if progress_callback:
            progress_callback("transcribing", f"Running Whisper {task_name} on {device_name}", device_name)
        _log(f"[PY] Starting {task_name} on {device_name}...")
        result = model.transcribe(
            audio_path,
            language=language_code or None,
            task=task_name,
            verbose=True,
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

    result, fp16 = run("cpu")
    return result, "cpu", fp16, gpu_error


def transcribe_from_request(payload: dict[str, Any]) -> dict[str, Any]:
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
    progress_state: dict[str, str] = {
        "stage": "starting",
        "message": "Preparing Whisper helper",
        "device": "pending",
    }

    def set_progress(stage: str, message: str, device: str | None = None) -> None:
        progress_state["stage"] = stage
        progress_state["message"] = message
        if device:
            progress_state["device"] = device
        _write_progress(
            progress_file,
            stage=progress_state["stage"],
            message=progress_state["message"],
            started_at=started_at,
            extra={
                "device": progress_state["device"],
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
        set_progress("importing_whisper", "Importing Whisper runtime")
        result, device, fp16, gpu_error = _run_transcription(
            audio_path=audio_path,
            model_name=model_name,
            language_code=language_code,
            task_name=task_name,
            prefer_gpu=prefer_gpu,
            progress_callback=set_progress,
        )
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
