#!/usr/bin/env python3

from __future__ import annotations

import argparse
import contextlib
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import keycloak_identity_sync as identity_sync

from keycloak_identity_sync import (
    IdentitySyncError,
    build_apply_sql,
    normalized_snapshot,
    read_subject,
    role_key,
    snapshot_query,
    snapshot_fingerprint,
    snapshots_match,
    sql_literal,
    validate_source,
    validate_target_context,
)


def snapshot() -> dict:
    return {
        "user": {
            "id": "student-subject",
            "realm_id": "dev-realm",
            "username": "student",
            "email": "student@example.invalid",
            "first_name": "Student",
            "last_name": "Example",
            "enabled": True,
            "email_verified": True,
            "created_timestamp": 1,
            "federation_link": None,
            "service_account_client_link": None,
            "not_before": 0,
            "email_constraint": "student@example.invalid",
        },
        "credentials": [{
            "id": "credential-id",
            "user_id": "student-subject",
            "type": "password",
            "secret_data": '{"value":"private-hash"}',
            "credential_data": '{"hashIterations":27500,"algorithm":"pbkdf2-sha256"}',
            "priority": 10,
        }],
        "attributes": [{"id": "attribute-id", "user_id": "student-subject", "name": "locale", "value": "ru"}],
        "requiredActions": [],
        "roles": [{"name": "student", "clientRole": False, "clientId": None}],
        "unsupported": {
            "federatedIdentities": 0,
            "groupMemberships": 0,
            "userConsents": 0,
            "federatedAttributes": 0,
        },
    }


def target_context() -> dict:
    return {
        "realmId": "prod-realm",
        "subjectExists": False,
        "usernameConflict": False,
        "emailConflict": False,
        "roles": [{"id": "prod-role", "name": "student", "clientRole": False, "clientId": None}],
        "columns": {
            "user_entity": list(snapshot()["user"]),
            "credential": list(snapshot()["credentials"][0]),
            "user_attribute": list(snapshot()["attributes"][0]),
            "user_required_action": ["user_id", "required_action"],
        },
    }


class KeycloakIdentitySyncTest(unittest.TestCase):
    def test_subject_file_requires_one_private_selector(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "subject"
            path.write_text("student-subject\n", encoding="utf-8")
            os.chmod(path, 0o600)
            self.assertEqual("student-subject", read_subject(path))
            path.write_text("one\ntwo\n", encoding="utf-8")
            with self.assertRaises(IdentitySyncError):
                read_subject(path)

    def test_subject_file_rejects_group_or_other_access(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "subject"
            path.write_text("student-subject\n", encoding="utf-8")
            os.chmod(path, 0o644)
            with self.assertRaisesRegex(IdentitySyncError, "group or other"):
                read_subject(path)

    def test_password_update_action_is_rejected(self) -> None:
        source = snapshot()
        source["requiredActions"] = [{"user_id": "student-subject", "required_action": "UPDATE_PASSWORD"}]
        with self.assertRaisesRegex(IdentitySyncError, "password change"):
            validate_source(source)

    def test_unsupported_relations_are_rejected(self) -> None:
        source = snapshot()
        source["unsupported"]["groupMemberships"] = 1
        with self.assertRaisesRegex(IdentitySyncError, "unsupported"):
            validate_source(source)

        source = snapshot()
        source["user"]["federation_link"] = "external-provider"
        with self.assertRaisesRegex(IdentitySyncError, "federated"):
            validate_source(source)

    def test_snapshot_query_supports_keycloak_without_optional_federated_table(self) -> None:
        without_optional_table = snapshot_query("student-subject", "playsay", False)
        self.assertIn("'federatedAttributes', 0", without_optional_table)
        self.assertNotIn("FROM federated_user_attribute", without_optional_table)

        with_optional_table = snapshot_query("student-subject", "playsay", True)
        self.assertIn("FROM federated_user_attribute", with_optional_table)

    def test_apply_sql_preserves_subject_and_hash_without_password_action(self) -> None:
        source = snapshot()
        target = target_context()
        roles = validate_target_context(source, target)
        sql = build_apply_sql("student-subject", "playsay", source, target, roles)
        self.assertIn("student-subject", sql)
        self.assertIn("private-hash", sql)
        self.assertIn("prod-realm", sql)
        self.assertIn("prod-role", sql)
        self.assertIn("password update action is forbidden", sql)
        self.assertNotIn("dev-realm", sql)

    def test_fingerprint_and_comparison_ignore_environment_realm_id(self) -> None:
        source = snapshot()
        target = snapshot()
        target["user"]["realm_id"] = "prod-realm"
        self.assertTrue(snapshots_match(source, target))
        self.assertEqual(snapshot_fingerprint(source), snapshot_fingerprint(target))
        target["credentials"][0]["secret_data"] = "changed"
        self.assertFalse(snapshots_match(source, target))

    def test_conflicts_and_missing_roles_fail_closed(self) -> None:
        source = snapshot()
        target = target_context()
        target["emailConflict"] = True
        with self.assertRaisesRegex(IdentitySyncError, "conflicting"):
            validate_target_context(source, target)
        target = target_context()
        target["roles"] = []
        with self.assertRaisesRegex(IdentitySyncError, "role"):
            validate_target_context(source, target)

    def test_sql_literal_does_not_allow_quote_escape(self) -> None:
        self.assertEqual("'x''; DROP TABLE realm; --'", sql_literal("x'; DROP TABLE realm; --"))

    def test_guard_cannot_consume_the_callers_subject_stream(self) -> None:
        completed = subprocess.CompletedProcess(["guard"], 0, b"", b"")
        with tempfile.TemporaryDirectory() as directory:
            guard = Path(directory) / "guard"
            guard.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            os.chmod(guard, 0o700)
            with mock.patch.object(
                identity_sync.subprocess, "run", return_value=completed
            ) as mocked_run:
                identity_sync.run_guard(guard)
        self.assertIs(subprocess.DEVNULL, mocked_run.call_args.kwargs["stdin"])

    def test_encrypted_backup_is_decryptable_and_contains_verified_dump(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            private_key = root / "private.pem"
            public_key = root / "public.pem"
            subprocess.run(
                [
                    "openssl", "genpkey", "-algorithm", "RSA",
                    "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(private_key),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            subprocess.run(
                ["openssl", "pkey", "-in", str(private_key), "-pubout", "-out", str(public_key)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            original_run = identity_sync.run_private

            def fake_database_commands(command, **kwargs):
                if command[0] == "pg_dump":
                    dump_argument = next(item for item in command if item.startswith("--file="))
                    Path(dump_argument.split("=", 1)[1]).write_bytes(b"test-custom-dump")
                    return subprocess.CompletedProcess(command, 0, b"", b"")
                if command[0] == "pg_restore":
                    return subprocess.CompletedProcess(command, 0, b"", b"")
                return original_run(command, **kwargs)

            backup_dir = root / "backups"
            with mock.patch.object(identity_sync, "run_private", side_effect=fake_database_commands):
                backup_id = identity_sync.create_encrypted_backup(
                    "prod-keycloak", backup_dir, public_key, private_key, "a" * 64
                )
                restore_root = root / "restore"
                restore_root.mkdir(mode=0o700)
                payload = identity_sync.decrypt_backup(
                    backup_dir, backup_id, private_key, restore_root
                )
            self.assertEqual(b"test-custom-dump", (payload / "keycloak-postgresql.dump").read_bytes())
            self.assertEqual(backup_id, (payload / "backup-id").read_text(encoding="utf-8").strip())

    def test_inventory_is_written_privately_without_printing_subjects(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "inventory" / "subjects"
            stdout = io.StringIO()
            with mock.patch.object(
                identity_sync, "psql_json", return_value=["subject-one", "subject-two"]
            ), contextlib.redirect_stdout(stdout):
                identity_sync.command_export_inventory(
                    argparse.Namespace(
                        realm="playsay", target_pg_service="prod-keycloak", output=str(output)
                    )
                )
            self.assertEqual("subject-one\nsubject-two\n", output.read_text(encoding="utf-8"))
            self.assertEqual(0o600, os.stat(output).st_mode & 0o777)
            self.assertNotIn("subject-one", stdout.getvalue())
            self.assertIn('"subjects":2', stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
