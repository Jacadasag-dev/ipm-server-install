#!/bin/bash

# iPeople Password Manager Installer Script
# This script installs Docker, Docker Compose, and sets up the password manager

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

# Check if running on Ubuntu/Debian
if [ ! -f /etc/os-release ]; then
    print_error "This installer requires Ubuntu or Debian"
    exit 1
fi

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   print_error "Please do not run this script as root. It will use sudo when needed."
   exit 1
fi

echo "======================================"
echo "iPeople Password Manager Installer"
echo "======================================"
echo ""

# Step 1: Install Docker
print_info "Checking for Docker installation..."
if ! command -v docker &> /dev/null; then
    print_info "Docker not found. Installing Docker..."
    
    # Add Docker's official GPG key
    print_status "Adding Docker GPG key..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add the repository to Apt sources
    print_status "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    print_status "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    print_status "Adding user to docker group..."
    sudo usermod -aG docker $USER
    print_info "You'll need to log out and back in for docker group membership to take effect"
    
else
    print_status "Docker is already installed"
fi

# Step 2: Check for Docker Compose plugin
print_info "Checking for Docker Compose plugin..."
if ! docker compose version &> /dev/null; then
    print_status "Installing Docker Compose plugin..."
    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin
else
    print_status "Docker Compose plugin is already installed"
fi

# Step 3: Create installation directory
INSTALL_DIR="$HOME/.local/share/ipeople-password-manager"
print_status "Creating installation directory at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Step 4: Create docker-compose.yml
print_status "Creating docker-compose.yml configuration..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  db:
    image: postgres:16-alpine
    container_name: ipeople-pm-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${DB_PASSWORD:-ipeople_pm_secure_password}
      POSTGRES_DB: ipeople_pm
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  app:
    image: jacadasag/ipeople-password-manager:latest
    container_name: ipeople-pm-app
    ports:
      - "${APP_PORT:-3000}:3000"
    environment:
      DATABASE_URL: postgres://postgres:${DB_PASSWORD:-ipeople_pm_secure_password}@db:5432/ipeople_pm
      JWT_SECRET: ${JWT_SECRET}
      RUST_LOG: ${LOG_LEVEL:-ipeople_password_manager=debug,tower_http=debug,axum=debug}
      # Email Configuration
      SMTP_HOST: ${SMTP_HOST:-}
      SMTP_PORT: ${SMTP_PORT:-587}
      SMTP_USERNAME: ${SMTP_USERNAME:-}
      SMTP_PASSWORD: ${SMTP_PASSWORD:-}
      SMTP_FROM_EMAIL: ${SMTP_FROM_EMAIL:-noreply@example.com}
      SMTP_FROM_NAME: ${SMTP_FROM_NAME:-iPeople Password Manager}
      BASE_URL: ${BASE_URL:-http://localhost:3000}
      # SAML Configuration (optional)
      SAML_ENTITY_ID: ${SAML_ENTITY_ID:-https://passwordmanager.yourdomain.com}
      SAML_ACS_URL: ${SAML_ACS_URL:-https://passwordmanager.yourdomain.com/saml/acs}
      SAML_SLO_URL: ${SAML_SLO_URL:-https://passwordmanager.yourdomain.com/saml/slo}
      SAML_CERTIFICATE: ${SAML_CERTIFICATE:-}
      SAML_PRIVATE_KEY: ${SAML_PRIVATE_KEY:-}
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

volumes:
  postgres_data:
    name: ipeople_pm_postgres_data

networks:
  default:
    name: ipeople_pm_network
EOF

# Step 5: Create .env file with secure defaults
print_status "Generating secure configuration..."
JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
DB_PASSWORD=$(openssl rand -hex 16 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

cat > .env << EOF
# iPeople Password Manager Configuration
# Generated on $(date)

# Database Configuration
DB_PASSWORD=$DB_PASSWORD

# JWT Secret for token signing
JWT_SECRET=$JWT_SECRET

# Application Port
APP_PORT=3000

# Logging Level
LOG_LEVEL=ipeople_password_manager=debug,tower_http=debug,axum=debug

# Email Configuration (optional - for email verification)
# Uncomment and configure these lines to enable email sending
# For Gmail, use an App Password: https://support.google.com/accounts/answer/185833
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
# SMTP_USERNAME=your-email@gmail.com
# SMTP_PASSWORD=your-app-password
SMTP_FROM_EMAIL=noreply@example.com
SMTP_FROM_NAME=iPeople Password Manager
BASE_URL=http://localhost:3000

# SAML Configuration (optional - configure for Azure AD integration)
# SAML_ENTITY_ID=https://passwordmanager.yourdomain.com
# SAML_ACS_URL=https://passwordmanager.yourdomain.com/saml/acs
# SAML_SLO_URL=https://passwordmanager.yourdomain.com/saml/slo
# SAML_CERTIFICATE=base64_encoded_certificate
# SAML_PRIVATE_KEY=base64_encoded_private_key
EOF

chmod 600 .env  # Secure the env file

# Step 6: Create management script
print_status "Creating management command..."
sudo tee /usr/local/bin/ipeople-pm > /dev/null << 'EOF'
#!/bin/bash

# Get the actual user's home directory, even when running with sudo
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

INSTALL_DIR="$USER_HOME/.local/share/ipeople-password-manager"
cd "$INSTALL_DIR" || exit 1

case "$1" in
    start)
        echo "Starting iPeople Password Manager..."
        if [ "$EUID" -eq 0 ]; then
            docker compose up -d
        else
            # Check if user is in docker group
            if groups | grep -q docker; then
                docker compose up -d
            else
                sudo docker compose up -d
            fi
        fi
        echo ""
        echo "✅ iPeople Password Manager is running!"
        echo "🌐 Access at: http://localhost:${APP_PORT:-3000}"
        echo "📁 Configuration: $INSTALL_DIR/.env"
        ;;
    stop)
        echo "Stopping iPeople Password Manager..."
        if [ "$EUID" -eq 0 ]; then
            docker compose down
        else
            if groups | grep -q docker; then
                docker compose down
            else
                sudo docker compose down
            fi
        fi
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    logs)
        if [ "$EUID" -eq 0 ]; then
            docker compose logs -f "${2:-}"
        else
            if groups | grep -q docker; then
                docker compose logs -f "${2:-}"
            else
                sudo docker compose logs -f "${2:-}"
            fi
        fi
        ;;
    status)
        if [ "$EUID" -eq 0 ]; then
            docker compose ps
        else
            if groups | grep -q docker; then
                docker compose ps
            else
                sudo docker compose ps
            fi
        fi
        ;;
    update)
        echo "Updating iPeople Password Manager..."
        
        # Pull latest images
        if [ "$EUID" -eq 0 ]; then
            docker compose pull
        else
            if groups | grep -q docker; then
                docker compose pull
            else
                sudo docker compose pull
            fi
        fi
        
        # Restart containers with existing configuration
        $0 restart
        
        echo "✅ Update complete!"
        ;;
    clean-update)
        echo "⚠️  This will remove the database and start fresh!"
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            echo "Performing clean update..."
            
            # Stop and remove everything
            $0 stop
            if [ "$EUID" -eq 0 ]; then
                docker compose down -v
            else
                if groups | grep -q docker; then
                    docker compose down -v
                else
                    sudo docker compose down -v
                fi
            fi
            
            # Pull latest images
            if [ "$EUID" -eq 0 ]; then
                docker compose pull
            else
                if groups | grep -q docker; then
                    docker compose pull
                else
                    sudo docker compose pull
                fi
            fi
            
            # Start fresh
            $0 start
            
            echo "✅ Clean update complete!"
        else
            echo "Clean update cancelled"
        fi
        ;;
    backup)
        BACKUP_DIR="$USER_HOME/ipeople-pm-backups"
        mkdir -p "$BACKUP_DIR"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        echo "Creating backup..."
        if [ "$EUID" -eq 0 ]; then
            docker compose exec -T db pg_dump -U postgres ipeople_pm | gzip > "$BACKUP_DIR/backup_$TIMESTAMP.sql.gz"
        else
            if groups | grep -q docker; then
                docker compose exec -T db pg_dump -U postgres ipeople_pm | gzip > "$BACKUP_DIR/backup_$TIMESTAMP.sql.gz"
            else
                sudo docker compose exec -T db pg_dump -U postgres ipeople_pm | gzip > "$BACKUP_DIR/backup_$TIMESTAMP.sql.gz"
            fi
        fi
        echo "✅ Backup saved to: $BACKUP_DIR/backup_$TIMESTAMP.sql.gz"
        ;;
    config)
        echo "Configuration file: $INSTALL_DIR/.env"
        echo ""
        echo "To edit configuration:"
        echo "  nano $INSTALL_DIR/.env"
        echo "  ipeople-pm restart"
        ;;
    uninstall)
        echo "⚠️  This will remove iPeople Password Manager and ALL DATA!"
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            $0 stop
            if [ "$EUID" -eq 0 ]; then
                docker compose down -v
            else
                if groups | grep -q docker; then
                    docker compose down -v
                else
                    sudo docker compose down -v
                fi
            fi
            rm -rf "$INSTALL_DIR"
            sudo rm -f /usr/local/bin/ipeople-pm
            echo "✅ iPeople Password Manager has been uninstalled"
        else
            echo "Uninstall cancelled"
        fi
        ;;
    *)
        echo "iPeople Password Manager Management Tool"
        echo ""
        echo "Usage: ipeople-pm {command}"
        echo ""
        echo "Commands:"
        echo "  start     - Start the password manager"
        echo "  stop      - Stop the password manager"
        echo "  restart   - Restart the password manager"
        echo "  status    - Show running status"
        echo "  logs      - View logs (optional: logs app/db)"
        echo "  update    - Update to latest version"
        echo "  clean-update - Update with fresh database (removes data)"
        echo "  backup    - Create database backup"
        echo "  config    - Show configuration location"
        echo "  uninstall - Remove the password manager"
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/ipeople-pm

# Step 7: Pull Docker images
print_status "Pulling Docker images..."
cd "$INSTALL_DIR"
if groups | grep -q docker 2>/dev/null; then
    docker compose pull
else
    sudo docker compose pull
fi

# Step 8: Start services
print_status "Starting services..."
if groups | grep -q docker 2>/dev/null; then
    docker compose up -d
else
    sudo docker compose up -d
fi

# Final message
echo ""
echo "======================================"
echo "✅ Installation Complete!"
echo "======================================"
echo ""
echo "iPeople Password Manager has been installed successfully!"
echo ""
echo "🌐 Access URL: http://localhost:3000"
echo "📁 Config location: $INSTALL_DIR/.env"
echo ""
echo "Available commands:"
echo "  ipeople-pm start     - Start the password manager"
echo "  ipeople-pm stop      - Stop the password manager"
echo "  ipeople-pm logs      - View logs"
echo "  ipeople-pm status    - Check status"
echo "  ipeople-pm update    - Update to latest version"
echo "  ipeople-pm backup    - Create a backup"
echo ""

if ! groups | grep -q docker 2>/dev/null; then
    echo "⚠️  IMPORTANT: You need to log out and back in for docker group membership to take effect."
    echo "   Until then, commands will use sudo."
fi

echo ""
echo "To configure Bitwarden clients:"
echo "  Set server URL to: http://localhost:3000"
echo ""
echo "For production use:"
echo "  1. Set up a reverse proxy with SSL (nginx/caddy)"
echo "  2. Configure your domain"
echo "  3. Edit $INSTALL_DIR/.env for SAML settings"
echo ""