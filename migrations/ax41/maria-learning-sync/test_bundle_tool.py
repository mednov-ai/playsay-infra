#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("bundle_tool.py")
SPEC = importlib.util.spec_from_file_location("bundle_tool", MODULE_PATH)
assert SPEC and SPEC.loader
bundle_tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bundle_tool)


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0])
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


class BundleToolTest(unittest.TestCase):
    def test_sql_templates_project_external_teacher_management_edges(self) -> None:
        root = Path(__file__).parent
        export_sql = (root / "export.sql.in").read_text(encoding="utf-8")
        apply_sql = (root / "apply.sql.in").read_text(encoding="utf-8")
        self.assertIn("CREATE TEMP TABLE sync_app_user", export_sql)
        self.assertIn("managed_by_teacher = false", export_sql)
        self.assertIn("managed_by_teacher_user_id = NULL", export_sql)
        self.assertIn("COPY (SELECT * FROM sync_app_user ORDER BY id)", export_sql)
        self.assertIn("CREATE TEMP TABLE sync_course_export", export_sql)
        self.assertIn("created_by_user_id = NULL", export_sql)
        self.assertIn("CREATE TEMP TABLE sync_lesson_material_export", export_sql)
        self.assertIn("owner_teacher_user_id = NULL", export_sql)
        self.assertIn("ALTER TABLE sync_materials ADD PRIMARY KEY", export_sql)
        self.assertIn("ALTER TABLE sync_templates ADD PRIMARY KEY", export_sql)
        self.assertIn("SELECT material_id FROM lesson_template_card", export_sql)
        self.assertIn("CREATE TEMP TABLE sync_assignment_export", export_sql)
        self.assertIn("CREATE TEMP TABLE sync_submission_export", export_sql)
        self.assertIn("management edge outside the selected cohort", apply_sql)
        self.assertIn("nullable owner edge outside the selected cohort", apply_sql)
        self.assertIn("bundle material/template closure is incomplete", apply_sql)
        self.assertIn("CREATE TEMP TABLE youtube_cache_id_map", apply_sql)
        self.assertIn("existing.video_id = incoming.video_id", apply_sql)
        self.assertIn("CREATE TEMP TABLE youtube_reference_id_map", apply_sql)
        self.assertIn("CREATE TEMP TABLE game_enrichment_id_map", apply_sql)

    def test_html_game_enrichment_compares_by_natural_key(self) -> None:
        source = {
            "source-id": {
                "id": "source-id", "material_id": "material", "asset_id": "asset",
                "block_id": "block", "status": "READY",
            }
        }
        target = {
            "target-id": {
                "id": "target-id", "material_id": "material", "asset_id": "asset",
                "block_id": "block", "status": "READY",
            }
        }
        self.assertEqual(
            bundle_tool.natural_key_rows(
                source, ("material_id", "asset_id", "block_id"), "enrichment"
            ),
            bundle_tool.natural_key_rows(
                target, ("material_id", "asset_id", "block_id"), "enrichment"
            ),
        )

    def test_youtube_cache_and_references_compare_by_natural_keys(self) -> None:
        source_caches = {
            "source-cache": {
                "id": "source-cache", "video_id": "video", "quality": "MEDIUM",
                "status": "READY", "storage_key": "cache/video",
            }
        }
        target_caches = {
            "target-cache": {
                "id": "target-cache", "video_id": "video", "quality": "MEDIUM",
                "status": "READY", "storage_key": "cache/video",
            }
        }
        source_logical, source_ids = bundle_tool.youtube_cache_logical_rows(source_caches)
        target_logical, target_ids = bundle_tool.youtube_cache_logical_rows(target_caches)
        self.assertEqual(source_logical, target_logical)

        source_references = {
            "source-reference": {
                "id": "source-reference", "cache_id": "source-cache",
                "material_id": "material", "block_id": "block", "created_at": "now",
            }
        }
        target_references = {
            "target-reference": {
                "id": "target-reference", "cache_id": "target-cache",
                "material_id": "material", "block_id": "block", "created_at": "now",
            }
        }
        self.assertEqual(
            bundle_tool.youtube_reference_logical_rows(source_references, source_ids),
            bundle_tool.youtube_reference_logical_rows(target_references, target_ids),
        )

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        (self.source / "tables").mkdir(parents=True)
        (self.source / "objects").mkdir()
        (self.source / "maria-subject.txt").write_text("subject-maria\n", encoding="utf-8")
        (self.source / "cohort-subjects.txt").write_text("subject-maria\nsubject-student\n", encoding="utf-8")
        (self.source / "database-schema.tsv").write_text("app_user\t1\tid\tuuid\tuuid\tNO\t\n", encoding="utf-8")
        (self.source / "objects-selection.json").write_text("[]", encoding="utf-8")
        write_csv(
            self.source / "tables/app_user.csv",
            [
                {"id": "00000000-0000-0000-0000-000000000001", "keycloak_subject": "subject-maria"},
                {"id": "00000000-0000-0000-0000-000000000002", "keycloak_subject": "subject-student"},
            ],
        )
        write_csv(
            self.source / "tables/lesson.csv",
            [{"id": "10000000-0000-0000-0000-000000000001", "status": "COMPLETED"}],
        )
        write_csv(
            self.source / "tables/lesson_material.csv",
            [{"id": "30000000-0000-0000-0000-000000000001", "title": "source"}],
        )
        bundle_tool.build_manifest(
            argparse.Namespace(
                payload=str(self.source),
                maria_subject_file=str(self.source / "maria-subject.txt"),
                bundle_id="maria-learning-vdsina-to-dev-20260810T120000Z",
                created_at="2026-08-10T12:00:00Z",
                cutoff_at="2026-08-10T12:00:00Z",
                platform_commit="platform-sha",
                infra_commit="infra-sha",
                source_environment="vdsina",
                target_environment="dev",
            )
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_manifest_validation_and_target_only_identity_policy(self) -> None:
        bundle_tool.validate_manifest(self.source)
        target = self.root / "target"
        (target / "tables").mkdir(parents=True)
        (target / "objects-selection.json").write_text(
            json.dumps([
                {"keySha256": "a" * 64, "sourceKinds": ["MATERIAL_ASSET"]},
                {"keySha256": "b" * 64, "sourceKinds": ["COLLABORATION_SNAPSHOT"]},
            ]),
            encoding="utf-8",
        )
        write_csv(
            target / "tables/app_user.csv",
            [
                {"id": "00000000-0000-0000-0000-000000000001", "keycloak_subject": "subject-maria"},
                {"id": "00000000-0000-0000-0000-000000000002", "keycloak_subject": "subject-student"},
                {"id": "00000000-0000-0000-0000-000000000003", "keycloak_subject": "target-only"},
            ],
        )
        write_csv(
            target / "tables/lesson.csv",
            [
                {"id": "10000000-0000-0000-0000-000000000001", "status": "SCHEDULED"},
                {"id": "10000000-0000-0000-0000-000000000002", "status": "COMPLETED"},
            ],
        )
        write_csv(
            target / "tables/lesson_material.csv",
            [
                {"id": "30000000-0000-0000-0000-000000000001", "title": "source"},
                {"id": "30000000-0000-0000-0000-000000000002", "title": "shared"},
            ],
        )
        output = self.root / "plan.json"
        bundle_tool.plan(argparse.Namespace(source=str(self.source), target=str(target), output=str(output)))
        report = json.loads(output.read_text(encoding="utf-8"))
        by_table = {item["name"]: item for item in report["tables"]}
        self.assertEqual(1, by_table["app_user"]["preservedTargetOnly"])
        self.assertEqual(0, by_table["app_user"]["delete"])
        self.assertEqual(1, by_table["lesson"]["update"])
        self.assertEqual(1, by_table["lesson"]["delete"])
        self.assertEqual(1, by_table["lesson_material"]["preservedTargetOnly"])
        self.assertEqual(0, by_table["lesson_material"]["delete"])
        self.assertEqual(1, report["objects"]["delete"])
        self.assertEqual(1, report["objects"]["preservedTargetOnly"])

    def test_due_reminder_is_made_non_replayable(self) -> None:
        reminder = self.root / "reminder.csv"
        write_csv(
            reminder,
            [{
                "id": "20000000-0000-0000-0000-000000000001",
                "due_at": "2026-08-10T11:00:00+00:00",
                "status": "FAILED",
                "last_error": "provider timeout",
            }],
        )
        bundle_tool.normalize_reminders(
            argparse.Namespace(file=str(reminder), cutoff="2026-08-10T12:00:00Z")
        )
        _, rows = bundle_tool.read_csv(reminder)
        row = next(iter(rows.values()))
        self.assertEqual("SKIPPED", row["status"])
        self.assertEqual("", row["last_error"])

    def test_manifest_route_is_bound_to_bundle_id(self) -> None:
        manifest_path = self.source / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["targetEnvironment"] = "prod"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "manifest contract violation"):
            bundle_tool.validate_manifest(self.source)


if __name__ == "__main__":
    unittest.main()
