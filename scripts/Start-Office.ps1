[CmdletBinding()]
param([string]$BuildRoot = 'C:\DNWBatch', [Parameter(Mandatory)][switch]$IsolatedNetwork)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
if (-not $IsolatedNetwork) { throw 'Use apenas no switch isolado indicado no roteiro.' }
if (-not (Test-Path -LiteralPath (Join-Path $BuildRoot 'dnw-batch.marker'))) { throw 'Bancada DNW nao encontrada.' }
$settings = Get-Content -LiteralPath (Join-Path $BuildRoot 'server.json') -Raw | ConvertFrom-Json
$nic = Get-NetIPConfiguration -InterfaceAlias $settings.InterfaceAlias
if ($nic.IPv4DefaultGateway -or -not ($nic.IPv4Address.IPAddress -contains $settings.ServerIP)) { throw 'A placa mudou de rede/IP. Confira a bancada isolada antes de iniciar DHCP.' }
if (Get-Process -Name tftpd64 -ErrorAction SilentlyContinue) { throw 'Tftpd64 ja esta rodando. Confira sua janela.' }
$tools = Join-Path $BuildRoot 'Tools'
# Janela interativa para o tecnico acompanhar DHCP e os arquivos pedidos por TFTP.
Start-Process -FilePath (Join-Path $tools 'tftpd64.exe') -ArgumentList ('-i "{0}"' -f (Join-Path $tools 'tftpd32.ini')) -WorkingDirectory $tools
Write-Host 'Tftpd64 aberto. Confira IP, Base Directory e servicos TFTP + DHCP; escolha UEFI PXE IPv4 nos notebooks.'
