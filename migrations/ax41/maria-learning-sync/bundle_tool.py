#!/usr/bin/env python3
"""Local manifest/diff helper. It never prints row values or object keys."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path


csv.field_size_limit(min(sys.maxsize, 2**31 - 1))


EXCLUSIONS = [
    "assignment_integration_outbox",
    "vocabulary_integration_outbox",
    "chat",
    "ai_tutor",
    "registration",
    "email_delivery",
    "audit",
    "sessions_and_tokens",
]

PRESERVED_TARGET_SUPERSET_TABLES = {
    "app_user",
    "student_profile",
    "teacher_profile",
    "course",
    "curriculum_topic",
    "lesson_material",
    "material_asset",
    "material_html_game_enrichment",
    "material_game_adaptation",
    "youtube_video_cache",
    "youtube_video_cache_reference",
    "lesson_template",
    "lesson_template_card",
}

PRESERVED_OBJECT_KINDS = {"MATERIAL_ASSET", "YOUTUBE_CACHE"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_csv(path: Path) -> tuple[list[str], dict[str, dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None or "id" not in reader.fieldnames:
            raise SystemExit(f"CSV contract violation for {path.name}: id column is required")
        rows: dict[str, dict[str, str]] = {}
        for row in reader:
            row_id = row["id"]
            if not row_id or row_id in rows:
                raise SystemExit(f"CSV contract violation for {path.name}: invalid or duplicate id")
            rows[row_id] = row
        return reader.fieldnames, rows


def youtube_cache_logical_rows(
    rows: dict[str, dict[str, str]],
) -> tuple[dict[tuple[str, str], dict[str, str]], dict[str, tuple[str, str]]]:
    logical: dict[tuple[str, str], dict[str, str]] = {}
    id_to_key: dict[str, tuple[str, str]] = {}
    for row_id, row in rows.items():
        key = (row.get("video_id", ""), row.get("quality", ""))
        if not all(key) or key in logical:
            raise SystemExit("YouTube cache natural-key contract violation")
        logical[key] = {name: value for name, value in row.items() if name != "id"}
        id_to_key[row_id] = key
    return logical, id_to_key


def natural_key_rows(
    rows: dict[str, dict[str, str]], columns: tuple[str, ...], label: str
) -> dict[tuple[str, ...], dict[str, str]]:
    logical: dict[tuple[str, ...], dict[str, str]] = {}
    for row in rows.values():
        key = tuple(row.get(column, "") for column in columns)
        if not all(key) or key in logical:
            raise SystemExit(f"{label} natural-key contract violation")
        logical[key] = {name: value for name, value in row.items() if name != "id"}
    return logical


def youtube_reference_logical_rows(
    rows: dict[str, dict[str, str]],
    cache_id_to_key: dict[str, tuple[str, str]],
) -> dict[tuple[str, str], dict[str, object]]:
    logical: dict[tuple[str, str], dict[str, object]] = {}
    for row in rows.values():
        key = (row.get("material_id", ""), row.get("block_id", ""))
        cache_key = cache_id_to_key.get(row.get("cache_id", ""))
        if not all(key) or cache_key is None or key in logical:
            raise SystemExit("YouTube cache reference natural-key contract violation")
        normalized: dict[str, object] = {
            name: value for name, value in row.items() if name not in {"id", "cache_id"}
        }
        normalized["cacheNaturalKey"] = cache_key
        logical[key] = normalized
    return logical


def logical_table_rows(root: Path, table: str) -> dict[object, dict[str, object]]:
    _, rows = read_csv(root / "tables" / f"{table}.csv")
    if table == "youtube_video_cache":
        logical, _ = youtube_cache_logical_rows(rows)
        return logical
    if table == "youtube_video_cache_reference":
        _, cache_rows = read_csv(root / "tables" / "youtube_video_cache.csv")
        _, cache_id_to_key = youtube_cache_logical_rows(cache_rows)
        return youtube_reference_logical_rows(rows, cache_id_to_key)
    if table == "material_html_game_enrichment":
        return natural_key_rows(
            rows, ("material_id", "asset_id", "block_id"), "HTML game enrichment"
        )
    return rows


def normalize_reminders(args: argparse.Namespace) -> None:
    path = Path(args.file)
    fields, rows = read_csv(path)
    cutoff = datetime.fromisoformat(args.cutoff.replace("Z", "+00:00"))
    changed = False
    for row in rows.values():
        if row.get("status") not in {"PENDING", "FAILED"}:
            continue
        due = datetime.fromisoformat(row["due_at"].replace("Z", "+00:00"))
        if due <= cutoff:
            row["status"] = "SKIPPED"
            if "last_error" in row:
                row["last_error"] = ""
            changed = True
    if changed:
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            for row_id in sorted(rows):
                writer.writerow(rows[row_id])


def build_objects(args: argparse.Namespace) -> None:
    source = Path(args.keys)
    output = Path(args.output)
    grouped: dict[str, set[str]] = {}
    with source.open(newline="", encoding="utf-8") as handle:
        for key_hex, source_kind in csv.reader(handle, delimiter="\t"):
            key = bytes.fromhex(key_hex).decode("utf-8")
            if not key or key.startswith("/") or ".." in Path(key).parts or "\x00" in key:
                raise SystemExit("unsafe object key in source selection")
            grouped.setdefault(key_hex, set()).add(source_kind)
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = [
        {
            "keyHex": key_hex,
            "keySha256": sha256_bytes(bytes.fromhex(key_hex)),
            "file": f"objects/{sha256_bytes(bytes.fromhex(key_hex))}",
            "sourceKinds": sorted(kinds),
        }
        for key_hex, kinds in sorted(grouped.items())
    ]
    output.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")


def build_manifest(args: argparse.Namespace) -> None:
    root = Path(args.payload)
    objects = json.loads((root / "objects-selection.json").read_text(encoding="utf-8"))
    for item in objects:
        object_path = root / item["file"]
        if not object_path.is_file():
            raise SystemExit("selected object payload is missing")
        item["size"] = object_path.stat().st_size
        item["sha256"] = sha256_file(object_path)
    tables = []
    for path in sorted((root / "tables").glob("*.csv")):
        _, rows = read_csv(path)
        digest = sha256_file(path)
        tables.append(
            {
                "name": path.stem,
                "rowCount": len(rows),
                "rowSha256": digest,
                "file": f"tables/{path.name}",
                "fileSha256": digest,
            }
        )
    cohort = (root / "cohort-subjects.txt").read_bytes()
    maria = Path(args.maria_subject_file).read_bytes().strip()
    manifest = {
        "schemaVersion": "2",
        "bundleId": args.bundle_id,
        "createdAt": args.created_at,
        "cutoffAt": args.cutoff_at,
        "sourceEnvironment": args.source_environment,
        "targetEnvironment": args.target_environment,
        "sourceDatabaseSchemaSha256": sha256_file(root / "database-schema.tsv"),
        "platformCommit": args.platform_commit,
        "infraCommit": args.infra_commit,
        "mariaSubjectSha256": sha256_bytes(maria),
        "cohortSubjectSha256": sha256_bytes(cohort),
        "tables": tables,
        "objects": objects,
        "exclusions": EXCLUSIONS,
    }
    (root / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def validate_manifest(root: Path) -> dict:
    manifest_path = root / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    required = {
        "schemaVersion", "bundleId", "createdAt", "cutoffAt",
        "sourceEnvironment", "targetEnvironment",
        "sourceDatabaseSchemaSha256", "platformCommit", "infraCommit",
        "mariaSubjectSha256", "cohortSubjectSha256", "tables", "objects", "exclusions",
    }
    routes = {("vdsina", "dev"), ("dev", "prod")}
    route = (manifest.get("sourceEnvironment"), manifest.get("targetEnvironment"))
    if set(manifest) != required or manifest["schemaVersion"] != "2" or route not in routes:
        raise SystemExit("manifest contract violation")
    expected_id = rf"maria-learning-{route[0]}-to-{route[1]}-[0-9]{{8}}T[0-9]{{6}}Z"
    if re.fullmatch(expected_id, manifest["bundleId"]) is None:
        raise SystemExit("manifest route does not match bundle ID")
    if manifest["exclusions"] != EXCLUSIONS:
        raise SystemExit("manifest exclusions were changed")
    if sha256_file(root / "database-schema.tsv") != manifest["sourceDatabaseSchemaSha256"]:
        raise SystemExit("database schema checksum mismatch")
    if sha256_bytes((root / "cohort-subjects.txt").read_bytes()) != manifest["cohortSubjectSha256"]:
        raise SystemExit("cohort checksum mismatch")
    if sha256_bytes((root / "maria-subject.txt").read_bytes().strip()) != manifest["mariaSubjectSha256"]:
        raise SystemExit("Maria subject checksum mismatch")
    for table in manifest["tables"]:
        path = root / table["file"]
        _, rows = read_csv(path)
        digest = sha256_file(path)
        if len(rows) != table["rowCount"] or digest != table["fileSha256"] or digest != table["rowSha256"]:
            raise SystemExit(f"table checksum/count mismatch: {table['name']}")
    for item in manifest["objects"]:
        key = bytes.fromhex(item["keyHex"])
        if sha256_bytes(key) != item["keySha256"]:
            raise SystemExit("object key checksum mismatch")
        path = root / item["file"]
        if path.stat().st_size != item["size"] or sha256_file(path) != item["sha256"]:
            raise SystemExit("object checksum/size mismatch")
    return manifest


def validate(args: argparse.Namespace) -> None:
    manifest = validate_manifest(Path(args.payload))
    print(json.dumps({"bundleId": manifest["bundleId"], "manifestSha256": sha256_file(Path(args.payload) / "manifest.json")}, separators=(",", ":")))


def plan(args: argparse.Namespace) -> None:
    source_root = Path(args.source)
    target_root = Path(args.target)
    manifest = validate_manifest(source_root)
    report = {"bundleId": manifest["bundleId"], "tables": [], "objects": {}}
    for table in manifest["tables"]:
        source_rows = logical_table_rows(source_root, table["name"])
        target_rows = logical_table_rows(target_root, table["name"])
        source_ids, target_ids = set(source_rows), set(target_rows)
        common = source_ids & target_ids
        updates = sum(source_rows[row_id] != target_rows[row_id] for row_id in common)
        preserve_target_only = table["name"] in PRESERVED_TARGET_SUPERSET_TABLES
        report["tables"].append({
            "name": table["name"],
            "insert": len(source_ids - target_ids),
            "update": updates,
            "delete": 0 if preserve_target_only else len(target_ids - source_ids),
            "preservedTargetOnly": len(target_ids - source_ids) if preserve_target_only else 0,
            "unchanged": len(common) - updates,
        })
    source_keys = {item["keySha256"] for item in manifest["objects"]}
    target_selection = json.loads((target_root / "objects-selection.json").read_text(encoding="utf-8"))
    target_by_key = {item["keySha256"]: item for item in target_selection}
    target_keys = set(target_by_key)
    target_only = target_keys - source_keys
    preserved_target_only = {
        key for key in target_only
        if PRESERVED_OBJECT_KINDS & set(target_by_key[key].get("sourceKinds", []))
    }
    report["objects"] = {
        "source": len(source_keys),
        "writeOrVerify": len(source_keys),
        "delete": len(target_only - preserved_target_only),
        "preservedTargetOnly": len(preserved_target_only),
    }
    Path(args.output).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def compare_target(args: argparse.Namespace) -> None:
    source_root = Path(args.source)
    target_root = Path(args.target)
    manifest = validate_manifest(source_root)
    superset_tables = PRESERVED_TARGET_SUPERSET_TABLES
    for table in manifest["tables"]:
        source_rows = logical_table_rows(source_root, table["name"])
        target_rows = logical_table_rows(target_root, table["name"])
        for row_id, source_row in source_rows.items():
            if target_rows.get(row_id) != source_row:
                raise SystemExit(f"target row mismatch: {table['name']}")
        if table["name"] not in superset_tables and set(target_rows) != set(source_rows):
            raise SystemExit(f"target scope is not exact: {table['name']}")
    print(json.dumps({"bundleId": manifest["bundleId"], "database": "verified"}, separators=(",", ":")))


def validate_schema_compatibility(args: argparse.Namespace) -> None:
    source_root = Path(args.source)
    target_root = Path(args.target)
    manifest = validate_manifest(source_root)
    target_columns: dict[str, list[str]] = {}
    with (target_root / "database-schema.tsv").open(newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 3:
                raise SystemExit("target database schema contract violation")
            target_columns.setdefault(row[0], []).append(row[2])
    for table in manifest["tables"]:
        source_fields, _ = read_csv(source_root / table["file"])
        if source_fields != target_columns.get(table["name"]):
            raise SystemExit(f"source/target column mismatch: {table['name']}")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    normalize = sub.add_parser("normalize-reminders")
    normalize.add_argument("--file", required=True)
    normalize.add_argument("--cutoff", required=True)
    normalize.set_defaults(func=normalize_reminders)
    objects = sub.add_parser("build-objects")
    objects.add_argument("--keys", required=True)
    objects.add_argument("--output", required=True)
    objects.set_defaults(func=build_objects)
    manifest = sub.add_parser("build-manifest")
    manifest.add_argument("--payload", required=True)
    manifest.add_argument("--maria-subject-file", required=True)
    manifest.add_argument("--bundle-id", required=True)
    manifest.add_argument("--created-at", required=True)
    manifest.add_argument("--cutoff-at", required=True)
    manifest.add_argument("--platform-commit", required=True)
    manifest.add_argument("--infra-commit", required=True)
    manifest.add_argument("--source-environment", choices=("vdsina", "dev"), required=True)
    manifest.add_argument("--target-environment", choices=("dev", "prod"), required=True)
    manifest.set_defaults(func=build_manifest)
    validate_cmd = sub.add_parser("validate")
    validate_cmd.add_argument("--payload", required=True)
    validate_cmd.set_defaults(func=validate)
    plan_cmd = sub.add_parser("plan")
    plan_cmd.add_argument("--source", required=True)
    plan_cmd.add_argument("--target", required=True)
    plan_cmd.add_argument("--output", required=True)
    plan_cmd.set_defaults(func=plan)
    compare_cmd = sub.add_parser("compare-target")
    compare_cmd.add_argument("--source", required=True)
    compare_cmd.add_argument("--target", required=True)
    compare_cmd.set_defaults(func=compare_target)
    schema_cmd = sub.add_parser("validate-schema-compatibility")
    schema_cmd.add_argument("--source", required=True)
    schema_cmd.add_argument("--target", required=True)
    schema_cmd.set_defaults(func=validate_schema_compatibility)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
