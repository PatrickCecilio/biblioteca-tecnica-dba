# ATENÇÃO: material de referência. Revise o ambiente e os parâmetros antes de executar comandos destrutivos.

#!/bin/bash

##############################################################################
#
#  encrypt_folder_linux.sh
#
#  Este script interativo cria um contêiner LUKS para criptografar
#  uma pasta no Linux. Ele cria um arquivo de imagem, configura a
#  criptografia LUKS com cryptsetup, formata o volume com sistema de arquivos
#  (padrão ext4), copia o conteúdo da pasta original para o volume
#  criptografado e monta o contêiner no caminho original da pasta. O
#  processo mantém a usabilidade dos dados: após montado, a pasta
#  criptografada se comporta como uma pasta comum.
#
#  Requisitos:
#    - cryptsetup (com suporte LUKS) instalado e configurado.
#    - utilitários básicos: dd ou fallocate, mkfs, mount, rsync.
#    - Permissões de root ou sudo para criar e montar dispositivos de loop.
#
#  Passos principais:
#    1. Solicita o caminho da pasta a ser criptografada e verifica se existe.
#    2. Solicita o caminho e tamanho do arquivo de contêiner.
#    3. Cria o contêiner (imagem de disco) com o tamanho escolhido.
#    4. Configura a criptografia LUKS com uma senha fornecida.
#    5. Abre o contêiner, formata em ext4 e monta temporariamente.
#    6. Copia todos os arquivos da pasta original para o contêiner.
#    7. Renomeia a pasta original para backup, cria diretório vazio e monta
#       o contêiner no caminho original.
#    8. Orienta o usuário sobre como desmontar e fechar o contêiner.
#
#  Nota: Este script evita sobrescrever arquivos e oferece um backup da
#        pasta original. Após confirmar que tudo está correto, você
#        poderá remover o backup manualmente.
#
#  Autor: ChatGPT
#  Data: 2025-08-15
##############################################################################

set -e

# Verifica se o script está executando como root
if [[ $EUID -ne 0 ]]; then
    echo "Este script deve ser executado com privilégios de root. Utilize sudo." >&2
    exit 1
fi

echo "--- Script de criptografia de pasta com LUKS ---"

# Função para ler entrada não vazia
read_nonempty() {
    local prompt="$1"
    local var
    while true; do
        read -r -p "$prompt" var
        if [[ -n "$var" ]]; then
            echo "$var"
            return
        else
            echo "Entrada vazia. Tente novamente." >&2
        fi
    done
}

# 1. Solicita pasta a criptografar
while true; do
    DIR=$(read_nonempty "Informe o caminho absoluto da pasta que deseja criptografar: ")
    if [[ -d "$DIR" ]]; then
        # Remove barra final, se houver
        DIR="$(readlink -f "$DIR")"
        break
    else
        echo "Caminho inválido ou não é um diretório." >&2
    fi
done
echo "Pasta alvo: $DIR"

# 2. Solicita o caminho para o contêiner
while true; do
    CONTAINER=$(read_nonempty "Informe o caminho absoluto para o arquivo do contêiner (ex.: /home/usuario/seguro.img): ")
    # Expande caminho e obtém diretório
    CONTAINER=$(readlink -f "$CONTAINER")
    CONTAINER_DIR=$(dirname "$CONTAINER")
    if [[ ! -d "$CONTAINER_DIR" ]]; then
        echo "Diretório onde salvar o contêiner não existe." >&2
        continue
    fi
    # Evita salvar contêiner dentro da pasta a ser criptografada
    if [[ "$CONTAINER" == "$DIR"* ]]; then
        echo "Não salve o contêiner dentro da pasta a ser criptografada. Escolha outro local." >&2
        continue
    fi
    break
done

# 3. Calcula o tamanho da pasta e sugere tamanho do contêiner
echo "Calculando tamanho da pasta..." >&2
DIR_SIZE_BYTES=$(du -sb "$DIR" | cut -f1)
DIR_SIZE_MB=$(( (DIR_SIZE_BYTES + 1024*1024 - 1) / (1024*1024) ))
DEFAULT_SIZE_MB=$(( DIR_SIZE_MB * 12 / 10 )) # 20% extra
DEFAULT_SIZE_GB=$(( (DEFAULT_SIZE_MB + 1023) / 1024 ))
echo "Tamanho atual da pasta: $(awk "BEGIN{print ${DIR_SIZE_MB}/1024;}") GB"
echo "Tamanho sugerido para o contêiner (20% extra): $DEFAULT_SIZE_GB GB"

# 4. Solicita tamanho do contêiner
while true; do
    read -r -p "Defina o tamanho do contêiner em gigabytes (pressione Enter para aceitar $DEFAULT_SIZE_GB): " SIZE_GB
    if [[ -z "$SIZE_GB" ]]; then
        SIZE_GB=$DEFAULT_SIZE_GB
    fi
    # Verifica número positivo inteiro
    if [[ "$SIZE_GB" =~ ^[0-9]+$ ]] && [[ "$SIZE_GB" -gt 0 ]]; then
        break
    else
        echo "Valor inválido. Informe um número inteiro maior que zero." >&2
    fi
done
echo "Tamanho do contêiner definido: ${SIZE_GB} GB"

# 5. Cria contêiner com dd (imagem vazia)
echo "Criando arquivo de contêiner em $CONTAINER..."
dd if=/dev/zero of="$CONTAINER" bs=1M count=$((SIZE_GB * 1024)) status=progress
echo "Arquivo de contêiner criado."

# 6. Configura criptografia LUKS
while true; do
    read -s -p "Digite uma senha forte para a criptografia LUKS: " PASS1
    echo
    read -s -p "Confirme a senha: " PASS2
    echo
    if [[ "$PASS1" != "$PASS2" ]]; then
        echo "As senhas não coincidem. Tente novamente." >&2
    elif [[ ${#PASS1} -lt 8 ]]; then
        echo "Senha muito curta. Use pelo menos 8 caracteres." >&2
    else
        break
    fi
done

echo "Configurando LUKS no contêiner..."
echo -n "$PASS1" | cryptsetup luksFormat "$CONTAINER" -q --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha512 --pbkdf argon2id --iter-time 2000 --batch-mode
echo "Contêiner LUKS formatado."

# 7. Abre o contêiner (define nome mapeado)
MAPPER_NAME="$(basename "$CONTAINER" | sed 's/[^a-zA-Z0-9]/_/g')_map"
echo -n "$PASS1" | cryptsetup open "$CONTAINER" "$MAPPER_NAME" -d - --type luks2
DEVICE="/dev/mapper/$MAPPER_NAME"
echo "Contêiner aberto em $DEVICE"

# 8. Formata o mapeamento como ext4
echo "Formatando o volume criptografado com ext4..."
mkfs.ext4 -q "$DEVICE"

# 9. Monta temporariamente
TEMP_MOUNT=$(mktemp -d)
mount "$DEVICE" "$TEMP_MOUNT"
echo "Montado temporariamente em $TEMP_MOUNT"

# 10. Copia dados para o volume criptografado
echo "Copiando arquivos da pasta original para o contêiner..."
rsync -aHAX --info=progress2 "$DIR/" "$TEMP_MOUNT/"
echo "Cópia concluída."

# 11. Desmonta temporário e fecha
umount "$TEMP_MOUNT"
rmdir "$TEMP_MOUNT"
cryptsetup close "$MAPPER_NAME"
echo "Volume temporário desmontado."

# 12. Renomeia pasta original e prepara montagem final
BACKUP_DIR="${DIR}_backup_original"
if [[ -e "$BACKUP_DIR" ]]; then
    echo "Já existe um backup em $BACKUP_DIR. Mova ou renomeie antes de continuar." >&2
    exit 1
fi
echo "Renomeando pasta original para $BACKUP_DIR"
mv "$DIR" "$BACKUP_DIR"
mkdir -p "$DIR"

# 13. Reabre o contêiner e monta na pasta
echo -n "$PASS1" | cryptsetup open "$CONTAINER" "$MAPPER_NAME" -d - --type luks2
mount "$DEVICE" "$DIR"
echo "Volume criptografado montado em $DIR"

cat <<EOF

=== Concluído! ===
Sua pasta "$DIR" agora está protegida por criptografia LUKS. O conteúdo original
foi preservado em "$BACKUP_DIR". Verifique se todos os arquivos estão intactos.
Após a verificação, você pode remover o backup manualmente para liberar espaço.

Para desmontar e fechar a pasta criptografada:
  sudo umount "$DIR"
  sudo cryptsetup close "$MAPPER_NAME"

Para montar novamente:
  sudo cryptsetup open "$CONTAINER" "$MAPPER_NAME"
  sudo mount "/dev/mapper/$MAPPER_NAME" "$DIR"

Lembre-se de manter sua senha em local seguro – perder a senha resultará
na perda permanente dos dados.
EOF

exit 0
