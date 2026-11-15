[CmdletBinding()]
param(
    [ValidateSet('Inventory','Prepare')][string]$Operation = 'Inventory',
    [ValidateSet('Quick','Traditional')][string]$Mode = 'Traditional',
    [int]$DiskNumber = -1,
    [string]$ExpectedFingerprint,
    [string]$ExpectedMediaFingerprint,
    [string]$ResultPath = 'X:\DNW\result.xml'
)
$ErrorActionPreference = 'Stop'
function Get-Fingerprint($Disk) {
    $text = "$($Disk.Number)|$($Disk.UniqueId)|$($Disk.SerialNumber)|$($Disk.Size)|$($Disk.BusType)"
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','') } finally { $hash.Dispose() }
}
function Test-InternalDisk($Disk, [int]$MediaDiskNumber) {
    return $Disk.Number -ne $MediaDiskNumber -and $Disk.BusType -ne 'USB' -and $Disk.Size -ge 64000000000 -and -not $Disk.IsOffline -and -not $Disk.IsReadOnly
}
function Write-Result([hashtable]$Attributes, $Disks) {
    $document = [Xml.XmlDocument]::new()
    $root = $document.CreateElement('deployment')
    [void]$document.AppendChild($root)
    foreach ($key in $Attributes.Keys) { $root.SetAttribute($key,[string]$Attributes[$key]) }
    foreach ($disk in $Disks) {
        $node = $document.CreateElement('disk')
        foreach ($key in $disk.Keys) { $node.SetAttribute($key,[string]$disk[$key]) }
        [void]$root.AppendChild($node)
    }
    $document.Save($ResultPath)
}
try {
    if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) { throw 'Este instalador funciona somente ao iniciar pelo pendrive. Nenhum disco foi alterado.' }
    & wpeutil.exe UpdateBootInfo | Out-Null
    if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType).PEFirmwareType -ne 2) { throw 'Reinicie pelo pendrive em modo UEFI. O modo Legacy nao e compativel com esta instalacao do Windows 11.' }
    $settings = Get-Content -LiteralPath 'X:\DNW\settings.json' -Raw | ConvertFrom-Json
    $uuid = ([string](Get-CimInstance Win32_ComputerSystemProduct).UUID).Trim()
    if ($settings.ProtectedComputerUuid -and $uuid -ieq $settings.ProtectedComputerUuid) { throw 'Este e o computador protegido de preparacao da midia. Use o pendrive no equipamento de destino.' }
    $sources = @(
        foreach ($volume in @(Get-Volume | Where-Object DriveLetter)) {
            $root = "$($volume.DriveLetter):\"
            if (-not (Test-Path -LiteralPath (Join-Path $root 'dnw-local-media.json'))) { continue }
            $descriptor = Get-Content -LiteralPath (Join-Path $root 'dnw-local-media.json') -Raw | ConvertFrom-Json
            $partition = Get-Partition -DriveLetter $volume.DriveLetter
            $sourceDisk = Get-Disk -Number $partition.DiskNumber
            if ($sourceDisk.BusType -eq 'USB' -and $descriptor.Format -eq 'DNWLocalMedia' -and (Test-Path -LiteralPath (Join-Path $root 'Media\setup.exe'))) {
                [pscustomobject]@{Root=$root;Disk=$sourceDisk}
            }
        }
    )
    if ($sources.Count -ne 1) { throw 'Conecte somente um pendrive DNW com os arquivos completos do Windows.' }
    $source = $sources[0]
    $mediaFingerprint = Get-Fingerprint $source.Disk
    if ($ExpectedMediaFingerprint -and $mediaFingerprint -cne $ExpectedMediaFingerprint) { throw 'O pendrive mudou durante a preparacao. Reinicie a tela e tente novamente.' }
    $image = Get-Content -LiteralPath (Join-Path $source.Root 'image.json') -Raw | ConvertFrom-Json
    if ($image.EditionId -ne 'Professional' -or $image.UILanguage -ne 'pt-BR' -or [int]$image.ImageIndex -lt 1) { throw 'A midia precisa conter o perfil Windows 11 Pro em portugues do Brasil.' }
    $wimPath = Join-Path $source.Root 'Media\sources\install.wim'
    if (-not (Test-Path -LiteralPath $wimPath)) { $wimPath = Join-Path $source.Root 'Media\sources\install.esd' }
    if (-not (Test-Path -LiteralPath $wimPath)) { throw 'Arquivo de instalacao do Windows nao encontrado no pendrive.' }
    . 'X:\DNW\Read-WimInfo.ps1'
    $actualImage = @(Read-WimInfo -ImagePath $wimPath | Where-Object ImageIndex -eq $image.ImageIndex)
    if ($actualImage.Count -ne 1 -or $actualImage[0].EditionId -ne 'Professional' -or $actualImage[0].Architecture -ne 9 -or $actualImage[0].UILanguage -ne 'pt-BR' -or $actualImage[0].Build -lt 22000) { throw 'O perfil nao corresponde ao Windows 11 Pro x64 pt-BR desta midia.' }
    $eligible = @(Get-Disk | Where-Object { Test-InternalDisk $_ $source.Disk.Number })
    if ($Operation -eq 'Inventory') {
        $records = @($eligible | ForEach-Object { @{number=$_.Number;model=$_.FriendlyName;serial=$_.SerialNumber;size=$_.Size;bus=[string]$_.BusType;fingerprint=(Get-Fingerprint $_)} })
        $computer = Get-CimInstance Win32_ComputerSystem
        Write-Result @{status='Ready';computer="$($computer.Manufacturer) $($computer.Model)";mediaFingerprint=$mediaFingerprint;imageIndex=$image.ImageIndex;sourceRoot=$source.Root} $records
        exit 0
    }
    $arguments = @{ImageIndex=[int]$image.ImageIndex;UILanguage='pt-BR';OutputPath='X:\DNW\unattend.xml'}
    if ($Mode -eq 'Quick') {
        if (-not $ExpectedFingerprint -or $DiskNumber -lt 0) { throw 'Selecione e confirme o disco de destino antes de instalar.' }
        $target = @($eligible | Where-Object Number -eq $DiskNumber)
        if ($target.Count -ne 1 -or (Get-Fingerprint $target[0]) -cne $ExpectedFingerprint) { throw 'O disco de destino mudou ou nao e um disco interno elegivel. Nenhum disco foi alterado.' }
        $arguments.DiskNumber = $DiskNumber
        $arguments.DiskSizeBytes = $target[0].Size
        $arguments.EraseSelectedDisk = $true
    }
    & 'X:\DNW\Kit\scripts\New-Unattend.ps1' @arguments | Out-Null
    $stateDirectory = Join-Path $source.Root 'State\Gui'
    [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
    $record = @{Mode=$Mode;ComputerUuid=$uuid;DiskNumber=$DiskNumber;TimeUtc=[DateTime]::UtcNow.ToString('o');Status='UserConfirmed';ImageIndex=$image.ImageIndex}
    $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDirectory ([guid]::NewGuid().ToString('N')+'.json')) -Encoding UTF8
    Write-Result @{status='Prepared';setup=(Join-Path $source.Root 'Media\setup.exe');answerFile='X:\DNW\unattend.xml';sourceRoot=$source.Root} @()
    exit 0
} catch {
    try { Write-Result @{status='Error';message=$_.Exception.Message} @() } catch { }
    exit 1
}
