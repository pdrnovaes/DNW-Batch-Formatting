[CmdletBinding()]
param([string]$IsoPath, [string]$OutputPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-WimInfo.ps1')
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not $IsoPath) {
    $folder = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ISO'
    $files = @(Get-ChildItem -LiteralPath $folder -Filter *.iso -File -ErrorAction SilentlyContinue)
    if ($files.Count -ne 1) { throw "Aguarde a ISO terminar em $folder ou informe -IsoPath." }
    $IsoPath = $files[0].FullName
}
$iso = (Resolve-Path -LiteralPath $IsoPath).Path
if ([IO.Path]::GetExtension($iso) -ne '.iso') { throw 'Somente ISO finalizada; nao use .crdownload ou arquivo parcial.' }
$mountedHere = $false
try {
    $diskImage = Get-DiskImage -ImagePath $iso
    if (-not $diskImage.Attached) { Mount-DiskImage -ImagePath $iso -Access ReadOnly | Out-Null; $mountedHere = $true }
    $volumes = @(Get-DiskImage -ImagePath $iso | Get-Volume | Where-Object DriveLetter)
    if ($volumes.Count -ne 1) { throw 'Volume da ISO nao identificado.' }
    $imageFile = "$($volumes[0].DriveLetter):\sources\install.wim"
    if (-not (Test-Path $imageFile)) { $imageFile = "$($volumes[0].DriveLetter):\sources\install.esd" }
    if (-not (Test-Path $imageFile)) { throw 'A ISO nao contem install.wim nem install.esd.' }
    $images = @(Read-WimInfo -ImagePath $imageFile)
    $report = [pscustomobject]@{IsoFile=[IO.Path]::GetFileName($iso);SizeBytes=(Get-Item -LiteralPath $iso).Length;Sha256=(Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash;Images=$images}
    if ($OutputPath) {
        $out = [IO.Path]::GetFullPath($OutputPath)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($out)) | Out-Null
        Write-Utf8 $out ($report | ConvertTo-Json -Depth 5)
    }
    Write-Output $report
} finally {
    if ($mountedHere) { Dismount-DiskImage -ImagePath $iso | Out-Null }
}
