#!/usr/bin/env python3
"""Generate a conservative, reproducible risk triage for the public library.

This is a search index, not approval to execute any command. A file inherits
the highest matching level; context and target must still be reviewed.
"""

from __future__ import annotations

import argparse
import re
from collections import Counter
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ("01-Iniciante", "02-Intermediario", "03-Avancado", "APRENDIZADO", "PROMPTS")
INDEX_NAME = "🗂️  ÍNDICE - 00 INDICE.md"
OUTPUT = ROOT / "INVENTARIO-RISCO.md"

RULES = {
    "D3": {
        "remoção de banco ou objeto": r"\bDROP\s+(?:DATABASE|PLUGGABLE\s+DATABASE|TABLESPACE|USER|TABLE)\b",
        "esvaziamento ou exclusão de dados": r"\b(?:TRUNCATE\s+TABLE|DELETE\s+FROM)\b",
        "remoção de arquivos": r"\brm\s+-(?:[a-z]*r[a-z]*f|[a-z]*f[a-z]*r)\b|\b(?:mkfs|wipefs)\b",
        "remoção de backups ou logs": r"\bDELETE\s+(?:OBSOLETE|ARCHIVELOG)\b",
        "mudança de linha temporal": r"\b(?:FLASHBACK\s+DATABASE|OPEN\s+RESETLOGS)\b",
        "interrupção forçada": r"\bkill\s+-9\b",
        "limpeza irreversível": r"\bfind\b[^\n]{0,200}\s-delete\b|\bdocker\s+(?:image|system|volume|container)\s+prune\b",
        "formatação de volume": r"\bcryptsetup\s+luksFormat\b|\bdd\s+if=",
        "remoção Docker": r"\bdocker\s+(?:container|volume|network|service)\s+rm\b",
        "exclusão por shell ou script": r"\bfind\b[\s\S]{0,250}?-exec\s+rm\s+-f\b|\b(?:Remove-Item|del\s+/q)\b|\brobocopy\b[^\n]*\s/MIR\b",
        "risco D3 declarado": r"\bRISCO\s+D3\b",
    },
    "D2": {
        "restore ou recovery": r"\b(?:RESTORE|RECOVER)\s+(?:DATABASE|PLUGGABLE\s+DATABASE|DATAFILE|TABLESPACE)\b",
        "mudança em banco ou PDB": r"\bALTER\s+(?:DATABASE|PLUGGABLE\s+DATABASE|SYSTEM)\b",
        "parada ou restart": r"\b(?:SHUTDOWN|STARTUP)\b|\bsystemctl\s+(?:stop|restart)\b",
        "patch Oracle": r"\b(?:OPATCH|datapatch)\b",
        "criação de PDB": r"\bCREATE\s+PLUGGABLE\s+DATABASE\b",
        "acesso exclusivo SQL Server": r"\bSINGLE_USER\s+WITH\s+ROLLBACK\s+IMMEDIATE\b",
        "serviço ou rede": r"\b(?:docker\s+(?:container\s+(?:stop|restart)|swarm\s+init|service\s+(?:create|update|scale))|firewall-cmd\s+--(?:add|remove|reload)|srvctl\s+(?:stop|start|modify))\b",
        "importação ou failover": r"\b(?:impdp|pg_restore|SWITCHOVER|FAILOVER)\b",
        "implantação de stack": r"\bdocker\s+stack\s+deploy\b",
    },
    "D1": {
        "DDL ou permissão": r"\b(?:CREATE|ALTER|GRANT|REVOKE)\s+(?:USER|ROLE|TABLE|INDEX|VIEW|SCHEMA|PROFILE|TABLESPACE)\b",
        "mudança em dados": r"\b(?:INSERT\s+INTO|UPDATE\s+\S+)\b",
        "backup ou configuração": r"\b(?:BACKUP\s+DATABASE|BACKUP\s+LOG|CONFIGURE\s+\w+)\b",
        "serviço ou pacote": r"\bsystemctl\s+start\b|\b(?:yum|dnf|apt(?:-get)?)\s+install\b",
        "permissão de arquivo": r"\b(?:chmod|chown)\s+",
        "Docker e exportação": r"\bdocker\s+(?:container\s+(?:run|start|exec)|volume\s+create|network\s+create|image\s+pull|build\b)|\bexpdp\b",
        "configuração de ambiente": r"\b(?:export\s+\w+=|firewall-cmd\s+--(?:list|query)|dnf\s+config-manager)\b",
        "configuração e automação": r"\b(?:CREATE\s+(?:PFILE|SPFILE)|dbms_monitor\.serv_mod_act_trace_enable|sudo\s+install|docker-machine\s+start|wget\s+|curl\s+|rman\s+target\s+|BACKUP\s+INCREMENTAL|crontab\s+-e|mkdir\s+|New-Item\s+|export\s+\w+(?:=|\s*$))",
        "agendamento de rotina": r"(?m)^\s*\d{1,2}\s+\d{1,2}\s+\*\s+\*\s+[\d*/,-]+\s+\S+",
        "geração de relatório": r"\bAuditoriaArquivos\.ps1\b",
    },
    "D0": {
        "consulta SQL": r"\bSELECT\b|\bSHOW\s+(?:PDBS|PARAMETER|DATABASES)\b",
        "consulta RMAN": r"\b(?:LIST\s+BACKUP|REPORT\s+OBSOLETE)\b",
        "consulta de sistema": r"\b(?:df\s+-h|lsblk\b|free\s+-[hm]|uname\s+-\w+|hostname\b|ip\s+(?:a\b|addr\s+show)|docker\s+(?:container\s+)?(?:ps|logs|images)\b)",
        "consulta de arquivos e logs": r"\b(?:grep\s+|find\s+[^\n]{0,150}\s-print\b|adrci\s+exec=.?show\b)",
        "consulta complementar": r"\b(?:findmnt|env\s*\|\s*sort|cat\s+/etc/passwd|sqlplus\s+/\s+as\s+sysdba|docker\s+stack\s+ls|docker\s+service\s+(?:ls|logs|inspect)|find\s+\S+\s+-maxdepth|Get-ChildItem\s+)",
        "consultas e cálculos locais": r"\b(?:cut\s+-d:|getent\s+passwd|tail\s+-n|journalctl\s+-u|lastlog\b|last\s+-a|read\s+(?:-r\s+)?n1\s+n2)\b",
    },
}

COMPILED = {
    level: [(name, re.compile(pattern, re.IGNORECASE | re.MULTILINE)) for name, pattern in rules.items()]
    for level, rules in RULES.items()
}

# Reviewed references and captured outputs without runnable commands.
# New content stays R until reviewed.
REVIEWED_NON_COMMAND = frozenset({
    "01-Iniciante/Linux/Administracao-do-Sistema/🐧  GUIA PRÁTICO - IDENTIFICAR KERNEL UNAME.txt",
    "01-Iniciante/Linux/Administracao-do-Sistema/🐧  GUIA PRÁTICO - LISTAR DISPOSITIVOS BLOCO LSBLK.txt",
    "01-Iniciante/Linux/Administracao-do-Sistema/🐧  GUIA PRÁTICO - VERIFICAR MEMORIA FREE.txt",
    "01-Iniciante/Linux/Administracao-do-Sistema/🐧  GUIA PRÁTICO - VERIFICAR MONTAGENS FILESYSTEM.txt",
    "01-Iniciante/Linux/Administracao-do-Sistema/🐧  GUIA PRÁTICO - VERIFICAR USO DISCO DF.txt",
    "01-Iniciante/Linux/Instalacao-Administracao/🛠️  GUIA PRÁTICO - CONCEITOS BASICOS SHELL.txt",
    "01-Iniciante/Oracle/Fundamentos-Referencias/🟠  GUIA PRÁTICO - DATILFES.txt",
    "01-Iniciante/Oracle/Instalacao-Administracao/🛠️  GUIA PRÁTICO - DSDS.txt",
    "01-Iniciante/Oracle/Instalacao-Administracao/🛠️  GUIA PRÁTICO - IDENTIFICAR VERSAO SISTEMA OPERACIONAL.txt",
    "01-Iniciante/Oracle/Instalacao-Administracao/🛠️  GUIA PRÁTICO - OS SUMMARY.txt",
    "01-Iniciante/Oracle/Instalacao-Administracao/🛠️  GUIA PRÁTICO - SSDS.txt",
    "01-Iniciante/Oracle/SQL/🟠  GUIA PRÁTICO - 🏷️ LIMITE DE OPERAÇÕES DDL POR MINUTO.txt",
    "02-Intermediario/Linux/Automacao-Shell/🐧  GUIA PRÁTICO - OPERADORES DE REDIRECIONAMENTO.txt",
    "02-Intermediario/Oracle/Administracao/🟠  GUIA PRÁTICO - OS ENV BEFORE ORAENV.txt",
    "02-Intermediario/Oracle/Conectividade/🌐  GUIA PRÁTICO - 🏷️ CONEXÃO AO MYSQL DB SYSTEM NA OCI.txt",
    "02-Intermediario/Oracle/Performance-Monitoramento/Logs-de-Exemplo/💾  GUIA PRÁTICO - BROTHERS.txt",
    "02-Intermediario/Oracle/Storage/🟠  GUIA PRÁTICO - SYSAUX PARTE 2.txt",
    "02-Intermediario/Oracle/Storage/🟠  GUIA PRÁTICO - SYSAUX.txt",
    "02-Intermediario/Oracle/Storage/🟠  GUIA PRÁTICO - 🏗️ COMO FUNCIONA NA PRÁTICA.txt",
    "03-Avancado/Oracle/Data-Pump-Migracao/🟠  GUIA PRÁTICO - RELATORIO TEMPOS RECRIACAO E MIGRACAO ORACLE.txt",
    "03-Avancado/Oracle/Fundamentos-Referencias/🔐  GUIA PRÁTICO - 🏷️ GOVERNANÇA, SEGURANÇA E ESCALABILIDADE NO EXADATA DENTRO DO OCI.txt",
    "03-Avancado/Oracle/Fundamentos-Referencias/🟠  GUIA PRÁTICO - GABARITO EXERCICIOS ORACLE.txt",
    "03-Avancado/Oracle/Fundamentos-Referencias/🟠  GUIA PRÁTICO - 🏷️ CONCEITO DE ZERO OCPUS.txt",
    "03-Avancado/Oracle/Fundamentos-Referencias/🟠  GUIA PRÁTICO - 🏷️ EXADATA X8 E EXADATA X8M.txt",
    "03-Avancado/Oracle/Fundamentos-Referencias/🟠  GUIA PRÁTICO - 🏷️ FLEXIBILIDADE E ALTA DISPONIBILIDADE NO ORACLE EXADATA DATABASE SERVICE.txt",
    "03-Avancado/Oracle/Material-Tecnico/🐧  GUIA PRÁTICO - GUIA SWAP LINUX.txt",
    "03-Avancado/Oracle/Performance-Monitoramento/💾  GUIA PRÁTICO - LOG BUFFER CONCEITO.txt",
    "APRENDIZADO/Desenvolvimento-Web/🎓  MATERIAL DE ESTUDO - SEGURANCA UX PERFORMANCE BACKEND.txt",
    "APRENDIZADO/Estudos-Tecnicos/🎓  MATERIAL DE ESTUDO - CONCEITO DE FILEGROUPS AUTOGROWTH.txt",
    "APRENDIZADO/Referencias-Operacionais/🎓  MATERIAL DE ESTUDO - USUARIOPS.txt",
    "PROMPTS/Geral/💬  PROMPT - CRIACAO SLIDES.txt",
    "PROMPTS/💬  PROMPT - ANALISE SITE ECOMMERCE.txt",
    "PROMPTS/💬  PROMPT - CRIAR IADBA.txt",
    "PROMPTS/💬  PROMPT - PROMPTS DBA FORMATACAO E MANUAL.txt",
    "PROMPTS/💬  PROMPT - SITE BLOCOS DE TRABALHO ALTERNATIVO.txt",
    "PROMPTS/💬  PROMPT - SITE BLOCOS DE TRABALHO.txt",
})


def files() -> list[Path]:
    return sorted(
        (path for folder in CONTENT for path in (ROOT / folder).rglob("*")
         if path.is_file() and path.name != INDEX_NAME),
        key=lambda path: path.relative_to(ROOT).as_posix().casefold(),
    )


def classify(text: str) -> tuple[str, list[str]]:
    for level in ("D3", "D2", "D1", "D0"):
        hits = [name for name, regex in COMPILED[level] if regex.search(text)]
        if hits:
            return level, hits
    return "R", []


def build() -> str:
    rows = []
    for path in files():
        raw = path.read_bytes()
        relative = path.relative_to(ROOT).as_posix()
        level, hits = classify(raw.decode("utf-8", errors="replace"))
        if level == "R" and relative in REVIEWED_NON_COMMAND:
            level, hits = "N", ["revisado: sem comando executável"]
        rows.append((level, relative, hits))

    counts = Counter(level for level, _, _ in rows)
    lines = [
        "# Inventário de risco dos arquivos",
        "",
        "Triagem de todo o conteúdo público por gatilhos textuais, com revisão manual das referências sem comandos. O nível D0-D3 é o **maior gatilho textual encontrado no arquivo**, não uma autorização de execução nem uma revisão semântica completa. Comandos citados em explicações também podem elevar o nível. `N` identifica arquivos revisados sem comando executável. `R` indica arquivo novo ou sem gatilho, ainda pendente de revisão; **não significa risco zero**. Consulte [Comandos por risco operacional](COMANDOS-POR-RISCO.md) para critérios e controles.",
        "",
        f"Arquivos analisados: **{len(rows)}**. D3: **{counts['D3']}**; D2: **{counts['D2']}**; D1: **{counts['D1']}**; D0: **{counts['D0']}**; sem comando (`N`): **{counts['N']}**; revisão pendente (`R`): **{counts['R']}**.",
        "",
        "Antes de usar qualquer procedimento, confira ambiente, versão, escopo, backup e linha exata do comando. Em caso de múltiplos níveis no mesmo arquivo, prevalece o maior risco.",
        "",
    ]
    for level, title in (
        ("D3", "D3 — destruição ou perda potencial"),
        ("D2", "D2 — indisponibilidade ou recuperação"),
        ("D1", "D1 — alteração localizada"),
        ("D0", "D0 — observação identificada"),
        ("N", "N — referência sem comando executável"),
        ("R", "R — requer classificação manual"),
    ):
        lines.extend([f"## {title} ({counts[level]})", "", "| Arquivo | Gatilhos textuais |", "|---|---|"])
        for row_level, relative, hits in rows:
            if row_level != level:
                continue
            url = quote(relative, safe="/")
            label = relative.replace("|", "\\|")
            reason = ", ".join(hits) if hits else "nenhum gatilho identificado"
            lines.append(f"| [{label}](<{url}>) | {reason} |")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    content = build()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != content:
            print("INVENTARIO-RISCO.md is out of date. Run generate_risk_inventory.py.")
            return 1
        print("Risk inventory is up to date.")
        return 0
    OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
