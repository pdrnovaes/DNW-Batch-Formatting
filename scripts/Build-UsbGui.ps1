[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.local\usb-gui'))
$ErrorActionPreference = 'Stop'
$output = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($output) | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Compilador do .NET Framework 4.x nao encontrado neste Windows.' }
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Xml.dll ("/out:"+(Join-Path $output 'DialDeploy.exe')) (Join-Path $PSScriptRoot '..\usb\DialDeploy.cs')
if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel compilar a interface.' }
foreach ($name in @('Deployment.ps1','winpeshl.ini','DialDeploy.exe.config')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\usb\$name") -Destination $output -Force }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\assets\dial-logo.png') -Destination $output -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Read-WimInfo.ps1') -Destination $output -Force
[IO.Directory]::CreateDirectory((Join-Path $output 'Kit\scripts')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $output 'Kit\templates')) | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'New-Unattend.ps1') -Destination (Join-Path $output 'Kit\scripts\New-Unattend.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\templates\Unattend.xml') -Destination (Join-Path $output 'Kit\templates\Unattend.xml') -Force
Write-Output $output
