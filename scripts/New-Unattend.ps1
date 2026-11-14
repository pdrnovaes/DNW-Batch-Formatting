[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$ImageIndex,
    [ValidatePattern('^[a-z]{2}-[A-Za-z]{2}$')][string]$UILanguage = 'pt-BR',
    [ValidateRange(0, 999)][int]$DiskNumber = 0,
    [long]$DiskSizeBytes = 0,
    [switch]$EraseSelectedDisk,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\templates\Unattend.xml') -Raw
$diskConfiguration = ''
$installTo = ''
if ($EraseSelectedDisk) {
    if ($DiskSizeBytes -lt 64000000000) { throw 'Informe o tamanho do disco confirmado (pelo menos 64 GB).' }
    # Reserva WinRE no fim do disco e uma margem para metadados/alinhamento GPT.
    $windowsSizeMiB = [long][math]::Floor($DiskSizeBytes / 1MB) - 260 - 16 - 1536 - 16
    $diskConfiguration = @"
<DiskConfiguration>
  <Disk wcm:action="add">
    <DiskID>$DiskNumber</DiskID><WillWipeDisk>true</WillWipeDisk>
    <CreatePartitions>
      <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>260</Size></CreatePartition>
      <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
      <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Size>$windowsSizeMiB</Size></CreatePartition>
      <CreatePartition wcm:action="add"><Order>4</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
    </CreatePartitions>
    <ModifyPartitions>
      <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
      <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
      <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>4</PartitionID><Format>NTFS</Format><Label>Recovery</Label><TypeID>DE94BBA4-06D1-4D40-A16A-BFD50179D6AC</TypeID></ModifyPartition>
    </ModifyPartitions>
  </Disk>
  <WillShowUI>OnError</WillShowUI>
</DiskConfiguration>
"@
    $installTo = "<InstallTo><DiskID>$DiskNumber</DiskID><PartitionID>3</PartitionID></InstallTo>"
}
$xmlText = $template.Replace('@@IMAGE_INDEX@@', [string]$ImageIndex).
    Replace('@@UI_LANGUAGE@@', $UILanguage).
    Replace('@@DISK_CONFIGURATION@@', $diskConfiguration).
    Replace('@@INSTALL_TO@@', $installTo)
[xml]$null = $xmlText
$fullPath = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($fullPath)) | Out-Null
[IO.File]::WriteAllText($fullPath, $xmlText, [Text.UTF8Encoding]::new($false))
Write-Output $fullPath
