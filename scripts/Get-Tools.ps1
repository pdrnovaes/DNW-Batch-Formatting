[CmdletBinding()]
param([string]$Destination = (Join-Path $PSScriptRoot '..\.local\tools'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$destinationPath = [IO.Path]::GetFullPath($Destination)
[IO.Directory]::CreateDirectory($destinationPath) | Out-Null
$zip = Join-Path $destinationPath 'tftpd64_portable_v4.74.zip'
$expectedHash = '3ad38a71c0d7d42915429f8f02945e27bcf88161ad1028980d1364af8f76bf22'
if (-not (Test-Path -LiteralPath $zip)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest 'https://github.com/PJO2/tftpd64/releases/download/v4.74/tftpd64_portable_v4.74.zip' -OutFile $zip -UseBasicParsing
}
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
    throw 'SHA256 do Tftpd64 diferente da distribuicao oficial. Download rejeitado.'
}
$extractPath = Join-Path $destinationPath 'tftpd64'
Expand-Archive -LiteralPath $zip -DestinationPath $extractPath -Force
$executables = @(Get-ChildItem -LiteralPath $extractPath -Filter tftpd64.exe -Recurse -File)
if ($executables.Count -ne 1) { throw 'Nao foi encontrado um unico tftpd64.exe no pacote oficial.' }
Write-Output $executables[0].FullName
