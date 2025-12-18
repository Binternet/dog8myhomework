#!/bin/bash
# Automatically installs required prerequisites (Docker, Terraform, AWS CLI) on macOS or Linux based on OS and architecture.

# Install prerequisites script
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

cd "$PROJECT_DIR"

echo -e "${BLUE}${BOLD}========================================${NC}"
echo -e "${BLUE}${BOLD}Installing Prerequisites${NC}"
echo -e "${BLUE}${BOLD}========================================${NC}\n"

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]] || [[ "$OS" == "Windows_NT" ]]; then
    OS="windows"
    echo -e "\n${YELLOW}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║                                                                ║${NC}"
    echo -e "${YELLOW}${BOLD}║          You are so brave running this on Windows!             ║${NC}"
    echo -e "${YELLOW}${BOLD}║                                                                ║${NC}"
    echo -e "${YELLOW}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${BOLD}\"Bravery and Stupidity are the same thing, the outcome determines your label.\"${NC}"
    echo -e "${BOLD}― Hayden Sixx${NC}\n"
    sleep 2
    echo -e "${YELLOW}Windows support is limited. Some tools need manual installation.${NC}\n"
else
    OS="unknown"
    echo -e "${YELLOW}Unknown OS. Please install prerequisites manually.${NC}"
    exit 1
fi

echo -e "${BLUE}Detected OS: ${OS}${NC}\n"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install unzip (required for Terraform and AWS CLI installation)
if ! command_exists unzip; then
    echo -e "${BLUE}Installing unzip...${NC}"
    if [ "$OS" == "macos" ]; then
        if command_exists brew; then
            brew install unzip
        else
            echo -e "${YELLOW}unzip should be pre-installed on macOS. If not, install Homebrew first.${NC}"
        fi
    elif [ "$OS" == "linux" ]; then
        if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ]; then
            sudo apt-get update
            sudo apt-get install -y unzip
        elif [ "$DISTRO" == "fedora" ] || [ "$DISTRO" == "rhel" ] || [ "$DISTRO" == "centos" ]; then
            sudo dnf install -y unzip
        else
            echo -e "${YELLOW}Please install unzip manually for your Linux distribution.${NC}"
        fi
    fi
    echo -e "${GREEN}✓ unzip installed${NC}"
else
    echo -e "${GREEN}✓ unzip is already installed${NC}"
fi

# Install Docker
if ! command_exists docker; then
    echo -e "${BLUE}Installing Docker...${NC}"
    if [ "$OS" == "macos" ]; then
        echo -e "${YELLOW}Please install Docker Desktop for Mac:${NC}"
        echo -e "  https://docs.docker.com/desktop/install/mac-install/"
        echo -e "${YELLOW}Or use Homebrew:${NC} brew install --cask docker"
    elif [ "$OS" == "windows" ]; then
        echo -e "${YELLOW}Please install Docker Desktop for Windows:${NC}"
        echo -e "  https://docs.docker.com/desktop/install/windows-install/"
    elif [ "$OS" == "linux" ]; then
        if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ]; then
            echo -e "${BLUE}Installing Docker on Ubuntu/Debian...${NC}"
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo usermod -aG docker $USER
            echo -e "${GREEN}✓ Docker installed. Please log out and back in for group changes to take effect.${NC}"
        elif [ "$DISTRO" == "fedora" ] || [ "$DISTRO" == "rhel" ] || [ "$DISTRO" == "centos" ]; then
            echo -e "${BLUE}Installing Docker on Fedora/RHEL/CentOS...${NC}"
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo systemctl start docker
            sudo systemctl enable docker
            sudo usermod -aG docker $USER
            echo -e "${GREEN}✓ Docker installed. Please log out and back in for group changes to take effect.${NC}"
        else
            echo -e "${YELLOW}Please install Docker manually for your Linux distribution:${NC}"
            echo -e "  https://docs.docker.com/engine/install/"
        fi
    fi
else
    echo -e "${GREEN}✓ Docker is already installed${NC}"
fi

# Check Docker Compose
if ! command_exists docker-compose && ! docker compose version &> /dev/null; then
    echo -e "${BLUE}Docker Compose not found. It should be included with Docker Desktop or Docker Engine.${NC}"
    if [ "$OS" == "linux" ]; then
        echo -e "${BLUE}Installing Docker Compose plugin...${NC}"
        if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ]; then
            sudo apt-get install -y docker-compose-plugin
        elif [ "$DISTRO" == "fedora" ] || [ "$DISTRO" == "rhel" ] || [ "$DISTRO" == "centos" ]; then
            sudo dnf install -y docker-compose-plugin
        fi
    elif [ "$OS" == "windows" ]; then
        echo -e "${YELLOW}Docker Compose is included with Docker Desktop for Windows.${NC}"
    fi
else
    echo -e "${GREEN}✓ Docker Compose is available${NC}"
fi

# Install Terraform
if ! command_exists terraform || ! terraform version >/dev/null 2>&1; then
    # Check if terraform exists but can't execute (wrong architecture)
    if command_exists terraform && ! terraform version >/dev/null 2>&1; then
        echo -e "${YELLOW}Terraform binary exists but cannot execute (wrong architecture). Removing...${NC}"
        sudo rm -f /usr/local/bin/terraform 2>/dev/null || rm -f ~/.local/bin/terraform 2>/dev/null || true
    fi
    
    echo -e "${BLUE}Installing Terraform...${NC}"
    if [ "$OS" == "macos" ]; then
        if command_exists brew; then
            brew tap hashicorp/tap
            brew install hashicorp/tap/terraform
        else
            echo -e "${YELLOW}Please install Homebrew first, or download Terraform manually:${NC}"
            echo -e "  https://www.terraform.io/downloads"
        fi
    elif [ "$OS" == "windows" ]; then
        echo -e "${YELLOW}Please install Terraform for Windows:${NC}"
        echo -e "  https://developer.hashicorp.com/terraform/downloads"
        echo -e "${YELLOW}Or use Chocolatey:${NC} choco install terraform"
    elif [ "$OS" == "linux" ]; then
        TERRAFORM_VERSION="1.6.0"
        # Detect architecture
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)
                TERRAFORM_ARCH="amd64"
                ;;
            aarch64|arm64)
                TERRAFORM_ARCH="arm64"
                ;;
            armv7l|armv6l)
                TERRAFORM_ARCH="arm"
                ;;
            *)
                echo -e "${YELLOW}Unsupported architecture: $ARCH. Please install Terraform manually.${NC}"
                echo -e "  https://www.terraform.io/downloads"
                exit 1
                ;;
        esac
        echo -e "${BLUE}Detected architecture: $ARCH, using $TERRAFORM_ARCH${NC}"
        wget -O /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip"
        unzip -o /tmp/terraform.zip -d /tmp
        sudo mv /tmp/terraform /usr/local/bin/
        rm /tmp/terraform.zip
        echo -e "${GREEN}✓ Terraform installed${NC}"
    fi
else
    TERRAFORM_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$TERRAFORM_VERSION" ]; then
        TERRAFORM_VERSION=$(terraform version 2>/dev/null | head -n1 | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | sed 's/v//' | head -n1)
    fi
    if [ -z "$TERRAFORM_VERSION" ]; then
        TERRAFORM_VERSION="unknown"
    fi
    echo -e "${GREEN}✓ Terraform is already installed (version: $TERRAFORM_VERSION)${NC}"
fi

# Install AWS CLI
if ! command_exists aws || ! aws --version >/dev/null 2>&1; then
    # Check if aws exists but can't execute (wrong architecture)
    if command_exists aws && ! aws --version >/dev/null 2>&1; then
        echo -e "${YELLOW}AWS CLI binary exists but cannot execute (wrong architecture). Removing...${NC}"
        sudo rm -rf /usr/local/bin/aws /usr/local/bin/aws_completer /usr/local/aws-cli 2>/dev/null || true
        sudo rm -rf /usr/local/aws 2>/dev/null || true
    fi
    
    echo -e "${BLUE}Installing AWS CLI...${NC}"
    if [ "$OS" == "macos" ]; then
        if command_exists brew; then
            brew install awscli
        else
            echo -e "${YELLOW}Please install Homebrew first, or download AWS CLI manually:${NC}"
            echo -e "  https://aws.amazon.com/cli/"
        fi
    elif [ "$OS" == "windows" ]; then
        echo -e "${YELLOW}Please install AWS CLI for Windows:${NC}"
        echo -e "  https://awscli.amazonaws.com/AWSCLIV2.msi"
        echo -e "${YELLOW}Or use Chocolatey:${NC} choco install awscli"
    elif [ "$OS" == "linux" ]; then
        # Detect architecture
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)
                AWS_CLI_ARCH="x86_64"
                ;;
            aarch64|arm64)
                AWS_CLI_ARCH="aarch64"
                ;;
            *)
                echo -e "${YELLOW}Unsupported architecture: $ARCH. Please install AWS CLI manually.${NC}"
                echo -e "  https://aws.amazon.com/cli/"
                exit 1
                ;;
        esac
        echo -e "${BLUE}Detected architecture: $ARCH, using $AWS_CLI_ARCH${NC}"
        curl "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_CLI_ARCH}.zip" -o "/tmp/awscliv2.zip"
        unzip -o /tmp/awscliv2.zip -d /tmp
        sudo /tmp/aws/install
        rm -rf /tmp/aws /tmp/awscliv2.zip
        echo -e "${GREEN}✓ AWS CLI installed${NC}"
    fi
else
    AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2)
    if [ -z "$AWS_VERSION" ]; then
        AWS_VERSION=$(aws --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    fi
    if [ -z "$AWS_VERSION" ]; then
        AWS_VERSION="unknown"
    fi
    echo -e "${GREEN}✓ AWS CLI is already installed (version: $AWS_VERSION)${NC}"
fi

echo -e "\n${GREEN}${BOLD}========================================${NC}"
echo -e "${GREEN}${BOLD}Required Prerequisites Installation Complete!${NC}"
echo -e "${GREEN}${BOLD}========================================${NC}\n"

# Ask if user wants to install optional prerequisites
echo -e "${BLUE}${BOLD}Optional Prerequisites${NC}"
echo -e "${BLUE}The following tools are optional but may be useful:${NC}"
echo -e "  • kubectl - For Kubernetes cluster management"
echo -e "  • Helm - For Kubernetes package management"
echo -e "  • Python 3.11+ - For local development (dependencies are in Dockerfile)"
echo -e "  • Git - For version control"
echo ""
read -p "Would you like to install optional prerequisites? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}${BOLD}Installing Optional Prerequisites...${NC}\n"
    
    # Install kubectl
    if ! command_exists kubectl; then
        echo -e "${BLUE}Installing kubectl...${NC}"
        if [ "$OS" == "macos" ]; then
            if command_exists brew; then
                brew install kubectl
            else
                echo -e "${YELLOW}Please install Homebrew first, or download kubectl manually:${NC}"
                echo -e "  https://kubernetes.io/docs/tasks/tools/"
            fi
        elif [ "$OS" == "linux" ]; then
            ARCH=$(uname -m)
            case "$ARCH" in
                x86_64)
                    KUBECTL_ARCH="amd64"
                    ;;
                aarch64|arm64)
                    KUBECTL_ARCH="arm64"
                    ;;
                *)
                    echo -e "${YELLOW}Unsupported architecture: $ARCH. Please install kubectl manually.${NC}"
                    echo -e "  https://kubernetes.io/docs/tasks/tools/"
                    ;;
            esac
            if [ -n "$KUBECTL_ARCH" ]; then
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${KUBECTL_ARCH}/kubectl"
                chmod +x kubectl
                sudo mv kubectl /usr/local/bin/
                echo -e "${GREEN}✓ kubectl installed${NC}"
            fi
        elif [ "$OS" == "windows" ]; then
            echo -e "${YELLOW}Please install kubectl manually for Windows:${NC}"
            echo -e "  https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
        fi
    else
        KUBECTL_VERSION=$(kubectl version --client --short 2>&1 | tr '\n' ' ' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | sed 's/v//' || echo "unknown")
        echo -e "${GREEN}✓ kubectl is already installed (version: $KUBECTL_VERSION)${NC}"
    fi
    
    # Install Helm
    if ! command_exists helm; then
        echo -e "${BLUE}Installing Helm...${NC}"
        if [ "$OS" == "macos" ]; then
            if command_exists brew; then
                brew install helm
            else
                echo -e "${YELLOW}Please install Homebrew first, or download Helm manually:${NC}"
                echo -e "  https://helm.sh/docs/intro/install/"
            fi
        elif [ "$OS" == "linux" ]; then
            ARCH=$(uname -m)
            case "$ARCH" in
                x86_64)
                    HELM_ARCH="amd64"
                    ;;
                aarch64|arm64)
                    HELM_ARCH="arm64"
                    ;;
                *)
                    echo -e "${YELLOW}Unsupported architecture: $ARCH. Please install Helm manually.${NC}"
                    echo -e "  https://helm.sh/docs/intro/install/"
                    ;;
            esac
            if [ -n "$HELM_ARCH" ]; then
                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                echo -e "${GREEN}✓ Helm installed${NC}"
            fi
        elif [ "$OS" == "windows" ]; then
            echo -e "${YELLOW}Please install Helm manually for Windows:${NC}"
            echo -e "  https://helm.sh/docs/intro/install/"
        fi
    else
        HELM_VERSION=$(helm version --short 2>&1 | sed 's/v//' | awk '{print $1}' || echo "unknown")
        echo -e "${GREEN}✓ Helm is already installed (version: $HELM_VERSION)${NC}"
    fi
    
    # Install Python 3.11+
    if ! command_exists python3; then
        echo -e "${BLUE}Installing Python 3.11+...${NC}"
        if [ "$OS" == "macos" ]; then
            if command_exists brew; then
                brew install python@3.11
            else
                echo -e "${YELLOW}Please install Homebrew first, or download Python manually:${NC}"
                echo -e "  https://www.python.org/downloads/"
            fi
        elif [ "$OS" == "linux" ]; then
            if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ]; then
                sudo apt-get update
                sudo apt-get install -y python3.11 python3.11-venv python3-pip
            elif [ "$DISTRO" == "fedora" ] || [ "$DISTRO" == "rhel" ] || [ "$DISTRO" == "centos" ]; then
                sudo dnf install -y python3.11 python3-pip
            else
                echo -e "${YELLOW}Please install Python 3.11+ manually for your Linux distribution:${NC}"
                echo -e "  https://www.python.org/downloads/"
            fi
        elif [ "$OS" == "windows" ]; then
            echo -e "${YELLOW}Please install Python 3.11+ manually for Windows:${NC}"
            echo -e "  https://www.python.org/downloads/windows/"
        fi
    else
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}' || echo "unknown")
        echo -e "${GREEN}✓ Python is already installed (version: $PYTHON_VERSION)${NC}"
    fi
    
    # Install Git
    if ! command_exists git; then
        echo -e "${BLUE}Installing Git...${NC}"
        if [ "$OS" == "macos" ]; then
            if command_exists brew; then
                brew install git
            else
                echo -e "${YELLOW}Please install Homebrew first, or download Git manually:${NC}"
                echo -e "  https://git-scm.com/download/mac"
            fi
        elif [ "$OS" == "linux" ]; then
            if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ]; then
                sudo apt-get update
                sudo apt-get install -y git
            elif [ "$DISTRO" == "fedora" ] || [ "$DISTRO" == "rhel" ] || [ "$DISTRO" == "centos" ]; then
                sudo dnf install -y git
            else
                echo -e "${YELLOW}Please install Git manually for your Linux distribution:${NC}"
                echo -e "  https://git-scm.com/download/linux"
            fi
        elif [ "$OS" == "windows" ]; then
            echo -e "${YELLOW}Please install Git manually for Windows:${NC}"
            echo -e "  https://git-scm.com/download/win"
        fi
    else
        GIT_VERSION=$(git --version | awk '{print $3}' || echo "unknown")
        echo -e "${GREEN}✓ Git is already installed (version: $GIT_VERSION)${NC}"
    fi
    
    echo -e "\n${GREEN}${BOLD}========================================${NC}"
    echo -e "${GREEN}${BOLD}Optional Prerequisites Installation Complete!${NC}"
    echo -e "${GREEN}${BOLD}========================================${NC}\n"
else
    echo -e "${YELLOW}Skipping optional prerequisites installation.${NC}\n"
fi

echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. If Docker was just installed, you may need to log out and back in"
echo -e "  2. Start Docker Desktop or Docker service"
echo -e "  3. Configure AWS CLI: ${YELLOW}aws configure${NC}"
echo -e "  4. Run prerequisite check: ${YELLOW}make check-req${NC}\n"

