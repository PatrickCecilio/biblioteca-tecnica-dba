# Laboratórios para comprovar os procedimentos D3

Os exemplos desta biblioteca foram revisados estaticamente. A execução
funcional depende de ambientes isolados e deve produzir evidência própria.
Nomes, caminhos e saídas abaixo são **cenários de laboratório**, não
resultados já obtidos. Priorize os testes na ordem indicada.

| Ordem | Laboratório | Ambiente isolado | Evidência mínima de aprovação |
|---:|---|---|---|
| 1 | [SQL Server: backup e point-in-time recovery](https://github.com/PatrickCecilio/sql-server-backup-recovery-lab) | SQL Server 2019+ Developer, bases `DBARecoveryLab` e `DBARecoveryLab_Restore` | Saída de `07-validate-recovery.sql`, cadeia full/diferencial/log em `msdb`, `STOPAT` efetivo, RPO/RTO medidos. A [issue #3](https://github.com/PatrickCecilio/sql-server-backup-recovery-lab/issues/3) acompanha a execução. |
| 2 | Oracle RMAN: backup, perda simulada e restore | CDB `ORCL` e PDB de teste em VM Oracle Linux; área de backup separada | `LIST BACKUP`, `RESTORE ... VALIDATE`, perda simulada de **objeto de teste**, restauração em ambiente alternativo e consulta que comprova o dado recuperado. Não use `DELETE OBSOLETE` até confirmar a cadeia. |
| 3 | Oracle PDB: clone e Flashback | CDB `ORCL`, PDBs fictícias `LABPDB` e `LABPDB_CLONE`, FRA dimensionada | Estado antes/depois em `V$PDBS`, restore point, SCN, alteração de tabela de teste, retorno e validação. Medir espaço na FRA; registrar `RESETLOGS` quando aplicável. |
| 4 | PostgreSQL pgBackRest: PITR | VM PostgreSQL isolada, stanza `lab`, PGDATA de laboratório | `pgbackrest info`, backup escolhido, WAL, timestamp alvo, log do restore e consulta que mostra o registro antes/depois. Preservar o cluster original em cópia ou VM separada. |
| 5 | Oracle ADRCI e audit: pré-visualização de retenção | VM Linux; primeiro em `/tmp/oracle-audit-lab.XXXXXX/ORCL/adump`, depois ADR home de teste | Listagem real dos `*.aud` antigos, caminho resolvido, retenção, contagem e validação pós-limpeza. O [runbook de diagnósticos](03-Avancado/Oracle/Performance-Monitoramento/RUNBOOK-LIMPEZA-DIAGNOSTICOS.md) inclui exercício sem exclusão. |
| 6 | Docker e criptografia de arquivos | VM descartável com Docker, `lab-postgres`, volume `lab-pg-data`, imagem LUKS nova | `docker context show`, inventário antes/depois, teste de recuperação do volume, validação de cópia e montagem LUKS. Testar os scripts com a trava de execução; preservar o backup original. |
| 7 | Data Guard: switchover e reintegração | Duas VMs Oracle com primary e physical standby de laboratório | `SHOW CONFIGURATION`, roles, transport/apply lag, SCN, switchover/failover simulado e validação da reintegração. Registrar perda observada e tempo até serviço, sem assumir RPO/RTO zero. |

## Registro de cada execução

1. Informe versão/edição, topologia, data e fuso, nomes dos bancos de laboratório,
   objetivo, pré-verificações e backup restaurável.
2. Preserve comandos, logs e consultas de validação com horário. Remova senhas,
   tokens, hostnames internos e dados reais antes de publicar.
3. Compare o estado esperado ao observado. Registre erro e recuperação quando
   houver; não transforme resultado esperado em evidência.
4. Anote RPO/RTO somente quando os eventos e horários foram medidos.
5. Publique a evidência no repositório do laboratório correspondente e mantenha
   esta lista como índice.

**Estado em 19/11/2026:** revisão de texto e validação estática concluídas.
Nenhum dos testes funcionais acima foi executado nesta revisão.
