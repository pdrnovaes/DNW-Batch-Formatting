function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Abra o Windows PowerShell como administrador.'
    }
}
function Invoke-Checked {
    param([string]$FilePath, [string[]]$Arguments)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$FilePath terminou com codigo $LASTEXITCODE." }
}
function Write-Utf8 {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}
function Get-IPv4Value {
    param([string]$Address)
    $parsed = $null
    if ($Address -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -or -not [Net.IPAddress]::TryParse($Address, [ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or $parsed.ToString() -ne $Address) {
        throw "IPv4 invalido: $Address"
    }
    $bytes = $parsed.GetAddressBytes()
    return ([long]$bytes[0] * 16777216 + [long]$bytes[1] * 65536 + [long]$bytes[2] * 256 + $bytes[3])
}
function Get-DnwImageMetadata {
    param([Parameter(Mandatory)]$Image)
    # DISM fornece Build e Languages/DefaultLanguageIndex. Version e apenas texto formatado.
    if ($Image.EditionId -ne 'Professional' -or [int]$Image.Architecture -ne 9 -or [int]$Image.Build -lt 22000 -or [int]$Image.ImageIndex -lt 1) {
        throw 'A imagem selecionada precisa ser Windows 11 Pro x64 (Professional).'
    }
    $languages = @($Image.Languages)
    $languageIndex = [int]$Image.DefaultLanguageIndex
    if ($languageIndex -lt 0 -or $languageIndex -ge $languages.Count) { throw 'Indice de idioma DISM invalido.' }
    $uiLanguage = [string]$languages[$languageIndex]
    if ($uiLanguage -notmatch '^[a-z]{2}-[A-Za-z]{2}$') { throw 'Nao foi possivel detectar o idioma principal da imagem.' }
    return @{ImageIndex=[int]$Image.ImageIndex;ImageName=$Image.ImageName;EditionId=$Image.EditionId;UILanguage=$uiLanguage}
}
function Get-IPv4Subnet {
    param([string]$Address, [ValidateRange(1,30)][int]$PrefixLength)
    $value = Get-IPv4Value $Address
    $block = [long][math]::Pow(2,32-$PrefixLength)
    $base = [long]([math]::Floor($value / $block) * $block)
    $a = [math]::Floor($base / 16777216)
    $b = [math]::Floor(($base % 16777216) / 65536)
    $c = [math]::Floor(($base % 65536) / 256)
    $d = $base % 256
    return "$a.$b.$c.$d/$PrefixLength"
}
function New-TftpdConfiguration {
    param([string]$Root, [string]$ServerIP, [switch]$IsolatedNetwork)
    Get-IPv4Value $ServerIP | Out-Null
    $services = 1 # Apenas TFTP. O DHCP continua no equipamento atual da empresa.
    $pool = ''
    $poolSize = 0
    if ($IsolatedNetwork) {
        $services = 5 # TFTP + DHCP, somente quando solicitado explicitamente.
        $octets = $ServerIP.Split('.')
        $pool = "$($octets[0]).$($octets[1]).$($octets[2]).100"
        $poolSize = 15
    }
    return @"
[TFTPD32]
BaseDirectory=$Root\TFTP
TftpPort=69
LocalIP=$ServerIP
DHCP LocalIP=$ServerIP
Services=$services
SecurityLevel=3
VirtualRoot=1
Negociate=1
PXECompatibility=1
WinSize=4
Timeout=5
MaxRetransmit=6
Enable IPv4=1
Enable IPv6=0
Max Simultaneous Transfers=15
TftpLogFile=$Root\tftp.log
[DHCP]
IP_Pool=$pool
PoolSize=$poolSize
BootFile=bootmgfw.efi
Mask=255.255.255.0
Gateway=
DNS=
DNS2=
WINS=
DomainName=
AddOptionNumber=0
AddOptionValue=
AddOptionNumber1=0
AddOptionValue1=
Lease (minutes)=120
"@
}
function Assert-TftpdConfiguration {
    param([string]$Configuration, [switch]$IsolatedNetwork)
    $serviceLines = @([regex]::Matches($Configuration,'(?m)^Services=(\d+)\r?$'))
    $expected = 1
    if ($IsolatedNetwork) { $expected = 5 }
    if ($serviceLines.Count -ne 1 -or [int]$serviceLines[0].Groups[1].Value -ne $expected) {
        throw 'Servicos do Tftpd64 diferentes do modo preparado. Nao inicie DHCP na rede existente.'
    }
}
