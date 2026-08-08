#!/usr/bin/env bash

###############################################################################
# session_killer.sh
#
# Este script interativo monitora o acesso a uma pasta restrita e encerra
# imediatamente a sessão de qualquer usuário especificado na lista de penalizados
# caso ele tente acessar essa pasta. Ele utiliza o utilitário `inotifywait` para
# detectar eventos de acesso à pasta e o comando `lsof` para identificar
# quais processos estão utilizando arquivos dentro da pasta restrita. Se um
# usuário penalizado for detectado, todos os seus processos são finalizados
# usando `pkill -KILL -u <usuario>`, efetivamente encerrando a sessão.
#
# Recursos principais:
#  * Definição da pasta restrita a ser monitorada.
#  * Adição, remoção e listagem de usuários penalizados via menu interativo.
#  * Capacidade de iniciar o monitoramento em segundo plano, mantendo o script
#    rodando sem intervenção. O monitoramento só para quando o usuário
#    selecionar explicitamente a opção de parada no menu. Enquanto ativo,
#    o monitor encerra imediatamente a sessão de usuários penalizados que
#    acessarem a pasta restrita.
#
# Requisitos:
#  * Este script deve ser executado como root para poder monitorar
#    diretórios de forma recursiva e finalizar sessões de outros usuários.
#  * O pacote `inotify-tools` deve estar instalado (fornece o comando
#    `inotifywait`).
#  * O utilitário `lsof` deve estar instalado para identificar processos
#    com arquivos abertos.
#
# Aviso:
#  * Colocar o usuário `root` na lista de penalizados poderá derrubar o
#    próprio script e potencialmente todo o sistema, pois todos os processos
#    pertencentes ao root serão terminados. Use com extremo cuidado.
#
# Baseado na utilização de inotify para monitorar eventos de acesso
# (leitura, escrita, execução e atributos) em diretórios e subdiretórios,
# conforme descrito na documentação do inotifywait【27298042611810†L26-L32】.
###############################################################################

# Diretório onde armazenamos a configuração e a lista de usuários
CONFIG_DIR="/etc/session_killer"
BANNED_FILE="$CONFIG_DIR/banned_users.list"
RESTRICTED_FILE="$CONFIG_DIR/restricted_dir"

# Garante que a configuração exista
init_config() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
    fi
    if [[ ! -f "$BANNED_FILE" ]]; then
        touch "$BANNED_FILE"
    fi
}

# Verifica dependências necessárias
check_dependencies() {
    for cmd in inotifywait lsof pkill; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Erro: o comando '$cmd' não está instalado. Instale-o antes de prosseguir." >&2
            exit 1
        fi
    done
}

# Define a pasta restrita
set_restricted_dir() {
    while true; do
        read -r -p "Informe o caminho completo da pasta restrita: " path
        if [[ -z "$path" ]]; then
            echo "Caminho vazio. Tente novamente."
            continue
        fi
        if [[ ! -d "$path" ]]; then
            echo "Diretório não encontrado: $path"
            continue
        fi
        # Salva o caminho absoluto no arquivo
        path=$(readlink -f "$path")
        echo "$path" > "$RESTRICTED_FILE"
        echo "Pasta restrita definida como: $path"
        break
    done
}

# Lê a pasta restrita a partir da configuração
get_restricted_dir() {
    if [[ -f "$RESTRICTED_FILE" ]]; then
        cat "$RESTRICTED_FILE"
    else
        echo ""
    fi
}

# Adiciona usuário à lista de penalizados
add_user() {
    read -r -p "Informe o nome de usuário para adicionar: " user
    if [[ -z "$user" ]]; then
        echo "Usuário vazio."
        return
    fi
    if ! getent passwd "$user" >/dev/null; then
        echo "Usuário '$user' não existe no sistema."
        return
    fi
    if grep -qx "${user}" "$BANNED_FILE"; then
        echo "Usuário '$user' já está na lista de penalizados."
    else
        echo "$user" >> "$BANNED_FILE"
        echo "Usuário '$user' adicionado com sucesso."
    fi
}

# Remove usuário da lista
remove_user() {
    read -r -p "Informe o nome de usuário para remover: " user
    if grep -qx "${user}" "$BANNED_FILE"; then
        # Remove o usuário da lista
        sed -i "\|^${user}$|d" "$BANNED_FILE"
        echo "Usuário '$user' removido da lista."
    else
        echo "Usuário '$user' não está na lista."
    fi
}

# Lista usuários penalizados
list_users() {
    if [[ ! -s "$BANNED_FILE" ]]; then
        echo "Nenhum usuário penalizado definido."
    else
        echo "Usuários penalizados:"
        cat "$BANNED_FILE"
    fi
}


# Arquivo que armazena o PID do monitor de fundo
MONITOR_PID_FILE="/run/session_killer_monitor.pid"

# Loop interno de monitoramento (utilizado pelo processo em segundo plano)
monitor_loop() {
    local restricted="$1"
    local banned_file="$2"
    #
    # Loop infinito de monitoramento.  Em vez de observar todos os tipos de
    # eventos (open, access, modify), limitamos explicitamente aos eventos
    # "open". Conforme a documentação do inotifywait【27298042611810†L260-L272】, o
    # evento "open" ocorre quando um arquivo dentro do diretório monitorado
    # é aberto.  Evitar eventos "access" e "modify" reduz falsos positivos
    # que poderiam ocorrer quando a pasta é apenas consultada (por exemplo
    # por scripts de login) sem de fato abrir um arquivo para leitura ou
    # escrita.  Assim, um usuário só será penalizado se realmente abrir
    # algum arquivo dentro do diretório restrito.
    while true; do
        # Aguarda o próximo evento "open" em qualquer arquivo/diretório
        # dentro da hierarquia restrita.  A opção --quiet suprime a
        # saída; event-format/timefmt vazios evitam saída de dados.
        inotifywait -r -e open "$restricted" --quiet --event-format '' --timefmt '' 2>/dev/null
        # Após detectar um evento "open", percorre a lista de usuários
        # penalizados para verificar se algum deles está com arquivos abertos
        # dentro da pasta restrita.  Essa verificação adicional impede
        # penalizações indevidas quando o evento foi originado por outro
        # usuário.
        while IFS= read -r banned_user; do
            # Ignora linhas vazias
            [[ -z "$banned_user" ]] && continue
            # Procura processos do usuário penalizado que tenham algum
            # descritor aberto no diretório restrito.  O uso de lsof com
            # +D lista recursivamente arquivos dentro do diretório【27298042611810†L260-L272】.
            # A opção -t devolve apenas os PIDs encontrados.  Se houver pelo
            # menos um PID, significa que o usuário acessou o conteúdo da
            # pasta e deve ser penalizado.
            pids=$(lsof +D "$restricted" -u "$banned_user" -t 2>/dev/null | sort -u)
            if [[ -n "$pids" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuário '$banned_user' acessou a pasta restrita '$restricted'. Finalizando sua sessão..." >> /var/log/session_killer.log
                pkill -KILL -u "$banned_user"
            fi
        done < "$banned_file"
    done
}

# Inicia o monitoramento em segundo plano
start_monitor_background() {
    # Verifica se já há monitor em execução
    if [[ -f "$MONITOR_PID_FILE" ]]; then
        local existing_pid
        existing_pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$existing_pid" 2>/dev/null; then
            echo "Um monitor já está em execução (PID $existing_pid). Pare-o antes de iniciar outro."
            return
        else
            # PID inválido, remove o arquivo
            rm -f "$MONITOR_PID_FILE"
        fi
    fi
    local restricted
    restricted=$(get_restricted_dir)
    if [[ -z "$restricted" ]]; then
        echo "Pasta restrita não definida. Utilize a opção apropriada no menu para definí-la."
        return
    fi
    if [[ ! -d "$restricted" ]]; then
        echo "Pasta restrita '$restricted' não existe ou não é um diretório."
        return
    fi
    echo "Iniciando monitoramento em segundo plano para a pasta '$restricted'..."
    # Inicia o loop de monitoramento em segundo plano
    (
        # copia variáveis locais para subshell
        monitor_loop "$restricted" "$BANNED_FILE"
    ) &
    local pid=$!
    echo "$pid" > "$MONITOR_PID_FILE"
    echo "Monitor iniciado. PID: $pid"
}

# Para o monitoramento em segundo plano
stop_monitor_background() {
    if [[ -f "$MONITOR_PID_FILE" ]]; then
        local pid
        pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$MONITOR_PID_FILE"
            echo "Monitor (PID $pid) parado."
        else
            rm -f "$MONITOR_PID_FILE"
            echo "Arquivo de PID encontrado, mas o processo não está em execução. Limpando estado."
        fi
    else
        echo "Nenhum monitor em execução."
    fi
}

# Exibe menu de opções
show_menu() {
    echo "\n=== Menu ==="
    echo "1) Definir/alterar pasta restrita"
    echo "2) Adicionar usuário penalizado"
    echo "3) Remover usuário penalizado"
    echo "4) Listar usuários penalizados"
    echo "5) Iniciar monitoramento em segundo plano"
    echo "6) Parar monitoramento"
    echo "7) Sair"
    echo -n "Escolha uma opção: "
}

# Programa principal
main() {
    # Verifica se é root
    if [[ $EUID -ne 0 ]]; then
        echo "Este script deve ser executado como root. Saindo..." >&2
        exit 1
    fi
    init_config
    check_dependencies
    # Instala um trap para garantir que qualquer monitor em segundo plano seja
    # encerrado apropriadamente quando o script receber um sinal de término
    # (por exemplo, se o usuário pressionar Ctrl+C).  Isso impede que o
    # monitor continue rodando após a saída do menu e cause desligamento
    # inesperado de sessões de usuários.
    trap 'stop_monitor_background; exit 0' INT TERM

    while true; do
        show_menu
        read -r choice
        case "$choice" in
            1)
                set_restricted_dir
                ;;
            2)
                add_user
                ;;
            3)
                remove_user
                ;;
            4)
                list_users
                ;;
            5)
                start_monitor_background
                ;;
            6)
                stop_monitor_background
                ;;
            7)
                echo "Saindo..."
                # Encerra o monitor de fundo antes de sair, caso esteja ativo
                stop_monitor_background
                exit 0
                ;;
            *)
                echo "Opção inválida. Tente novamente."
                ;;
        esac
    done
}

main "$@"
