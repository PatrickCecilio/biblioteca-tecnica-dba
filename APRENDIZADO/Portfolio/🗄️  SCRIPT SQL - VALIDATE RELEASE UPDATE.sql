SET LINES 200
SET PAGES 200

COLUMN description FORMAT A70
COLUMN status FORMAT A15
COLUMN action FORMAT A15

SELECT
    con_id,
    patch_id,
    action,
    status,
    description,
    action_time
FROM cdb_registry_sqlpatch
WHERE patch_id = 37960098
ORDER BY con_id, action_time;

SELECT banner_full
FROM v$version;

SHOW PDBS;
