from __future__ import annotations

import hashlib
import os
import re
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SKIP = {".git"}
TEXT = {".sql", ".txt", ".md", ".sh", ".ps1", ".py", ".ini", ".xml", ".yml", ".yaml", ".html"}
FORBIDDEN = re.compile(
    r"(?i)(BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY|AKIA[0-9A-Z]{16}|"
    r"Authorization:\s*Bearer\s+|DarlingData|Erik Darling|Brent Ozar|"
    r"First Responder|DBA[ -]Toolbox|Ola Hallengren|Paul Randal|"
    r"sp_Blitz|sp_Quickie|sp_WhoIsActive)"
)


def files() -> list[Path]:
    return [p for p in ROOT.rglob("*") if p.is_file() and not any(part in SKIP for part in p.parts)]


def main() -> int:
    errors: list[str] = []
    seen: dict[str, Path] = {}
    for path in files():
        relative = path.relative_to(ROOT)
        if path.stat().st_size == 0:
            errors.append(f"arquivo vazio: {relative}")
        if len(str(relative)) > 200:
            errors.append(f"caminho longo: {relative}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest in seen:
            errors.append(f"duplicata: {relative} == {seen[digest].relative_to(ROOT)}")
        else:
            seen[digest] = path
        if (
            os.getenv("STRICT_PUBLIC") == "1"
            and path.suffix.lower() in TEXT
            and path.resolve() != Path(__file__).resolve()
        ):
            try:
                text = path.read_text(encoding="utf-8-sig")
            except UnicodeError:
                errors.append(f"texto sem UTF-8: {relative}")
            else:
                if FORBIDDEN.search(text):
                    errors.append(f"marcador proibido: {relative}")
        if path.suffix.lower() in {".zip", ".docx", ".pptx", ".xlsx"}:
            try:
                with zipfile.ZipFile(path) as archive:
                    bad = archive.testzip()
                    if bad:
                        errors.append(f"arquivo compactado inválido: {relative}: {bad}")
            except zipfile.BadZipFile:
                errors.append(f"arquivo compactado corrompido: {relative}")
    if errors:
        print("\n".join(errors))
        return 1
    print(f"Validação concluída: {len(files())} arquivos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
