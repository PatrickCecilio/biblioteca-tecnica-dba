"""Summarize command candidates in the generated D3 inventory for editorial review."""

import argparse
from pathlib import Path
import re
from urllib.parse import unquote


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--end", type=int, default=1000)
    args = parser.parse_args()
    inventory = Path("INVENTARIO-RISCO.md").read_text(encoding="utf-8")
    section = inventory.split("## D3", 1)[1].split("## D2", 1)[0]
    rows = [line for line in section.splitlines() if line.startswith("| [")]
    pattern = re.compile(
        r"(?i)(?:\b(?:drop|truncate|delete|flashback|restore|resetlogs|mkfs|"
        r"cryptsetup|rm|prune|purge|kill|wipe|dd)\b|find .*-exec)"
    )
    for number, row in enumerate(rows, 1):
        if not args.start <= number <= args.end:
            continue
        path = Path(unquote(row.split("(<", 1)[1].split(">)", 1)[0]))
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        matches = [
            f"{index}: {line[:145]}"
            for index, line in enumerate(lines, 1)
            if pattern.search(line)
        ]
        print(f"{number}. {path} [{len(lines)} lines; {len(matches)} candidates]")
        for match in matches[:5]:
            print(f"  {match}")


if __name__ == "__main__":
    main()
