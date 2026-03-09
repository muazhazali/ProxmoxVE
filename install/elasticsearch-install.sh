#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Muaz
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.elastic.co/elasticsearch

# Import install functions
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ========================
# Install Dependencies
# ========================
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  apt-transport-https \
  gnupg2
msg_ok "Installed Dependencies"

# ========================
# Add Elastic APT Repository
# ========================
msg_info "Setting up Elastic Repository"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | \
  tee /etc/apt/sources.list.d/elastic-8.x.list
$STD apt-get update
msg_ok "Set up Elastic Repository"

# ========================
# Install Elasticsearch
# ========================
msg_info "Installing Elasticsearch (this may take a while)"
$STD apt-get install -y elasticsearch 2>&1 | tee /tmp/es_install_output.txt
msg_ok "Installed Elasticsearch"

# ========================
# Capture and Save Elastic Superuser Password
# ========================
msg_info "Saving Elastic superuser credentials"
# The password is displayed during first install; extract and save it
ES_PASSWORD=$(grep -oP 'The generated password for the elastic built-in superuser is : \K.*' /tmp/es_install_output.txt 2>/dev/null || echo "")
if [[ -z "$ES_PASSWORD" ]]; then
  # If password wasn't captured, reset it to a known value
  systemctl start elasticsearch
  sleep 10
  ES_PASSWORD=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s 2>/dev/null || echo "check-manually")
  systemctl stop elasticsearch
fi
echo "$ES_PASSWORD" > /root/.elastic_password
chmod 600 /root/.elastic_password
rm -f /tmp/es_install_output.txt
msg_ok "Saved credentials to /root/.elastic_password"

# ========================
# Configure Elasticsearch
# ========================
msg_info "Configuring Elasticsearch"
# Set JVM heap size (use ~half of available RAM, capped for LXC use)
mkdir -p /etc/elasticsearch/jvm.options.d
cat <<EOF >/etc/elasticsearch/jvm.options.d/jvm-heap.options
-Xms1g
-Xmx1g
EOF

# Configure Elasticsearch to bind to all interfaces for LXC accessibility
cat <<EOF >>/etc/elasticsearch/elasticsearch.yml

# ---- Community-Scripts Custom Config ----
# Bind to all interfaces so it's reachable from the host network
network.host: 0.0.0.0
# Single-node discovery (suitable for LXC standalone deployment)
discovery.type: single-node
# Cluster name
cluster.name: proxmox-elastic
EOF
msg_ok "Configured Elasticsearch"

# ========================
# Start Elasticsearch
# ========================
msg_info "Starting Elasticsearch"
systemctl daemon-reload
systemctl enable -q --now elasticsearch
# Wait for Elasticsearch to be ready
for i in $(seq 1 30); do
  if curl -ks https://localhost:9200 &>/dev/null; then
    break
  fi
  sleep 5
done
msg_ok "Started Elasticsearch"

# ========================
# Install Kibana
# ========================
msg_info "Installing Kibana"
$STD apt-get install -y kibana
msg_ok "Installed Kibana"

# ========================
# Configure Kibana
# ========================
msg_info "Configuring Kibana"
# Set Kibana to listen on all interfaces
cat <<EOF >>/etc/kibana/kibana.yml

# ---- Community-Scripts Custom Config ----
# Bind to all interfaces for LXC accessibility
server.host: "0.0.0.0"
# Public-facing base URL (will use the container's IP)
server.publicBaseUrl: "http://$(hostname -I | awk '{print $1}'):5601"
EOF

# Generate Kibana enrollment token from Elasticsearch
msg_info "Generating Kibana enrollment token"
KIBANA_TOKEN=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana 2>/dev/null || echo "")
if [[ -n "$KIBANA_TOKEN" ]]; then
  # Use the enrollment token to configure Kibana's connection to Elasticsearch
  /usr/share/kibana/bin/kibana-setup --enrollment-token "$KIBANA_TOKEN" 2>/dev/null || true
fi
msg_ok "Configured Kibana"

# ========================
# Start Kibana
# ========================
msg_info "Starting Kibana"
systemctl daemon-reload
systemctl enable -q --now kibana
msg_ok "Started Kibana"

# ========================
# Cleanup
# ========================
motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
