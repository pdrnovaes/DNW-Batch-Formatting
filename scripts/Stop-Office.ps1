[CmdletBinding()]
param([string]$BuildRoot = 'C:\DNWBatch')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
$root = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $root 'dnw-batch.marker'))) { throw 'Pasta nao identificada como bancada DNW.' }
$exe = Join-Path $root 'Tools\tftpd64.exe'
Get-Process -Name tftpd64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | Stop-Process
$share = Get-SmbShare -Name DNWDeploy -ErrorAction SilentlyContinue
if ($share) {
    if ($share.Path -ne (Join-Path $root 'Share')) { throw 'DNWDeploy pertence a outra pasta. Nenhum compartilhamento removido.' }
    Remove-SmbShare -Name DNWDeploy -Force
}
foreach ($name in @('DNWBatch-SMB','DNWBatch-TFTP')) { Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule }
$user = Get-LocalUser -Name DNWDeploy -ErrorAction SilentlyContinue
if ($user -and $user.Description -eq 'Leitura da midia DNW; remover ao encerrar a bancada') { $user | Remove-LocalUser }
Write-Host 'Tftpd64 encerrado; compartilhamento, conta temporaria e regras DNW removidos. Parametros do DHCP externo nao foram alterados.'
Write-Host "Os arquivos foram preservados em $root; o IP da placa tambem. Para montar novamente, use outra BuildRoot."
