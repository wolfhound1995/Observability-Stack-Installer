A comprehensive universal installer script for your monitoring stack. Here's what it includes:
Key Features:

Multi-OS Support:

Ubuntu/Debian
RHEL/CentOS/Rocky/AlmaLinux
Fedora
openSUSE/SLES
Arch Linux/Manjaro

Dual Installation Methods:

Docker: Uses docker-compose with isolated containers
Native: System-level installation with systemd services

Components:

Grafana (with default admin credentials)
Prometheus (with Node Exporter in Docker mode)
Loki (with Promtail for log collection)
InfluxDB (v2 with initial setup)

Additional Features:

Nginx Reverse Proxy - Optional, with path-based routing
Let's Encrypt SSL - Automated certificate management with Certbot
Firewall Configuration - UFW and firewalld support
Health Checks - Verifies all services are running
Interactive Setup - User-friendly configuration wizard
Uninstall Option - Clean removal of all components

Usage:
# Make executable
chmod +x install.sh

# Run interactive installer
sudo ./install.sh

# Uninstall everything
sudo ./install.sh --uninstall

# Show help
./install.sh --help
What the script handles:

✅ OS detection and package manager selection
✅ Dependency installation
✅ Docker installation (if needed)
✅ Service configuration files
✅ Data persistence directories
✅ Security (firewall rules, SSL certificates)
✅ Auto-renewal for SSL certificates
✅ Service health verification
✅ Comprehensive post-install summary

The script uses error handling, provides colored output for better readability, and includes rollback functionality if something goes wrong during installation.
