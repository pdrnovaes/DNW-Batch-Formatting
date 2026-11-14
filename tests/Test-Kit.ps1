# Validacao sem montar ISO, abrir firewall, criar contas ou tocar discos fisicos.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$testRoot = Join-Path $repo ('.local\test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$count = 0
function Assert-True([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
    $script:count++
}
$files = @(Get-ChildItem -LiteralPath $repo -Recurse -Filter *.ps1 -File | Where-Object { $_.FullName -notlike '*\.local\*' })
foreach ($file in $files) {
    $parseErrors = $null; $tokens = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert-True (-not $parseErrors) "Erro de sintaxe em $($file.Name): $parseErrors"
}
$generator = Join-Path $repo 'scripts\New-Unattend.ps1'
$manual = Join-Path $testRoot 'manual.xml'
& $generator -ImageIndex 6 -OutputPath $manual | Out-Null
[xml]$xml = Get-Content -LiteralPath $manual -Raw
$ns = [Xml.XmlNamespaceManager]::new($xml.NameTable)
$ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
Assert-True ($xml.SelectNodes('//u:DiskConfiguration', $ns).Count -eq 0) 'Perfil manual nao pode apagar/selecionar discos.'
Assert-True ($xml.SelectNodes('//u:InstallTo', $ns).Count -eq 0) 'Perfil manual nao pode selecionar particao.'
Assert-True ($xml.SelectSingleNode('//u:LocalAccount/u:Name', $ns).InnerText -ceq 'User') 'A conta deve ser User.'
Assert-True ($xml.SelectNodes('//u:LocalAccount', $ns).Count -eq 1) 'Deve haver uma unica conta de entrega.'
Assert-True ($xml.SelectSingleNode('//u:LocalAccount/u:Password/u:Value', $ns).InnerText -eq '') 'A senha precisa estar vazia.'
Assert-True ($xml.SelectNodes('//u:AutoLogon|//u:RunSynchronousCommand|//u:FirstLogonCommands', $ns).Count -eq 0) 'Nao deve haver autologon nem comandos adicionais na imagem.'
Assert-True ($xml.SelectSingleNode('//u:MetaData/u:Value', $ns).InnerText -eq '6') 'Indice de imagem incorreto.'
$erase = Join-Path $testRoot 'erase.xml'
& $generator -ImageIndex 3 -UILanguage en-US -DiskNumber 2 -DiskSizeBytes 256GB -EraseSelectedDisk -OutputPath $erase | Out-Null
[xml]$xml = Get-Content -LiteralPath $erase -Raw
Assert-True ($xml.SelectSingleNode('//u:Disk/u:DiskID', $ns).InnerText -eq '2') 'Limpeza precisa usar o disco confirmado.'
Assert-True ($xml.SelectSingleNode('//u:InstallTo/u:DiskID', $ns).InnerText -eq '2') 'Instalacao precisa usar o mesmo disco confirmado.'
Assert-True ($xml.SelectSingleNode('//u:Disk/u:WillWipeDisk', $ns).InnerText -eq 'true') 'Perfil confirmado deve limpar o disco.'
Assert-True ($xml.SelectNodes('//u:CreatePartition', $ns).Count -eq 4) 'EFI, MSR, Windows e WinRE devem existir.'
Assert-True ($xml.SelectSingleNode('//u:MetaData/u:Value', $ns).InnerText -eq '3') 'Indice deve acompanhar a ISO, sem fixar Pro em indice 6.'
Assert-True ($xml.SelectSingleNode('//u:SetupUILanguage/u:UILanguage', $ns).InnerText -eq 'en-US') 'Idioma da ISO deve ser respeitado.'
Assert-True (-not ((Get-Content $erase -Raw) -match '@@[A-Z_]+@@')) 'Nao pode restar marcador no XML gerado.'
$rejected = $false
try { & $generator -ImageIndex 6 -EraseSelectedDisk -DiskSizeBytes 32GB -OutputPath (Join-Path $testRoot 'invalid.xml') | Out-Null } catch { $rejected = $true }
Assert-True $rejected 'Disco pequeno/nao informado deve ser rejeitado antes de gerar perfil destrutivo.'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $testRoot 'invalid.xml'))) 'Perfil destrutivo invalido nao deve ser gravado.'
. (Join-Path $repo 'scripts\Common.ps1')
Assert-True ((Get-IPv4Value '192.168.50.1') -eq 3232248321) 'IPv4 valido deve ser interpretado.'
$rejected = $false
try { Get-IPv4Value '192.168.50.999' | Out-Null } catch { $rejected = $true }
Assert-True $rejected 'IPv4 invalido deve ser rejeitado.'
$rejected = $false
try { Get-IPv4Value '127.1' | Out-Null } catch { $rejected = $true }
Assert-True $rejected 'IPv4 abreviado nao pode virar configuracao de DHCP.'
$dismImage = [pscustomobject]@{ImageIndex=6;ImageName='Windows 11 Pro';EditionId='Professional';Architecture=9;Build=26100;Version='10.0.26100.1';Languages=@('en-US','pt-BR');DefaultLanguageIndex=1}
$metadata = Get-DnwImageMetadata -Image $dismImage
Assert-True ($metadata.UILanguage -eq 'pt-BR') 'Usar idioma padrao pelo indice fornecido pelo DISM.'
Assert-True ($metadata.ImageIndex -eq 6) 'Preservar indice da imagem DISM.'
foreach ($edition in @('Core','ProfessionalN','Enterprise')) {
    $dismImage.EditionId = $edition
    $rejected = $false
    try { Get-DnwImageMetadata -Image $dismImage | Out-Null } catch { $rejected = $true }
    Assert-True $rejected "A edicao $edition deve ser rejeitada."
}
$dismImage.EditionId = 'Professional'
$dismImage.Architecture = 12
$rejected = $false
try { Get-DnwImageMetadata -Image $dismImage | Out-Null } catch { $rejected = $true }
Assert-True $rejected 'ISO ARM64 deve ser rejeitada por este kit x64.'
Assert-True ((Get-IPv4Subnet '10.25.7.200' 22) -eq '10.25.4.0/22') 'Calcular a sub-rede real, sem presumir /24.'
Assert-True ((Get-IPv4Subnet '192.168.50.150' 24) -eq '192.168.50.0/24') 'Aceitar IP reservado com final acima de 99 na LAN.'
$lanConfig = New-TftpdConfiguration -Root 'C:\Test' -ServerIP '10.25.7.200'
Assert-TftpdConfiguration -Configuration $lanConfig
Assert-True ($lanConfig -match '(?m)^Services=1\r?$') 'Na rede existente, habilitar somente TFTP.'
Assert-True ($lanConfig -match '(?m)^PoolSize=0\r?$') 'Na rede existente, nao definir pool DHCP.'
$rejected = $false
try { Assert-TftpdConfiguration -Configuration ($lanConfig.Replace('Services=1','Services=5')) } catch { $rejected=$true }
Assert-True $rejected 'Recusar inicio na LAN se o INI foi alterado para ligar DHCP.'
$isolatedConfig = New-TftpdConfiguration -Root 'C:\Test' -ServerIP '192.168.50.1' -IsolatedNetwork
Assert-TftpdConfiguration -Configuration $isolatedConfig -IsolatedNetwork
Assert-True ($isolatedConfig -match '(?m)^Services=5\r?$') 'DHCP proprio apenas no modo isolado explicito.'
Write-Host "$count verificacoes passaram. Nenhuma instalacao real foi executada." -ForegroundColor Green
