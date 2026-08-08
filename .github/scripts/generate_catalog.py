from __future__ import annotations

import argparse
import difflib
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "CATALOGO.md"
CONTENT_ROOTS = (
    "01-Iniciante",
    "02-Intermediario",
    "03-Avancado",
    "APRENDIZADO",
    "PROMPTS",
)
GENERATED_INDEX_NAMES = {"🗂️  ÍNDICE - 00 INDICE.md"}


def count_content() -> tuple[dict[str, int], list[Path]]:
    counts: dict[str, int] = {}
    excluded: list[Path] = []

    for directory_name in CONTENT_ROOTS:
        directory = ROOT / directory_name
        if not directory.is_dir():
            raise FileNotFoundError(f"Pasta obrigatória ausente: {directory_name}")

        count = 0
        for path in sorted(directory.rglob("*")):
            if not path.is_file():
                continue
            if path.name in GENERATED_INDEX_NAMES:
                excluded.append(path.relative_to(ROOT))
                continue
            count += 1
        counts[directory_name] = count

    return counts, excluded


def render_catalog() -> str:
    counts, excluded = count_content()
    total = sum(counts.values())

    lines = [
        "# Catálogo Canônico da Biblioteca Técnica DBA",
        "",
        "Este é o único catálogo canônico de contagem da biblioteca pública.",
        "",
        "## Critério de contagem",
        "",
        "Entram na contagem todos os arquivos localizados, de forma recursiva, em:",
        "",
    ]
    lines.extend(f"- `{directory}`" for directory in CONTENT_ROOTS)
    lines.extend(
        [
            "",
            "São excluídos apenas os arquivos locais de índice gerado chamados "
            "`🗂️  ÍNDICE - 00 INDICE.md`.",
            "Arquivos de governança, automação e documentação na raiz ou em `.github` "
            "não fazem parte do conteúdo contado.",
            "",
            "## Geração automática",
            "",
            "O catálogo é gerado a partir do filesystem pelo script "
            "`.github/scripts/generate_catalog.py`.",
            "O workflow de validação falha quando o arquivo versionado diverge da árvore real.",
            "",
            "## Contagem por pasta",
            "",
            "| Pasta | Arquivos de conteúdo |",
            "|---|---:|",
        ]
    )
    lines.extend(f"| `{directory}` | {counts[directory]} |" for directory in CONTENT_ROOTS)
    lines.extend(
        [
            f"| **Total canônico** | **{total}** |",
            "",
            f"Arquivos de índice excluídos da contagem: **{len(excluded)}**.",
            "",
        ]
    )
    return "\n".join(lines)


def check_catalog(expected: str) -> int:
    current = CATALOG.read_text(encoding="utf-8") if CATALOG.exists() else ""
    if current == expected:
        print("CATALOGO.md está sincronizado com a árvore atual.")
        return 0

    print("CATALOGO.md está desatualizado. Execute:")
    print("python .github/scripts/generate_catalog.py")
    diff = "".join(
        difflib.unified_diff(
            current.splitlines(keepends=True),
            expected.splitlines(keepends=True),
            fromfile="CATALOGO.md (versionado)",
            tofile="CATALOGO.md (esperado)",
        )
    )
    output_encoding = sys.stdout.encoding or "utf-8"
    printable_diff = diff.encode(output_encoding, errors="backslashreplace").decode(
        output_encoding
    )
    print(printable_diff)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Gera o catálogo canônico da biblioteca.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Valida o catálogo sem modificar arquivos.",
    )
    args = parser.parse_args()

    expected = render_catalog()
    if args.check:
        return check_catalog(expected)

    CATALOG.write_text(expected, encoding="utf-8", newline="\n")
    print(f"CATALOGO.md gerado em {CATALOG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
