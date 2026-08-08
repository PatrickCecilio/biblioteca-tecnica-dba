# Catálogo Canônico da Biblioteca Técnica DBA

Este é o único catálogo canônico de contagem da biblioteca pública.

## Critério de contagem

Entram na contagem todos os arquivos localizados, de forma recursiva, em:

- `01-Iniciante`
- `02-Intermediario`
- `03-Avancado`
- `APRENDIZADO`
- `PROMPTS`

São excluídos apenas os arquivos locais de índice gerado chamados `🗂️  ÍNDICE - 00 INDICE.md`.
Arquivos de governança, automação e documentação na raiz ou em `.github` não fazem parte do conteúdo contado.

## Geração automática

O catálogo é gerado a partir do filesystem pelo script `.github/scripts/generate_catalog.py`.
O workflow de validação falha quando o arquivo versionado diverge da árvore real.

## Contagem por pasta

| Pasta | Arquivos de conteúdo |
|---|---:|
| `01-Iniciante` | 146 |
| `02-Intermediario` | 231 |
| `03-Avancado` | 75 |
| `APRENDIZADO` | 5 |
| `PROMPTS` | 7 |
| **Total canônico** | **464** |

Arquivos de índice excluídos da contagem: **5**.
