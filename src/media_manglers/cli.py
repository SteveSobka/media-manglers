"""CLI entry point for tracked Media Manglers Python helpers."""

from __future__ import annotations

import argparse
from collections.abc import Sequence
from typing import Any, Callable

from .contracts import CommandResult, read_json_file, write_json_file
from .core.readmes import write_package_readme_from_request
from .providers import argos_local, hybrid_text, whisper_local


Handler = Callable[[dict[str, Any]], dict[str, Any]]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="media_manglers",
        description="Tracked cross-platform helper CLI for Media Manglers.",
    )
    subparsers = parser.add_subparsers(dest="command")

    for name in (
        "whisper-probe",
        "whisper-plan",
        "whisper-transcribe",
        "argos-status",
        "argos-probe",
        "argos-install",
        "argos-translate",
        "hybrid-translate",
        "hybrid-validate",
        "write-package-readme",
    ):
        command = subparsers.add_parser(
            name,
            help="Run a tracked Media Manglers helper command.",
        )
        command.add_argument("--request-file", required=True)
        command.add_argument("--result-file", required=True)

    return parser


def _build_handlers() -> dict[str, Handler]:
    return {
        "whisper-probe": lambda payload: whisper_local.probe_environment(),
        "whisper-plan": whisper_local.build_runtime_plan_from_request,
        "whisper-transcribe": whisper_local.transcribe_from_request,
        "argos-status": lambda payload: argos_local.get_module_status(),
        "argos-probe": argos_local.probe_from_request,
        "argos-install": argos_local.install_from_request,
        "argos-translate": argos_local.translate_from_request,
        "hybrid-translate": hybrid_text.translate_from_request,
        "hybrid-validate": hybrid_text.validate_from_request,
        "write-package-readme": write_package_readme_from_request,
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help()
        return 0

    handlers = _build_handlers()
    handler = handlers[args.command]
    request = read_json_file(args.request_file)
    payload = request.get("payload") or {}

    try:
        data = handler(payload)
        write_json_file(
            args.result_file,
            CommandResult(ok=True, data=data, error="").to_dict(),
        )
        return 0
    except Exception as exc:
        write_json_file(
            args.result_file,
            CommandResult(ok=False, data={}, error=str(exc)).to_dict(),
        )
        return 1
