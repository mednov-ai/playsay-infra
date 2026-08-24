#!/usr/bin/env python3
"""Synchronize Maria's dev-accepted learning graph from dev to production."""

from route_entry import run_route


if __name__ == "__main__":
    run_route("dev", "prod")
