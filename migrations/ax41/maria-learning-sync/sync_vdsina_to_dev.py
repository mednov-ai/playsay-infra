#!/usr/bin/env python3
"""Synchronize Maria's selected learning graph from VDSina to dev."""

from route_entry import run_route


if __name__ == "__main__":
    run_route("vdsina", "dev")
