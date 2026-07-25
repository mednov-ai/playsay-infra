\set ON_ERROR_STOP on

WITH maria AS (
  SELECT id
  FROM app_user
  WHERE lower(coalesce(display_name, name, username)) = 'maria'
    AND roles LIKE '%TEACHER%'
),
approved_users AS (
  SELECT id, keycloak_subject, roles
  FROM app_user
  WHERE id IN (SELECT id FROM maria)
     OR managed_by_teacher_user_id IN (SELECT id FROM maria)
),
approved_materials AS (
  SELECT id
  FROM lesson_material
  WHERE owner_teacher_user_id = (SELECT id FROM maria)
    AND lower(title) <> 'hello'
),
approved_assets AS (
  SELECT id, material_id, storage_key
  FROM material_asset
  WHERE material_id IN (SELECT id FROM approved_materials)
),
approved_enrichments AS (
  SELECT id, material_id, asset_id
  FROM material_html_game_enrichment
  WHERE material_id IN (SELECT id FROM approved_materials)
),
gates AS (
  SELECT
    (SELECT count(*) FROM maria) = 1 AS maria_ok,
    (SELECT count(*) FROM approved_users) = 7 AS users_ok,
    (SELECT count(*) FROM approved_materials) = 22 AS materials_ok,
    (SELECT count(*) FROM approved_assets) = 51 AS assets_ok,
    (SELECT count(*) FROM approved_enrichments) = 11 AS enrichments_ok,
    (SELECT count(*) FROM lesson_material
       WHERE owner_teacher_user_id = (SELECT id FROM maria)
         AND lower(title) = 'hello') = 1 AS excluded_hello_ok
)
SELECT jsonb_pretty(
  jsonb_build_object(
    'schemaVersion', '1',
    'targetEnvironment', 'prod',
    'generatedAt', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'gates', (SELECT to_jsonb(gates) FROM gates),
    'users', (SELECT jsonb_agg(jsonb_build_object(
      'appUserId', id,
      'keycloakSubject', keycloak_subject,
      'roles', roles
    ) ORDER BY id) FROM approved_users),
    'materialIds', (SELECT jsonb_agg(id ORDER BY id) FROM approved_materials),
    'assets', (SELECT jsonb_agg(jsonb_build_object(
      'id', id,
      'materialId', material_id,
      'storageKey', storage_key
    ) ORDER BY id) FROM approved_assets),
    'enrichments', (SELECT jsonb_agg(jsonb_build_object(
      'id', id,
      'materialId', material_id,
      'assetId', asset_id
    ) ORDER BY id) FROM approved_enrichments)
  )
)
FROM gates
WHERE maria_ok AND users_ok AND materials_ok AND assets_ok
  AND enrichments_ok AND excluded_hello_ok;
