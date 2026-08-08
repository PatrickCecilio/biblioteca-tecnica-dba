#!/usr/bin/env bash
#
# oracle_install_menu.sh – menu interativo para instalar e configurar o Oracle Database 23ai Free
#
# Este script implementa as melhorias sugeridas para as etapas de pré‑instalação
# e instalação do Oracle Database Free 23ai em Oracle Linux 9. O objetivo é
# permitir que o usuário selecione quais etapas executar, evitar duplicidade
# e proporcionar visibilidade do que está sendo feito.
#
# Pré‑requisitos:
#   – Deve ser executado como root.
#   – Necessário acesso a internet para instalar pacotes.
#   – O RPM do Oracle deve estar disponível em um diretório acessível
#     (por padrão, /u01/app/oracle ou /tmp). O script detecta automaticamente.
#
# O menu permite executar individualmente as seguintes ações:
#   1. Verificar requisitos de hardware e ambiente (memória, disco, swap).
#   2. Verificar FQDN em /etc/hosts e hostname.
#   3. Instalar o pacote oracle-database-preinstall-23ai.
#   4. Configurar variáveis de ambiente para o usuário oracle.
#   5. Ajustar as regras do firewall (abrir portas em vez de desativar firewalld).
#   6. Ajustar o modo do SELinux (opcional).
#   7. Localizar e instalar o RPM oracle-database-free-23ai.*.el9.x86_64.rpm.
#   8. Configurar o Oracle (modo interativo ou silencioso).
#   9. Ativar o serviço para iniciar no boot.
#   10. Sair.
#
# Cada ação define um estado interno para evitar reexecução desnecessária.
#
set -Eeuo pipefail

# Variáveis globais
ORACLE_BASE="/u01/app/oracle"
ORACLE_USER="oracle"
ORACLE_HOME="/opt/oracle/product/23ai/dbhomeFree"
BASH_PROFILE="/home/${ORACLE_USER}/.bash_profile"

# Arquivo de log. Todas as mensagens serão gravadas aqui além de exibidas na tela.
# É criado no diretório padrão de logs do sistema. Requer permissão de root para escrever.
LOG_FILE="/var/log/oracle_install_menu.log"

# Estados para evitar duplicidade
checked_system=false
checked_hosts=false
preinstall_done=false
env_set=false
firewall_done=false
selinux_done=false
rpm_installed=false
oracle_configured=false
service_enabled=false

### Funções auxiliares ###

log() {
  # Mostra mensagem com carimbo de hora
  local msg="$1"
  local timestamp="[$(date +%H:%M:%S)]"
  # Imprime na tela
  echo "$timestamp $msg"
  # Grava em log, se possível
  { echo "$timestamp $msg"; } >> "$LOG_FILE" 2>/dev/null || true
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "⚠️  Este script deve ser executado como root. Use sudo ou su -" >&2
    exit 1
  fi
  # Garante a criação do arquivo de log e define permissões
  if [[ ! -f "$LOG_FILE" ]]; then
    touch "$LOG_FILE" 2>/dev/null || true
    chmod 644 "$LOG_FILE" 2>/dev/null || true
  fi
}

check_system_requirements() {
  if $checked_system; then
    log "Checagem de requisitos já executada."; return
  fi
  log "Verificando memória, swap e espaço em disco..."
  total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  total_mem_mb=$((total_mem_kb/1024))
  swap_kb=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
  swap_mb=$((swap_kb/1024))
  # espaço livre em / (root) e ORACLE_BASE
  # Usa df com blocos de 1 byte para evitar separadores de milhares locais. Depois converte para MB
  local root_bytes=$(df --output=avail -B1 / | tail -1)
  # Remove quaisquer caracteres não numéricos (por exemplo, pontos de separador)
  root_bytes=${root_bytes//[!0-9]/}
  local root_free=$((root_bytes/1024/1024))
  local oracle_free=0
  if [[ -d "$ORACLE_BASE" ]]; then
    local oracle_bytes=$(df --output=avail -B1 "$ORACLE_BASE" 2>/dev/null | tail -1)
    oracle_bytes=${oracle_bytes//[!0-9]/}
    # se não vier nada, assume 0
    if [[ -n "$oracle_bytes" ]]; then
      oracle_free=$((oracle_bytes/1024/1024))
    fi
  fi
  log "Memória total: ${total_mem_mb} MB"
  log "Swap total: ${swap_mb} MB"
  log "Espaço livre na partição /: ${root_free} MB"
  if (( oracle_free > 0 )); then
    log "Espaço livre em $ORACLE_BASE: ${oracle_free} MB"
  fi
  # critérios mínimos (1 GB RAM, 2 GB swap, 10 GB disco)
  local ok=true
  if (( total_mem_mb < 1024 )); then
    log "⚠️  Memória total (${total_mem_mb} MB) é menor que o mínimo recomendado (1024 MB)"; ok=false
  fi
  if (( swap_mb < 2048 )); then
    log "⚠️  Swap total (${swap_mb} MB) é menor que o recomendado (2048 MB)"; ok=false
  fi
  if (( root_free < 10240 )) && (( oracle_free < 10240 )); then
    log "⚠️  Espaço livre em disco insuficiente (<10 GB) em / e em $ORACLE_BASE"; ok=false
  fi
  if $ok; then
    log "Requisitos de sistema atendidos."
  else
    log "⚠️  Requisitos de sistema não atendidos. Ajuste recursos antes de prosseguir."
  fi
  # Exibe versão do sistema operacional
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    log "Sistema operacional: ${NAME} ${VERSION} (ID=${ID}, VERSION_ID=${VERSION_ID})"
  fi
  checked_system=true
}

check_hosts_file() {
  if $checked_hosts; then
    log "Checagem de hostname já executada."; return
  fi
  log "Verificando configuração de hostname e /etc/hosts..."
  local current_host=$(hostname)
  log "Hostname atual: $current_host"
  # procura FQDN em /etc/hosts
  if grep -qE "\s${current_host}(\s|$)" /etc/hosts; then
    log "Entrada para $current_host encontrada em /etc/hosts."
  else
    log "⚠️  Nenhuma entrada para $current_host encontrada em /etc/hosts."
    log "Adicione uma linha com IP, nome totalmente qualificado e hostname. Exemplo:"
    log "  <HOST_OR_IP> myhost.dominio.local myhost"
  fi
  checked_hosts=true
}

install_preinstall_package() {
  if $preinstall_done; then
    log "Pacote preinstall já instalado."; return
  fi
  # Verifica se o pacote já está instalado
  if rpm -q oracle-database-preinstall-23ai &>/dev/null; then
    log "oracle-database-preinstall-23ai já está instalado."
  else
    log "Instalando pacote oracle-database-preinstall-23ai..."
    dnf install -y oracle-database-preinstall-23ai.x86_64
    log "Pacote preinstall instalado com sucesso."
  fi
  preinstall_done=true
}

configure_environment() {
  if $env_set; then
    log "Variáveis de ambiente já configuradas."; return
  fi
  log "Configurando variáveis de ambiente para o usuário $ORACLE_USER..."
  # garante que o diretório ORACLE_BASE exista
  mkdir -p "$ORACLE_BASE"
  chown -R ${ORACLE_USER}:oinstall "$ORACLE_BASE"
  chmod -R 775 "$ORACLE_BASE"
  # verifica se ORACLE_HOME existe (normalmente /opt/oracle/product/23ai/dbhomeFree)
  if [[ ! -d "$ORACLE_HOME" ]]; then
    log "⚠️  Diretório ORACLE_HOME não existe ainda: $ORACLE_HOME. Ele será criado após a instalação do RPM."
  fi
  if ! grep -q 'ORACLE_HOME' "$BASH_PROFILE"; then
    cat >> "$BASH_PROFILE" <<-EOF

# --- Início Oracle Free 23ai (menu script) ---
export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_HOME=${ORACLE_HOME}
export ORACLE_SID='<ORACLE_SID>'
export PATH=\$ORACLE_HOME/bin:\$PATH
# --- Fim Oracle Free 23ai (menu script) ---
EOF
    log "Variáveis de ambiente adicionadas em $BASH_PROFILE"
  else
    log "Entradas do Oracle já presentes em $BASH_PROFILE; nenhuma alteração realizada."
  fi
  env_set=true
}

configure_firewall() {
  if $firewall_done; then
    log "Firewall já configurado."; return
  fi
  log "Configurando firewalld para permitir portas do Oracle (1521 e 5500)..."
  # Verifica se o comando firewall-cmd está disponível
  if ! command -v firewall-cmd &>/dev/null; then
    log "⚠️  O utilitário firewall-cmd não foi encontrado. Parece que o pacote firewalld não está instalado. Instale firewalld manualmente ou configure as regras de firewall de outra forma."
    firewall_done=true
    return
  fi
  # Verifica se firewalld está ativo; se não, tenta habilitar
  if ! systemctl is-active --quiet firewalld; then
    log "firewalld não está ativo. Ativando e habilitando firewalld..."
    systemctl enable --now firewalld || true
  fi
  # Aplica as regras permanentes de portas
  firewall-cmd --permanent --add-port=1521/tcp || true
  firewall-cmd --permanent --add-port=5500/tcp || true
  firewall-cmd --reload || true
  log "Portas 1521/tcp e 5500/tcp liberadas no firewall."
  firewall_done=true
}

configure_selinux() {
  if $selinux_done; then
    log "SELinux já configurado."; return
  fi
  # Verifica se getenforce está disponível
  if ! command -v getenforce &>/dev/null; then
    log "Comando getenforce não encontrado. SELinux pode não estar instalado ou configurado. Nenhuma alteração feita."
    selinux_done=true
    return
  fi
  local selinux_mode
  selinux_mode=$(getenforce)
  log "Modo atual do SELinux: $selinux_mode"
  if [[ "$selinux_mode" == "Enforcing" ]]; then
    log "⚠️  SELinux está em modo enforcing. Recomenda-se mudar para permissive durante a instalação."
    read -p "Deseja alterar para permissive (y/n)? " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      setenforce 0
      # ajusta /etc/selinux/config se possível
      if [[ -f /etc/selinux/config ]]; then
        sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
      fi
      log "SELinux alterado para permissive."
    else
      log "Manteremos o SELinux em enforcing."
    fi
  else
    log "SELinux já está permissive ou disabled."
  fi
  selinux_done=true
}

install_oracle_rpm() {
  if $rpm_installed; then
    log "RPM do Oracle já instalado."; return
  fi
  log "Procurando RPM oracle-database-free-23ai-*.el9.x86_64.rpm..."
  local search_dirs=("$ORACLE_BASE" "/tmp" "/u01/app/oracle")
  local rpms_found=()
  for dir in "${search_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      while IFS= read -r -d '' file; do
        rpms_found+=("$file")
      done < <(find "$dir" -maxdepth 1 -type f -name "oracle-database-free-23ai-*.el9.x86_64.rpm" -print0 2>/dev/null)
    fi
  done
  if [[ ${#rpms_found[@]} -eq 0 ]]; then
    log "❌ Nenhum RPM oracle-database-free-23ai encontrado nas pastas pesquisadas."
    log "Baixe manualmente o pacote de  e copie para $ORACLE_BASE."
    return
  fi
  # escolhe o maior RPM (tamanho > 100MB)
  local best_rpm=""
  local best_size=0
  for rpm in "${rpms_found[@]}"; do
    local size=$(stat -c %s "$rpm")
    if (( size > best_size )); then
      best_size=$size
      best_rpm=$rpm
    fi
  done
  if (( best_size < 100*1024*1024 )); then
    log "❌ O RPM encontrado ($best_rpm) é muito pequeno ($best_size bytes). Verifique se está completo."
    return
  fi
  log "Instalando RPM: ${best_rpm} (tamanho: $((best_size/1024/1024)) MB)..."
  dnf install -y "$best_rpm"
  rpm_installed=true
  log "RPM do Oracle instalado com sucesso."
}

configure_oracle() {
  if $oracle_configured; then
    log "Oracle já configurado."; return
  fi
  # confere se script de configuração existe
  local cfg_script="/etc/init.d/oracle-free-23ai"
  if [[ ! -x "$cfg_script" ]]; then
    log "❌ Script de configuração $cfg_script não encontrado. Instale o RPM primeiro."
    return
  fi
  log "Escolha o modo de configuração do Oracle:"
  echo "  1) Interativo (solicita senha durante a execução)"
  echo "  2) Silencioso (defina a senha antes e não haverá prompts)"
  read -p "Opção [1/2]: " mode
  if [[ "$mode" == "2" ]]; then
    read -s -p "Informe a senha para as contas SYS, SYSTEM e PDBADMIN: " DB_PASSWORD
    echo
    export DB_PASSWORD
    # executa o script de configuração em modo silencioso
    log "Executando configuração silenciosa..."
    (echo "$DB_PASSWORD"; echo "$DB_PASSWORD") | $cfg_script configure
  else
    # modo interativo
    log "Executando configuração interativa..."
    $cfg_script configure
  fi
  oracle_configured=true
  log "Configuração do Oracle concluída."
}

enable_service() {
  if $service_enabled; then
    log "Serviço já habilitado."; return
  fi
  log "Habilitando serviço oracle-free-23ai para iniciar no boot..."
  systemctl enable --now oracle-free-23ai || true
  service_enabled=true
  log "Serviço habilitado."
}

### Menu principal ###

main_menu() {
  require_root
  while true; do
    echo
    echo "================== Menu de Instalação Oracle 23ai =================="
    echo "Selecione uma opção para executar a ação correspondente:"
    echo "  1) Verificar requisitos de sistema (RAM, swap, disco)"
    echo "  2) Verificar FQDN e /etc/hosts"
    echo "  3) Instalar pacote preinstall"
    echo "  4) Configurar variáveis de ambiente"
    echo "  5) Configurar firewall (liberar portas)"
    echo "  6) Configurar SELinux (permissive)"
    echo "  7) Instalar RPM do Oracle"
    echo "  8) Configurar Oracle (interativo ou silencioso)"
    echo "  9) Habilitar serviço no boot"
    echo "  0) Sair"
    echo "===================================================================="
    read -p "Opção: " opt
    case $opt in
      1) check_system_requirements ;;
      2) check_hosts_file ;;
      3) install_preinstall_package ;;
      4) configure_environment ;;
      5) configure_firewall ;;
      6) configure_selinux ;;
      7) install_oracle_rpm ;;
      8) configure_oracle ;;
      9) enable_service ;;
      0) log "Saindo..."; break ;;
      *) log "Opção inválida." ;;
    esac
  done
}

# Executar o menu se o script estiver sendo chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main_menu
fi
