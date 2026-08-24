#!/usr/bin/env python3
"""Fixed-route operator entrypoint for one missing student identity."""

from keycloak_identity_sync import main


if __name__ == "__main__":
    raise SystemExit(main())
