#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Muaz
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.elastic.co/elasticsearch

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  mc \
  apt-transport-https \
  gnupg2
msg_ok "Installed Dependencies"

msg_info "Setting up Elastic Repository"
$STD wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
  >/etc/apt/sources.list.d/elastic-8.x.list
$STD apt-get update
msg_ok "Set up Elastic Repository"

msg_info "Installing Elasticsearch (this may take a while)"
DEBIAN_FRONTEND=noninteractive $STD apt-get install -y elasticsearch
msg_ok "Installed Elasticsearch"

msg_info "Configuring Elasticsearch"
# Set JVM heap to 25% of total RAM (min 512m, max 2g) to leave room for Kibana + OS
TOTAL_MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
HEAP_MB=$((TOTAL_MEM_MB / 4))
[[ $HEAP_MB -lt 512 ]] && HEAP_MB=512
[[ $HEAP_MB -gt 2048 ]] && HEAP_MB=2048
mkdir -p /etc/elasticsearch/jvm.options.d
cat <<EOF >/etc/elasticsearch/jvm.options.d/jvm-heap.options
-Xms${HEAP_MB}m
-Xmx${HEAP_MB}m
EOF

cat <<EOF >>/etc/elasticsearch/elasticsearch.yml

network.host: 0.0.0.0
discovery.type: single-node
cluster.name: proxmox-elastic
EOF
msg_ok "Configured Elasticsearch"

msg_info "Starting Elasticsearch"
systemctl enable -q --now elasticsearch
for i in $(seq 1 36); do
  if curl -ks https://localhost:9200 &>/dev/null; then
    break
  fi
  sleep 5
done
msg_ok "Started Elasticsearch"

msg_info "Saving Elastic superuser credentials"
ES_PASSWORD=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s 2>/dev/null || echo "check-manually")
echo "$ES_PASSWORD" >/root/.elastic_password
chmod 600 /root/.elastic_password
msg_ok "Saved credentials to /root/.elastic_password"

msg_info "Installing Kibana"
DEBIAN_FRONTEND=noninteractive $STD apt-get install -y kibana
msg_ok "Installed Kibana"

msg_info "Configuring Kibana"
cat <<EOF >>/etc/kibana/kibana.yml

server.host: "0.0.0.0"
server.publicBaseUrl: "http://$(hostname -I | awk '{print $1}'):5601"
EOF

KIBANA_TOKEN=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana 2>/dev/null || echo "")
if [[ -n "$KIBANA_TOKEN" ]]; then
  $STD /usr/share/kibana/bin/kibana-setup --enrollment-token "$KIBANA_TOKEN" || true
fi
msg_ok "Configured Kibana"

msg_info "Starting Kibana"
systemctl enable -q --now kibana
msg_ok "Started Kibana"

motd_ssh
customize
cleanup_lxc
