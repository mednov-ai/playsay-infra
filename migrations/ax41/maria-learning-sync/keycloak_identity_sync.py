#!/usr/bin/env python3
"""Operator-only, fixed-route Keycloak identity migration from dev to prod.

The tool intentionally talks to PostgreSQL through libpq service names. Sensitive
identity data is held in memory or a mode-0700 temporary directory and is never
printed. Production mutation requires a stopped-Keycloak guard, an encrypted full
database backup and an explicit operator approval flag.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")
SAFE_IDENTIFIER = re.compile(r"^[a-z][a-z0-9_]*$")
CHILD_TABLES = ("credential", "user_attribute", "user_required_action")
PORTABLE_USER_COLUMNS = {
    "id",
    "username",
    "first_name",
    "last_name",
    "email",
    "email_constraint",
    "email_verified",
    "enabled",
    "created_timestamp",
    "federation_link",
    "service_account_client_link",
    "not_before",
}


class IdentitySyncError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise IdentitySyncError(message)


def validate_service_name(value: str) -> str:
    if not SAFE_NAME.fullmatch(value):
        fail("libpq service name contains unsafe characters")
    return value


def read_subject(path: Path) -> str:
    if not path.is_file():
        fail("student subject file is missing")
    if stat.S_IMODE(path.stat().st_mode) & 0o077:
        fail("student subject file must not be accessible by group or other users")
    lines = path.read_text(encoding="utf-8").splitlines()
    if len(lines) != 1 or not lines[0] or len(lines[0]) > 255:
        fail("student subject file must contain exactly one non-empty line")
    return lines[0]


def subject_sha256(subject: str) -> str:
    return hashlib.sha256(subject.encode("utf-8")).hexdigest()


def sql_literal(value: Any) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if "\x00" in text:
        fail("identity data contains an unsupported NUL byte")
    return "'" + text.replace("'", "''") + "'"


def quote_identifier(value: str) -> str:
    if not SAFE_IDENTIFIER.fullmatch(value):
        fail("database schema contains an unsafe identifier")
    return f'"{value}"'


def require_tools(*names: str) -> None:
    missing = [name for name in names if shutil.which(name) is None]
    if missing:
        fail("required commands are missing: " + ", ".join(missing))


def run_private(
    command: list[str],
    *,
    stdin: str | bytes | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[bytes]:
    payload = stdin.encode("utf-8") if isinstance(stdin, str) else stdin
    run_options: dict[str, Any] = {
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
        "env": env,
        "check": False,
    }
    if payload is None:
        run_options["stdin"] = subprocess.DEVNULL
    else:
        run_options["input"] = payload
    completed = subprocess.run(command, **run_options)
    if completed.returncode != 0:
        fail(f"{Path(command[0]).name} failed; sensitive command output was suppressed")
    return completed


def psql_json(service: str, sql: str) -> Any:
    completed = run_private(
        [
            "psql",
            f"service={validate_service_name(service)}",
            "-X",
            "--no-psqlrc",
            "--set=ON_ERROR_STOP=1",
            "--tuples-only",
            "--no-align",
            "--quiet",
        ],
        stdin=sql,
    )
    text = completed.stdout.decode("utf-8").strip()
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        fail("database returned an invalid private JSON result")


def psql_execute(service: str, sql: str) -> None:
    run_private(
        [
            "psql",
            f"service={validate_service_name(service)}",
            "-X",
            "--no-psqlrc",
            "--set=ON_ERROR_STOP=1",
            "--quiet",
        ],
        stdin=sql,
    )


def relation_exists(service: str, relation: str) -> bool:
    if not SAFE_IDENTIFIER.fullmatch(relation):
        fail("database relation contains unsafe characters")
    result = psql_json(
        service,
        f"""
SELECT to_jsonb(EXISTS (
  SELECT 1
  FROM information_schema.tables
  WHERE table_schema = current_schema() AND table_name = {sql_literal(relation)}
))::text;
""",
    )
    if not isinstance(result, bool):
        fail("database returned an invalid relation check")
    return result


def snapshot_query(subject: str, realm: str, has_federated_attributes: bool) -> str:
    subject_sql = sql_literal(subject)
    realm_sql = sql_literal(realm)
    federated_attributes_sql = (
        "(SELECT count(*) FROM federated_user_attribute x WHERE x.user_id = u.id)"
        if has_federated_attributes
        else "0"
    )
    return f"""
SELECT jsonb_build_object(
  'user', to_jsonb(u),
  'credentials', COALESCE((
    SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM credential c WHERE c.user_id = u.id
  ), '[]'::jsonb),
  'attributes', COALESCE((
    SELECT jsonb_agg(to_jsonb(a) ORDER BY a.name, a.id) FROM user_attribute a WHERE a.user_id = u.id
  ), '[]'::jsonb),
  'requiredActions', COALESCE((
    SELECT jsonb_agg(to_jsonb(a) ORDER BY a.required_action)
    FROM user_required_action a WHERE a.user_id = u.id
  ), '[]'::jsonb),
  'roles', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'name', kr.name,
      'clientRole', kr.client_role,
      'clientId', client.client_id
    ) ORDER BY COALESCE(client.client_id, ''), kr.name)
    FROM user_role_mapping urm
    JOIN keycloak_role kr ON kr.id = urm.role_id
    LEFT JOIN client client ON client.id = kr.client
    WHERE urm.user_id = u.id
  ), '[]'::jsonb),
  'unsupported', jsonb_build_object(
    'federatedIdentities', (SELECT count(*) FROM federated_identity x WHERE x.user_id = u.id),
    'groupMemberships', (SELECT count(*) FROM user_group_membership x WHERE x.user_id = u.id),
    'userConsents', (SELECT count(*) FROM user_consent x WHERE x.user_id = u.id),
    'federatedAttributes', {federated_attributes_sql}
  )
)::text
FROM user_entity u
JOIN realm r ON r.id = u.realm_id
WHERE u.id = {subject_sql} AND r.name = {realm_sql};
"""


def target_context_query(subject: str, realm: str, username: Any, email: Any) -> str:
    subject_sql = sql_literal(subject)
    realm_sql = sql_literal(realm)
    username_sql = sql_literal(username)
    email_sql = sql_literal(email)
    conflict_username = (
        "FALSE"
        if username is None
        else f"EXISTS (SELECT 1 FROM user_entity x WHERE x.realm_id = r.id AND x.id <> {subject_sql} AND lower(x.username) = lower({username_sql}))"
    )
    conflict_email = (
        "FALSE"
        if email is None
        else f"EXISTS (SELECT 1 FROM user_entity x WHERE x.realm_id = r.id AND x.id <> {subject_sql} AND x.email IS NOT NULL AND lower(x.email) = lower({email_sql}))"
    )
    return f"""
SELECT jsonb_build_object(
  'realmId', r.id,
  'subjectExists', EXISTS (SELECT 1 FROM user_entity x WHERE x.id = {subject_sql} AND x.realm_id = r.id),
  'usernameConflict', {conflict_username},
  'emailConflict', {conflict_email},
  'roles', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', kr.id,
      'name', kr.name,
      'clientRole', kr.client_role,
      'clientId', client.client_id
    ))
    FROM keycloak_role kr
    LEFT JOIN client client ON client.id = kr.client
    WHERE kr.realm_id = r.id
  ), '[]'::jsonb),
  'columns', (
    SELECT jsonb_object_agg(table_name, columns)
    FROM (
      SELECT table_name, jsonb_agg(column_name ORDER BY ordinal_position) AS columns
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND table_name IN ('user_entity', 'credential', 'user_attribute', 'user_required_action')
      GROUP BY table_name
    ) schema_columns
  )
)::text
FROM realm r
WHERE r.name = {realm_sql};
"""


def load_snapshot(service: str, subject: str, realm: str) -> dict[str, Any] | None:
    has_federated_attributes = relation_exists(service, "federated_user_attribute")
    result = psql_json(
        service,
        snapshot_query(subject, realm, has_federated_attributes),
    )
    if result is None:
        return None
    if not isinstance(result, dict):
        fail("identity snapshot has an invalid shape")
    return result


def validate_source(snapshot: dict[str, Any]) -> None:
    user = snapshot.get("user")
    if not isinstance(user, dict):
        fail("source identity is missing")
    if user.get("service_account_client_link") is not None:
        fail("service-account identities are not supported")
    if user.get("federation_link") is not None:
        fail("federated identities are not supported")
    unsupported = snapshot.get("unsupported", {})
    if any(int(value) != 0 for value in unsupported.values()):
        fail("source identity has unsupported federation, group or consent relations")
    credentials = snapshot.get("credentials", [])
    if not any(row.get("type") == "password" for row in credentials):
        fail("source identity has no password credential")
    required = {row.get("required_action") for row in snapshot.get("requiredActions", [])}
    if "UPDATE_PASSWORD" in required:
        fail("source identity requires a password change")


def role_key(role: dict[str, Any]) -> tuple[str, bool, str | None]:
    return (str(role.get("name")), bool(role.get("clientRole")), role.get("clientId"))


def validate_target_context(
    source: dict[str, Any], target: dict[str, Any] | None
) -> dict[tuple[str, bool, str | None], str]:
    if target is None:
        fail("target realm is missing")
    if target.get("usernameConflict") or target.get("emailConflict"):
        fail("target realm has a conflicting username or email")
    columns = target.get("columns") or {}
    missing_tables = [table for table in ("user_entity", *CHILD_TABLES) if table not in columns]
    if missing_tables:
        fail("target Keycloak schema is missing required tables")
    target_roles = {role_key(role): str(role["id"]) for role in target.get("roles", [])}
    missing_roles = [role_key(role) for role in source.get("roles", []) if role_key(role) not in target_roles]
    if missing_roles:
        fail("target realm is missing one or more required role mappings")
    return target_roles


def normalized_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    user = snapshot["user"]
    return {
        "user": {key: user.get(key) for key in sorted(PORTABLE_USER_COLUMNS)},
        "credentials": sorted(snapshot.get("credentials", []), key=lambda row: str(row.get("id"))),
        "attributes": sorted(snapshot.get("attributes", []), key=lambda row: str(row.get("id"))),
        "requiredActions": sorted(
            snapshot.get("requiredActions", []), key=lambda row: str(row.get("required_action"))
        ),
        "roles": sorted(
            [list(role_key(role)) for role in snapshot.get("roles", [])],
            key=lambda row: json.dumps(row, sort_keys=True),
        ),
    }


def snapshot_fingerprint(snapshot: dict[str, Any]) -> str:
    encoded = json.dumps(normalized_snapshot(snapshot), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def snapshots_match(source: dict[str, Any], target: dict[str, Any]) -> bool:
    return normalized_snapshot(source) == normalized_snapshot(target)


def json_record_insert(table: str, row: dict[str, Any], target_columns: list[str]) -> str:
    columns = sorted(set(row) & set(target_columns))
    if not columns:
        fail(f"no compatible columns for {table}")
    identifiers = ", ".join(quote_identifier(column) for column in columns)
    payload = sql_literal(json.dumps(row, sort_keys=True, separators=(",", ":")))
    return (
        f"WITH source_row AS (SELECT * FROM jsonb_populate_record(NULL::{quote_identifier(table)}, "
        f"{payload}::jsonb)) INSERT INTO {quote_identifier(table)} ({identifiers}) "
        f"SELECT {identifiers} FROM source_row;"
    )


def build_apply_sql(
    subject: str,
    realm: str,
    source: dict[str, Any],
    target: dict[str, Any],
    target_roles: dict[tuple[str, bool, str | None], str],
) -> str:
    subject_sql = sql_literal(subject)
    realm_sql = sql_literal(realm)
    user = dict(source["user"])
    user["id"] = subject
    user["realm_id"] = target["realmId"]
    columns = target["columns"]
    statements = [
        "BEGIN ISOLATION LEVEL SERIALIZABLE;",
        f"DO $$ BEGIN IF EXISTS (SELECT 1 FROM user_entity WHERE id = {subject_sql}) THEN RAISE EXCEPTION 'target subject already exists'; END IF; END $$;",
    ]
    if user.get("username") is not None:
        statements.append(
            "DO $$ BEGIN IF EXISTS (SELECT 1 FROM user_entity WHERE realm_id = "
            f"{sql_literal(target['realmId'])} AND lower(username) = lower({sql_literal(user['username'])})) "
            "THEN RAISE EXCEPTION 'target username conflict'; END IF; END $$;"
        )
    if user.get("email") is not None:
        statements.append(
            "DO $$ BEGIN IF EXISTS (SELECT 1 FROM user_entity WHERE realm_id = "
            f"{sql_literal(target['realmId'])} AND email IS NOT NULL AND lower(email) = lower({sql_literal(user['email'])})) "
            "THEN RAISE EXCEPTION 'target email conflict'; END IF; END $$;"
        )
    statements.append(json_record_insert("user_entity", user, columns["user_entity"]))
    for table, key in (
        ("credential", "credentials"),
        ("user_attribute", "attributes"),
        ("user_required_action", "requiredActions"),
    ):
        for source_row in source.get(key, []):
            row = dict(source_row)
            row["user_id"] = subject
            statements.append(json_record_insert(table, row, columns[table]))
    for role in source.get("roles", []):
        statements.append(
            "INSERT INTO user_role_mapping (user_id, role_id) VALUES "
            f"({subject_sql}, {sql_literal(target_roles[role_key(role)])});"
        )
    statements.extend(
        [
            f"DO $$ BEGIN IF EXISTS (SELECT 1 FROM user_required_action WHERE user_id = {subject_sql} AND required_action = 'UPDATE_PASSWORD') THEN RAISE EXCEPTION 'password update action is forbidden'; END IF; END $$;",
            f"DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM realm WHERE id = {sql_literal(target['realmId'])} AND name = {realm_sql}) THEN RAISE EXCEPTION 'target realm changed'; END IF; END $$;",
            "COMMIT;",
        ]
    )
    return "\n".join(statements) + "\n"


def run_guard(path: Path) -> None:
    if not path.is_file() or not os.access(path, os.X_OK):
        fail("maintenance guard must be an executable file")
    completed = subprocess.run(
        [str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if completed.returncode != 0:
        fail("maintenance guard rejected the operation")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def create_encrypted_backup(
    target_service: str,
    backup_dir: Path,
    public_key: Path,
    private_key: Path,
    subject_hash: str,
) -> str:
    for path in (public_key, private_key):
        if not path.is_file():
            fail("backup key file is missing")
    backup_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(backup_dir, 0o700)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_id = f"keycloak-student-dev-to-prod-{subject_hash[:12]}-{timestamp}"
    with tempfile.TemporaryDirectory(prefix="playsay-keycloak-backup-") as temp_name:
        temp = Path(temp_name)
        os.chmod(temp, 0o700)
        payload = temp / "payload"
        payload.mkdir(mode=0o700)
        dump = payload / "keycloak-postgresql.dump"
        run_private(
            [
                "pg_dump",
                f"service={validate_service_name(target_service)}",
                "--format=custom",
                "--no-owner",
                "--no-privileges",
                f"--file={dump}",
            ]
        )
        run_private(["pg_restore", "--list", str(dump)])
        (payload / "backup-id").write_text(backup_id + "\n", encoding="utf-8")
        (payload / "environment").write_text("prod\n", encoding="utf-8")
        (payload / "subject-sha256").write_text(subject_hash + "\n", encoding="utf-8")
        (payload / "keycloak-postgresql.dump.sha256").write_text(
            sha256_file(dump) + "\n", encoding="utf-8"
        )
        archive = temp / f"{backup_id}.rollback.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            for item in sorted(payload.iterdir()):
                tar.add(item, arcname=item.name, recursive=False)
        data_key = temp / "data-key.txt"
        data_key.write_text(secrets.token_hex(32) + "\n", encoding="ascii")
        os.chmod(data_key, stat.S_IRUSR | stat.S_IWUSR)
        encrypted_archive = backup_dir / f"{backup_id}.rollback.tar.gz.enc"
        encrypted_key = backup_dir / f"{backup_id}.rollback.key.enc"
        transport = backup_dir / f"{backup_id}.rollback.transport.sha256"
        if encrypted_archive.exists() or encrypted_key.exists() or transport.exists():
            fail("backup artifact already exists")
        run_private(
            [
                "openssl",
                "enc",
                "-aes-256-cbc",
                "-salt",
                "-pbkdf2",
                "-iter",
                "200000",
                "-md",
                "sha256",
                "-pass",
                f"file:{data_key}",
                "-in",
                str(archive),
                "-out",
                str(encrypted_archive),
            ]
        )
        run_private(
            [
                "openssl",
                "pkeyutl",
                "-encrypt",
                "-pubin",
                "-inkey",
                str(public_key),
                "-pkeyopt",
                "rsa_padding_mode:oaep",
                "-pkeyopt",
                "rsa_oaep_md:sha256",
                "-in",
                str(data_key),
                "-out",
                str(encrypted_key),
            ]
        )
        verify_key = temp / "verify-key.txt"
        verify_archive = temp / "verify.tar.gz"
        run_private(
            [
                "openssl",
                "pkeyutl",
                "-decrypt",
                "-inkey",
                str(private_key),
                "-pkeyopt",
                "rsa_padding_mode:oaep",
                "-pkeyopt",
                "rsa_oaep_md:sha256",
                "-in",
                str(encrypted_key),
                "-out",
                str(verify_key),
            ]
        )
        run_private(
            [
                "openssl",
                "enc",
                "-d",
                "-aes-256-cbc",
                "-pbkdf2",
                "-iter",
                "200000",
                "-md",
                "sha256",
                "-pass",
                f"file:{verify_key}",
                "-in",
                str(encrypted_archive),
                "-out",
                str(verify_archive),
            ]
        )
        with tarfile.open(verify_archive, "r:gz") as tar:
            names = set(tar.getnames())
        if "keycloak-postgresql.dump" not in names:
            fail("encrypted backup verification failed")
        transport.write_text(
            f"{sha256_file(encrypted_archive)}  {encrypted_archive.name}\n"
            f"{sha256_file(encrypted_key)}  {encrypted_key.name}\n",
            encoding="ascii",
        )
        for path in (encrypted_archive, encrypted_key, transport):
            os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
    return backup_id


def decrypt_backup(backup_dir: Path, backup_id: str, private_key: Path, output: Path) -> Path:
    if not SAFE_NAME.fullmatch(backup_id):
        fail("backup ID contains unsafe characters")
    encrypted_archive = backup_dir / f"{backup_id}.rollback.tar.gz.enc"
    encrypted_key = backup_dir / f"{backup_id}.rollback.key.enc"
    transport = backup_dir / f"{backup_id}.rollback.transport.sha256"
    for path in (encrypted_archive, encrypted_key, transport, private_key):
        if not path.is_file():
            fail("rollback artifact is missing")
    expected = {}
    for line in transport.read_text(encoding="ascii").splitlines():
        digest, name = line.split(maxsplit=1)
        expected[name] = digest
    for path in (encrypted_archive, encrypted_key):
        if expected.get(path.name) != sha256_file(path):
            fail("rollback transport checksum mismatch")
    data_key = output / "data-key.txt"
    archive = output / "rollback.tar.gz"
    run_private(
        [
            "openssl", "pkeyutl", "-decrypt", "-inkey", str(private_key),
            "-pkeyopt", "rsa_padding_mode:oaep", "-pkeyopt", "rsa_oaep_md:sha256",
            "-in", str(encrypted_key), "-out", str(data_key),
        ]
    )
    run_private(
        [
            "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "200000",
            "-md", "sha256", "-pass", f"file:{data_key}", "-in", str(encrypted_archive),
            "-out", str(archive),
        ]
    )
    payload = output / "payload"
    payload.mkdir(mode=0o700)
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            if member.name.startswith("/") or ".." in Path(member.name).parts:
                fail("unsafe rollback archive")
        tar.extractall(payload)
    return payload


def restore_encrypted_backup(
    target_service: str, backup_dir: Path, backup_id: str, private_key: Path
) -> None:
    with tempfile.TemporaryDirectory(prefix="playsay-keycloak-restore-") as temp_name:
        temp = Path(temp_name)
        os.chmod(temp, 0o700)
        payload = decrypt_backup(backup_dir, backup_id, private_key, temp)
        if (payload / "backup-id").read_text(encoding="utf-8").strip() != backup_id:
            fail("rollback backup ID does not match")
        if (payload / "environment").read_text(encoding="utf-8").strip() != "prod":
            fail("rollback backup belongs to another environment")
        dump = payload / "keycloak-postgresql.dump"
        expected = (payload / "keycloak-postgresql.dump.sha256").read_text(
            encoding="ascii"
        ).strip()
        if sha256_file(dump) != expected:
            fail("rollback database checksum mismatch")
        run_private(
            [
                "pg_restore", "--clean", "--if-exists", "--no-owner", "--no-privileges",
                "--single-transaction", "--exit-on-error",
                f"--dbname=service={validate_service_name(target_service)}", str(dump),
            ]
        )


def load_pair(args: argparse.Namespace) -> tuple[str, dict[str, Any], dict[str, Any], dict[Any, str]]:
    if args.source_pg_service == args.target_pg_service:
        fail("source and target libpq services must be different")
    subject = read_subject(Path(args.student_subject_file))
    source = load_snapshot(args.source_pg_service, subject, args.realm)
    if source is None:
        fail("student identity is absent from source Keycloak")
    validate_source(source)
    user = source["user"]
    target = psql_json(
        args.target_pg_service,
        target_context_query(subject, args.realm, user.get("username"), user.get("email")),
    )
    roles = validate_target_context(source, target)
    return subject, source, target, roles


def command_plan(args: argparse.Namespace) -> None:
    subject, source, target, _ = load_pair(args)
    target_snapshot = load_snapshot(args.target_pg_service, subject, args.realm)
    status = "create" if target_snapshot is None else (
        "already-synchronized" if snapshots_match(source, target_snapshot) else "conflict"
    )
    print(json.dumps({
        "status": status,
        "subjectSha256": subject_sha256(subject),
        "identityFingerprint": snapshot_fingerprint(source),
        "credentials": len(source.get("credentials", [])),
        "attributes": len(source.get("attributes", [])),
        "requiredActions": len(source.get("requiredActions", [])),
        "roles": len(source.get("roles", [])),
        "updatePasswordRequired": False,
    }, separators=(",", ":")))
    if target.get("subjectExists") and status == "conflict":
        fail("target subject exists with different identity data")


def command_apply(args: argparse.Namespace) -> None:
    if not args.operator_production_approval:
        fail("production requires --operator-production-approval")
    run_guard(Path(args.source_maintenance_guard_command))
    run_guard(Path(args.target_maintenance_guard_command))
    subject, source, target, roles = load_pair(args)
    existing = load_snapshot(args.target_pg_service, subject, args.realm)
    if existing is not None:
        if snapshots_match(source, existing):
            print(json.dumps({"status": "already-synchronized", "subjectSha256": subject_sha256(subject)}))
            return
        fail("target subject exists with different identity data")
    apply_sql = build_apply_sql(subject, args.realm, source, target, roles)
    preflight_sql = apply_sql.rsplit("COMMIT;", 1)[0] + "ROLLBACK;\n"
    psql_execute(args.target_pg_service, preflight_sql)
    backup_id = create_encrypted_backup(
        args.target_pg_service,
        Path(args.backup_dir),
        Path(args.backup_public_key),
        Path(args.backup_private_key),
        subject_sha256(subject),
    )
    psql_execute(args.target_pg_service, apply_sql)
    applied = load_snapshot(args.target_pg_service, subject, args.realm)
    if applied is None or not snapshots_match(source, applied):
        restore_encrypted_backup(
            args.target_pg_service,
            Path(args.backup_dir),
            backup_id,
            Path(args.backup_private_key),
        )
        fail("post-apply identity verification failed; prod Keycloak was restored")
    print(json.dumps({
        "status": "complete",
        "subjectSha256": subject_sha256(subject),
        "identityFingerprint": snapshot_fingerprint(source),
        "backupId": backup_id,
        "updatePasswordRequired": False,
    }, separators=(",", ":")))


def command_verify(args: argparse.Namespace) -> None:
    subject, source, _, _ = load_pair(args)
    target = load_snapshot(args.target_pg_service, subject, args.realm)
    if target is None or not snapshots_match(source, target):
        fail("target identity does not match source")
    print(json.dumps({
        "status": "verified",
        "subjectSha256": subject_sha256(subject),
        "identityFingerprint": snapshot_fingerprint(source),
        "updatePasswordRequired": False,
    }, separators=(",", ":")))


def command_export_inventory(args: argparse.Namespace) -> None:
    realm_sql = sql_literal(args.realm)
    subjects = psql_json(
        args.target_pg_service,
        f"""
SELECT COALESCE(jsonb_agg(u.id ORDER BY u.id), '[]'::jsonb)::text
FROM user_entity u
JOIN realm r ON r.id = u.realm_id
WHERE r.name = {realm_sql};
""",
    )
    if not isinstance(subjects, list):
        fail("target subject inventory has an invalid shape")
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if output.is_symlink():
        fail("subject inventory output must not be a symlink")
    temporary = output.with_name(f".{output.name}.{secrets.token_hex(8)}.tmp")
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            for subject in subjects:
                handle.write(str(subject) + "\n")
        os.replace(temporary, output)
        os.chmod(output, 0o600)
    finally:
        temporary.unlink(missing_ok=True)
    print(json.dumps({"status": "written", "subjects": len(subjects)}, separators=(",", ":")))


def command_rollback(args: argparse.Namespace) -> None:
    if not args.operator_production_approval:
        fail("production requires --operator-production-approval")
    run_guard(Path(args.target_maintenance_guard_command))
    restore_encrypted_backup(
        args.target_pg_service,
        Path(args.backup_dir),
        args.confirm_backup_id,
        Path(args.backup_private_key),
    )
    print(json.dumps({"status": "rolled-back", "backupId": args.confirm_backup_id}, separators=(",", ":")))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Copy one missing Keycloak student identity from dev to prod without password reset."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("plan", "apply", "verify"):
        command = subparsers.add_parser(name)
        command.add_argument("--source-pg-service", required=True)
        command.add_argument("--target-pg-service", required=True)
        command.add_argument("--student-subject-file", required=True)
        command.add_argument("--realm", default="playsay")
        if name == "apply":
            command.add_argument("--backup-dir", required=True)
            command.add_argument("--backup-public-key", required=True)
            command.add_argument("--backup-private-key", required=True)
            command.add_argument("--source-maintenance-guard-command", required=True)
            command.add_argument("--target-maintenance-guard-command", required=True)
            command.add_argument("--operator-production-approval", action="store_true")
    inventory = subparsers.add_parser("export-inventory")
    inventory.add_argument("--target-pg-service", required=True)
    inventory.add_argument("--realm", default="playsay")
    inventory.add_argument("--output", required=True)
    rollback = subparsers.add_parser("rollback")
    rollback.add_argument("--target-pg-service", required=True)
    rollback.add_argument("--backup-dir", required=True)
    rollback.add_argument("--backup-private-key", required=True)
    rollback.add_argument("--target-maintenance-guard-command", required=True)
    rollback.add_argument("--confirm-backup-id", required=True)
    rollback.add_argument("--operator-production-approval", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    require_tools("psql", "pg_dump", "pg_restore", "openssl")
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "plan":
            command_plan(args)
        elif args.command == "apply":
            command_apply(args)
        elif args.command == "verify":
            command_verify(args)
        elif args.command == "export-inventory":
            command_export_inventory(args)
        elif args.command == "rollback":
            command_rollback(args)
        else:
            parser.error("unsupported command")
    except IdentitySyncError as error:
        parser.exit(1, f"ERROR: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
