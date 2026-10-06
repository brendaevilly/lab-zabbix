FROM alpine:3.22

RUN apk add --no-cache net-snmp

COPY snmpd.conf /etc/snmp/snmpd.conf

EXPOSE 1161/udp

# -C le só o arquivo do laboratorio. Sem isso o snmpd abre o mesmo
# agentAddress duas vezes e encerra com "Error opening specified endpoint".
CMD ["snmpd", "-f", "-Lo", "-C", "-c", "/etc/snmp/snmpd.conf"]
