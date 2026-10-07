# Ambiente de monitoramento de redes com Zabbix

Documento de projeto do laboratório de gerência de redes. Descreve três notebooks na mesma rede, com o Zabbix Server instalado no Linux e o Zabbix Agent instalado em cada Windows. O passo a passo está no [README](README.md).

## Objetivo

Montar um laboratório em que um servidor Zabbix acompanhe a disponibilidade e o desempenho de **dois notebooks Windows**:

1. `WINDOWS-01`, coletado pelo Zabbix Agent.
2. `WINDOWS-02`, coletado pelo Zabbix Agent.

O servidor centraliza coleta, armazenamento, interface web, gráficos e alertas. Os Windows não executam o Zabbix Server; apenas expõem métricas.

O servidor roda no próprio Linux, na rede do Wi-Fi ou do cabo. O agente em cada Windows escuta na porta 10050 desse notebook. A coleta usa esses IPv4, sem rede interna de contêiner.

## Versão e plataforma

| Componente | Escolha |
| --- | --- |
| Máquinas | **1 Linux** e **2 Windows** na mesma rede local |
| Zabbix | **7.0 LTS**, pacotes oficiais |
| Banco de dados | **MySQL**, no Linux |
| Interface web | **Nginx + PHP**, porta 80 |
| Agente | **Zabbix Agent** 7.0, instalador MSI em cada Windows |

O Linux previsto é o Ubuntu 24.04. No Ubuntu 22.04 muda o pacote do repositório e o serviço `php8.1-fpm`, como está no README.

## Arquitetura

```text
                    +---------------------------+
                    |      zabbix-server        |
                    |         SERVIDOR          |
                    |                           |
                    |  Nginx + PHP  (porta 80)  |
                    |  Zabbix Server            |
                    |  MySQL                    |
                    +-------------+-------------+
                                  |
                         rede do laboratório
                                  |
              +-------------------+-------------------+
              |                                       |
   +----------v-----------+             +-------------v----------+
   |      WINDOWS-01      |             |      WINDOWS-02        |
   |                      |             |                        |
   |  Zabbix Agent        |             |  Zabbix Agent          |
   |  porta 10050/TCP     |             |  porta 10050/TCP       |
   +----------------------+             +------------------------+
```

Há três máquinas e somente dois alvos de monitoramento. O próprio servidor Zabbix não entra na contagem.

| Máquina | O que executa | Função |
| --- | --- | --- |
| `SERVIDOR` | MySQL, Zabbix Server, Nginx | Servidor, banco e interface web |
| `WINDOWS-01` | Zabbix Agent | Dispositivo 1 |
| `WINDOWS-02` | Zabbix Agent | Dispositivo 2 |

Os três notebooks ficam na mesma rede e respondem a ping a partir do Linux. O firewall de cada Windows libera `10050/TCP` e ICMP só a partir do IPv4 do servidor. No Linux, se o UFW estiver ativo, a porta `80/TCP` fica liberada para a interface.

## Como o monitoramento funciona

1. O Linux recebe os pacotes do Zabbix 7.0, o MySQL e o esquema do banco. O assistente da interface abre em `http://SERVIDOR`.
2. Cada Windows instala o Agent 7.0. O campo `Server` aceita só o IPv4 do Linux. O `Hostname` é único e igual ao nome do host na interface.
3. O operador entra em `http://SERVIDOR` (usuário `Admin`, senha inicial `zabbix`) e cadastra os dois hosts pelo IPv4 de cada Windows, com o template **Windows by Zabbix agent**.
4. O Zabbix Server abre uma conexão TCP em `WINDOWS:10050` e pede as métricas ao agente (modo passivo).
5. Os valores voltam ao servidor, são gravados no MySQL e aparecem em dashboards, gráficos e problemas.
6. Quando um limite é ultrapassado (máquina fora do ar, CPU alta, disco cheio), o Zabbix registra um problema na interface.

ICMP (ping) testa as **máquinas**. O ping sai do Linux para o IPv4 de cada Windows.

O `ServerActive` aponta para o mesmo IPv4 do Linux. A luz verde do **ZBX** na coluna Availability depende da coleta passiva: o servidor precisa alcançar a porta 10050.

## O que cada Windows expõe

Template: **Windows by Zabbix agent**.

| Área | Exemplos de métrica |
| --- | --- |
| Disponibilidade | agente no ar, ICMP ping |
| Processador | utilização de CPU |
| Memória | memória usada e disponível |
| Disco | espaço usado |
| Rede | tráfego de entrada e saída |
| Sistema | uptime, número de processos |

Configuração do agente, em `C:\Program Files\Zabbix Agent\zabbix_agentd.conf`:

- `Hostname` — igual ao nome do host na interface
- `Server` — IPv4 do Linux; só esse endereço consulta o agente
- `ListenPort=10050`
- `ServerActive` — IPv4 do Linux

## Portas e protocolos

| Origem | Destino | Porta | Protocolo | Uso |
| --- | --- | --- | --- | --- |
| Navegador | `SERVIDOR` | 80/TCP | HTTP | Interface web |
| Zabbix Server | MySQL no mesmo Linux | 3306/TCP | MySQL | Banco, só em localhost |
| `SERVIDOR` | cada Windows | 10050/TCP | Zabbix | Coleta do agente |
| `SERVIDOR` | cada Windows | — | ICMP | Disponibilidade da máquina |

O usuário do banco é `zabbix`, com a senha `zabbixlab`. O login da interface continua `Admin` / `zabbix`.

## O que instalar

### Nos três notebooks

- Endereço IPv4 pelo qual os outros notebooks do laboratório alcançam esta máquina
- Os três na mesma rede, com ping a partir do Linux

### `SERVIDOR` (Linux)

Pacotes do repositório oficial do Zabbix 7.0 e o MySQL:

| Pacote | Função |
| --- | --- |
| `zabbix-server-mysql` | Coleta e alertas |
| `zabbix-frontend-php` e `zabbix-nginx-conf` | Interface web na porta 80 |
| `zabbix-sql-scripts` | Esquema do banco |
| `zabbix-agent` | Agente local do Linux; não substitui os dois Windows |
| `zabbix-get` | Teste `zabbix_get` a partir do servidor |
| `mysql-server` | Banco `zabbix` |

`DBPassword=zabbixlab` em `/etc/zabbix/zabbix_server.conf`. Em `/etc/zabbix/nginx.conf`, `listen 80` e `server_name _`. O site padrão do Nginx sai de `sites-enabled` para não disputar a porta 80.

### Cada Windows

- Instalador MSI do Zabbix Agent 7.0, amd64, OpenSSL
- Serviço `Zabbix Agent` automático
- Firewall de entrada: TCP 10050 e ICMP echo só a partir do IPv4 do Linux

## Cadastro previsto na interface

| Host | Interface no Zabbix | Template |
| --- | --- | --- |
| o `Hostname` do primeiro Windows | Agente, IPv4 desse notebook, porta `10050` | Windows by Zabbix agent |
| o `Hostname` do segundo Windows | Agente, IPv4 desse notebook, porta `10050` | Windows by Zabbix agent |

Usar **IP**. O nome do host na interface é o mesmo `Hostname` gravado no agente.

## Alertas mínimos do laboratório

| Condição | Severidade |
| --- | --- |
| Máquina não responde ao ICMP | High |
| Agente indisponível | Average |
| Uso de CPU acima de 80% por 5 minutos | Warning |
| Disco do sistema acima de 85% | Warning |

A entrega de aviso por e-mail fica fora do escopo inicial. Os problemas aparecem em **Monitoring → Problems**.

Parar o serviço `Zabbix Agent` derruba a coleta e mantém o ping da máquina. Desligar o notebook derruba os dois.

## Critério de pronto

A instalação está concluída quando:

- os dois Windows respondem a ping a partir do Linux;
- `systemctl status zabbix-server nginx php8.3-fpm` mostra os serviços em execução no Linux;
- a interface abre em `http://SERVIDOR` e o login `Admin` / `zabbix` funciona;
- `zabbix_get -s WINDOWS-01 -k agent.ping` e o mesmo comando para `WINDOWS-02` devolvem `1`;
- os dois hosts aparecem com o quadradinho **ZBX** verde em **Data collection → Hosts**.

## Fora deste documento

O passo a passo está no [README](README.md).

Ainda não fazem parte do laboratório:

- Dashboards e mapas da topologia
- Notificação por e-mail, webhook ou Telegram
- Proxy Zabbix e alta disponibilidade
