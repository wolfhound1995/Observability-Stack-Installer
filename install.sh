#!/bin/bash

#############################################################################
# Universal Monitoring Stack Installer
# Supports: Grafana, Loki, Prometheus, InfluxDB
# OS Support: Ubuntu/Debian, RHEL/CentOS/Rocky/AlmaLinux, Fedora, openSUSE, Arch
# Deployment: Docker & Native installation options
# Includes: Nginx reverse proxy with SSL (Certbot)
#############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SCRIPT_VERSION="1.0.0"
INSTALL_DIR="/opt/monitoring"
CONFIG_DIR="/etc/monitoring"
DATA_DIR="/var/lib/monitoring"
LOG_DIR="/var/log/monitoring"

# Default ports
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
LOKI_PORT=3100
INFLUXDB_PORT=8086

# Service versions (update as needed)
GRAFANA_VERSION="latest"
PROMETHEUS_VERSION="latest"
LOKI_VERSION="latest"
INFLUXDB_VERSION="latest"

# Global variables
OS_TYPE=""
OS_VERSION=""
INSTALL_METHOD=""
USE_DOCKER=""
INSTALL_NGINX=""
USE_SSL=""
DOMAIN_NAME=""
EMAIL=""
COMPONENTS=()

#############################################################################
# Helper Functions
#############################################################################

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

detect_os() {
    print_header "Detecting Operating System"
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_TYPE=$ID
        OS_VERSION=$VERSION_ID
        
        case $OS_TYPE in
            ubuntu|debian)
                OS_FAMILY="debian"
                ;;
            rhel|centos|rocky|almalinux)
                OS_FAMILY="rhel"
                ;;
            fedora)
                OS_FAMILY="fedora"
                ;;
            opensuse*|sles)
                OS_FAMILY="suse"
                ;;
            arch|manjaro)
                OS_FAMILY="arch"
                ;;
            *)
                print_error "Unsupported OS: $OS_TYPE"
                exit 1
                ;;
        esac
        
        print_success "Detected: $OS_TYPE $OS_VERSION"
    else
        print_error "Cannot detect OS. /etc/os-release not found"
        exit 1
    fi
}

check_dependencies() {
    print_header "Checking System Dependencies"
    
    local deps=("curl" "wget" "tar" "systemctl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warning "Missing dependencies: ${missing[*]}"
        install_system_dependencies
    else
        print_success "All required dependencies are installed"
    fi
}

install_system_dependencies() {
    print_info "Installing system dependencies..."
    
    case $OS_FAMILY in
        debian)
            apt-get update -qq
            apt-get install -y curl wget tar gnupg2 software-properties-common apt-transport-https ca-certificates
            ;;
        rhel|fedora)
            if [[ $OS_FAMILY == "fedora" ]]; then
                dnf install -y curl wget tar gnupg2 ca-certificates
            else
                yum install -y curl wget tar gnupg2 ca-certificates
            fi
            ;;
        suse)
            zypper refresh
            zypper install -y curl wget tar gnupg2 ca-certificates
            ;;
        arch)
            pacman -Sy --noconfirm curl wget tar gnupg ca-certificates
            ;;
    esac
    
    print_success "System dependencies installed"
}

#############################################################################
# Interactive Configuration
#############################################################################

get_user_input() {
    print_header "Configuration Wizard"
    
    # Installation method
    echo ""
    echo "Select installation method:"
    echo "1) Docker (recommended)"
    echo "2) Native installation"
    read -p "Choice [1-2]: " method_choice
    
    case $method_choice in
        1)
            USE_DOCKER="yes"
            INSTALL_METHOD="docker"
            ;;
        2)
            USE_DOCKER="no"
            INSTALL_METHOD="native"
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    # Components selection
    echo ""
    echo "Select components to install (space-separated numbers, e.g., '1 2 3'):"
    echo "1) Grafana"
    echo "2) Prometheus"
    echo "3) Loki"
    echo "4) InfluxDB"
    echo "5) All"
    read -p "Components: " comp_choice
    
    if [[ $comp_choice == *"5"* ]]; then
        COMPONENTS=("grafana" "prometheus" "loki" "influxdb")
    else
        [[ $comp_choice == *"1"* ]] && COMPONENTS+=("grafana")
        [[ $comp_choice == *"2"* ]] && COMPONENTS+=("prometheus")
        [[ $comp_choice == *"3"* ]] && COMPONENTS+=("loki")
        [[ $comp_choice == *"4"* ]] && COMPONENTS+=("influxdb")
    fi
    
    if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
        print_error "No components selected"
        exit 1
    fi
    
    # Nginx configuration
    echo ""
    read -p "Install and configure Nginx reverse proxy? [y/N]: " nginx_choice
    if [[ $nginx_choice =~ ^[Yy]$ ]]; then
        INSTALL_NGINX="yes"
        
        read -p "Configure SSL with Let's Encrypt? [y/N]: " ssl_choice
        if [[ $ssl_choice =~ ^[Yy]$ ]]; then
            USE_SSL="yes"
            read -p "Enter domain name (e.g., monitoring.example.com): " DOMAIN_NAME
            read -p "Enter email for Let's Encrypt: " EMAIL
            
            if [[ -z "$DOMAIN_NAME" ]] || [[ -z "$EMAIL" ]]; then
                print_error "Domain and email are required for SSL"
                exit 1
            fi
        else
            USE_SSL="no"
        fi
    else
        INSTALL_NGINX="no"
        USE_SSL="no"
    fi
    
    # Summary
    echo ""
    print_header "Installation Summary"
    echo "OS: $OS_TYPE $OS_VERSION"
    echo "Method: $INSTALL_METHOD"
    echo "Components: ${COMPONENTS[*]}"
    echo "Nginx: $INSTALL_NGINX"
    echo "SSL: $USE_SSL"
    [[ $USE_SSL == "yes" ]] && echo "Domain: $DOMAIN_NAME"
    echo ""
    read -p "Proceed with installation? [y/N]: " proceed
    
    if [[ ! $proceed =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
}

#############################################################################
# Docker Installation
#############################################################################

install_docker() {
    print_header "Installing Docker"
    
    if command -v docker &> /dev/null; then
        print_success "Docker already installed"
        return
    fi
    
    case $OS_FAMILY in
        debian)
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            rm get-docker.sh
            ;;
        rhel|fedora)
            if [[ $OS_FAMILY == "fedora" ]]; then
                dnf -y install dnf-plugins-core
                dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            else
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
        suse)
            zypper install -y docker docker-compose
            ;;
        arch)
            pacman -S --noconfirm docker docker-compose
            ;;
    esac
    
    systemctl enable docker
    systemctl start docker
    
    print_success "Docker installed and started"
}

create_docker_network() {
    if ! docker network inspect monitoring &> /dev/null; then
        docker network create monitoring
        print_success "Created Docker network: monitoring"
    fi
}

#############################################################################
# Grafana Installation
#############################################################################

install_grafana_docker() {
    print_header "Installing Grafana (Docker)"
    
    mkdir -p "$DATA_DIR/grafana"
    chmod 777 "$DATA_DIR/grafana"
    
    cat > "$INSTALL_DIR/docker-compose-grafana.yml" <<EOF
version: '3.8'

services:
  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    container_name: grafana
    restart: unless-stopped
    ports:
      - "${GRAFANA_PORT}:3000"
    environment:
      - GF_SERVER_ROOT_URL=http://localhost:3000
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_INSTALL_PLUGINS=
    volumes:
      - ${DATA_DIR}/grafana:/var/lib/grafana
    networks:
      - monitoring

networks:
  monitoring:
    external: true
EOF
    
    cd "$INSTALL_DIR"
    docker compose -f docker-compose-grafana.yml up -d
    
    print_success "Grafana installed and running on port $GRAFANA_PORT"
    print_warning "Default credentials - Username: admin, Password: admin"
}

install_grafana_native() {
    print_header "Installing Grafana (Native)"
    
    case $OS_FAMILY in
        debian)
            wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/grafana.gpg > /dev/null
            echo "deb [signed-by=/etc/apt/trusted.gpg.d/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
            apt-get update -qq
            apt-get install -y grafana
            ;;
        rhel|fedora)
            cat > /etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
            if [[ $OS_FAMILY == "fedora" ]]; then
                dnf install -y grafana
            else
                yum install -y grafana
            fi
            ;;
        suse)
            zypper addrepo https://rpm.grafana.com grafana
            zypper refresh
            zypper install -y grafana
            ;;
        arch)
            pacman -S --noconfirm grafana
            ;;
    esac
    
    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server
    
    print_success "Grafana installed and running on port $GRAFANA_PORT"
    print_warning "Default credentials - Username: admin, Password: admin"
}

#############################################################################
# Prometheus Installation
#############################################################################

install_prometheus_docker() {
    print_header "Installing Prometheus (Docker)"
    
    mkdir -p "$CONFIG_DIR/prometheus" "$DATA_DIR/prometheus"
    
    cat > "$CONFIG_DIR/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['node_exporter:9100']
EOF
    
    cat > "$INSTALL_DIR/docker-compose-prometheus.yml" <<EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION}
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "${PROMETHEUS_PORT}:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    volumes:
      - ${CONFIG_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ${DATA_DIR}/prometheus:/prometheus
    networks:
      - monitoring

  node_exporter:
    image: prom/node-exporter:latest
    container_name: node_exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    networks:
      - monitoring

networks:
  monitoring:
    external: true
EOF
    
    cd "$INSTALL_DIR"
    docker compose -f docker-compose-prometheus.yml up -d
    
    print_success "Prometheus installed and running on port $PROMETHEUS_PORT"
}

install_prometheus_native() {
    print_header "Installing Prometheus (Native)"
    
    local PROM_VERSION="2.47.2"
    local ARCH=$(uname -m)
    
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
    esac
    
    cd /tmp
    wget "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-${ARCH}.tar.gz"
    tar xzf "prometheus-${PROM_VERSION}.linux-${ARCH}.tar.gz"
    
    useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
    
    mkdir -p "$CONFIG_DIR/prometheus" "$DATA_DIR/prometheus"
    
    cp "prometheus-${PROM_VERSION}.linux-${ARCH}/prometheus" /usr/local/bin/
    cp "prometheus-${PROM_VERSION}.linux-${ARCH}/promtool" /usr/local/bin/
    cp -r "prometheus-${PROM_VERSION}.linux-${ARCH}/consoles" "$CONFIG_DIR/prometheus/"
    cp -r "prometheus-${PROM_VERSION}.linux-${ARCH}/console_libraries" "$CONFIG_DIR/prometheus/"
    
    cat > "$CONFIG_DIR/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    
    chown -R prometheus:prometheus "$CONFIG_DIR/prometheus" "$DATA_DIR/prometheus"
    chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
    
    cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file=$CONFIG_DIR/prometheus/prometheus.yml \\
    --storage.tsdb.path=$DATA_DIR/prometheus/ \\
    --web.console.templates=$CONFIG_DIR/prometheus/consoles \\
    --web.console.libraries=$CONFIG_DIR/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
    
    rm -rf "/tmp/prometheus-${PROM_VERSION}.linux-${ARCH}"*
    
    print_success "Prometheus installed and running on port $PROMETHEUS_PORT"
}

#############################################################################
# Loki Installation
#############################################################################

install_loki_docker() {
    print_header "Installing Loki (Docker)"
    
    mkdir -p "$CONFIG_DIR/loki" "$DATA_DIR/loki"
    
    cat > "$CONFIG_DIR/loki/loki-config.yml" <<EOF
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093
EOF
    
    cat > "$INSTALL_DIR/docker-compose-loki.yml" <<EOF
version: '3.8'

services:
  loki:
    image: grafana/loki:${LOKI_VERSION}
    container_name: loki
    restart: unless-stopped
    ports:
      - "${LOKI_PORT}:3100"
    volumes:
      - ${CONFIG_DIR}/loki/loki-config.yml:/etc/loki/local-config.yaml
      - ${DATA_DIR}/loki:/loki
    command: -config.file=/etc/loki/local-config.yaml
    networks:
      - monitoring

  promtail:
    image: grafana/promtail:${LOKI_VERSION}
    container_name: promtail
    restart: unless-stopped
    volumes:
      - /var/log:/var/log:ro
      - ${CONFIG_DIR}/loki/promtail-config.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml
    networks:
      - monitoring

networks:
  monitoring:
    external: true
EOF
    
    cat > "$CONFIG_DIR/loki/promtail-config.yml" <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*log
EOF
    
    cd "$INSTALL_DIR"
    docker compose -f docker-compose-loki.yml up -d
    
    print_success "Loki installed and running on port $LOKI_PORT"
}

install_loki_native() {
    print_header "Installing Loki (Native)"
    
    local LOKI_VERSION="2.9.3"
    local ARCH=$(uname -m)
    
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
    esac
    
    cd /tmp
    wget "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-${ARCH}.zip"
    unzip "loki-linux-${ARCH}.zip"
    
    useradd --no-create-home --shell /bin/false loki 2>/dev/null || true
    
    mkdir -p "$CONFIG_DIR/loki" "$DATA_DIR/loki"
    mv "loki-linux-${ARCH}" /usr/local/bin/loki
    chmod +x /usr/local/bin/loki
    
    cat > "$CONFIG_DIR/loki/loki-config.yml" <<EOF
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: $DATA_DIR/loki
  storage:
    filesystem:
      chunks_directory: $DATA_DIR/loki/chunks
      rules_directory: $DATA_DIR/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
EOF
    
    chown -R loki:loki "$CONFIG_DIR/loki" "$DATA_DIR/loki"
    
    cat > /etc/systemd/system/loki.service <<EOF
[Unit]
Description=Loki
After=network.target

[Service]
Type=simple
User=loki
ExecStart=/usr/local/bin/loki -config.file=$CONFIG_DIR/loki/loki-config.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable loki
    systemctl start loki
    
    rm -f "/tmp/loki-linux-${ARCH}.zip"
    
    print_success "Loki installed and running on port $LOKI_PORT"
}

#############################################################################
# InfluxDB Installation
#############################################################################

install_influxdb_docker() {
    print_header "Installing InfluxDB (Docker)"
    
    mkdir -p "$DATA_DIR/influxdb"
    
    cat > "$INSTALL_DIR/docker-compose-influxdb.yml" <<EOF
version: '3.8'

services:
  influxdb:
    image: influxdb:${INFLUXDB_VERSION}
    container_name: influxdb
    restart: unless-stopped
    ports:
      - "${INFLUXDB_PORT}:8086"
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword
      - DOCKER_INFLUXDB_INIT_ORG=myorg
      - DOCKER_INFLUXDB_INIT_BUCKET=mybucket
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=mytoken123
    volumes:
      - ${DATA_DIR}/influxdb:/var/lib/influxdb2
    networks:
      - monitoring

networks:
  monitoring:
    external: true
EOF
    
    cd "$INSTALL_DIR"
    docker compose -f docker-compose-influxdb.yml up -d
    
    print_success "InfluxDB installed and running on port $INFLUXDB_PORT"
    print_warning "Initial credentials - Username: admin, Password: adminpassword"
}

install_influxdb_native() {
    print_header "Installing InfluxDB (Native)"
    
    case $OS_FAMILY in
        debian)
            wget -q https://repos.influxdata.com/influxdata-archive_compat.key
            echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c
            cat influxdata-archive_compat.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
            echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | tee /etc/apt/sources.list.d/influxdata.list
            apt-get update -qq
            apt-get install -y influxdb2
            rm influxdata-archive_compat.key
            ;;
        rhel|fedora)
            cat > /etc/yum.repos.d/influxdb.repo <<EOF
[influxdb]
name = InfluxDB Repository - RHEL
baseurl = https://repos.influxdata.com/rhel/\$releasever/\$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive_compat.key
EOF
            if [[ $OS_FAMILY == "fedora" ]]; then
                dnf install -y influxdb2
            else
                yum install -y influxdb2
            fi
            ;;
        suse)
            zypper addrepo https://repos.influxdata.com/sles/\$releasever/\$basearch/stable influxdb
            zypper refresh
            zypper install -y influxdb2
            ;;
        arch)
            pacman -S --noconfirm influxdb
            ;;
    esac
    
    systemctl enable influxdb
    systemctl start influxdb
    
    print_success "InfluxDB installed and running on port $INFLUXDB_PORT"
    print_info "Complete setup at http://localhost:$INFLUXDB_PORT"
}

#############################################################################
# Nginx Installation and Configuration
#############################################################################

install_nginx() {
    print_header "Installing Nginx"
    
    case $OS_FAMILY in
        debian)
            apt-get install -y nginx
            ;;
        rhel|fedora)
            if [[ $OS_FAMILY == "fedora" ]]; then
                dnf install -y nginx
            else
                yum install -y nginx
            fi
            ;;
        suse)
            zypper install -y nginx
            ;;
        arch)
            pacman -S --noconfirm nginx
            ;;
    esac
    
    systemctl enable nginx
    print_success "Nginx installed"
}

configure_nginx() {
    print_header "Configuring Nginx"
    
    # Backup default config
    [[ -f /etc/nginx/sites-available/default ]] && mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
    
    # Create monitoring config
    cat > /etc/nginx/sites-available/monitoring <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME:-localhost};

    location /grafana/ {
        proxy_pass http://localhost:${GRAFANA_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /prometheus/ {
        proxy_pass http://localhost:${PROMETHEUS_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /loki/ {
        proxy_pass http://localhost:${LOKI_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /influxdb/ {
        proxy_pass http://localhost:${INFLUXDB_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/monitoring /etc/nginx/sites-enabled/
    
    # Test and reload
    nginx -t
    systemctl reload nginx
    
    print_success "Nginx configured"
}

install_certbot() {
    print_header "Installing Certbot"
    
    case $OS_FAMILY in
        debian)
            apt-get install -y certbot python3-certbot-nginx
            ;;
        rhel|fedora)
            if [[ $OS_FAMILY == "fedora" ]]; then
                dnf install -y certbot python3-certbot-nginx
            else
                yum install -y certbot python3-certbot-nginx
            fi
            ;;
        suse)
            zypper install -y certbot python3-certbot-nginx
            ;;
        arch)
            pacman -S --noconfirm certbot certbot-nginx
            ;;
    esac
    
    print_success "Certbot installed"
}

configure_ssl() {
    print_header "Configuring SSL with Let's Encrypt"
    
    # Obtain certificate
    certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "$EMAIL" --redirect
    
    # Setup auto-renewal
    systemctl enable certbot-renew.timer 2>/dev/null || {
        echo "0 0,12 * * * root certbot renew --quiet" >> /etc/crontab
    }
    
    print_success "SSL configured for $DOMAIN_NAME"
}

#############################################################################
# Firewall Configuration
#############################################################################

configure_firewall() {
    print_header "Configuring Firewall"
    
    if command -v ufw &> /dev/null; then
        # UFW (Ubuntu/Debian)
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        [[ $INSTALL_NGINX != "yes" ]] && {
            ufw allow $GRAFANA_PORT/tcp
            ufw allow $PROMETHEUS_PORT/tcp
            ufw allow $LOKI_PORT/tcp
            ufw allow $INFLUXDB_PORT/tcp
        }
        ufw --force enable
        print_success "UFW firewall configured"
    elif command -v firewall-cmd &> /dev/null; then
        # firewalld (RHEL/CentOS/Fedora)
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        [[ $INSTALL_NGINX != "yes" ]] && {
            firewall-cmd --permanent --add-port=$GRAFANA_PORT/tcp
            firewall-cmd --permanent --add-port=$PROMETHEUS_PORT/tcp
            firewall-cmd --permanent --add-port=$LOKI_PORT/tcp
            firewall-cmd --permanent --add-port=$INFLUXDB_PORT/tcp
        }
        firewall-cmd --reload
        print_success "Firewalld configured"
    else
        print_warning "No firewall detected. Please configure manually."
    fi
}

#############################################################################
# Directory Setup
#############################################################################

setup_directories() {
    print_header "Setting Up Directories"
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$LOG_DIR"
    
    chmod 755 "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    print_success "Directories created"
}

#############################################################################
# Health Checks
#############################################################################

wait_for_service() {
    local service=$1
    local port=$2
    local max_attempts=30
    local attempt=0
    
    print_info "Waiting for $service to be ready..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "http://localhost:$port" > /dev/null 2>&1; then
            print_success "$service is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    print_warning "$service health check timeout"
    return 1
}

verify_installation() {
    print_header "Verifying Installation"
    
    local all_ok=true
    
    for component in "${COMPONENTS[@]}"; do
        case $component in
            grafana)
                if [[ $USE_DOCKER == "yes" ]]; then
                    docker ps | grep -q grafana && print_success "Grafana container running" || { print_error "Grafana container not running"; all_ok=false; }
                else
                    systemctl is-active --quiet grafana-server && print_success "Grafana service active" || { print_error "Grafana service not active"; all_ok=false; }
                fi
                wait_for_service "Grafana" $GRAFANA_PORT
                ;;
            prometheus)
                if [[ $USE_DOCKER == "yes" ]]; then
                    docker ps | grep -q prometheus && print_success "Prometheus container running" || { print_error "Prometheus container not running"; all_ok=false; }
                else
                    systemctl is-active --quiet prometheus && print_success "Prometheus service active" || { print_error "Prometheus service not active"; all_ok=false; }
                fi
                wait_for_service "Prometheus" $PROMETHEUS_PORT
                ;;
            loki)
                if [[ $USE_DOCKER == "yes" ]]; then
                    docker ps | grep -q loki && print_success "Loki container running" || { print_error "Loki container not running"; all_ok=false; }
                else
                    systemctl is-active --quiet loki && print_success "Loki service active" || { print_error "Loki service not active"; all_ok=false; }
                fi
                wait_for_service "Loki" $LOKI_PORT
                ;;
            influxdb)
                if [[ $USE_DOCKER == "yes" ]]; then
                    docker ps | grep -q influxdb && print_success "InfluxDB container running" || { print_error "InfluxDB container not running"; all_ok=false; }
                else
                    systemctl is-active --quiet influxdb && print_success "InfluxDB service active" || { print_error "InfluxDB service not active"; all_ok=false; }
                fi
                wait_for_service "InfluxDB" $INFLUXDB_PORT
                ;;
        esac
    done
    
    if [[ $INSTALL_NGINX == "yes" ]]; then
        systemctl is-active --quiet nginx && print_success "Nginx service active" || { print_error "Nginx service not active"; all_ok=false; }
    fi
    
    if $all_ok; then
        print_success "All services verified successfully"
    else
        print_warning "Some services failed verification"
    fi
}

#############################################################################
# Post-Installation Summary
#############################################################################

print_summary() {
    print_header "Installation Complete!"
    
    echo ""
    echo "=== Access Information ==="
    echo ""
    
    if [[ $INSTALL_NGINX == "yes" ]]; then
        if [[ $USE_SSL == "yes" ]]; then
            BASE_URL="https://$DOMAIN_NAME"
        else
            BASE_URL="http://${DOMAIN_NAME:-localhost}"
        fi
        
        for component in "${COMPONENTS[@]}"; do
            case $component in
                grafana)
                    echo "Grafana:    $BASE_URL/grafana/"
                    echo "  - Username: admin"
                    echo "  - Password: admin (change on first login)"
                    ;;
                prometheus)
                    echo "Prometheus: $BASE_URL/prometheus/"
                    ;;
                loki)
                    echo "Loki:       $BASE_URL/loki/"
                    ;;
                influxdb)
                    echo "InfluxDB:   $BASE_URL/influxdb/"
                    ;;
            esac
        done
    else
        for component in "${COMPONENTS[@]}"; do
            case $component in
                grafana)
                    echo "Grafana:    http://localhost:$GRAFANA_PORT"
                    echo "  - Username: admin"
                    echo "  - Password: admin (change on first login)"
                    ;;
                prometheus)
                    echo "Prometheus: http://localhost:$PROMETHEUS_PORT"
                    ;;
                loki)
                    echo "Loki:       http://localhost:$LOKI_PORT"
                    ;;
                influxdb)
                    echo "InfluxDB:   http://localhost:$INFLUXDB_PORT"
                    if [[ $USE_DOCKER == "yes" ]]; then
                        echo "  - Username: admin"
                        echo "  - Password: adminpassword"
                        echo "  - Token: mytoken123"
                    fi
                    ;;
            esac
        done
    fi
    
    echo ""
    echo "=== Configuration Files ==="
    echo "Install directory: $INSTALL_DIR"
    echo "Config directory:  $CONFIG_DIR"
    echo "Data directory:    $DATA_DIR"
    echo "Log directory:     $LOG_DIR"
    
    if [[ $USE_DOCKER == "yes" ]]; then
        echo ""
        echo "=== Docker Commands ==="
        echo "View logs:     docker compose -f $INSTALL_DIR/docker-compose-<service>.yml logs -f"
        echo "Restart:       docker compose -f $INSTALL_DIR/docker-compose-<service>.yml restart"
        echo "Stop:          docker compose -f $INSTALL_DIR/docker-compose-<service>.yml down"
        echo "Start:         docker compose -f $INSTALL_DIR/docker-compose-<service>.yml up -d"
    else
        echo ""
        echo "=== Service Management ==="
        for component in "${COMPONENTS[@]}"; do
            case $component in
                grafana)
                    echo "Grafana:    systemctl status grafana-server"
                    ;;
                prometheus)
                    echo "Prometheus: systemctl status prometheus"
                    ;;
                loki)
                    echo "Loki:       systemctl status loki"
                    ;;
                influxdb)
                    echo "InfluxDB:   systemctl status influxdb"
                    ;;
            esac
        done
    fi
    
    echo ""
    echo "=== Next Steps ==="
    echo "1. Change default passwords"
    echo "2. Configure data sources in Grafana"
    echo "3. Import dashboards"
    echo "4. Configure alerting rules"
    echo "5. Set up backup procedures"
    
    if [[ $USE_SSL == "yes" ]]; then
        echo "6. SSL certificate will auto-renew"
    fi
    
    echo ""
    echo "=== Documentation ==="
    echo "Grafana:    https://grafana.com/docs/"
    echo "Prometheus: https://prometheus.io/docs/"
    echo "Loki:       https://grafana.com/docs/loki/"
    echo "InfluxDB:   https://docs.influxdata.com/"
    
    echo ""
    print_success "Installation completed successfully!"
    
    # Save summary to file
    cat > "$INSTALL_DIR/installation-summary.txt" <<EOF
Monitoring Stack Installation Summary
======================================
Date: $(date)
OS: $OS_TYPE $OS_VERSION
Installation Method: $INSTALL_METHOD
Components: ${COMPONENTS[*]}

Access URLs and credentials have been displayed above.
Please save this information securely.

Configuration: $CONFIG_DIR
Data: $DATA_DIR
Logs: $LOG_DIR
EOF
    
    print_info "Summary saved to: $INSTALL_DIR/installation-summary.txt"
}

#############################################################################
# Cleanup and Rollback
#############################################################################

cleanup_on_error() {
    print_error "Installation failed. Cleaning up..."
    
    if [[ $USE_DOCKER == "yes" ]]; then
        cd "$INSTALL_DIR" 2>/dev/null
        for compose_file in docker-compose-*.yml; do
            [[ -f "$compose_file" ]] && docker compose -f "$compose_file" down 2>/dev/null
        done
    else
        systemctl stop grafana-server prometheus loki influxdb 2>/dev/null
        systemctl disable grafana-server prometheus loki influxdb 2>/dev/null
    fi
    
    print_info "Cleanup completed. Check logs for details."
    exit 1
}

#############################################################################
# Uninstall Function
#############################################################################

uninstall() {
    print_header "Uninstalling Monitoring Stack"
    
    read -p "This will remove all monitoring components and data. Continue? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi
    
    if [[ $USE_DOCKER == "yes" ]]; then
        print_info "Stopping and removing Docker containers..."
        cd "$INSTALL_DIR" 2>/dev/null
        for compose_file in docker-compose-*.yml; do
            [[ -f "$compose_file" ]] && docker compose -f "$compose_file" down -v
        done
        docker network rm monitoring 2>/dev/null
    else
        print_info "Stopping and removing services..."
        systemctl stop grafana-server prometheus loki influxdb nginx 2>/dev/null
        systemctl disable grafana-server prometheus loki influxdb 2>/dev/null
        
        case $OS_FAMILY in
            debian)
                apt-get remove -y grafana prometheus influxdb2 nginx
                ;;
            rhel|fedora)
                if [[ $OS_FAMILY == "fedora" ]]; then
                    dnf remove -y grafana prometheus influxdb2 nginx
                else
                    yum remove -y grafana prometheus influxdb2 nginx
                fi
                ;;
        esac
    fi
    
    print_info "Removing directories..."
    rm -rf "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    rm -f /etc/systemd/system/{prometheus,loki}.service
    rm -f /etc/nginx/sites-available/monitoring
    rm -f /etc/nginx/sites-enabled/monitoring
    
    systemctl daemon-reload
    
    print_success "Uninstall completed"
}

#############################################################################
# Main Installation Flow
#############################################################################

main() {
    trap cleanup_on_error ERR
    
    print_header "Monitoring Stack Installer v$SCRIPT_VERSION"
    
    # Pre-flight checks
    check_root
    detect_os
    check_dependencies
    
    # Get user configuration
    get_user_input
    
    # Setup base directories
    setup_directories
    
    # Install Docker if needed
    if [[ $USE_DOCKER == "yes" ]]; then
        install_docker
        create_docker_network
    fi
    
    # Install selected components
    for component in "${COMPONENTS[@]}"; do
        if [[ $USE_DOCKER == "yes" ]]; then
            case $component in
                grafana) install_grafana_docker ;;
                prometheus) install_prometheus_docker ;;
                loki) install_loki_docker ;;
                influxdb) install_influxdb_docker ;;
            esac
        else
            case $component in
                grafana) install_grafana_native ;;
                prometheus) install_prometheus_native ;;
                loki) install_loki_native ;;
                influxdb) install_influxdb_native ;;
            esac
        fi
    done
    
    # Install and configure Nginx if requested
    if [[ $INSTALL_NGINX == "yes" ]]; then
        install_nginx
        configure_nginx
        
        if [[ $USE_SSL == "yes" ]]; then
            install_certbot
            configure_ssl
        fi
    fi
    
    # Configure firewall
    configure_firewall
    
    # Verify installation
    sleep 5
    verify_installation
    
    # Print summary
    print_summary
}

#############################################################################
# Script Entry Point
#############################################################################

case "${1:-}" in
    --uninstall)
        uninstall
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (no options)    Interactive installation"
        echo "  --uninstall     Remove all components"
        echo "  --help, -h      Show this help message"
        echo ""
        echo "Supported OS:"
        echo "  - Ubuntu/Debian"
        echo "  - RHEL/CentOS/Rocky/AlmaLinux"
        echo "  - Fedora"
        echo "  - openSUSE"
        echo "  - Arch Linux"
        echo ""
        echo "Components:"
        echo "  - Grafana"
        echo "  - Prometheus"
        echo "  - Loki"
        echo "  - InfluxDB"
        ;;
    *)
        main
        ;;
esac
