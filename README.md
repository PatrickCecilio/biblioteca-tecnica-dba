# Biblioteca Técnica DBA

Biblioteca pública de estudos e procedimentos de Oracle Database, SQL Server, Linux, Docker e PostgreSQL, organizada por nível de conhecimento.

## Organização

- `01-Iniciante`: fundamentos, instalação e primeiros comandos;
- `02-Intermediario`: administração, segurança, backup e diagnóstico;
- `03-Avancado`: alta disponibilidade, performance e automação;
- `APRENDIZADO`: materiais educacionais revisados;
- `PROMPTS`: modelos de trabalho e documentação.

O catálogo canônico, gerado automaticamente a partir da árvore real, está em [`CATALOGO.md`](CATALOGO.md).

## Comandos por risco operacional

O nível de conhecimento das pastas não representa o impacto de execução. Consulte [`COMANDOS-POR-RISCO.md`](COMANDOS-POR-RISCO.md) para classificar procedimentos de D0 (consulta) a D3 (destrutivo ou recuperação com perda potencial de dados). O índice aponta comandos críticos que hoje aparecem inclusive em `01-Iniciante`.

O [inventário atualizado](INVENTARIO-RISCO.md) aplica uma triagem textual reproduzível a todo o acervo. Ele registra o maior risco detectado por arquivo e separa os casos sem gatilho conhecido para revisão manual; a classificação contextual de cada comando continua necessária.

A [revisão D3 por impacto](REVISAO-D3-2026-11-19.md) registra a triagem dos 80
arquivos sinalizados no início do ciclo e os controles aplicados. Os
[laboratórios para comprovação](LABORATORIOS-PARA-COMPROVACAO.md) indicam as
execuções necessárias antes de apresentar resultados funcionais.

## Uso seguro

Os arquivos são referências educacionais. Antes de qualquer execução, identifique ambiente, instância, banco e container; confirme backup restaurável, cadeia de logs, RPO/RTO, janela e plano de retorno. Comandos D2 e D3 exigem revisão específica do procedimento. Nenhum script deve ser executado diretamente em produção.

## Autoria

A curadoria, organização e responsabilidade editorial são de Patrick Cecílio. Parte do processo de revisão e padronização recebeu assistência de inteligência artificial. Consulte [`AUTORIA-E-PROVENIENCIA.md`](AUTORIA-E-PROVENIENCIA.md).

## Autor

Patrick Cecílio — DBA Oracle

[Perfil no GitHub](https://github.com/PatrickCecilio)
