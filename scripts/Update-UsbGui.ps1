[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[D-Zd-z]$')][string]$BootDrive,
    [Parameter(Mandatory)][ValidatePattern('^[D-Zd-z]$')][string]$MediaDrive,
    [Parameter(Mandatory)][string]$ExpectedDiskSerial,
    [Parameter(Mandatory)][string]$WimlibPath,
    [string]$WorkRoot = (Join-Path $PSScriptRoot '..\.local\usb-updates')
)
$ErrorActionPreference = 'Stop'
function Assert-UsbTarget {
    $bootPartition = Get-Partition -DriveLetter $BootDrive
    $mediaPartition = Get-Partition -DriveLetter $MediaDrive
    if ($bootPartition.DiskNumber -ne $mediaPartition.DiskNumber) { throw 'Boot e midia nao pertencem ao mesmo pendrive.' }
    $disk = Get-Disk -Number $bootPartition.DiskNumber
    if ($disk.BusType -ne 'USB' -or $disk.IsBoot -or $disk.IsSystem -or ([string]$disk.SerialNumber).Trim() -cne $ExpectedDiskSerial.Trim()) { throw 'Identidade do pendrive diferente da esperada. Nada sera gravado.' }
    return $disk
}
function Invoke-Wim([string[]]$Arguments) {
    & $WimlibPath @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "wimlib retornou $LASTEXITCODE; atualizacao interrompida." }
}
$WimlibPath = (Resolve-Path -LiteralPath $WimlibPath).Path
$target = Assert-UsbTarget
$bootRoot = "${BootDrive}:\"
$mediaRoot = "${MediaDrive}:\"
$bootWim = Join-Path $bootRoot 'sources\boot.wim'
$descriptorPath = Join-Path $mediaRoot 'dnw-local-media.json'
$descriptor = Get-Content -LiteralPath $descriptorPath -Raw | ConvertFrom-Json
if ($descriptor.Format -ne 'DNWLocalMedia') { throw 'O pendrive nao foi identificado como midia local DNW.' }
if (-not (Test-Path -LiteralPath (Join-Path $mediaRoot 'Media\setup.exe'))) { throw 'Instalador do Windows ausente.' }
$run = Join-Path ([IO.Path]::GetFullPath($WorkRoot)) ([DateTime]::Now.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
[IO.Directory]::CreateDirectory($run) | Out-Null
$backup = Join-Path $run 'backup'
[IO.Directory]::CreateDirectory($backup) | Out-Null
Copy-Item -LiteralPath $bootWim -Destination (Join-Path $backup 'boot.wim')
Copy-Item -LiteralPath $descriptorPath -Destination (Join-Path $backup 'dnw-local-media.json')
$originalHash = (Get-FileHash -LiteralPath (Join-Path $backup 'boot.wim') -Algorithm SHA256).Hash
Invoke-Wim @('extract',$bootWim,'1','/DNW/settings.json',"--dest-dir=$backup",'--no-acls')
$oldSettings = Get-Content -LiteralPath (Join-Path $backup 'settings.json') -Raw | ConvertFrom-Json
$payload = & (Join-Path $PSScriptRoot 'Build-UsbGui.ps1') -OutputDirectory (Join-Path $run 'payload')
$newSettings = @{MediaMode='LocalUsb';AutomaticInstall=$false;UserInterface='DialMenu';Version=2}
if ($oldSettings.ProtectedComputerUuid) { $newSettings.ProtectedComputerUuid = $oldSettings.ProtectedComputerUuid }
$newSettings | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $payload 'settings.json') -Encoding UTF8
$stagedWim = Join-Path $run 'boot.wim'
Copy-Item -LiteralPath (Join-Path $backup 'boot.wim') -Destination $stagedWim
$commands = @(
    "add `"$payload`" /DNW",
    "add `"$(Join-Path $payload 'winpeshl.ini')`" /Windows/System32/winpeshl.ini",
    "add `"$(Join-Path $PSScriptRoot '..\usb\startnet.cmd')`" /Windows/System32/startnet.cmd",
    'delete /DNW/Start-Deploy.ps1'
)
$commandsPath = Join-Path $run 'update-commands.txt'
[IO.File]::WriteAllLines($commandsPath,$commands,[Text.UTF8Encoding]::new($false))
# ProcessStartInfo evita passar os caminhos por um segundo shell e permite stdin real.
$start = [Diagnostics.ProcessStartInfo]::new($WimlibPath)
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.Arguments = 'update "'+$stagedWim+'" 1 --no-acls --check'
$process = [Diagnostics.Process]::Start($start)
$process.StandardInput.Write([IO.File]::ReadAllText($commandsPath))
$process.StandardInput.Close()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$stdoutTask.Result | Set-Content -LiteralPath (Join-Path $run 'wim-update.log') -Encoding UTF8
$stderrTask.Result | Set-Content -LiteralPath (Join-Path $run 'wim-update-errors.log') -Encoding UTF8
if ($process.ExitCode -ne 0) { throw "Falha ao atualizar a copia local do boot. Veja $run. O pendrive foi preservado." }
Invoke-Wim @('verify',$stagedWim)
$check = Join-Path $run 'check'
Invoke-Wim @('extract',$stagedWim,'1','/DNW/DialDeploy.exe','/DNW/Deployment.ps1','/DNW/settings.json','/Windows/System32/winpeshl.ini',"--dest-dir=$check",'--no-acls')
foreach ($file in @('DialDeploy.exe','Deployment.ps1','settings.json','winpeshl.ini')) {
    if ((Get-FileHash -LiteralPath (Join-Path $check $file)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $payload $file)).Hash) { throw "Verificacao da imagem falhou para $file. Pendrive preservado." }
}
$target = Assert-UsbTarget
if ((Get-FileHash -LiteralPath $bootWim -Algorithm SHA256).Hash -ne $originalHash) { throw 'O boot do pendrive foi alterado durante a preparacao. Gravacao cancelada.' }
$temporaryWim = Join-Path $bootRoot 'sources\boot.dnw-new.wim'
if (Test-Path -LiteralPath $temporaryWim) { throw 'Ja existe uma copia temporaria de boot no pendrive. Confira antes de continuar.' }
Copy-Item -LiteralPath $stagedWim -Destination $temporaryWim
$newHash = (Get-FileHash -LiteralPath $stagedWim -Algorithm SHA256).Hash
if ((Get-FileHash -LiteralPath $temporaryWim -Algorithm SHA256).Hash -ne $newHash) { throw 'A copia para USB nao passou na verificacao. O boot original continua ativo.' }
$previousName = 'boot.before-dial-menu-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss')+'.wim'
Rename-Item -LiteralPath $bootWim -NewName $previousName
try { Rename-Item -LiteralPath $temporaryWim -NewName 'boot.wim' } catch {
    Rename-Item -LiteralPath (Join-Path $bootRoot ('sources\'+$previousName)) -NewName 'boot.wim'
    throw
}
$descriptor | Add-Member -NotePropertyName Version -NotePropertyValue 2 -Force
$descriptor | Add-Member -NotePropertyName Mode -NotePropertyValue 'DialMenu' -Force
$descriptor | Add-Member -NotePropertyName DisplayName -NotePropertyValue 'DNW - Batch Formatting' -Force
$descriptor | ConvertTo-Json | Set-Content -LiteralPath $descriptorPath -Encoding UTF8
$result = @{BackupDirectory=$backup;UsbPreviousBoot=(Join-Path $bootRoot ('sources\'+$previousName));BootSha256=$newHash;Serial=$ExpectedDiskSerial;Mode='DialMenu';InstalledAtUtc=[DateTime]::UtcNow.ToString('o')}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'update-result.json') -Encoding UTF8
Write-Output ([pscustomobject]$result)
