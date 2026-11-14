# Este arquivo roda SOMENTE dentro do Windows PE nos notebooks de destino.
$ErrorActionPreference = 'Stop'
try {
    if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
        throw 'Execucao permitida somente no WinPE. Nenhum disco foi alterado.'
    }
    wpeutil.exe UpdateBootInfo | Out-Null
    $firmware = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType).PEFirmwareType
    if ($firmware -ne 2) { throw 'Inicie este notebook em UEFI (PXE IPv4), sem modo Legacy/CSM.' }
    $settings = Get-Content -LiteralPath 'X:\DNW\settings.json' -Raw | ConvertFrom-Json
    Write-Host 'DNW - Windows 11 Pro limpo / User sem senha' -ForegroundColor Cyan
    Write-Host 'Conectando ao servidor...'
    $connected = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        & net.exe use Z: $settings.SharePath $settings.SharePassword "/user:$($settings.ShareUser)" /persistent:no 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $connected = $true; break }
        Start-Sleep -Seconds 5
    }
    if (-not $connected) { throw 'Sem acesso SMB ao servidor. Confira cabo, driver de rede, firewall e credenciais; reconstrua o WinPE se a senha mudou.' }
    if (-not (Test-Path 'Z:\Media\setup.exe')) { throw 'Midia nao encontrada no compartilhamento.' }
    $image = Get-Content 'Z:\image.json' -Raw | ConvertFrom-Json
    if ($image.EditionId -ne 'Professional') { throw 'O perfil nao e do Windows 11 Pro.' }
    $disks = @(Get-Disk | Where-Object { $_.BusType -ne 'USB' -and $_.Size -ge 64000000000 })
    if ($disks.Count -eq 0) { throw 'Nenhum disco interno de pelo menos 64 GB. Confira o driver de armazenamento/NVMe/VMD.' }
    $disks | Select-Object Number, FriendlyName, SerialNumber, BusType, @{Name='GB';Expression={[math]::Round($_.Size / 1GB)}} | Format-Table -AutoSize
    $selection = Read-Host 'Numero do disco que sera APAGADO (Enter cancela)'
    $number = -1
    if (-not [int]::TryParse($selection, [ref]$number)) { throw 'Cancelado. Nenhum disco foi alterado.' }
    $disk = $disks | Where-Object Number -eq $number
    if (-not $disk) { throw 'Disco invalido ou USB. Nenhum disco foi alterado.' }
    $diskFingerprint = "$($disk.UniqueId)|$($disk.SerialNumber)|$($disk.Size)"
    $confirmation = Read-Host "Todos os dados do disco $number serao apagados. Digite APAGAR $number"
    if ($confirmation -cne "APAGAR $number") { throw 'Cancelado. Nenhum disco foi alterado.' }
    $currentDisk = Get-Disk -Number $number
    if ("$($currentDisk.UniqueId)|$($currentDisk.SerialNumber)|$($currentDisk.Size)" -ne $diskFingerprint -or $currentDisk.BusType -eq 'USB') {
        throw 'A lista de discos mudou. Reinicie a preparacao.'
    }
    & 'Z:\Kit\scripts\New-Unattend.ps1' -ImageIndex $image.ImageIndex -UILanguage $image.UILanguage -DiskNumber $number -DiskSizeBytes $currentDisk.Size -EraseSelectedDisk -OutputPath 'X:\DNW\unattend.xml' | Out-Null
    Write-Host 'Iniciando a instalacao. O notebook reiniciara pelo SSD; nao selecione PXE novamente.' -ForegroundColor Green
    # A limpeza do disco ocorre dentro do Windows Setup, so depois da confirmacao.
    $setupProcess = Start-Process 'Z:\Media\setup.exe' -ArgumentList '/unattend:X:\DNW\unattend.xml' -PassThru -Wait
    if ($setupProcess.ExitCode -ne 0) { throw "Windows Setup retornou $($setupProcess.ExitCode). Logs em X:\Windows\Panther ou no disco de destino." }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'Abra outro prompt com Shift+F10 para diagnostico. Nenhuma nova tentativa automatica sera feita.'
    try { Read-Host 'Enter para retornar ao prompt' | Out-Null } catch { }
    exit 1
}
