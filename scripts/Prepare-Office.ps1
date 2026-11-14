[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][string]$ServerIP,
    [Parameter(Mandatory)][switch]$IsolatedNetwork,
    [string]$IsoPath,
    [ValidateRange(0, 999)][int]$ImageIndex = 0,
    [string]$BuildRoot = 'C:\DNWBatch',
    [string]$TftpdExe,
    [string]$DriversPath,
    [ValidateSet('2011','2023')][string]$BootCA = '2023'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
if (-not $IsolatedNetwork) { throw 'Este kit usa DHCP somente em bancada isolada. Leia o roteiro antes de usar -IsolatedNetwork.' }
$serverValue = Get-IPv4Value $ServerIP
$octets = $ServerIP.Split('.')
if ([int]$octets[3] -lt 1 -or [int]$octets[3] -gt 99) { throw 'Use IP final 1 a 99 para o servidor; o pool da bancada sera .100 a .114.' }
$subnet = "$($octets[0]).$($octets[1]).$($octets[2]).0/24"
$adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop
$adapterAddresses = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
$address = @($adapterAddresses | Where-Object { $_.IPAddress -eq $ServerIP -and $_.PrefixLength -eq 24 -and $_.PrefixOrigin -eq 'Manual' })
if ($address.Count -ne 1) { throw "Configure manualmente $ServerIP / 255.255.255.0, sem gateway, na placa $InterfaceAlias. O kit nao altera enderecos de rede." }
$network = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
if ($network.IPv4DefaultGateway) { throw 'A placa da bancada tem gateway. Use um switch isolado, sem uplink ao roteador/LAN, sem gateway nesta placa.' }
if (-not $IsoPath) {
    $isoFolder = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ISO'
    $isoFiles = @(Get-ChildItem -LiteralPath $isoFolder -Filter *.iso -File -ErrorAction SilentlyContinue)
    if ($isoFiles.Count -ne 1) { throw "Coloque uma unica ISO em $isoFolder ou informe -IsoPath." }
    $IsoPath = $isoFiles[0].FullName
}
$iso = (Resolve-Path -LiteralPath $IsoPath).Path
if ([IO.Path]::GetExtension($iso) -ne '.iso') { throw 'Informe um arquivo ISO.' }
if (-not (Test-Path -LiteralPath "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\copype.cmd")) {
    throw 'Instale Windows ADK (Deployment Tools) e Windows PE Add-on conforme o README.'
}
$root = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\')
if ($root -notmatch '^[A-Za-z]:\\[^&|<>^%!"\r\n]+$' -or $root -match '[&|<>^%!"\r\n]') { throw 'BuildRoot deve ser uma pasta local dedicada, sem caracteres especiais do cmd.exe.' }
if (Test-Path -LiteralPath $root) { throw "BuildRoot ja existe: $root. Use outra pasta ou encerre/remova a bancada anterior conforme o roteiro." }
if (Get-SmbShare -Name DNWDeploy -ErrorAction SilentlyContinue) { throw 'O compartilhamento DNWDeploy ja existe. Encerre a bancada anterior primeiro.' }
if (Get-LocalUser -Name DNWDeploy -ErrorAction SilentlyContinue) { throw 'A conta DNWDeploy ja existe. Encerre a bancada anterior primeiro.' }
if (-not $TftpdExe) { $TftpdExe = & (Join-Path $PSScriptRoot 'Get-Tools.ps1') }
$TftpdExe = (Resolve-Path -LiteralPath $TftpdExe).Path
if ([IO.Path]::GetFileName($TftpdExe) -ne 'tftpd64.exe') { throw 'Informe o tftpd64.exe do pacote portatil oficial.' }
$mountedHere = $false
try {
    $diskImage = Get-DiskImage -ImagePath $iso
    if (-not $diskImage.Attached) { Mount-DiskImage -ImagePath $iso -Access ReadOnly | Out-Null; $mountedHere = $true }
    $volumes = @(Get-DiskImage -ImagePath $iso | Get-Volume | Where-Object DriveLetter)
    if ($volumes.Count -ne 1) { throw 'Nao foi possivel identificar o volume da ISO.' }
    $source = "$($volumes[0].DriveLetter):\"
    $imagePath = Join-Path $source 'sources\install.wim'
    if (-not (Test-Path $imagePath)) { $imagePath = Join-Path $source 'sources\install.esd' }
    if (-not (Test-Path $imagePath)) { throw 'ISO sem sources\install.wim ou install.esd. Use midia oficial Windows 11 x64.' }
    $images = @(Get-WindowsImage -ImagePath $imagePath)
    if ($ImageIndex -eq 0) {
        $pro = @($images | Where-Object { $_.ImageName -eq 'Windows 11 Pro' })
        if ($pro.Count -ne 1) { $images | Select-Object ImageIndex,ImageName | Format-Table; throw 'Selecione o indice Pro com -ImageIndex.' }
        $ImageIndex = $pro[0].ImageIndex
    }
    $selectedImage = Get-WindowsImage -ImagePath $imagePath -Index $ImageIndex
    $metadata = Get-DnwImageMetadata -Image $selectedImage
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $private = Join-Path $root 'Private'
    [IO.Directory]::CreateDirectory($private) | Out-Null
    Invoke-Checked 'icacls.exe' @($private,'/inheritance:r','/grant:r','*S-1-5-32-544:(OI)(CI)F','*S-1-5-18:(OI)(CI)F')
    Write-Utf8 (Join-Path $root 'dnw-batch.marker') 'DNW Batch Formatting v1'
    $share = Join-Path $root 'Share'
    [IO.Directory]::CreateDirectory((Join-Path $share 'Media')) | Out-Null
    & robocopy.exe $source (Join-Path $share 'Media') /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS
    if ($LASTEXITCODE -ge 8) { throw "Falha ao copiar a ISO: robocopy $LASTEXITCODE." }
    [IO.Directory]::CreateDirectory((Join-Path $share 'Kit\scripts')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $share 'Kit\templates')) | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'New-Unattend.ps1') -Destination (Join-Path $share 'Kit\scripts\New-Unattend.ps1')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\templates\Unattend.xml') -Destination (Join-Path $share 'Kit\templates\Unattend.xml')
    $metadata.IsoSha256 = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash
    Write-Utf8 (Join-Path $share 'image.json') ($metadata | ConvertTo-Json)
    $passwordBytes = New-Object byte[] 24
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($passwordBytes) } finally { $random.Dispose() }
    $password = [Convert]::ToBase64String($passwordBytes) + 'aA1!'
    $localUser = New-LocalUser -Name DNWDeploy -Password (ConvertTo-SecureString $password -AsPlainText -Force) -Description 'Leitura da midia DNW; remover ao encerrar a bancada' -AccountNeverExpires -PasswordNeverExpires -UserMayNotChangePassword
    $usersGroup = Get-LocalGroup -SID 'S-1-5-32-545'
    if (-not (Get-LocalGroupMember -Group $usersGroup | Where-Object { $_.SID -eq $localUser.SID })) {
        Add-LocalGroupMember -Group $usersGroup -Member $localUser
    }
    $userIdentity = "$env:COMPUTERNAME\DNWDeploy"
    Invoke-Checked 'icacls.exe' @($share,'/grant',"*$($localUser.SID.Value):(OI)(CI)RX")
    New-SmbShare -Name DNWDeploy -Path $share -ReadAccess $userIdentity -ConcurrentUserLimit 15 | Out-Null
    $settings = @{SharePath="\\$ServerIP\DNWDeploy"; ShareUser=$userIdentity; SharePassword=$password}
    $settingsPath = Join-Path $private 'settings.json'
    Write-Utf8 $settingsPath ($settings | ConvertTo-Json)
    & (Join-Path $PSScriptRoot 'Build-WinPE.ps1') -BuildRoot $root -SettingsPath $settingsPath -DriversPath $DriversPath -BootCA $BootCA
    $tools = Join-Path $root 'Tools'
    [IO.Directory]::CreateDirectory($tools) | Out-Null
    Copy-Item -Path (Join-Path (Split-Path $TftpdExe) '*') -Destination $tools -Recurse -Force
    $ini = @"
[TFTPD32]
BaseDirectory=$root\TFTP
TftpPort=69
LocalIP=$ServerIP
DHCP LocalIP=$ServerIP
Services=5
SecurityLevel=3
VirtualRoot=1
Negociate=1
PXECompatibility=1
WinSize=4
Timeout=5
MaxRetransmit=6
Enable IPv4=1
Enable IPv6=0
Max Simultaneous Transfers=15
TftpLogFile=$root\tftp.log
[DHCP]
IP_Pool=$($octets[0]).$($octets[1]).$($octets[2]).100
PoolSize=15
BootFile=bootmgfw.efi
Mask=255.255.255.0
Gateway=
DNS=
DNS2=
WINS=
DomainName=
AddOptionNumber=0
AddOptionValue=
AddOptionNumber1=0
AddOptionValue1=
Lease (minutes)=120
"@
    [IO.File]::WriteAllText((Join-Path $tools 'tftpd32.ini'),$ini,[Text.Encoding]::Default)
    foreach ($rule in @('DNWBatch-SMB','DNWBatch-TFTP')) { if (Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue) { throw "Regra $rule ja existe. Encerre a bancada anterior." } }
    New-NetFirewallRule -Name DNWBatch-SMB -DisplayName 'DNW Batch - SMB bancada' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 445 -LocalAddress $ServerIP -RemoteAddress $subnet -InterfaceAlias $InterfaceAlias -Profile Any | Out-Null
    New-NetFirewallRule -Name DNWBatch-TFTP -DisplayName 'DNW Batch - TFTP e DHCP bancada' -Direction Inbound -Action Allow -Program (Join-Path $tools 'tftpd64.exe') -Protocol UDP -LocalAddress $ServerIP -RemoteAddress Any -InterfaceAlias $InterfaceAlias -Profile Any | Out-Null
    Write-Utf8 (Join-Path $root 'server.json') (@{InterfaceAlias=$InterfaceAlias;ServerIP=$ServerIP;Subnet=$subnet;BootCA=$BootCA} | ConvertTo-Json)
    Write-Host "Preparado em $root. O DHCP ainda NAO foi iniciado." -ForegroundColor Green
    Write-Host 'Com o cabo apenas no switch isolado, execute Start-Office.ps1. Piloto: 1 notebook, depois 2, depois 10.'
} finally {
    if ($mountedHere) { Dismount-DiskImage -ImagePath $iso | Out-Null }
}
