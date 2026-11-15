$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'usb\Deployment.ps1'),[ref]$null,[ref]$null)
$internalDisk = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-InternalDisk'},$true)
Invoke-Expression $internalDisk.Extent.Text
$disk = [pscustomobject]@{Number=0;BusType='NVMe';Size=512000000000;IsOffline=$false;IsReadOnly=$false}
if (-not (Test-InternalDisk $disk 1)) { throw 'Disco NVMe interno deve ser elegivel.' }
$disk.BusType='SATA'
if (-not (Test-InternalDisk $disk 1)) { throw 'Disco SATA de desktop deve ser elegivel.' }
$disk.BusType='USB'
if (Test-InternalDisk $disk 1) { throw 'Disco USB nao pode ser destino rapido.' }
$disk.BusType='NVMe';$disk.Number=1
if (Test-InternalDisk $disk 1) { throw 'O proprio disco da midia nunca pode ser selecionado.' }
$disk.Number=0;$disk.IsReadOnly=$true
if (Test-InternalDisk $disk 1) { throw 'Disco somente leitura deve ser rejeitado.' }
$disk.IsReadOnly=$false;$disk.IsOffline=$true
if (Test-InternalDisk $disk 1) { throw 'Disco offline deve ser rejeitado.' }
$disk.IsOffline=$false;$disk.Size=32000000000
if (Test-InternalDisk $disk 1) { throw 'Disco menor que 64 GB deve ser rejeitado.' }
$out = Join-Path $repo '.local\usb-test'
[IO.Directory]::CreateDirectory($out) | Out-Null
$result = Join-Path $out 'guard.xml'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repo 'usb\Deployment.ps1') -Operation Prepare -Mode Quick -DiskNumber 0 -ExpectedFingerprint TEST -ResultPath $result
if ($LASTEXITCODE -ne 1) { throw 'O backend precisa recusar execucao fora do WinPE.' }
[xml]$guard = Get-Content -LiteralPath $result -Raw
if ($guard.deployment.status -ne 'Error' -or $guard.deployment.message -notmatch 'somente ao iniciar pelo pendrive') { throw 'A protecao de execucao fora do WinPE falhou.' }
& (Join-Path $repo 'scripts\Build-UsbGui.ps1') -OutputDirectory (Join-Path $out 'build') | Out-Null
Write-Host 'Protecoes de disco, bloqueio fora do WinPE e compilacao da interface passaram.' -ForegroundColor Green
