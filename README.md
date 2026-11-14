<p align="center">
  <img src="assets/dial-logo.png" alt="Dial Network" width="360">
</p>

# DNW - Batch Formatting (Formatação em lote)

**[⬇ Baixar o kit completo em ZIP](https://github.com/pdrnovaes/DNW-Batch-Formatting/archive/refs/heads/main.zip)** · [Abrir o repositório](https://github.com/pdrnovaes/DNW-Batch-Formatting)

Kit para instalar Windows 11 Pro x64 pt-BR limpo, com conta local **`User` sem senha**, em vários notebooks em paralelo. Usa um PC **Windows 11 comum** temporariamente como servidor, Tftpd64 e WinPE/ADK. Não exige comprar uma ferramenta de distribuição. As licenças de Windows continuam sendo individuais conforme o procedimento da empresa.

**Para continuar com outro Codex no escritório: abra esta pasta e peça para ler [CONTINUAR-NO-ESCRITORIO.md](CONTINUAR-NO-ESCRITORIO.md).** O arquivo `AGENTS.md` já registra as decisões, o ambiente e o que falta validar.

## Rede usada no escritório

Foi confirmada infraestrutura **MikroTik/Ubiquiti ligada à LAN existente**, sem switch isolado. Ainda falta identificar onde está o DHCP e quais são os IPs, máscaras e VLANs reais.

```text
Rede existente do escritório (MikroTik / Ubiquiti)
              |
       switches existentes
        /             \
PC Windows 11       notebooks
TFTP + SMB          UEFI PXE IPv4 -> WinPE -> Windows Setup
```

**O DHCP atual continua distribuindo os IPs.** O PC da bancada fornece arquivos de boot por TFTP e a mídia por SMB. O padrão do kit é `ExistingDhcp`, com **somente TFTP ativo e DHCP próprio desligado**. Não use `-IsolatedNetwork` nessa LAN.

Antes do piloto, a TI precisa identificar/configurar o boot no DHCP atual: destino TFTP = IP reservado do PC da bancada; arquivo de boot = `bootmgfw.efi` para UEFI x64. O kit não acessa nem altera automaticamente MikroTik, Ubiquiti ou o DHCP da empresa. Se houver outras VLANs, é necessário conferir roteamento, encaminhamento de boot e escopo de firewall; a configuração gerada permite somente a sub-rede da placa do servidor.

## Estado atual

- ISO pt-BR conferida: `Windows11_Client_x64_pt-br_26300_9457.iso`, build **26300.9457**, Windows 11 Pro x64 no **índice 4**. O kit detecta o índice novamente ao preparar a mídia.
- SHA-256 do arquivo conferido: `D9AC87C1E9E47E0EB34EED443E5691C31781074E67608A51AEE50D7C7039F684`. Identifica o arquivo local; não substitui a comparação com hash oficial nem comprova sua origem.
- Scripts, geração do XML e bloqueio de DHCP próprio no modo LAN verificados localmente. CI executa os mesmos testes no Windows.
- **Ainda não houve construção completa do WinPE nem instalação de um notebook.** Falta ADK/WinPE no servidor, configuração do boot no DHCP e piloto com hardware real.

## Preparar no PC do escritório

1. Baixar e extrair o ZIP. A ISO não vem nele: colocá-la separadamente em `Área de Trabalho\ISO`.
2. Abrir o Codex nesta pasta e seguir o arquivo de retomada para descobrir placa, IP, máscara, DHCP e VLANs. Reservar o IP do servidor no DHCP existente, preservando gateway e DNS.
3. Instalar pela [página oficial da Microsoft](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) o Windows ADK com **Deployment Tools** e o **Windows PE Add-on** correspondente à mídia, com as atualizações indicadas pelo fabricante.
4. Abrir Windows PowerShell de 64 bits como administrador. Executar os comandos abaixo com os valores reais.

```powershell
Get-NetAdapter | Format-Table Name, Status, LinkSpeed
Get-NetIPConfiguration
Set-ExecutionPolicy -Scope Process Bypass
```

Preparação: o exemplo usa uma variável que deve ser preenchida com o endereço real e reservado da placa. O script não atribui nem muda endereços IP.

```powershell
$ipServidor = Read-Host 'IP reservado do PC da bancada'
.\scripts\Prepare-Office.ps1 -InterfaceAlias 'Ethernet' -ServerIP $ipServidor -IsoPath "$env:USERPROFILE\Desktop\ISO\Windows11_Client_x64_pt-br_26300_9457.iso"
```

Troque `Ethernet` pelo nome correto da placa. Se o Desktop estiver redirecionado ou o nome da ISO mudar, ajuste `-IsoPath`. Se houver exatamente uma ISO na pasta Desktop\ISO, pode omitir esse parâmetro. **Não fixe o índice 6:** na mídia pt-BR conferida ele é Pro for Workstations. O script escolhe Pro e rejeita outras edições.

A saída padrão é `C:\DNWBatch`, que precisa não existir antes da preparação. Recomenda-se ao menos 30 GB livres. Se precisar de drivers para rede/NVMe/VMD, extraia os arquivos INF assinados do fabricante e acrescente `-DriversPath 'C:\DriversWinPE'`.

A preparação copia a mídia, constrói o WinPE, gera boot UEFI e uma ISO alternativa, cria a conta temporária **não administrativa** `DNWDeploy` no servidor e um compartilhamento somente para leitura. Essa conta tem senha aleatória e é diferente do `User` sem senha entregue nos notebooks. As regras de firewall são vinculadas à placa/IP e à sub-rede local. O firewall não é desativado, e SMB1/acesso de convidado não são habilitados.

Após conferir o boot no DHCP atual, iniciar:

```powershell
.\scripts\Start-Office.ps1
```

Na janela do Tftpd64, conferir:

- Base Directory: `C:\DNWBatch\TFTP`.
- **Somente TFTP Server ativo. DHCP Server desmarcado.** O INI deve conter `Services=1` e pool vazio.
- TFTP vinculado ao IP do PC em Settings. O dropdown de interface da tela principal não substitui esse vínculo.

Não publicar TFTP/SMB na internet nem criar redirecionamento de portas no IP público. Os arquivos são distribuídos na LAN.

## Piloto e operação em lote

1. Conectar um notebook autorizado à energia e ao cabo da rede. Remover discos USB de dados.
2. Selecionar **UEFI PXE IPv4** no menu de boot único do fabricante.
3. Conferir modelo, serial e capacidade do disco. Informar seu número e digitar `APAGAR N`, por exemplo `APAGAR 0`.
4. A instalação limpa segue automaticamente. A confirmação apaga o disco inteiro, incluindo arquivos e partições de recuperação de fábrica. O novo layout contém EFI, MSR, Windows e recuperação.
5. No reinício, deixar iniciar pelo Windows Boot Manager do SSD. Não selecionar PXE de novo.
6. Conferir edição Pro, idioma pt-BR, entrada no `User` sem senha, drivers e funcionamento. Em terminal elevado, conferir `reagentc /info`. Ativação conforme a licença do equipamento.
7. Repetir com 2 notebooks e depois ampliar para 10, observando o uso normal da LAN.

A conta de entrega `User` é administradora local porque é a única conta de preparação. Não há autologon configurado. Nenhum programa adicional, agente, remoção de aplicativos ou bypass de requisitos de hardware é aplicado. O XML aceita os termos da mídia durante a instalação; cabe à operação usar mídia e licenças autorizadas.

O compartilhamento e os arquivos de boot foram configurados para até **15 clientes**. Esta versão não usa multicast e não foi dimensionada/testada para 100 simultâneos no Windows desktop: dividir o volume total em lotes.

## Secure Boot, drivers e alternativa USB

O boot padrão usa Windows UEFI CA 2023, do ADK recente. O firmware precisa confiar nessa CA. Para frota ainda compatível apenas com CA 2011, uma construção separada com `-BootCA 2011 -BuildRoot C:\DNWBatch2011` pode ser necessária. Máquinas que revogaram os arquivos antigos exigem os novos. Validar conforme a orientação da Microsoft; o kit não desativa Secure Boot.

Adaptador USB para RJ-45 precisa ter suporte de PXE pelo firmware do notebook. Injetar seu driver no WinPE não resolve a falta desse suporte na primeira etapa do boot.

A construção também gera `C:\DNWBatch\DNW-WinPE.iso`: pode iniciar uma VM ou ser gravada em pendrive por ferramenta apropriada. Nesse caso, o USB inicia o ambiente e a instalação continua vindo pela rede. A gravação apaga o pendrive escolhido. Drivers específicos do Windows instalado precisam ser conferidos no piloto, mesmo que o WinPE tenha rede e disco funcionando.

## Encerrar

Depois que todos os instaladores terminarem:

```powershell
.\scripts\Stop-Office.ps1
```

O comando fecha o Tftpd64 desta bancada, remove o compartilhamento, a conta temporária e as regras DNW. Não remove os arquivos, não muda o IP e **não restaura parâmetros de boot no DHCP externo**: a TI deve desfazer somente as alterações temporárias feitas no roteador, usando o registro dos valores anteriores.

O WinPE contém a credencial de leitura da bancada. Guardar `C:\DNWBatch` como material interno. A remoção da conta temporária revoga esse acesso. Para reconstruir, usar uma pasta nova; imagens WIM que permaneçam montadas após falha exigem tratamento pelo DISM antes de remover seus arquivos.

## Verificações e arquivos

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Kit.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Inspect-Iso.ps1 -IsoPath 'CAMINHO_DA_ISO'
```

O primeiro comando verifica sintaxe, geração de XML, seleção de disco, edição/idioma e configuração LAN sem DHCP próprio. Não formata discos nem configura rede. O segundo monta somente a ISO em leitura, consulta os metadados pela API WIMGAPI e a desmonta ao terminar.

O Git contém código, modelo e documentação. ISO, WIM, executáveis, credenciais, relatórios locais e arquivos de execução ficam fora. O script `Get-Tools.ps1` baixa o Tftpd64 4.74 portátil oficial e confere SHA-256; pode ser executado antes para deixar a ferramenta em `.local\tools`.

## Referências

- [Tftpd64 oficial](https://pjo2.github.io/tftpd64/) e [release 4.74](https://github.com/PJO2/tftpd64/releases/tag/v4.74).
- [Microsoft — Windows ADK/WinPE](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install), [criar WinPE](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-create-usb-bootable-drive?view=windows-11) e [arquivos PXE](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/os-deployment/understand-pxe-boot).
- [Microsoft — automatizar Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup?view=windows-11) e [OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe?view=windows-11).
- [MikroTik — DHCP Server](https://manual.mikrotik.com/docs/network-management/dhcp/server/).
- [Microsoft — conexões do Windows desktop](https://www.microsoft.com/licensing/terms/product/WindowsDesktopOperatingSystem/all).
