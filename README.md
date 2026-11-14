# DNW — instalação de Windows em lote

Kit para instalar **Windows 11 Pro x64 limpo pela rede**, usando um **PC com Windows 11 comum** como servidor da bancada, sem comprar software de distribuição.

Entrega nos notebooks: uma conta local **`User`**, **senha vazia**, com permissão de administrador local. Português do Brasil e teclado ABNT2; a interface permanece no idioma disponível na ISO. Nenhum programa extra, agente de gerenciamento ou alteração de aplicativos do Windows é instalado. O nome do computador é gerado pelo Windows. A ativação fica para a conferência final, conforme a licença de cada equipamento.

**Estado: scripts preparados e verificados, ainda sem instalação completa de um notebook.** A pasta `ISO` foi encontrada vazia durante a preparação. O primeiro uso exige a ISO, o ADK/WinPE e um piloto com o hardware do escritório. Verificação de XML e sintaxe não substitui esse piloto.

## Como funciona

```text
PC Windows 11 da bancada, com ISO e Tftpd64
                    |
             switch isolado
          /         |         \
       notebook  notebook   notebook
          UEFI PXE IPv4 -> WinPE -> Windows Setup
```

O Tftpd64 entrega o boot e o endereço IP. O WinPE acessa uma pasta somente para leitura no servidor. O instalador usa os arquivos originais da ISO e um arquivo de respostas para configurar a conta `User`.

O técnico escolhe o disco e digita `APAGAR N` em cada notebook. A partir daí a instalação segue em paralelo. A confirmação se refere ao disco inteiro: partições, arquivos e recuperação de fábrica são apagados. O layout novo contém EFI, MSR, Windows e uma partição de recuperação.

**Começar com 1, depois 2 e depois 10 notebooks.** O kit limita o compartilhamento a 15 clientes e o pool DHCP a 15 endereços para deixar margem no Windows desktop. Um lote de 100 deve ser dividido. Esta versão não faz multicast e não promete 100 instalações simultâneas; o link do servidor é compartilhado entre os clientes.

## O que entra no Git

Scripts, modelo de respostas, testes e este roteiro. ISO, imagens WinPE, executáveis, credenciais, logs e licenças ficam fora. A ISO do Windows precisa estar disponível separadamente no escritório.

## Hoje: preparar os arquivos

1. Clone este repositório ou baixe seu ZIP. Leve a pasta ao escritório.
2. Salve a ISO oficial Windows 11 x64 em `Área de Trabalho\ISO`. Se a pasta tiver várias ISOs, informe `-IsoPath` no comando de preparação.
3. No PC que vai preparar a bancada, instale pela [página oficial do Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install):
   - **Windows ADK**, selecionando **Deployment Tools**.
   - **Windows PE Add-on** da mesma versão do ADK.
   - Escolha o ADK correspondente à versão do Windows na ISO, com as atualizações de manutenção indicadas pela Microsoft. Não use ADK antigo de Windows 10 para este kit.
4. Opcionalmente, já baixe a ferramenta TFTP, sem executar servidor algum:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-Tools.ps1
   ```

   O script usa Tftpd64 4.74 portátil do repositório oficial e verifica SHA-256 fixado a partir do release. O pacote fica em `.local\tools`, ignorado pelo Git. Essa pasta pode acompanhar o kit ao escritório. A preparação reutiliza o arquivo já baixado.

Não precisa instalar ADK nem configurar a rede do PC de casa se a preparação será feita no escritório. Sem ISO e ADK não é possível gerar o boot final.

Para conferir uma ISO finalizada sem preparar servidor ou formatar nada, execute `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Inspect-Iso.ps1`. O script monta somente a ISO em leitura, consulta metadados pela API nativa WIMGAPI e desmonta ao terminar. Não instala nem inicia o Windows contido nela.

## No escritório: montar a bancada

### 1. Separar a rede

Use **um switch sem uplink para o roteador, rede corporativa ou outro DHCP**. Conecte nele apenas a placa de rede da bancada e os notebooks a preparar. Internet não é necessária durante a instalação. Pode manter o servidor com internet por outra placa/Wi-Fi, sem bridge nem compartilhamento de internet entre as placas.

Neste roteiro, a placa da bancada usa:

| Campo | Valor |
|---|---|
| IPv4 do servidor | `192.168.50.1` |
| Máscara | `255.255.255.0` |
| Gateway e DNS | Em branco |
| Endereços dos notebooks | `192.168.50.100` a `192.168.50.114` |

Configure esse IPv4 manualmente nas propriedades da placa de rede do Windows. O script confere o endereço e a ausência de gateway, mas **não consegue detectar fisicamente se o switch está desconectado da rede corporativa**. Ele não muda o IP de nenhuma placa.

Este kit não configura PXE sobre o DHCP corporativo existente. Essa alternativa exige combinar os parâmetros de boot com quem administra a rede.

### 2. Preparar o servidor

Abra **Windows PowerShell de 64 bits como administrador**, entre na pasta do repositório e confira o nome da placa:

```powershell
Get-NetAdapter | Format-Table Name, Status, LinkSpeed
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Prepare-Office.ps1 -InterfaceAlias "Ethernet" -ServerIP 192.168.50.1 -IsolatedNetwork
```

Troque `Ethernet` pelo nome correto. `-IsolatedNetwork` declara que a placa está no switch separado. A pasta padrão de saída é `C:\DNWBatch`, que precisa ainda não existir. Deixe espaço para uma cópia dos arquivos da ISO e para a construção do WinPE; recomenda-se ao menos 30 GB livres.

O comando:

- Lê a ISO, identifica o índice **Windows 11 Pro** e confere edição/arquitetura. Não presume que Pro seja sempre o índice 6.
- Copia seus arquivos, monta um WinPE com PowerShell e suporte a rede/armazenamento e gera os arquivos de boot PXE e uma ISO de boot alternativa.
- Cria **apenas no servidor** a conta temporária `DNWDeploy`, sem poderes administrativos, com senha aleatória, para leitura da mídia por SMB. Essa senha é independente da conta `User` sem senha dos notebooks.
- Cria o compartilhamento `DNWDeploy`, somente para leitura da conta temporária, e regras de firewall vinculadas à placa/IP da bancada. Não desativa o firewall nem habilita SMB1 ou acesso de convidado.
- Prepara o Tftpd64, mas **não inicia o DHCP**.

Se a ISO tiver nome de imagem diferente, use o índice listado pelo próprio erro:

```powershell
.\scripts\Prepare-Office.ps1 -InterfaceAlias "Ethernet" -ServerIP 192.168.50.1 -IsolatedNetwork -IsoPath "$env:USERPROFILE\Desktop\ISO\Windows11.iso" -ImageIndex 6
```

O índice acima é só um exemplo. O script rejeita Home, Pro N, Enterprise, ARM64 e imagens que não sejam Windows 11 Pro x64.

Se houver drivers de rede/NVMe/VMD que o WinPE não reconheça, extraia o pacote **INF assinado do fabricante** e acrescente `-DriversPath "C:\DriversWinPE"`. O kit injeta esses drivers no WinPE; o Windows instalado ainda precisa ser conferido quanto aos drivers específicos do modelo.

### 3. Iniciar o PXE

```powershell
.\scripts\Start-Office.ps1 -IsolatedNetwork
```

Na janela do Tftpd64, confira em **Settings**, antes de conectar clientes:

- Base Directory: `C:\DNWBatch\TFTP`.
- Somente TFTP Server e DHCP Server ativos.
- TFTP e DHCP vinculados ao IP `192.168.50.1`. Escolher o IP no dropdown da tela principal não substitui o vínculo em Settings.
- Pool `192.168.50.100`, tamanho `15`, máscara `255.255.255.0`.
- Boot File `bootmgfw.efi`; gateway e DNS vazios.

O log TFTP mostra quais arquivos o firmware pediu. Se houver erro de BCD, verifique os pedidos no log: as cópias do BCD estão em `Boot\BCD`, `EFI\Microsoft\Boot\BCD` e na raiz. O kit usa boot manager UEFI nativo da Microsoft, sem serviço WDS.

### 4. Fazer o piloto

1. Conecte um notebook de teste à energia e à rede da bancada. Desconecte discos USB de dados.
2. Use o menu de boot único do fabricante (frequentemente F12) e escolha **UEFI Network / PXE IPv4**.
3. No WinPE, confira modelo, serial e capacidade do disco exibido. Digite seu número e depois `APAGAR N`, por exemplo `APAGAR 0`.
4. Deixe instalar. No reinício, deixe iniciar pelo **Windows Boot Manager do SSD**, sem selecionar PXE de novo.
5. Entre no `User` sem senha e confira: edição Pro, acesso local, drivers e Windows funcionando. Em um terminal elevado, confira `reagentc /info` para confirmar que a recuperação foi configurada. Verifique a ativação conforme o procedimento normal da empresa.
6. Repita em outro notebook/modelo antes de ampliar para 10. Se aparecer uma tela inesperada de conta/OOBE, pare a ampliação e valide o arquivo de respostas com aquela ISO.

A conta de entrega `User` é administradora local porque é a única conta criada para a preparação. Não há autologon configurado. O XML aceita os termos da mídia durante a instalação; cabe à operação usar a mídia/licenças autorizadas.

### Secure Boot e adaptadores

O boot padrão usa arquivos assinados para **Windows UEFI CA 2023**, do ADK recente. O firmware precisa confiar nessa CA. Não existe uma configuração única compatível com todos os estados de atualização/revogação de firmware. Se a frota ainda usa somente a CA 2011, uma construção separada com `-BootCA 2011 -BuildRoot C:\DNWBatch2011` pode ser necessária; máquinas que revogaram os arquivos antigos exigem os novos. Valide no piloto, seguindo a orientação da Microsoft sobre a mídia de boot. O kit não desativa Secure Boot nem burla TPM/CPU/RAM.

Adaptador USB para RJ-45 só consegue iniciar por PXE se o firmware do notebook suportar aquele adaptador. O driver do WinPE entra numa segunda etapa e não resolve a ausência de PXE no firmware.

Se PXE não funcionar em um modelo, o kit também gera `C:\DNWBatch\DNW-WinPE.iso`. Ela pode iniciar uma VM ou ser gravada em mídia USB por ferramenta apropriada. Esse USB contém o boot; o restante continua vindo pela rede. Ao gravar, selecione o pendrive correto, pois a gravação apaga seu conteúdo.

### Encerrar a bancada

Depois que todos os instaladores terminarem:

```powershell
.\scripts\Stop-Office.ps1
```

O comando fecha o processo Tftpd64 desta bancada, remove o compartilhamento, as regras DNW e a conta temporária. Não apaga os arquivos gerados nem altera o endereço da placa. Restaure a placa para DHCP nas propriedades do Windows se ela voltar ao uso normal.

O boot WinPE contém a credencial de leitura da bancada. Guarde seus arquivos como material interno; não publique `C:\DNWBatch` nem `.local` no Git. Encerrar a bancada revoga a conta. Para montar outra, use uma pasta nova. Se a preparação falhar depois de criar a pasta, `Stop-Office.ps1` também permite retirar os recursos já criados; uma imagem WIM que permaneça montada deve ser tratada pelo DISM antes de remover seus arquivos.

## Verificações de desenvolvimento

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Kit.ps1
```

Os testes verificam sintaxe e geração de XML, seleção explícita do disco, conta e senha solicitadas e rejeição de parâmetros inválidos. Não montam imagens, não configuram rede e não formatam discos. A ação GitHub roda o mesmo conjunto no Windows.

Faltam validações com a ISO e hardware reais: validação do XML pelo Windows SIM/Setup, boot UEFI/Secure Boot, acesso SMB, partições/WinRE, conta local após OOBE e desempenho em lote. O resultado dessas etapas determina a liberação do uso em produção.

## Fontes e ferramentas

- [Tftpd64 — projeto oficial e código aberto](https://pjo2.github.io/tftpd64/) e [release 4.74](https://github.com/PJO2/tftpd64/releases/tag/v4.74).
- [Microsoft — Windows ADK e Windows PE](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install).
- [Microsoft — criar e personalizar o WinPE](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-create-usb-bootable-drive?view=windows-11).
- [Microsoft — arquivos e BCD para PXE/WinPE](https://learn.microsoft.com/en-us/windows/deployment/configure-a-pxe-server-to-load-windows-pe). O exemplo dessa página é antigo e usa BIOS; este kit constrói BCD/loader UEFI com `winload.efi`.
- [Microsoft — arquivos de boot PXE e diferença entre bootmgfw/wdsmgfw](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/os-deployment/understand-pxe-boot).
- [Microsoft — automatizar a instalação](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup?view=windows-11) e [OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe?view=windows-11).
- [Microsoft — limite de conexões do Windows desktop](https://www.microsoft.com/licensing/terms/product/WindowsDesktopOperatingSystem/all).

O kit não exige comprar um servidor de implantação. As ferramentas externas e o Windows continuam sujeitos aos próprios termos de uso; nenhum instalador do Windows é distribuído neste repositório.
