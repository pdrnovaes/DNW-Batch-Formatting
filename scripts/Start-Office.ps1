[CmdletBinding()]
param([string]$BuildRoot = 'C:\DNWBatch', [switch]$IsolatedNetwork)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
if (-not (Test-Path -LiteralPath (Join-Path $BuildRoot 'dnw-batch.marker'))) { throw 'Bancada DNW nao encontrada.' }
$settings = Get-Content -LiteralPath (Join-Path $BuildRoot 'server.json') -Raw | ConvertFrom-Json
$nic = Get-NetIPConfiguration -InterfaceAlias $settings.InterfaceAlias
if (-not ($nic.IPv4Address.IPAddress -contains $settings.ServerIP)) { throw 'A placa mudou de IP. Reconstrua a bancada com o IP reservado.' }
if ($settings.PrefixLength) {
    $currentAddress = @(Get-NetIPAddress -InterfaceAlias $settings.InterfaceAlias -AddressFamily IPv4 | Where-Object IPAddress -eq $settings.ServerIP)
    if ($currentAddress.Count -ne 1 -or $currentAddress[0].PrefixLength -ne $settings.PrefixLength) { throw 'A mascara da placa mudou. Reconstrua a bancada para atualizar o escopo do firewall.' }
}
$isIsolated = $settings.NetworkMode -eq 'Isolated' -or -not $settings.NetworkMode
if ($isIsolated -and (-not $IsolatedNetwork -or $nic.IPv4DefaultGateway)) { throw 'Bancada antiga/isolada: exige -IsolatedNetwork e switch separado sem gateway. Para a LAN, prepare novamente sem essa opcao.' }
if (-not $isIsolated -and $IsolatedNetwork) { throw 'Esta bancada foi preparada para usar o DHCP existente. Nao altere para DHCP proprio.' }
if (-not $isIsolated -and $settings.NetworkMode -ne 'ExistingDhcp') { throw 'Modo de rede desconhecido.' }
if (Get-Process -Name tftpd64 -ErrorAction SilentlyContinue) { throw 'Tftpd64 ja esta rodando. Confira sua janela.' }
$tools = Join-Path $BuildRoot 'Tools'
Assert-TftpdConfiguration -Configuration (Get-Content -LiteralPath (Join-Path $tools 'tftpd32.ini') -Raw) -IsolatedNetwork:$isIsolated
# Janela interativa para o tecnico acompanhar DHCP e os arquivos pedidos por TFTP.
Start-Process -FilePath (Join-Path $tools 'tftpd64.exe') -ArgumentList ('-i "{0}"' -f (Join-Path $tools 'tftpd32.ini')) -WorkingDirectory $tools
Write-Host "Tftpd64 aberto. Modo $($settings.NetworkMode). Na LAN, mantenha SOMENTE TFTP ativo."
