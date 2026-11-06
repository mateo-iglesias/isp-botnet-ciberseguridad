# Rules to stop botnet-infected devices on PPPoE customers
# MikroTik RouterOS v7
# Check the list names before applying.

# -------------------------------------------------------------
# 1. Botnet servers observed
# -------------------------------------------------------------
/ip firewall address-list
# Case 1 - TCP ports 100-299
add list=BOTNET_C2 address=43.116.104.159 comment="case 1"
add list=BOTNET_C2 address=43.116.44.216 comment="case 1"
add list=BOTNET_C2 address=43.116.78.215 comment="case 1"
add list=BOTNET_C2 address=43.116.96.176 comment="case 1"
add list=BOTNET_C2 address=43.117.69.111 comment="case 1"
add list=BOTNET_C2 address=43.117.72.34 comment="case 1"
add list=BOTNET_C2 address=43.117.144.62 comment="case 1"
add list=BOTNET_C2 address=43.102.24.128 comment="case 1"
add list=BOTNET_C2 address=43.102.227.177 comment="case 1"
add list=BOTNET_C2 address=43.153.72.39 comment="case 1"
add list=BOTNET_C2 address=43.134.137.138 comment="case 1"
add list=BOTNET_C2 address=43.173.73.175 comment="case 1"
add list=BOTNET_C2 address=101.47.137.151 comment="case 1"
add list=BOTNET_C2 address=101.47.51.172 comment="case 1"
add list=BOTNET_C2 address=98.96.240.200 comment="case 1"
add list=BOTNET_C2 address=45.78.209.152 comment="case 1"
# Case 2 - TCP port 9377
add list=BOTNET_C2 address=47.252.43.28 comment="case 2"
add list=BOTNET_C2 address=47.252.25.16 comment="case 2"
add list=BOTNET_C2 address=47.90.133.211 comment="case 2"

# -------------------------------------------------------------
# 2. Suspicious customers
#    Added through their PPP profile so the rules keep
#    working even if the IP changes when they reconnect.
# -------------------------------------------------------------
/ppp profile
add name=contencion-botnet address-list=CONTENCION_BOTNET
# To move a customer to this profile:
# /ppp secret set [find name="customer-user"] profile=contencion-botnet

# -------------------------------------------------------------
# 3. Rules
# -------------------------------------------------------------
/ip firewall raw
# Nobody on the network can connect to the botnet servers
add chain=prerouting dst-address-list=BOTNET_C2 action=drop log=yes log-prefix="BOTNET" \
    comment="Block botnet servers"

# Suspicious customers: block the control-channel ports
# Case 1: TCP 100-299 (POP3 110 and IMAP 143 are allowed)
add chain=prerouting src-address-list=CONTENCION_BOTNET protocol=tcp \
    dst-port=100-109,111-142,144-299 action=drop log=yes log-prefix="BOTNET-PORTS" \
    comment="Block case 1 botnet ports on suspicious customers"
# Case 2: TCP 9377
add chain=prerouting src-address-list=CONTENCION_BOTNET protocol=tcp \
    dst-port=9377 action=drop log=yes log-prefix="BOTNET-9377" \
    comment="Block case 2 botnet port on suspicious customers"

/ip firewall filter
# Suspicious customers: limit new UDP connections (stops floods like case 2)
# DNS and NTP are allowed first
add chain=forward src-address-list=CONTENCION_BOTNET protocol=udp dst-port=53,123 \
    action=accept comment="Containment: allow DNS and NTP"
add chain=forward src-address-list=CONTENCION_BOTNET protocol=udp \
    connection-state=new connection-limit=50,32 action=drop \
    comment="Containment: limit new UDP connections"

# -------------------------------------------------------------
# 4. Check whether the rules are blocking anything
# -------------------------------------------------------------
# /ip firewall raw print stats where comment~"botnet"
# /ip firewall filter print stats where comment~"Containment"
