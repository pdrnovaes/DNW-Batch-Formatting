# Contexto para o Codex do escritorio

Leia primeiro `CONTINUAR-NO-ESCRITORIO.md` e depois `README.md`.

## Escopo confirmado pelo usuario

- Instalar Windows 11 Pro x64 limpo em varios notebooks em paralelo pela rede.
- Conta local `User`, senha vazia, sem programas adicionais. A conta unica de preparacao e administradora local, como documentado no kit.
- Usar ISO pt-BR. Nao distribuir ISO, WIM, chaves, credenciais ou arquivos gerados no Git.
- PC de bancada Windows 11 comum, temporariamente como servidor. Sem Windows Server ou servidor fisico dedicado.
- Rede existente com MikroTik e infraestrutura Ubiquiti. **Nao existe switch isolado.**
- Nao comprar licenca de ferramenta de distribuicao. Nao usar iVentoy Free para operacao comercial.
- Repositorio publico por solicitacao explicita: https://github.com/pdrnovaes/DNW-Batch-Formatting
- O usuario vai abrir o Codex no PC do escritorio para finalizar a configuracao local.
- Escopo adicional confirmado: pendrive offline com menu grafico Dial, instalacao rapida/tradicional, User sem senha, para desktops montados e notebooks sem filtro de marca/modelo. Ler `docs/PENDRIVE-GRAFICO.md`. O modo de rede continua separado e usa DHCP existente.
- O menu USB nao inicia formatacao automaticamente no boot; a opcao rapida exige escolher o disco e confirmar graficamente. Nao reintroduzir a antiga restricao ThinkPad E14 nem a antiga inicializacao automatica do pendrive.

## Cuidados que decorrem da implementacao

- `Prepare-Office.ps1` sem `-IsolatedNetwork` usa o DHCP existente e prepara somente TFTP. Esse e o modo destinado ao escritorio.
- Nao habilitar DHCP do Tftpd64 na LAN da empresa. Nao presumir IP, mascara, VLAN ou que o DHCP esteja no MikroTik: descobrir os valores reais.
- Nao trocar o IP/gateway da placa para o exemplo de rede isolada. Reservar o endereco do servidor no DHCP atual ou usar o endereco estatico autorizado pela TI.
- Nao executar scripts de formatacao no PC servidor. `winpe/Start-Deploy.ps1` so roda no WinPE e exige selecionar e confirmar o disco do notebook.
- Nao modificar escopos DHCP de outras redes nem criar NAT/exposicao dos servicos na internet. Identificar o escopo de boot antes de mudar parametros do roteador.
- Scripts passaram verificacoes locais/CI. Isso nao comprova boot PXE, OOBE ou instalacao completa. Concluir o piloto antes de ampliar o lote.
- Use `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Kit.ps1` ao alterar scripts.

Continue o trabalho autorizado usando o contexto acima; colete no escritorio somente as informacoes que ainda faltarem.
