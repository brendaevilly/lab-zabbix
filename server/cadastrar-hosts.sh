#!/bin/bash
# Cadastra os dois hosts do laboratório na API do Zabbix.
# Executar no notebook zabbix-server, dentro do diretório server/, com a stack no ar.
set -euo pipefail

cd "$(dirname "$0")"

HOST_LINUX_IP="${HOST_LINUX_IP:-192.168.56.20}"
SNMP_IP="${SNMP_IP:-192.168.56.30}"
SNMP_COMMUNITY="${SNMP_COMMUNITY:-zabbixlab}"
ZABBIX_ADMIN_USER="${ZABBIX_ADMIN_USER:-Admin}"
ZABBIX_ADMIN_PASSWORD="${ZABBIX_ADMIN_PASSWORD:-zabbix}"

docker compose exec -T \
  -e HOST_LINUX_IP="$HOST_LINUX_IP" \
  -e SNMP_IP="$SNMP_IP" \
  -e SNMP_COMMUNITY="$SNMP_COMMUNITY" \
  -e ZABBIX_ADMIN_USER="$ZABBIX_ADMIN_USER" \
  -e ZABBIX_ADMIN_PASSWORD="$ZABBIX_ADMIN_PASSWORD" \
  zabbix-server bash -s <<'SCRIPT'
set -euo pipefail

api() {
  local args=(-sS -H "Content-Type: application/json-rpc" --data-binary @-)
  if [[ -n "${TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${TOKEN}")
  fi
  curl "${args[@]}" http://zabbix-web:8080/api_jsonrpc.php
}

fail_if_error() {
  local response="$1"
  local message
  message=$(jq -r '.error.data // .error.message // empty' <<<"$response")
  if [[ -n "$message" ]]; then
    echo "API do Zabbix recusou a chamada: $message" >&2
    echo "$response" >&2
    exit 1
  fi
}

login=$(api <<EOF
{"jsonrpc":"2.0","method":"user.login","params":{"username":"${ZABBIX_ADMIN_USER}","password":"${ZABBIX_ADMIN_PASSWORD}"},"id":1}
EOF
)
fail_if_error "$login"
TOKEN=$(jq -r '.result' <<<"$login")

template_id() {
  local name="$1"
  local response
  response=$(api <<EOF
{"jsonrpc":"2.0","method":"template.get","params":{"filter":{"host":["${name}"]},"output":["templateid"]},"id":1}
EOF
)
  fail_if_error "$response"
  local id
  id=$(jq -r '.result[0].templateid // empty' <<<"$response")
  if [[ -z "$id" ]]; then
    echo "Template não encontrado: $name" >&2
    exit 1
  fi
  echo "$id"
}

group_id() {
  local name="$1"
  local response
  response=$(api <<EOF
{"jsonrpc":"2.0","method":"hostgroup.get","params":{"filter":{"name":["${name}"]},"output":["groupid"]},"id":1}
EOF
)
  fail_if_error "$response"
  local id
  id=$(jq -r '.result[0].groupid // empty' <<<"$response")
  if [[ -n "$id" ]]; then
    echo "$id"
    return
  fi
  response=$(api <<EOF
{"jsonrpc":"2.0","method":"hostgroup.create","params":{"name":"${name}"},"id":1}
EOF
)
  fail_if_error "$response"
  jq -r '.result.groupids[0]' <<<"$response"
}

host_exists() {
  local name="$1"
  local response
  response=$(api <<EOF
{"jsonrpc":"2.0","method":"host.get","params":{"filter":{"host":["${name}"]},"output":["hostid"]},"id":1}
EOF
)
  fail_if_error "$response"
  jq -e '.result[0].hostid' <<<"$response" >/dev/null
}

LINUX_TEMPLATE=$(template_id "Linux by Zabbix agent")
SNMP_TEMPLATE=$(template_id "Network Generic Device by SNMP")
ICMP_TEMPLATE=$(template_id "ICMP Ping")
LINUX_GROUP=$(group_id "Laboratorio/Linux")
SNMP_GROUP=$(group_id "Laboratorio/Rede")

if host_exists "host-linux"; then
  echo "host-linux já existe"
else
  created=$(api <<EOF
{"jsonrpc":"2.0","method":"host.create","params":{"host":"host-linux","groups":[{"groupid":"${LINUX_GROUP}"}],"templates":[{"templateid":"${LINUX_TEMPLATE}"},{"templateid":"${ICMP_TEMPLATE}"}],"interfaces":[{"type":1,"main":1,"useip":1,"ip":"${HOST_LINUX_IP}","dns":"","port":"10050"}]},"id":1}
EOF
)
  fail_if_error "$created"
  echo "host-linux cadastrado em ${HOST_LINUX_IP}"
fi

if host_exists "dispositivo-rede"; then
  echo "dispositivo-rede já existe"
else
  created=$(api <<EOF
{"jsonrpc":"2.0","method":"host.create","params":{"host":"dispositivo-rede","groups":[{"groupid":"${SNMP_GROUP}"}],"templates":[{"templateid":"${SNMP_TEMPLATE}"},{"templateid":"${ICMP_TEMPLATE}"}],"interfaces":[{"type":2,"main":1,"useip":1,"ip":"${SNMP_IP}","dns":"","port":"161","details":{"version":2,"community":"${SNMP_COMMUNITY}","bulk":1}}]},"id":1}
EOF
)
  fail_if_error "$created"
  echo "dispositivo-rede cadastrado em ${SNMP_IP}"
fi
SCRIPT
