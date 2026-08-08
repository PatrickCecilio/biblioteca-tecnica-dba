<##>
<#
    🪟  SCRIPT POWERSHELL - ENCRYPT FOLDER WINDOWS.ps1

    Este script interativo cria um contêiner criptografado usando BitLocker
    para proteger uma pasta específica no Windows. Ele funciona criando
    um arquivo VHDX, formatando‑o com NTFS, habilitando o BitLocker no
    volume virtual e montando-o no caminho da pasta original. O script
    copia todo o conteúdo da pasta para o novo volume criptografado e
    mantém a estrutura operacional. É necessário executar este script
    com privilégios de administrador.

    Passos principais:
      1. Pergunta ao usuário a pasta a ser criptografada.
      2. Pergunta onde salvar o arquivo VHDX e seu tamanho.
      3. Cria e monta o VHDX.
      4. Inicializa, particiona e formata o volume virtual em NTFS.
      5. Solicita uma senha de BitLocker e habilita a criptografia.
      6. Copia os dados da pasta original para o volume criptografado.
      7. Monta o volume criptografado no caminho da pasta original e renomeia
         a pasta original como backup.
      8. Oferece remover o backup se tudo ocorrer bem.

    Observações:
      - O script calcula automaticamente o tamanho mínimo necessário do contêiner
        somando o tamanho da pasta e adicionando 20%. O usuário pode optar
        por fornecer outro valor manualmente.
      - Após a execução, para acessar os dados o contêiner deve estar
        montado e desbloqueado. Para desmontar use o Gerenciador de Disco
        ou os cmdlets Dismount-VHD e Lock-BitLocker.
      - Guarde a senha e a chave de recuperação do BitLocker em um local seguro.

    Autor: ChatGPT
    Data: 2025-08-15
#>

param()

# Verifica se o script está sendo executado como administrador
function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Host "Este script deve ser executado com privilégios de administrador. Abra o PowerShell como administrador e tente novamente." -ForegroundColor Red
    exit 1
}

Write-Host "--- Script de criptografia de pasta com BitLocker ---" -ForegroundColor Cyan

# Solicita o caminho da pasta a criptografar
do {
    $folderPath = Read-Host "Informe o caminho completo da pasta que deseja criptografar (ex.: C:\\Users\\SeuUsuario\\Documentos\\Sigilosos)"
    if (-not (Test-Path -Path $folderPath -PathType Container)) {
        Write-Host "Caminho inválido ou a pasta não existe. Tente novamente." -ForegroundColor Yellow
        $folderPath = $null
    }
} until ($folderPath)

# Normaliza caminho (remove barra final)
$folderPath = (Get-Item $folderPath).FullName

Write-Host "\nPasta a ser criptografada: $folderPath" -ForegroundColor Green

# Pergunta onde salvar o VHDX
do {
    $vhdPath = Read-Host "Informe o caminho e nome do arquivo VHDX que será criado (ex.: C:\\Encrypted\\container.vhdx)"
    if ([string]::IsNullOrWhiteSpace($vhdPath)) {
        Write-Host "Você deve fornecer um caminho válido." -ForegroundColor Yellow
        continue
    }
    $vhdDir = Split-Path -Path $vhdPath -Parent
    if (-not (Test-Path -Path $vhdDir -PathType Container)) {
        Write-Host "O diretório especificado para salvar o VHDX não existe." -ForegroundColor Yellow
        $vhdPath = $null
    }
    # Impede salvar o VHDX dentro da própria pasta para evitar recursão
    elseif ($folderPath.StartsWith((Get-Item $vhdDir).FullName)) {
        Write-Host "Não salve o contêiner dentro da pasta a ser criptografada. Escolha outro local." -ForegroundColor Yellow
        $vhdPath = $null
    }
} until ($vhdPath)

# Calcula tamanho da pasta atual em bytes
Write-Host "Calculando tamanho da pasta..." -NoNewline
$dirSizeBytes = (Get-ChildItem -Path $folderPath -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
Write-Host " concluído." -ForegroundColor Green

$dirSizeMB = [math]::Ceiling($dirSizeBytes / 1MB)
$defaultSizeMB = [math]::Ceiling($dirSizeMB * 1.2)
Write-Host "Tamanho atual da pasta: $([math]::Round($dirSizeMB/1024,2)) GB"
Write-Host "Tamanho sugerido para o contêiner (20% extra): $([math]::Round($defaultSizeMB/1024,2)) GB"

# Pergunta tamanho desejado
do {
    $sizeInput = Read-Host "Defina o tamanho do contêiner em gigabytes (pressione Enter para aceitar o valor sugerido)"
    if ([string]::IsNullOrWhiteSpace($sizeInput)) {
        $sizeGB = [math]::Ceiling($defaultSizeMB / 1024)
    }
    elseif ([double]::TryParse($sizeInput, [ref]$null) -and [double]$sizeInput -gt 0) {
        $sizeGB = [double]$sizeInput
    }
    else {
        Write-Host "Valor inválido. Informe um número maior que zero." -ForegroundColor Yellow
        $sizeInput = $null
        continue
    }
    break
} until ($false)

Write-Host "Tamanho definido para o contêiner: $sizeGB GB" -ForegroundColor Green

# Cria o arquivo VHDX
Write-Host "\nCriando contêiner VHDX em $vhdPath..."
New-VHD -Path $vhdPath -SizeBytes ([math]::Ceiling($sizeGB * 1GB)) -Dynamic | Out-Null
Write-Host "VHDX criado com sucesso." -ForegroundColor Green

# Monta o VHDX e obtém o disco
Write-Host "Montando VHDX..."
$mountedVHD = Mount-VHD -Path $vhdPath -Passthru
$disk = $mountedVHD | Get-Disk
$diskNumber = $disk.Number

# Inicializa disco e particiona
Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction Stop | Out-Null
$partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter
$driveLetter = $partition.DriveLetter
Write-Host "Disco virtual inicializado. Unidade atribuída: $driveLetter:" -ForegroundColor Green

# Formata volume
Write-Host "Formatando volume em NTFS..."
Format-Volume -DriveLetter $driveLetter -FileSystem NTFS -NewFileSystemLabel "EncryptedVolume" -Confirm:$false | Out-Null
Write-Host "Volume formatado." -ForegroundColor Green

# Solicita senha BitLocker
do {
    $blPwd = Read-Host "Informe uma senha forte para o contêiner BitLocker (mínimo 8 caracteres)" -AsSecureString
    $blPwdPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($blPwd))
    if ($blPwdPlain.Length -lt 8) {
        Write-Host "Senha muito curta. Escolha uma senha com pelo menos 8 caracteres." -ForegroundColor Yellow
        $blPwd = $null
        continue
    }
} until ($blPwd)

Write-Host "Ativando BitLocker no volume..."
Enable-BitLocker -MountPoint "$driveLetter:`" -PasswordProtector -Password $blPwd -EncryptionMethod XtsAes256 -UsedSpaceOnly -ErrorAction Stop | Out-Null

# Monitora o progresso da criptografia
Write-Host "Criptografando volume (isso pode levar alguns minutos)..."
while ((Get-BitLockerVolume -MountPoint "$driveLetter:`").VolumeStatus -ne 'FullyEncrypted') {
    Start-Sleep -Seconds 5
}
Write-Host "Criptografia concluída." -ForegroundColor Green

# Copia dados
Write-Host "Copiando arquivos da pasta original para o volume criptografado..."
$source = Join-Path -Path $folderPath -ChildPath '*'  # todos os arquivos
$dest   = "$driveLetter:`\"
try {
    # Usamos RoboCopy para preservar atributos e lidar bem com grandes quantidades de dados
    Start-Process -FilePath robocopy.exe -ArgumentList @($folderPath, $dest, '/MIR', '/COPY:DATSO', '/R:0', '/W:0') -Wait -NoNewWindow
    Write-Host "Cópia concluída." -ForegroundColor Green
} catch {
    Write-Host "Erro ao copiar arquivos: $_" -ForegroundColor Red
    Write-Host "Encerrando script. O volume permanece montado em $driveLetter:." -ForegroundColor Yellow
    exit 1
}

# Renomeia pasta original e monta volume no caminho
$backupDir = "$folderPath`_backup_original"
if (Test-Path $backupDir) {
    Write-Host "Já existe um backup chamado $backupDir. Escolha outro nome ou mova o backup existente." -ForegroundColor Red
    exit 1
}

Write-Host "Renomeando pasta original para $backupDir..."
Rename-Item -Path $folderPath -NewName (Split-Path -Path $backupDir -Leaf)

Write-Host "Criando diretório vazio para montar o volume criptografado..."
New-Item -ItemType Directory -Path $folderPath | Out-Null

# Monta o volume na pasta usando Add-MountPoint
$volumeId = (Get-Volume -DriveLetter $driveLetter).ObjectId
Add-MountPoint -VolumeObjectId $volumeId -Path $folderPath

# Remove a letra de unidade para evitar acesso acidental por letra (opcional)
Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $partition.PartitionNumber -AccessPath "$driveLetter:`" -ErrorAction SilentlyContinue

Write-Host "\nProcesso concluído! A pasta original agora é um volume criptografado BitLocker."
Write-Host "Backup da pasta original: $backupDir"
Write-Host "O volume está montado em: $folderPath"
Write-Host "Para desmontar o contêiner no futuro, use Dismount-VHD -Path '$vhdPath' e para montá-lo novamente use Mount-VHD -Path '$vhdPath'."
Write-Host "Para desbloquear o volume, forneça a senha BitLocker quando solicitado."

# Pergunta se deseja remover backup
$resp = Read-Host "Deseja excluir o backup da pasta original ($backupDir)? (S/N)"
if ($resp -match '^[Ss]$') {
    try {
        Remove-Item -Path $backupDir -Recurse -Force
        Write-Host "Backup removido." -ForegroundColor Green
    } catch {
        Write-Host "Falha ao remover o backup: $_" -ForegroundColor Yellow
    }
}

Write-Host "\nLembre-se de guardar a senha de desbloqueio e a chave de recuperação do BitLocker em um local seguro."
