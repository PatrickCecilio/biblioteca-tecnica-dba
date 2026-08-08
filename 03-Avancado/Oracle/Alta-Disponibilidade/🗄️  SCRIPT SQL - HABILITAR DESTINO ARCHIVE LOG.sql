-- HABILITAR DESTINO DE ARCHIVE LOG
-- Valide o número do destino e a configuração do Data Guard antes da alteração.

SELECT dest_id, status, destination, error
FROM v$archive_dest
WHERE dest_id = 3;

ALTER SYSTEM SET log_archive_dest_state_3=ENABLE SCOPE=BOTH SID='*';

SELECT dest_id, status, destination, error
FROM v$archive_dest
WHERE dest_id = 3;
