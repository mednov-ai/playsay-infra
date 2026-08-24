#!/usr/bin/env python3
"""Fixed-route Python entrypoint for Maria learning-data synchronization."""

from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path


COMMANDS = ("export", "verify-bundle", "plan", "apply", "verify-target", "rollback")
FORBIDDEN_ROUTE_FLAGS = {"--source-environment", "--target-environment", "--environment"}


def build_driver_command(
    source_environment: str,
    target_environment: str,
    command: str,
    forwarded: list[str],
) -> list[str]:
    if command not in COMMANDS:
        raise ValueError(f"unsupported command: {command}")
    supplied_flags = {item.split("=", 1)[0] for item in forwarded if item.startswith("--")}
    forbidden = supplied_flags & FORBIDDEN_ROUTE_FLAGS
    if forbidden:
        raise ValueError(f"route flags are fixed by this script: {', '.join(sorted(forbidden))}")

    driver = Path(__file__).with_name("maria-learning-sync.sh")
    result = [
        str(driver),
        command,
        "--source-environment",
        source_environment,
        "--target-environment",
        target_environment,
    ]
    if command in {"plan", "apply", "verify-target", "rollback"}:
        result.extend(("--environment", target_environment))
    result.extend(forwarded)
    return result


def run_route(source_environment: str, target_environment: str) -> None:
    parser = argparse.ArgumentParser(
        description=(
            f"Synchronize Maria Mednova's learning graph: "
            f"{source_environment} -> {target_environment}."
        ),
        epilog=(
            "Credentials are read only through a libpq service and an existing mc alias. "
            "Run '<command> --help-driver' to see the internal driver contract."
        ),
    )
    parser.add_argument("command", choices=COMMANDS)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    forwarded = args.arguments
    if forwarded == ["--help-driver"]:
        forwarded = ["--help"]
    try:
        driver_command = build_driver_command(
            source_environment, target_environment, args.command, forwarded
        )
    except ValueError as error:
        parser.error(str(error))

    environment = os.environ.copy()
    environment.setdefault("LC_ALL", "C")
    completed = subprocess.run(driver_command, env=environment, check=False)
    raise SystemExit(completed.returncode)


if __name__ == "__main__":
    raise SystemExit("import run_route from a fixed-route entrypoint")
