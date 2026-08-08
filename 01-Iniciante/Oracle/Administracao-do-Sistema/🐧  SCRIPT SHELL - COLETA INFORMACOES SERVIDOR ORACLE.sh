#!/usr/bin/env bash
#
# oracle_server_info_final.sh – coleta informações sobre bancos de dados Oracle
# instalados localmente e do sistema operacional.
#
# Este script detecta automaticamente as instâncias do Oracle em execução no
# servidor (identificando processos *pmon*), permite selecionar uma ou várias
# instâncias e, em seguida, coleta informações sobre tamanho do banco, versão
# do Oracle, tamanho das tablespaces e informações de hardware/OS. Ele usa
# `nproc`, `free` e `df` para obter dados do sistema【108139131318936†L15-L25】【661536711664076†L22-L24】【867722277239968†L23-L28】, e
# consulta dicionários Oracle para calcular o tamanho do banco de dados e
# tablespaces conforme documentado【143072264583368†L322-L336】【748033480106900†L38-L46】.
#
# Diferentemente das versões anteriores, este script tenta derivar o
# ORACLE_HOME diretamente a partir do ambiente da instância PMON. Ele lê
# `/proc/<pid>/environ` para recuperar ORACLE_HOME, ORACLE_BASE e ORACLE_SID
# e ajusta o PATH de modo que o `sqlplus` possa ser encontrado, mesmo que
# `oraenv` não esteja disponível ou o arquivo oratab não contenha a
# instância.
#
# É necessário executar como usuário com permissões para ler o ambiente
# do processo PMON (geralmente root ou o próprio usuário oracle).

set -euo pipefail

### Funções auxiliares ###

# Exibe informações básicas do sistema operacional
display_separator() {
  printf '\n'
}
function show_os_info() {
  echo "==== Informações do Sistema Operacional ===="
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "Sistema: ${PRETTY_NAME:-$NAME $VERSION}"
  else
    echo "Sistema: $(uname -s) $(uname -r)"
  fi
  if command -v nproc >/dev/null 2>&1; then
    echo "CPUs disponíveis: $(nproc)"
  else
    echo "CPUs disponíveis: comando nproc não encontrado"
  fi
  if command -v free >/dev/null 2>&1; then
    mem_kb=$(free -k | awk '/^Mem:/ {print $2}')
    mem_gb=$(awk -v kb="$mem_kb" 'BEGIN {printf "%.2f", kb/1024/1024}')
    echo "Memória total: ${mem_gb} GiB"
  else
    echo "Memória total: comando free não encontrado"
  fi
  if command -v df >/dev/null 2>&1; then
    disk_total=$(df -BG --total 2>/dev/null | awk '/^total/ {print $2}')
    disk_used=$(df -BG --total 2>/dev/null | awk '/^total/ {print $3}')
    disk_avail=$(df -BG --total 2>/dev/null | awk '/^total/ {print $4}')
    echo "Disco total: ${disk_total:-N/A}"
    echo "Disco usado: ${disk_used:-N/A}"
    echo "Disco livre: ${disk_avail:-N/A}"
  else
    echo "Disco total: comando df não encontrado"
  fi
  echo
}

# Executa uma consulta SQL via sqlplus no ambiente atual
# Usa sqlplus via PATH; se desejado, defina SQLPLUS_CMD antes de chamar
function exec_sql() {
  local query="$1"
  local tmpfile
  tmpfile=$(mktemp)
  {
    echo "set pages 999 lines 400 feed off head on trimspool on tab off";
    echo "$query";
    echo "exit";
  } > "$tmpfile"
  # Determine qual comando de sqlplus usar: SQLPLUS_CMD override ou fallback no PATH
  local cmd=${SQLPLUS_CMD:-sqlplus}
  "$cmd" -S "/ as sysdba" @"$tmpfile"
  rm -f "$tmpfile"
}

# Deriva ORACLE_HOME e outras variáveis a partir do ambiente do processo PMON
# Retorna 0 se conseguiu extrair ORACLE_HOME, 1 caso contrário
function set_env_from_pmon() {
  local sid="$1"
  # Procura PID do pmon correspondente ao SID; usa pgrep com padrões exatos
  local pid=""
  pid=$(pgrep -o -f "(^ora_pmon_|^db_pmon_)${sid}$" || true)
  if [[ -z "$pid" ]]; then
    return 1
  fi
  local env_file="/proc/$pid/environ"
  if [[ ! -r "$env_file" ]]; then
    return 1
  fi
  # Lê ORACLE_HOME, ORACLE_BASE e ORACLE_SID da lista de variáveis de ambiente
  local env_list
  env_list=$(tr '\0' '\n' < "$env_file" | grep -E '^(ORACLE_HOME|ORACLE_BASE|ORACLE_SID)=' || true)
  if [[ -z "$env_list" ]]; then
    return 1
  fi
  # Exporta as variáveis extraídas. shellcheck disable SC2046 (palavras divididas intencionalmente)
  export $(echo "$env_list")
  # Atualiza PATH se ORACLE_HOME existir
  if [[ -n "${ORACLE_HOME:-}" ]]; then
    case ":$PATH:" in
      *":${ORACLE_HOME}/bin:"*) ;; # já existe
      *) PATH="${ORACLE_HOME}/bin:${PATH}" ;;
    esac
    export PATH
  fi
  # Atualiza LD_LIBRARY_PATH
  if [[ -n "${ORACLE_HOME:-}" ]]; then
    if [[ -z "${LD_LIBRARY_PATH:-}" ]]; then
      LD_LIBRARY_PATH="${ORACLE_HOME}/lib"
    else
      case ":$LD_LIBRARY_PATH:" in
        *":${ORACLE_HOME}/lib:"*) ;; # já presente
        *) LD_LIBRARY_PATH="${ORACLE_HOME}/lib:${LD_LIBRARY_PATH}" ;;
      esac
    fi
    export LD_LIBRARY_PATH
  fi
  return 0
}

# Coleta informações para uma instância específica
function show_info_for_sid() {
  local sid="$1"
  echo "==== Informações para a instância ${sid} ===="
  # Guarda ORACLE_SID original
  local orig_sid=${ORACLE_SID:-}
  # Define ORACLE_SID para a instância selecionada
  export ORACLE_SID="$sid"
  # Primeiro, tenta configurar o ambiente lendo o PMON
  local env_ok=1
  if set_env_from_pmon "$sid"; then
    env_ok=0
  fi
  # Em seguida, tenta oraenv se sqlplus ainda não está disponível
  if ! command -v sqlplus >/dev/null 2>&1; then
    # Configura ORAENV para não perguntar e tenta oraenv do PATH
    export ORAENV_ASK=NO
    if command -v oraenv >/dev/null 2>&1; then
      . oraenv >/dev/null 2>&1 || true
    else
      # Procura oraenv em locais comuns
      for candidate in /usr/local/bin/oraenv /usr/bin/oraenv ${ORACLE_HOME:-}/bin/oraenv; do
        if [[ -x "$candidate" ]]; then
          . "$candidate" >/dev/null 2>&1 || true
          break
        fi
      done
    fi
  fi
  # Se ainda assim sqlplus não estiver no PATH, tenta obter ORACLE_HOME de /etc/oratab
  if ! command -v sqlplus >/dev/null 2>&1; then
    local oratab_file=""
    for f in /etc/oratab /var/opt/oracle/oratab; do
      if [[ -f "$f" ]]; then oratab_file="$f"; break; fi
    done
    if [[ -n "$oratab_file" ]]; then
      local line
      line=$(grep -E "^${sid}:" "$oratab_file" || true)
      if [[ -n "$line" ]]; then
        local oh
        oh=$(echo "$line" | awk -F: '{print $2}')
        if [[ -n "$oh" ]]; then
          export ORACLE_HOME="$oh"
          PATH="${ORACLE_HOME}/bin:${PATH}"
          export PATH
          LD_LIBRARY_PATH="${ORACLE_HOME}/lib:${LD_LIBRARY_PATH:-}"
          export LD_LIBRARY_PATH
        fi
      fi
    fi
  fi
  # Ainda não encontrou sqlplus? tente usar ORACLE_HOME/bin/sqlplus diretamente
  if ! command -v sqlplus >/dev/null 2>&1; then
    if [[ -x "${ORACLE_HOME:-}/bin/sqlplus" ]]; then
      SQLPLUS_CMD="${ORACLE_HOME}/bin/sqlplus"
    else
      echo "⚠️  sqlplus não encontrado para a instância ${sid}. Verifique a instalação do Oracle ou ajuste as variáveis ORACLE_HOME/ORAENV."
      # Restaura ORACLE_SID original e retorna
      export ORACLE_SID="$orig_sid"
      return
    fi
  fi
  # Versão do Oracle
  echo "Versão do Oracle:"
  # Use v\$version to avoid shell variable expansion when set -u is enabled
  exec_sql "SELECT banner FROM v\$version WHERE banner LIKE 'Oracle%';" || true
  echo
  # Tamanho total, usado e livre do banco (em GB)
  echo "Tamanho total do banco / espaço usado / espaço livre (em GB):"
  # Esta consulta calcula o tamanho total da base usando dba_data_files e
  # o espaço livre usando dba_free_space. O uso é calculado pela diferença.
  exec_sql "SELECT round(df.total_gb, 2) AS \"TOTAL_GB\",
                 round(df.total_gb - fs.free_gb, 2) AS \"USED_GB\",
                 round(fs.free_gb, 2) AS \"FREE_GB\"
          FROM   (SELECT SUM(bytes)/1024/1024/1024 AS total_gb FROM dba_data_files) df,
                 (SELECT SUM(bytes)/1024/1024/1024 AS free_gb FROM dba_free_space) fs;" || true
  echo
  # Tamanho das tablespaces
  echo "Tamanhos das tablespaces (MB):"
  exec_sql "SELECT tablespace_name, round(sum(bytes) / 1024 / 1024, 2) AS size_mb
            FROM   dba_data_files
            GROUP  BY tablespace_name
            ORDER  BY tablespace_name;" || true
  echo
  # Restaura o ORACLE_SID original
  export ORACLE_SID="$orig_sid"
}

# Detecta instâncias de banco de dados Oracle em execução
function detect_instances() {
  local instances=()
  # A coluna 'comm' contém apenas o nome do executável. Precisamos de 'args' para obter nomes completos.
  # Usamos ps -eo args para pegar a linha completa e extrair SIDs.
  while IFS= read -r line; do
    # Caso a linha contenha ora_pmon_<SID> ou db_pmon_<SID>
    if [[ "$line" =~ (ora|db)_pmon_([A-Za-z0-9_]+) ]]; then
      local sid="${BASH_REMATCH[2]}"
      [[ -n "$sid" ]] && instances+=("$sid")
    fi
  done < <(ps -eo args)
  if [[ ${#instances[@]} -gt 0 ]]; then
    printf '%s\n' "${instances[@]}" | sort -u
  fi
}

# Menu principal interativo
function main() {
  # Detecta instâncias ativas
  mapfile -t insts < <(detect_instances)
  echo ""
  echo "==== Script de Levantamento de Informações Oracle ===="
  # Primeiro, imprime informações do sistema operacional
  show_os_info
  # Se não encontrou instâncias
  if [[ ${#insts[@]} -eq 0 ]]; then
    echo "Nenhuma instância Oracle em execução foi detectada via processos PMON."
    echo "Se desejar, você pode executar consultas manualmente definindo ORACLE_HOME e sqlplus."
    return
  fi
  # Caso exista ao menos uma instância, apresenta opções
  echo "Instâncias Oracle detectadas:"
  local i=1
  for sid in "${insts[@]}"; do
    echo "  $i) ${sid}"
    i=$((i+1))
  done
  echo "  a) Todas"
  echo "  0) Sair"
  read -r -p "Escolha a instância para coletar informações: " choice
  if [[ "$choice" == "0" ]]; then
    echo "Saindo..."
    return
  fi
  if [[ "$choice" =~ ^[Aa]$ ]]; then
    # Todas as instâncias
    for sid in "${insts[@]}"; do
      show_info_for_sid "$sid"
    done
  elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#insts[@]} )); then
    local selected="${insts[$((choice-1))]}"
    show_info_for_sid "$selected"
  else
    echo "Opção inválida."
  fi
  echo "Coleta finalizada."
}

main "$@"
