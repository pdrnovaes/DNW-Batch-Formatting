# Retomada no PC do escritorio

O usuario preparou este kit em casa e vai abrir outro Codex no PC de bancada para terminar a configuracao. O repositorio e publico e ja pode ser baixado pelo [ZIP da branch main](https://github.com/pdrnovaes/dnw-batch-formatting/archive/refs/heads/main.zip).

## Resultado pretendido

Instalacoes simultaneas de Windows 11 Pro x64 pt-BR, original e limpo, com conta local `User` sem senha. Sem aplicativos adicionais. Usar cabos RJ-45; adaptadores USB de rede precisam ser compativeis com PXE no firmware. Ativacao/conferencia final por equipamento.

## Ambiente informado pelo usuario

- Windows 11 comum no PC que servira a midia temporariamente.
- Nao ha servidor fisico dedicado nem Windows Server.
- Infraestrutura de rede MikroTik e Ubiquiti, ligada a rede do escritorio. **Nao ha switch isolado.**
- Internet principal Onn Telecom de 1 Gbps com IP fixo; Starlink como secundaria. A instalacao usa a LAN, nao requer publicar o servidor no IP publico nem depende do link de internet para copiar a midia local.
- Ferramentas sem custo de licenca de distribuicao: Tftpd64 + WinPE/ADK + compartilhamento SMB.
- Comecar com 1, depois 2 e depois 10 clientes; este kit limita o compartilhamento a 15. Nao foi dimensionado/testado para 100 simultaneos no Windows desktop.

## O que ja foi feito

- Scripts e arquivo de respostas implementados; conta `User` com senha vazia e permissao administrativa local.
- Inspecao de ISO somente para leitura, sem necessidade de instalar a imagem.
- ISO pt-BR conferida em 14/11/2026: `Windows11_Client_x64_pt-br_26300_9457.iso`, Windows 11 Pro x64 **indice 4**, build 26300.9457. SHA-256 `D9AC87C1E9E47E0EB34EED443E5691C31781074E67608A51AEE50D7C7039F684`. O indice 6 desta ISO e Pro for Workstations, nao o Pro solicitado. Reinspecionar se o arquivo mudar; a origem/autenticidade nao foi comparada com um hash publicado pelo fornecedor.
- Download oficial do Tftpd64 4.74 com SHA-256 fixado. Sem executaveis no Git.
- Geracao de WinPE, BCD/boot UEFI, compartilhamento de leitura, regras de firewall vinculadas a placa/IP e encerramento da bancada.
- **Modo padrao atualizado para `ExistingDhcp`: somente TFTP, DHCP proprio desligado e pool vazio.** O inicio recusa INI que habilite DHCP nesse modo.
- O primeiro prototipo exigia switch isolado. Isso foi corrigido apos o usuario explicar a rede. Nao seguir instrucoes antigas com `-IsolatedNetwork` no escritorio.
- O PC de casa nao tinha ADK/WinPE e o processo do Codex nao estava elevado. **Nao foi construido/testado o boot final nem instalada uma maquina.**

## Informacoes a descobrir no local

1. Placa Ethernet do PC servidor, IP, prefixo/mascara, gateway e se o IP e estatico ou reservado.
2. Qual equipamento realmente fornece DHCP, modelo e versao. MikroTik esta presente, mas seu papel de DHCP **ainda nao foi confirmado**.
3. Se servidor e notebooks estao na mesma VLAN/sub-rede. As regras atuais do kit permitem somente a sub-rede da placa do servidor; se houver outra VLAN, ajustar escopo de firewall/roteamento e encaminhamento de boot conforme a topologia real.
4. Parametros de boot PXE ja existentes, eventual outro servidor PXE e o escopo que pode ser usado para estes notebooks.
5. Estado de confianca CA 2023/Secure Boot dos notebooks, drivers de rede/armazenamento e compatibilidade dos adaptadores.

Para inventario local inicial, sem alterar a rede:

```powershell
Get-NetAdapter | Format-Table Name, Status, LinkSpeed
Get-NetIPConfiguration
Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin
```

## Proximas etapas

1. Ler o `AGENTS.md`, confirmar os dados acima e verificar a ISO pt-BR em `Area de Trabalho\ISO`. Se houver mais de uma ISO, passar o caminho explicitamente.
2. Instalar Deployment Tools do Windows ADK e WinPE Add-on correspondentes a versao da midia, com as atualizacoes oficiais.
3. Reservar o IP do PC servidor no DHCP existente. Preservar gateway, DNS e configuracao da LAN.
4. Preparar o servidor com `Prepare-Office.ps1 -InterfaceAlias "NOME_REAL" -ServerIP IP_REAL -IsoPath "CAMINHO_REAL.iso"`, **sem `-IsolatedNetwork`**.
5. Definir o boot no DHCP atual para o escopo apropriado. O destino TFTP sera o IP reservado do PC e o bootfile UEFI x64 sera `bootmgfw.efi`. Descobrir a versao/topologia e preservar os valores anteriores para desfazer a alteracao ao encerrar. Nao aplicar comandos com enderecos de exemplo.
6. Abrir somente TFTP com `Start-Office.ps1`. Conferir `Services=1`, DHCP desmarcado e interface correta.
7. Fazer um piloto por UEFI PXE IPv4 com um notebook autorizado, selecionar e confirmar seu disco; no reinicio, iniciar pelo SSD.
8. Validar Windows Pro, idioma pt-BR, conta `User` sem senha, drivers, `reagentc /info`, ativacao quando aplicavel e ausencia de repeticao de formatacao no boot seguinte.
9. Somente depois ampliar para 2 e 10 equipamentos e observar o impacto no uso normal da LAN.
10. Encerrar o kit com `Stop-Office.ps1` e restaurar manualmente apenas os parametros temporarios de boot do DHCP que foram alterados. O script nao acessa o MikroTik e nao faz esse rollback sozinho.

No MikroTik, os parametros relevantes documentados sao `next-server` e `boot-file-name` em `/ip/dhcp-server/network`. Isso e uma referencia para investigacao; **nao e evidencia de que esse seja o DHCP desta rede nem uma instrucao para mudar todos os escopos**. Consulte a [documentacao oficial](https://manual.mikrotik.com/docs/network-management/dhcp/server/) da versao local antes de preparar a mudanca.

## Limites atuais

Nao ha teste completo de instalacao, validacao Windows SIM nem medicao de desempenho em lote. O modo de rede existente foi testado quanto a configuracao gerada e bloqueio de DHCP proprio, sem executar servicos na LAN. Nao afirmar que esta pronto para producao ate concluir o piloto.

Credenciais geradas da conta de leitura ficam dentro do WinPE. Tratar o diretorio `C:\DNWBatch` como material interno e remover a conta temporaria ao encerrar. Esse diretorio, ISOs e relatórios locais nao entram no repositorio publico.
