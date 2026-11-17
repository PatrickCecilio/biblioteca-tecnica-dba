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
        "risco D3 declarado": r"\bRISCO\s+D3\b",
    },
    "D2": {
        "restore ou recovery": r"\b(?:RESTORE|RECOVER)\s+(?:DATABASE|PLUGGABLE\s+DATABASE|DATAFILE|TABLESPACE)\b",
        "mudança em banco ou PDB": r"\bALTER\s+(?:DATABASE|PLUGGABLE\s+DATABASE|SYSTEM)\b",
        "parada ou restart": r"\b(?:SHUTDOWN|STARTUP)\b|\bsystemctl\s+(?:stop|restart)\b",
        "patch Oracle": r"\b(?:OPATCH|datapatch)\b",
        "criação de PDB": r"\bCREATE\s+PLUGGABLE\s+DATABASE\b",
        "acesso exclusivo SQL Server": r"\bSINGLE_USER\s+WITH\s+ROLLBACK\s+IMMEDIATE\b",
    },
    "D1": {
        "DDL ou permissão": r"\b(?:CREATE|ALTER|GRANT|REVOKE)\s+(?:USER|ROLE|TABLE|INDEX|VIEW|SCHEMA|PROFILE|TABLESPACE)\b",
        "mudança em dados": r"\b(?:INSERT\s+INTO|UPDATE\s+\S+)\b",
        "backup ou configuração": r"\b(?:BACKUP\s+DATABASE|BACKUP\s+LOG|CONFIGURE\s+\w+)\b",
        "serviço ou pacote": r"\bsystemctl\s+start\b|\b(?:yum|dnf|apt(?:-get)?)\s+install\b",
        "permissão de arquivo": r"\b(?:chmod|chown)\s+",
    },
    "D0": {
        "consulta SQL": r"\bSELECT\b|\bSHOW\s+(?:PDBS|PARAMETER|DATABASES)\b",
        "consulta RMAN": r"\b(?:LIST\s+BACKUP|REPORT\s+OBSOLETE)\b",
        "consulta de sistema": r"\b(?:df\s+-h|lsblk\b|free\s+-[hm]|uname\s+-|hostname\b)\b",
    },
}

COMPILED = {
    level: [(name, re.compile(pattern, re.IGNORECASE | re.MULTILINE)) for name, pattern in rules.items()]
    for level, rules in RULES.items()
}


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
        rows.append((level, relative, hits))

    counts = Counter(level for level, _, _ in rows)
    lines = [
        "# Inventário de risco dos arquivos",
        "",
        "Triagem automatizada de todo o conteúdo público. O nível é o **maior gatilho textual encontrado no arquivo**, não uma autorização de execução nem uma revisão semântica. Comandos citados em explicações também podem elevar o nível. `R` significa que a busca não identificou um comando conhecido; **não significa risco zero**. Consulte [Comandos por risco operacional](COMANDOS-POR-RISCO.md) para critérios e controles.",
        "",
        f"Arquivos analisados: **{len(rows)}**. D3: **{counts['D3']}**; D2: **{counts['D2']}**; D1: **{counts['D1']}**; D0: **{counts['D0']}**; revisão manual (`R`): **{counts['R']}**.",
        "",
        "Antes de usar qualquer procedimento, confira ambiente, versão, escopo, backup e linha exata do comando. Em caso de múltiplos níveis no mesmo arquivo, prevalece o maior risco.",
        "",
    ]
    for level, title in (
        ("D3", "D3 — destruição ou perda potencial"),
        ("D2", "D2 — indisponibilidade ou recuperação"),
        ("D1", "D1 — alteração localizada"),
        ("D0", "D0 — observação identificada"),
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
