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
