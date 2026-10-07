# Laboratório Zabbix — gerência de redes

Três notebooks na mesma rede. O Zabbix Server fica instalado no Linux e usa a rede real dessa máquina. Cada Windows só roda o Zabbix Agent. Não há Docker nem máquina virtual. O desenho está em [ambiente-zabbix.md](ambiente-zabbix.md).

| Papel | Notebook | O que anotar |
| --- | --- | --- |
| `SERVIDOR` | Linux com Zabbix Server, MySQL e interface web | IPv4 do Wi-Fi ou do cabo |
| `WINDOWS-01` | primeiro Windows, com o Agent | IPv4 e o Hostname do agente |
| `WINDOWS-02` | segundo Windows, com o Agent | IPv4 e outro Hostname |

Interface: `http://SERVIDOR`  
Login inicial: `Admin` / `zabbix`

A senha do banco é `zabbixlab` (usuário `zabbix`). É senha de laboratório. O login da interface não usa essa senha.

## 1. Colocar os três na mesma rede

Ligue os três no mesmo Wi-Fi ou no mesmo switch. No Linux, antes de instalar:

```bash
ping WINDOWS-01
ping WINDOWS-02
```

Os dois precisam responder. Se o ping falhar, a coleta também falha. Roteador com isolamento de clientes (AP isolation) e vários hotspots de celular impedem um notebook de falar com o outro. Nesse caso use outra rede, um cabo, ou desligue o isolamento.

Anote o IPv4 de cada um. No Windows, PowerShell:

```powershell
ipconfig
```

Use o "Endereço IPv4" do adaptador Wi-Fi ou Ethernet. Ignore `127.0.0.1` e endereços `172.x` da interface vEthernet do Docker ou do WSL.

No Linux:

```bash
ip -4 addr show
```

Se o roteador mudar o IP depois, repita o `Server` do agente e o IP do host na interface. Um IP fixo, ou uma reserva DHCP no roteador, evita esse retrabalho.

## 2. Linux — instalar o Zabbix Server

Ubuntu 24.04. No Ubuntu 22.04, troque `ubuntu24.04` por `ubuntu22.04` no endereço do pacote e `php8.3-fpm` por `php8.1-fpm`.

```bash
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
sudo dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
sudo apt update
sudo apt install zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent zabbix-get mysql-server -y
```

Crie o banco. No `sudo mysql`, uma linha por vez:

```text
create database zabbix character set utf8mb4 collate utf8mb4_bin;
create user zabbix@localhost identified by 'zabbixlab';
grant all privileges on zabbix.* to zabbix@localhost;
set global log_bin_trust_function_creators = 1;
quit;
```

Importe o esquema. Pode levar cerca de um minuto:

```bash
sudo zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -pzabbixlab zabbix
sudo mysql -e "set global log_bin_trust_function_creators = 0;"
```

Em `/etc/zabbix/zabbix_server.conf`, descomente e preencha:

```text
DBPassword=zabbixlab
```

O pacote do Nginx deixa `listen` e `server_name` comentados em `/etc/zabbix/nginx.conf`. Sem isso a interface não abre. Deixe assim:

```text
listen 80;
server_name _;
```

O site padrão do Nginx também ocupa a porta 80. Remova esse site e suba os serviços:

```bash
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart zabbix-server zabbix-agent nginx php8.3-fpm
sudo systemctl enable zabbix-server zabbix-agent nginx php8.3-fpm
```

Se o UFW estiver ativo:

```bash
sudo ufw allow 80/tcp
```

No navegador, abra `http://SERVIDOR` e siga o assistente. No banco: host `localhost`, banco `zabbix`, usuário `zabbix`, senha `zabbixlab`. Depois entre com `Admin` / `zabbix`.

## 3. Cada Windows — instalar o Zabbix Agent

Repita esta seção nos dois notebooks. O Hostname de um não pode ser igual ao do outro. Anote o nome: ele entra igualzinho no host do Zabbix.

Baixe o Agent 7.0 LTS para Windows, amd64, com OpenSSL:

https://cdn.zabbix.com/zabbix/binaries/stable/7.0/latest/zabbix_agent-7.0-latest-windows-amd64-openssl.msi

PowerShell como administrador. Troque `SERVIDOR` pelo IPv4 do Linux e `NOME` pelo Hostname deste notebook (por exemplo `Windows-01` no primeiro e `Windows-02` no segundo):

```powershell
msiexec /i zabbix_agent-7.0-latest-windows-amd64-openssl.msi /qn SERVER=SERVIDOR LISTENPORT=10050 SERVERACTIVE=SERVIDOR HOSTNAME=NOME
New-NetFirewallRule -DisplayName "Zabbix Agent" -Direction Inbound -Protocol TCP -LocalPort 10050 -Action Allow -RemoteAddress SERVIDOR
New-NetFirewallRule -DisplayName "ICMP Zabbix" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -RemoteAddress SERVIDOR
Restart-Service "Zabbix Agent"
```

Na instalação pela janela do MSI, os mesmos campos são: Host name = `NOME`, Zabbix server IP/DNS = `SERVIDOR`, Agent listen port = `10050`, ServerActive = `SERVIDOR`.

O serviço fica em execução automática. A configuração fica em `C:\Program Files\Zabbix Agent\zabbix_agentd.conf`. Se o IP do Linux mudar, altere `Server` e `ServerActive` nesse arquivo e rode de novo `Restart-Service "Zabbix Agent"`.

Neste notebook o agente já está instalado: o Hostname é `BRENDA`, a porta é `10050` e o `Server` aceita a rede `10.0.0.0/24`. No Zabbix, o host dessa máquina usa esse nome e o IPv4 do Wi-Fi dela. Os outros Windows seguem o comando acima, cada um com o próprio Hostname.

Confira neste notebook:

```powershell
Get-Service "Zabbix Agent"
```

O status precisa ser `Running`.

## 4. Cadastrar os dois hosts

Na interface (`http://SERVIDOR`, `Admin` / `zabbix`), para cada Windows:

1. **Data collection** → **Hosts** → **Create host**.
2. **Host name:** o mesmo `NOME` do agente.
3. **Templates:** `Windows by Zabbix agent`.
4. **Host groups:** um grupo, por exemplo `Dispositivos`.
5. **Interfaces:** **Add** → **Agent**. Apague `127.0.0.1` e coloque o IPv4 deste Windows. Porta `10050`.
6. **Add**.

Em um ou dois minutos, o quadradinho **ZBX** na coluna Availability fica verde. CPU, memória, disco e rede passam a ser coletados. Repita com o segundo Hostname e o segundo IPv4.

## 5. Conferir a partir do Linux

```bash
zabbix_get -s WINDOWS-01 -k agent.ping
zabbix_get -s WINDOWS-02 -k agent.ping
```

A resposta esperada é `1`.

Os problemas de disponibilidade aparecem em **Monitoring → Problems**. Parar o serviço `Zabbix Agent` derruba a coleta e mantém o ping da máquina. Desligar o notebook derruba os dois.
