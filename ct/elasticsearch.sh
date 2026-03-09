#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Muaz
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.elastic.co/elasticsearch

# Import main orchestrator
source <(curl -fsSL https://raw.githubusercontent.com/muazhazali/ProxmoxVE/feat/elasticsearch-kibana/misc/build.func)

# Application Configuration
APP="Elasticsearch"
var_tags="search;analytics;kibana"

# Container Resources (Elasticsearch is memory-intensive, Kibana needs extra)
var_cpu="4"
var_ram="6144"
var_disk="20"

# Container Type & OS
var_os="debian"
var_version="12"
var_unprivileged="1"

# Display header ASCII art
header_info "$APP"

# Process command-line arguments and load configuration
variables

# Setup ANSI color codes and formatting
color

# Initialize error handling
catch_errors

function update_script() {
  header_info

  # Always start with these checks
  check_container_storage
  check_container_resources

  # Verify Elasticsearch is installed
  if ! dpkg -s elasticsearch &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  apt-get update
  apt-get install -y elasticsearch kibana
  msg_ok "Updated ${APP}"

  # Restart services after update
  systemctl restart elasticsearch
  systemctl restart kibana
  msg_ok "Restarted Elasticsearch and Kibana services"

  exit
}

# Start the container creation workflow
start

# Build the container with selected configuration
build_container

# Set container description/notes in Proxmox UI
description

# Display success message
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access Kibana using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5601${CL}"
echo -e "${INFO}${YW} Elasticsearch API:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:9200${CL}"
echo -e "${INFO}${YW} Elastic superuser password was saved to:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/root/.elastic_password${CL}"
