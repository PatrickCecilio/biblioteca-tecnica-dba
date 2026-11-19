# Limpeza de diagnósticos Oracle — D3

Material de laboratório. A remoção de arquivos de auditoria, alertas, incidentes ou traces pode eliminar evidências necessárias para investigação e suporte. Execute somente com retenção aprovada para o ambiente e janela de manutenção definida.

## 1. Pré-verificações

- Confirme host, `ORACLE_BASE`, `DB_UNIQUE_NAME`, `ORACLE_SID` e ADR home. Não use caminhos copiados de outro ambiente.
- Confirme se há incidente aberto, exigência de auditoria, coleta de suporte ou retenção legal. Preserve os arquivos pertinentes antes da limpeza.
- Registre o espaço atual, a política de retenção e o diretório exato. Não limpe arquivos ativos nem use `rm -rf` ou curinga fora do alvo validado.
- Prefira as políticas do ADR para alert, trace e incident. O `ADRCI PURGE` opera no ADR home selecionado e deve ser usado somente após conferir `SHOW HOMES` e `SHOW CONTROL`.

```text
adrci
SHOW HOMES
SET HOMEPATH <ADR_HOME_VALIDADO>
SHOW CONTROL
```

## 2. Inspeção sem alteração

Para arquivos de auditoria fora do ADR, execute primeiro apenas a listagem.
O cenário abaixo usa uma instância fictícia `ORCL` em laboratório, com
retenção ilustrativa de 30 dias. Antes de executar em outro ambiente, confirme
o `ORACLE_BASE`, o `ORACLE_SID` e a política real.

```bash
TARGET='/u01/app/oracle/admin/ORCL/adump'
RETENTION_DAYS=30
test -d "$TARGET" && test ! -L "$TARGET" || { echo 'Alvo ausente ou link simbólico'; exit 1; }
realpath -- "$TARGET"
find "$TARGET" -xdev -type f -name '*.aud' -mtime +"$RETENTION_DAYS" -print
```

Saída **simulada** para mostrar o formato esperado; não é evidência de
execução neste repositório:

```text
/u01/app/oracle/admin/ORCL/adump
/u01/app/oracle/admin/ORCL/adump/audit001.aud
/u01/app/oracle/admin/ORCL/adump/audit002.aud
/u01/app/oracle/admin/ORCL/adump/audit003.aud
```

Na execução real, registre host, data, retenção, comando, listagem e contagem.
Uma lista vazia também é um resultado válido e não justifica reduzir a retenção.

### Exercício reproduzível sem tocar no Oracle

Crie arquivos fictícios em `/tmp` numa VM Linux de laboratório. O comando
somente lista os três arquivos; registre a saída real do seu ambiente.

```bash
LAB_ROOT=$(mktemp -d /tmp/oracle-audit-lab.XXXXXX)
mkdir -p "$LAB_ROOT/ORCL/adump"
touch "$LAB_ROOT/ORCL/adump/audit001.aud" "$LAB_ROOT/ORCL/adump/audit002.aud" "$LAB_ROOT/ORCL/adump/audit003.aud"
touch -d '31 days ago' "$LAB_ROOT/ORCL/adump/"*.aud
TARGET="$LAB_ROOT/ORCL/adump"
RETENTION_DAYS=30
find "$TARGET" -xdev -type f -name '*.aud' -mtime +"$RETENTION_DAYS" -print
```

Esse exercício demonstra o filtro de retenção. Ele não valida a política de
auditoria Oracle nem autoriza a exclusão de arquivos reais.

Confira a lista, o volume de arquivos, as datas e o caminho resolvido. Guarde evidência da listagem. **Pare** se o alvo, a retenção ou os arquivos encontrados divergirem do plano.

## 3. Execução controlada

Após aprovação operacional, execute uma categoria por vez. Para dados do ADR, selecione um único ADR home e use a política aprovada; `-age` é informado em **minutos**. Não use retenção de um dia por padrão.

```text
adrci
SET HOMEPATH <ADR_HOME_VALIDADO>
SHOW CONTROL
PURGE -AGE <MINUTOS_APROVADOS> -TYPE TRACE
```

Para `adump`, se a política permitir exclusão direta, repita **exatamente** os filtros inspecionados, trocando somente `-print` por `-delete`, após confirmar o `realpath` do alvo. Não execute esse passo durante uma investigação.

## 4. Validação

Repita a listagem com os mesmos filtros, confira alertas, incidentes e espaço disponível, registre horário, operador, comando, quantidade removida e exceções. Se houver comportamento inesperado, interrompa a rotina e preserve os arquivos restantes. Arquivos apagados não têm rollback automático.

Referência: [Oracle Database 19c — ADRCI](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-adr-command-interpreter-adrci.html).
