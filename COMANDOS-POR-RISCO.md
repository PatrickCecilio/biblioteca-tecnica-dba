# Comandos por risco operacional

Esta classificação descreve o **impacto de uma execução incorreta**, não a senioridade necessária nem a complexidade sintática. A biblioteca continua organizada por nível de estudo; este índice permite localizar operações pelo potencial de indisponibilidade ou perda de dados. Exemplos são materiais de laboratório e dependem de versão, topologia e política de recuperação.

| Nível | Impacto possível | Exemplos | Controle mínimo |
|---|---|---|---|
| **D0 — Observação** | Sem alteração intencional de estado | `SELECT`, `SHOW PDBS`, `LIST BACKUP`, `REPORT OBSOLETE`, `df -h` | Confirmar alvo e privilégios de leitura. |
| **D1 — Mudança localizada** | Alteração reversível com escopo limitado | `GRANT`/`REVOKE`, `ALTER USER`, configuração de parâmetros, criação de objetos de teste | Registrar estado anterior, escopo e plano de retorno. |
| **D2 — Interrupção ou mudança estrutural** | Indisponibilidade, bloqueio de sessões ou necessidade de restore | `ALTER DATABASE ... SINGLE_USER`, `SHUTDOWN`, `ALTER PLUGGABLE DATABASE ... CLOSE`, patch, `RESTORE` em destino alternativo | Janela, dependências, backup validado e critérios de parada. |
| **D3 — Destruição ou recuperação com perda potencial** | Remoção de banco/arquivos, perda de dados ou mudança de linha temporal | `DROP DATABASE`, `DROP PLUGGABLE DATABASE ... INCLUDING DATAFILES`, `TRUNCATE`, `rm -rf` no diretório de dados, `OPEN RESETLOGS`, `DELETE OBSOLETE` | Aprovação operacional, alvo inequívoco, RPO/RTO, evidência de restore testado e plano de contingência. |

## Sequência de decisão para D2 e D3

1. Identifique host, serviço, SID/instância, banco, CDB/PDB ou database de destino. Confirme que a sessão está no ambiente esperado.
2. Defina o estado a preservar e o ponto de recuperação. Verifique backup, logs/archivelogs e capacidade de restaurar no **destino pretendido**.
3. Registre pré condições, comandos exatos, janela, impacto, critérios de parada e responsável pela validação.
4. Execute uma etapa por vez. Reavalie o estado após cada etapa; não encadeie remoção com recuperação sem conferir o resultado intermediário.
5. Valide dados, integridade, serviços, jobs, alertas e logs. Guarde evidências e documente o resultado ou a reversão.

## Mapa prioritário de comandos existentes

O mesmo arquivo pode conter comandos de níveis distintos. Abra o guia e classifique **cada comando**, sem presumir que todo o arquivo tenha o nível da pasta.

### D0 — Diagnóstico e preflight

- Oracle: `SHOW PDBS`, `V$VERSION` e validação de patch no [laboratório Oracle 19c](https://github.com/PatrickCecilio/oracle-19c-multitenant-deployment).
- SQL Server: consulta ao catálogo e histórico de backup no [laboratório de recuperação pontual](https://github.com/PatrickCecilio/sql-server-backup-recovery-lab).
- RMAN: `LIST EXPIRED` e `REPORT OBSOLETE` em [backup e recovery](02-Intermediario/Oracle/Backup-Recovery/). A leitura do resultado não autoriza `DELETE`.

### D1 — Alterações de escopo limitado

- `GRANT` e `REVOKE` de privilégios comuns: confirme usuário, role e privilégios efetivos antes e depois. Concessões administrativas como `DROP USER` ampliam risco de segurança e exigem revisão específica; há exemplos em [roles e grants](01-Iniciante/Oracle/Administracao-Seguranca/).
- `CROSSCHECK BACKUP`: consulta a mídia e **atualiza o status no repositório RMAN**. Confirme catálogo e dispositivo antes de executar; não confunda com `LIST`.

### D2 — Indisponibilidade e recuperação controlada

- `ALTER DATABASE ... SET SINGLE_USER WITH ROLLBACK IMMEDIATE`: encerra transações e conexões; aparece junto a `DROP DATABASE` em guias de nível iniciante. Classifique o procedimento completo como **D3**.
- `RESTORE DATABASE ... WITH NORECOVERY` e aplicação de logs: preserve a cadeia e valide destino, nomes lógicos e caminhos. O [laboratório SQL Server](https://github.com/PatrickCecilio/sql-server-backup-recovery-lab) usa uma base alternativa e evita `REPLACE`.
- `SHUTDOWN` e fechamento de PDB: planeje janela, impacto em aplicações e reabertura. Patches com OPatch/datapatch exigem validação binária e SQL após a execução.
- `CREATE RESTORE POINT ... GUARANTEE FLASHBACK DATABASE`: pode reter flashback logs e pressionar a FRA; monitore capacidade e remova o restore point somente após validar o fim da janela.

### D3 — Remoção e recuperação com perda potencial

| Comando ou padrão | Risco específico | Referência existente |
|---|---|---|
| `DROP DATABASE` | Remove banco e dados; `SINGLE_USER WITH ROLLBACK IMMEDIATE` interrompe sessões antes da remoção. | [SQL Server — remoção de database](01-Iniciante/SQL-Server/) |
| `DROP PLUGGABLE DATABASE ... INCLUDING DATAFILES` | Remove a PDB e seus datafiles. | [Oracle — clone de PDB](02-Intermediario/Oracle/Multitenant/) |
| `DROP USER ... CASCADE` / `DROP TABLESPACE ... INCLUDING CONTENTS AND DATAFILES` | Remove objetos ou arquivos associados. | [Oracle — storage](02-Intermediario/Oracle/Storage/) |
| `TRUNCATE TABLE` | Esvazia tabela com efeitos de DDL; não trate como `DELETE` transacional comum. | [Oracle — DDL/DML](02-Intermediario/Oracle/) |
| `rm -rf /var/lib/pgsql/14/data/*` | Apaga o diretório de dados PostgreSQL; o exemplo não constitui um runbook de restauração completo. | [PostgreSQL — restaurar](02-Intermediario/PostgreSQL/) |
| `DELETE OBSOLETE` / `DELETE ARCHIVELOG` | Pode eliminar a janela de recuperação exigida se retenção e backups externos não forem conferidos. | [Oracle — backup e recovery](02-Intermediario/Oracle/Backup-Recovery/) |
| `FLASHBACK DATABASE` e `OPEN RESETLOGS` | Altera a linha temporal de recuperação; depende de pré condições e validação de backups. | [Oracle — flashback](03-Avancado/Oracle/Backup-Recovery/) |
| `kill -9` em processo do Oracle | Pode afetar instância e recuperação; não é substituto de diagnóstico de sessão. | [Oracle — performance e monitoramento](03-Avancado/Oracle/Performance-Monitoramento/) |

## Pontos de revisão do acervo

- Há exemplos D3 em `01-Iniciante`; o caminho indica progressão didática, **não permissão para execução**.
- O guia PostgreSQL que contém `rm -rf` deve ser tratado como fragmento de referência, não como procedimento pronto. Exige plano de restore, verificação de backup e de diretório antes de qualquer uso.
- Alguns arquivos repetem material ou misturam consultas com remoção. Prefira os laboratórios com preflight, validação e ambiente isolado ao estudar uma sequência completa.
- Se um comando usar nome de ambiente, schema ou caminho real, substitua pelos parâmetros do seu laboratório; jamais copie literalmente para produção.
