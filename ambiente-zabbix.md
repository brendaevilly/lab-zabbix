# Ambiente de monitoramento de redes com Zabbix

Documento de projeto do laboratório de gerência de redes. Descreve a arquitetura em três máquinas separadas, com Docker em cada uma, e o que precisa estar instalado antes da configuração do monitoramento.

## Objetivo

Montar um laboratório em que um servidor Zabbix acompanhe a disponibilidade e o desempenho de **dois dispositivos**, cada um em sua própria máquina:

1. Um host Linux, coletado pelo **Zabbix Agent 2**.
2. Um equipamento de rede, coletado por **SNMP**.

O servidor centraliza coleta, armazenamento, interface web, gráficos e alertas. Os dois dispositivos não executam o Zabbix Server; apenas expõem métricas.

O Zabbix, o banco, o agente e o SNMP rodam em contêineres. As máquinas continuam separadas: o servidor consulta os dispositivos pelo IP da rede do laboratório, não por uma rede interna do Docker.

## Versão e plataforma

| Componente | Escolha |
| --- | --- |
| Máquinas | **3 notebooks** na mesma rede local, cada um com Docker |
| Orquestração | **Docker** e **Docker Compose** v2 em cada máquina |
| Zabbix | **7.0 LTS**, imagens oficiais com tag `alpine-7.0-latest` |
| Banco de dados | **MariaDB 11** |
| Interface web | **Nginx + PHP**, imagem `zabbix-web-nginx-mysql` |
| Agente | **Zabbix Agent 2**, imagem `zabbix-agent2` |
| SNMP | **Net-SNMP** (`snmpd`) em imagem local baseada no Alpine |

As imagens do Zabbix vêm do Docker Hub (`zabbix/*`). A tag `alpine-7.0-latest` acompanha a linha 7.0 LTS sem saltar para a 7.4.

O sistema da máquina só hospeda o Docker. No notebook com Windows, isso é o Docker Desktop com contêineres Linux. No Ubuntu, Docker Engine. Os pacotes do Zabbix não são instalados no sistema.

## Arquitetura

```text
                    +---------------------------+
                    |      zabbix-server        |
                    |      192.168.56.10        |
                    |                           |
                    |  contêiner zabbix-web     |
                    |  contêiner zabbix-server  |
                    |  contêiner mysql          |
                    +-------------+-------------+
                                  |
                    rede do laboratório 192.168.56.0/24
                                  |
              +-------------------+-------------------+
              |                                       |
   +----------v-----------+             +-------------v----------+
   |      host-linux      |             |    dispositivo-rede    |
   |    192.168.56.20     |             |     192.168.56.30      |
   |                      |             |                        |
   |  contêiner Agent 2   |             |  contêiner snmpd       |
   |  porta 10050/TCP     |             |  porta 161/UDP         |
   +----------------------+             +------------------------+
```

Há três máquinas e somente dois alvos de monitoramento. O próprio servidor Zabbix não entra na contagem.

| Máquina | Endereço | Contêineres | Função |
| --- | --- | --- | --- |
| `zabbix-server` | `192.168.56.10` | `mysql`, `zabbix-server`, `zabbix-web` | Servidor, banco e interface web |
| `host-linux` | `192.168.56.20` | `zabbix-agent2` | Dispositivo 1 — agente |
| `dispositivo-rede` | `192.168.56.30` | `zabbix-lab-snmp` | Dispositivo 2 — SNMP |

Os endereços `192.168.56.0/24` são só o exemplo gravado nos arquivos. No laboratório, cada notebook usa o IPv4 do Wi-Fi ou do cabo. O passo a passo está em [README.md](README.md), na seção "Três notebooks".

Nos notebooks, três pontos deixam de usar o exemplo `192.168.56.x`:

| Arquivo | Ajuste |
| --- | --- |
| `agent/.env` | `ZABBIX_SERVER_IP` recebe o IPv4 do notebook do Zabbix |
| `snmp/snmpd.conf` | a origem da `rocommunity zabbixlab` passa a ser esse mesmo IPv4 |
| `cadastrar-hosts.sh` | `HOST_LINUX_IP` e `SNMP_IP` recebem o IPv4 dos outros dois notebooks |

Os três notebooks ficam na mesma rede e respondem a ping entre si. O firewall do notebook do agente libera `10050/TCP` e ICMP só a partir do Zabbix. O do SNMP libera `161/UDP` e ICMP da mesma origem. O do Zabbix libera `8080/TCP` para a interface. No Windows isso são regras de entrada do Firewall do Defender. No Ubuntu, regras do UFW.

Na máquina do servidor, `mysql`, `zabbix-server` e `zabbix-web` compartilham uma rede bridge local do Compose. Só a interface web sai para o host, na porta **8080**. O processo de coleta alcança os outros dois notebooks pelos IPs deles.

O segundo dispositivo é uma máquina com o daemon SNMP no papel de roteador ou switch. Um equipamento real com SNMP habilitado pode ocupar o mesmo endereço e a mesma comunidade, sem alterar o desenho do servidor.

## Como o monitoramento funciona

1. Cada notebook sobe os próprios contêineres. Na primeira execução do notebook do servidor, a imagem do Zabbix cria o esquema no MariaDB. Não há assistente de instalação no navegador.
2. O operador acessa `http://192.168.56.10:8080` (usuário `Admin`, senha inicial `zabbix`) e cadastra os dois hosts pelos IPs das máquinas.
3. O contêiner `zabbix-server` consulta cada máquina no intervalo definido (por padrão, 1 minuto para itens e 30 segundos para disponibilidade ICMP).
4. Na `host-linux`, o servidor abre uma conexão TCP em `192.168.56.20:10050` e pede as métricas ao Agent 2 (modo passivo). O Docker desse notebook publica a porta 10050 do contêiner no IP da máquina.
5. Na `dispositivo-rede`, o servidor envia requisições **SNMPv2c** para `192.168.56.30:161/UDP`, comunidade `zabbixlab`. A porta 161 do contêiner está publicada no IP da máquina.
6. Os valores voltam ao servidor, são gravados no MariaDB e aparecem em dashboards, gráficos e problemas.
7. Quando um limite é ultrapassado (máquina fora do ar, CPU alta, interface com erro), o Zabbix registra um problema na interface.

ICMP (ping) testa as **máquinas**, não o contêiner isolado. O ping vai para `192.168.56.20` e `192.168.56.30`. O contêiner do servidor precisa da capability `NET_RAW` para o `fping` emitir esses pacotes. Como o contêiner usa a rede bridge, o notebook faz SNAT e o dispositivo vê o IPv4 do notebook do Zabbix.

## O que cada dispositivo expõe

### Dispositivo 1 — `host-linux` (Zabbix Agent 2)

Template previsto: **Linux by Zabbix agent**.

O agente mede o contêiner publicado nessa máquina. CPU, memória e disco refletem o limite do contêiner. O ICMP mede a máquina `192.168.56.20`.

| Área | Exemplos de métrica |
| --- | --- |
| Disponibilidade | ICMP ping, perda de pacotes, tempo de resposta |
| Processador | utilização de CPU, carga média |
| Memória | memória usada, disponível e cache |
| Disco | espaço usado em `/` |
| Rede | tráfego de entrada e saída da interface do contêiner |
| Sistema | uptime, número de processos |

Variáveis do contêiner:

- `ZBX_HOSTNAME=host-linux` — igual ao nome do host na interface
- `ZBX_SERVER_HOST=192.168.56.10` — no laboratório, este valor é o IPv4 do notebook do servidor; só ele pode consultar o agente
- `ZBX_PASSIVE_ALLOW=true`

### Dispositivo 2 — `dispositivo-rede` (SNMP)

Template previsto: **Network Generic Device by SNMP**, com ICMP ping.

Não existe imagem oficial do Zabbix para esse papel. O laboratório constrói `zabbix-lab-snmp` a partir do Alpine, com o pacote `net-snmp` e um `snmpd.conf` montado no contêiner. Ele representa um roteador ou switch.

| Área | Exemplos de métrica |
| --- | --- |
| Disponibilidade | ICMP ping da máquina e reachability SNMP |
| Identidade | `sysName`, `sysDescr`, `sysUpTime` |
| Interfaces | estado operacional (up/down), velocidade |
| Tráfego | octetos de entrada e saída, erros e descartes |

Configuração do `snmpd`:

- escuta em UDP 1161 dentro do contêiner; o Compose publica essa porta como `161/UDP` no IP `192.168.56.30`
- comunidade de leitura `zabbixlab`
- origem permitida: `192.168.56.10`
- `sysLocation` e `sysContact` preenchidos para identificar o equipamento
- visão SNMP cobrindo a árvore do sistema (`.1.3.6.1.2.1`), suficiente para interfaces, tráfego e uptime

Essa máquina não recebe imagem do Zabbix Server nem do Agent 2.

## Portas e protocolos

| Origem | Destino | Porta | Protocolo | Uso |
| --- | --- | --- | --- | --- |
| Navegador do operador | `192.168.56.10` | 8080/TCP | HTTP | Interface web |
| `zabbix-web` | `zabbix-server` | 10051/TCP | Zabbix | API interna, só no notebook do servidor |
| `zabbix-server` | `mysql` | 3306/TCP | MySQL | Banco, só no notebook do servidor |
| `192.168.56.10` | `192.168.56.20` | 10050/TCP | Zabbix | Coleta do agente |
| `192.168.56.10` | `192.168.56.30` | 161/UDP | SNMP | Consulta SNMP |
| `192.168.56.10` | as duas máquinas | — | ICMP | Disponibilidade da máquina |
| Operador | as três máquinas | 22/TCP | SSH | Administração |

A porta **10051/TCP** fica interna ao notebook do servidor. Este laboratório usa coleta passiva: o servidor busca os dados e o agente não abre conexão de volta.

A comunidade SNMP de laboratório é `zabbixlab`, restrita ao endereço `192.168.56.10`. Não usar `public`.

## O que instalar

### Em todas as máquinas

- Docker em execução e `docker compose version` funcionando
- Endereço IPv4 pelo qual as outras máquinas do laboratório alcançam esta
- Nos notebooks, os três na mesma rede, com ping entre eles
- `openssh-server`, quando a administração for por SSH
- Resolução local em `/etc/hosts` com os três nomes, quando os testes não puderem depender de DNS externo

O Docker é o único meio de instalar Zabbix, MariaDB, o agente e o SNMP. Não usar os pacotes `zabbix-*` nem `snmpd` do apt, exceto o que a imagem local do SNMP embute no build.

Recursos mínimos sugeridos para os notebooks:

| Máquina | vCPU | Memória | Disco |
| --- | --- | --- | --- |
| `zabbix-server` | 2 | 4 GB | 20 GB |
| `host-linux` | 1 | 1 GB | 10 GB |
| `dispositivo-rede` | 1 | 1 GB | 10 GB |

O notebook do servidor pede mais memória porque concentra três contêineres, entre eles o MariaDB.

Firewall (UFW), se estiver ativo:

| Máquina | Liberar |
| --- | --- |
| `zabbix-server` | `22/tcp` e `8080/tcp`; ICMP de saída para a rede do laboratório |
| `host-linux` | `22/tcp`, `10050/tcp` só a partir de `192.168.56.10`, ICMP |
| `dispositivo-rede` | `22/tcp`, `161/udp` só a partir de `192.168.56.10`, ICMP |

### `zabbix-server` (192.168.56.10)

Um `compose.yaml` com três serviços:

| Serviço | Imagem | Publicação |
| --- | --- | --- |
| `mysql` | `mariadb:11` | nenhuma; só a rede interna do Compose |
| `zabbix-server` | `zabbix/zabbix-server-mysql:alpine-7.0-latest` | nenhuma; a coleta sai do notebook em direção aos outros |
| `zabbix-web` | `zabbix/zabbix-web-nginx-mysql:alpine-7.0-latest` | `8080:8080` |

Banco:

- banco `zabbix` e usuário `zabbix` pelas variáveis `MARIADB_DATABASE`, `MARIADB_USER` e `MARIADB_PASSWORD`
- `MARIADB_ROOT_PASSWORD` no `.env` desse notebook
- volume `mysql-data` para o histórico sobreviver a `docker compose down`

Servidor:

- `DB_SERVER_HOST=mysql` e as mesmas credenciais do banco
- na primeira subida, importa o esquema sozinho
- `cap_add: [NET_RAW]` para o ICMP até `192.168.56.20` e `192.168.56.30`
- `fping` e a biblioteca SNMP na imagem oficial; o comando `snmpget` não vem nessa imagem e o teste da comunidade usa um contêiner avulso com `net-snmp-tools`

Interface:

- `ZBX_SERVER_HOST=zabbix-server`
- `PHP_TZ=America/Sao_Paulo`
- o Nginx da imagem escuta em 8080, por isso a publicação é `8080:8080`

### `host-linux` (192.168.56.20)

Um Compose com um único serviço:

- imagem `zabbix/zabbix-agent2:alpine-7.0-latest`
- publicação `10050:10050` no IP da máquina
- `ZBX_HOSTNAME=host-linux`
- `ZBX_SERVER_HOST=192.168.56.10`

### `dispositivo-rede` (192.168.56.30)

Um Compose com um único serviço e um build local:

- imagem `zabbix-lab-snmp`, Alpine com `net-snmp`
- `snmp/Dockerfile` e `snmp/snmpd.conf` nessa máquina
- publicação `161:1161/udp` (o `snmpd` escuta em 1161; o notebook continua respondendo na porta 161)
- `snmpd` em primeiro plano

O `snmpd.conf` restringe a comunidade `zabbixlab` à origem `192.168.56.10`.

## Cadastro previsto na interface

Depois que as três máquinas estiverem no ar, a interface recebe dois hosts. Este documento só registra o que será cadastrado.

| Host | Interface no Zabbix | Template |
| --- | --- | --- |
| `host-linux` | Agente, IP `192.168.56.20`, porta `10050` | Linux by Zabbix agent |
| `dispositivo-rede` | SNMP, IP `192.168.56.30`, porta `161`, comunidade `zabbixlab` | Network Generic Device by SNMP |

Usar **IP**. O nome Docker de um contêiner não existe na rede entre os notebooks.

Os dois hosts também recebem o template **ICMP Ping**, apontando para o mesmo IP da máquina.

Grupos de hosts: `Laboratorio/Linux` e `Laboratorio/Rede`.

## Alertas mínimos do laboratório

| Condição | Severidade |
| --- | --- |
| Máquina não responde ao ICMP | High |
| Agente do `host-linux` indisponível | Average |
| SNMP do `dispositivo-rede` sem resposta | Average |
| Uso de CPU do `host-linux` acima de 80% por 5 minutos | Warning |
| Sistema de arquivos `/` acima de 85% | Warning |
| Interface de rede do dispositivo SNMP em down | High |

A entrega de aviso por e-mail fica fora do escopo inicial. Os problemas aparecem em **Monitoring → Problems**.

Desligar o notebook, ou só o contêiner (`docker compose stop` na máquina do dispositivo), provoca o alerta de indisponibilidade. Parar o contêiner derruba o agente ou o SNMP e mantém o ping da máquina. Desligar o notebook derruba os dois.

## Critério de pronto da instalação

A etapa de instalação (ainda não executada) estará concluída quando:

- os três notebooks responderem a ping a partir do notebook do Zabbix;
- `docker compose ps` no notebook do servidor mostrar `mysql`, `zabbix-server` e `zabbix-web` em execução;
- a interface abrir em `http://192.168.56.10:8080` e o login `Admin` / `zabbix` funcionar;
- no notebook do servidor, `docker compose exec zabbix-server zabbix_get -s 192.168.56.20 -k agent.ping` devolver `1`, trocando o IP pelo do notebook do agente;
- um `snmpget` SNMPv2c para `192.168.56.30`, comunidade `zabbixlab`, OID `1.3.6.1.2.1.1.5.0`, devolver o `sysName` `dispositivo-rede`.

## Fora deste documento

Os arquivos de subida e o passo a passo estão no [README](README.md): `server/compose.yaml`, `agent/compose.yaml`, `snmp/` e `server/cadastrar-hosts.sh`.

Ainda não fazem parte do laboratório:

- Dashboards e mapas da topologia
- Notificação por e-mail, webhook ou Telegram
- Proxy Zabbix, alta disponibilidade e SNMPv3

SNMPv2c é suficiente para a rede fechada dos três notebooks. Se o ambiente deixar de ser esse laboratório, a comunidade em texto claro deve ser trocada por SNMPv3.
