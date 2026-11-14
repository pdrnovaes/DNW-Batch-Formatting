[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$SettingsPath,
    [string]$DriversPath,
    [ValidateSet('2011','2023')][string]$BootCA = '2023',
    [string]$AdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
$peRoot = Join-Path $AdkRoot 'Windows Preinstallation Environment'
$deploymentRoot = Join-Path $AdkRoot 'Deployment Tools'
$copype = Join-Path $peRoot 'copype.cmd'
$makeMedia = Join-Path $peRoot 'MakeWinPEMedia.cmd'
$dism = Join-Path $deploymentRoot 'amd64\DISM\dism.exe'
$adkEnv = Join-Path $deploymentRoot 'DandISetEnv.bat'
foreach ($required in @($copype, $makeMedia, $dism, $adkEnv, $SettingsPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Falta $required. Instale Deployment Tools do ADK e o WinPE Add-on correspondente." }
}
$root = [IO.Path]::GetFullPath($BuildRoot)
$work = Join-Path $root 'WinPE'
if (Test-Path -LiteralPath $work) { throw "A pasta $work ja existe. Use outra BuildRoot; nao removemos imagens montadas automaticamente." }
[IO.Directory]::CreateDirectory($root) | Out-Null
# copype e MakeWinPEMedia precisam das variaveis do ambiente ADK no mesmo cmd.exe.
$copyCommand = 'call "{0}" && call "{1}" amd64 "{2}"' -f $adkEnv, $copype, $work
Invoke-Checked 'cmd.exe' @('/d','/c',$copyCommand)
$mount = Join-Path $work 'mount'
$wim = Join-Path $work 'media\sources\boot.wim'
$mounted = $false
try {
    Invoke-Checked $dism @('/Mount-Image',"/ImageFile:$wim",'/Index:1',"/MountDir:$mount")
    $mounted = $true
    $ocRoot = Join-Path $peRoot 'amd64\WinPE_OCs'
    foreach ($package in @('WinPE-WMI','WinPE-NetFX','WinPE-Scripting','WinPE-PowerShell','WinPE-StorageWMI','WinPE-SecureStartup')) {
        Invoke-Checked $dism @("/Image:$mount",'/Add-Package',"/PackagePath:$(Join-Path $ocRoot "$package.cab")")
        $languageCab = Join-Path $ocRoot "en-us\${package}_en-us.cab"
        if (Test-Path -LiteralPath $languageCab) { Invoke-Checked $dism @("/Image:$mount",'/Add-Package',"/PackagePath:$languageCab") }
    }
    if ($DriversPath) {
        $drivers = (Resolve-Path -LiteralPath $DriversPath).Path
        Invoke-Checked $dism @("/Image:$mount",'/Add-Driver',"/Driver:$drivers",'/Recurse')
    }
    [IO.Directory]::CreateDirectory((Join-Path $mount 'DNW')) | Out-Null
    Copy-Item -LiteralPath $SettingsPath -Destination (Join-Path $mount 'DNW\settings.json')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\winpe\Start-Deploy.ps1') -Destination (Join-Path $mount 'DNW\Start-Deploy.ps1')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\winpe\startnet.cmd') -Destination (Join-Path $mount 'Windows\System32\startnet.cmd') -Force
    # bootmgfw.efi e um NBP UEFI nativo; nao usar wdsmgfw.efi, que exige WDS.
    $efiSource = Join-Path $mount 'Windows\Boot\EFI'
    if ($BootCA -eq '2023') { $efiSource = Join-Path $mount 'Windows\Boot\EFI_EX' }
    $bootManager = Join-Path $efiSource 'bootmgfw.efi'
    if (-not (Test-Path -LiteralPath $bootManager)) { throw "Boot manager CA $BootCA indisponivel neste ADK: $bootManager" }
    $tftp = Join-Path $root 'TFTP'
    [IO.Directory]::CreateDirectory((Join-Path $tftp 'Boot')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $tftp 'EFI\Microsoft\Boot')) | Out-Null
    Copy-Item -Path (Join-Path $efiSource '*') -Destination (Join-Path $tftp 'EFI\Microsoft\Boot') -Recurse -Force
    Copy-Item -LiteralPath $bootManager -Destination (Join-Path $tftp 'bootmgfw.efi')
    Copy-Item -LiteralPath (Join-Path $work 'media\Boot\boot.sdi') -Destination (Join-Path $tftp 'Boot\boot.sdi')
    # Fonts/Resources e boot.stl acompanham o ADK escolhido.
    Copy-Item -Path (Join-Path $work 'media\Boot\*') -Destination (Join-Path $tftp 'Boot') -Recurse -Force
    Copy-Item -Path (Join-Path $work 'media\EFI\Microsoft\Boot\*') -Destination (Join-Path $tftp 'EFI\Microsoft\Boot') -Recurse -Force
    $bcd = Join-Path $root 'BCD'
    Invoke-Checked 'bcdedit.exe' @('/createstore', $bcd)
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/create','{ramdiskoptions}','/d','DNW RAMDisk')
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/set','{ramdiskoptions}','ramdisksdidevice','boot')
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/set','{ramdiskoptions}','ramdisksdipath','\Boot\boot.sdi')
    $loader = '{' + [guid]::NewGuid().ToString() + '}'
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/create',$loader,'/d','DNW Windows PE','/application','osloader')
    foreach ($field in @('device','osdevice')) { Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/set',$loader,$field,'ramdisk=[boot]\Boot\boot.wim,{ramdiskoptions}') }
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/set',$loader,'path','\Windows\System32\winload.efi')
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/set',$loader,'systemroot','\Windows')
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/set',$loader,'winpe','Yes')
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/set',$loader,'detecthal','Yes')
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/create','{bootmgr}','/d','DNW Boot Manager')
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/default',$loader)
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/displayorder',$loader,'/addlast')
    Invoke-Checked 'bcdedit.exe' @('/store',$bcd,'/timeout','0')
    foreach ($bcdDestination in @('Boot\BCD','EFI\Microsoft\Boot\BCD','BCD')) {
        Copy-Item -LiteralPath $bcd -Destination (Join-Path $tftp $bcdDestination) -Force
    }
    Invoke-Checked $dism @('/Unmount-Image',"/MountDir:$mount",'/Commit')
    $mounted = $false
    Copy-Item -LiteralPath $wim -Destination (Join-Path $tftp 'Boot\boot.wim') -Force
    $bootEx = ''
    if ($BootCA -eq '2023') { $bootEx = ' /bootex' }
    $isoPath = Join-Path $root 'DNW-WinPE.iso'
    $mediaCommand = 'call "{0}" && call "{1}" /ISO "{2}" "{3}"{4}' -f $adkEnv, $makeMedia, $work, $isoPath, $bootEx
    Invoke-Checked 'cmd.exe' @('/d','/c',$mediaCommand)
    Write-Host "WinPE criado: $isoPath e $tftp" -ForegroundColor Green
} finally {
    if ($mounted) { & $dism /Unmount-Image "/MountDir:$mount" /Discard | Out-Null }
}
