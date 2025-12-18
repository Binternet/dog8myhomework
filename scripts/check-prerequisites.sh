#!/bin/bash
# Checks that all required prerequisites (Docker, Terraform, AWS CLI, etc.) are installed and displays results in a table format.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Arrays to store results
declare -a TOOL_NAMES
declare -a REQUIRED_VERSIONS
declare -a CURRENT_VERSIONS
declare -a RESULTS
declare -a STATUS_COLORS

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Function to check if command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check version
check_version() {
    local min_version=$1
    local current_version=$2
    
    if [ -z "$current_version" ]; then
        return 1
    fi
    
    # Compare versions (simple numeric comparison)
    if [ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1)" = "$min_version" ]; then
        return 0
    else
        return 1
    fi
}

# Function to add result to table
add_result() {
    local name=$1
    local required=$2
    local current=$3
    local result=$4
    local status_color=$5
    
    TOOL_NAMES+=("$name")
    REQUIRED_VERSIONS+=("$required")
    CURRENT_VERSIONS+=("$current")
    RESULTS+=("$result")
    STATUS_COLORS+=("$status_color")
    
    case "$result" in
        "PASS")
            ((PASSED++))
            ;;
        "FAIL")
            ((FAILED++))
            ;;
        "WARN")
            ((WARNINGS++))
            ;;
    esac
}

# Function to print table
print_table() {
    local max_name_len=15
    local max_req_len=20
    local max_cur_len=20
    local max_result_len=10
    
    # Calculate column widths
    for i in "${!TOOL_NAMES[@]}"; do
        name_len=${#TOOL_NAMES[$i]}
        req_len=${#REQUIRED_VERSIONS[$i]}
        cur_len=${#CURRENT_VERSIONS[$i]}
        result_len=${#RESULTS[$i]}
        
        [ $name_len -gt $max_name_len ] && max_name_len=$name_len
        [ $req_len -gt $max_req_len ] && max_req_len=$req_len
        [ $cur_len -gt $max_cur_len ] && max_cur_len=$cur_len
        [ $result_len -gt $max_result_len ] && max_result_len=$result_len
    done
    
    # Add padding
    max_name_len=$((max_name_len + 2))
    max_req_len=$((max_req_len + 2))
    max_cur_len=$((max_cur_len + 2))
    max_result_len=$((max_result_len + 2))
    
    # Print header
    printf "${BOLD}${CYAN}%-${max_name_len}s %-${max_req_len}s %-${max_cur_len}s %-${max_result_len}s${NC}\n" \
        "NAME" "REQUIRED VERSION" "CURRENT VERSION" "RESULT"
    echo -e "${CYAN}$(printf '=%.0s' $(seq 1 $((max_name_len + max_req_len + max_cur_len + max_result_len + 3))))${NC}"
    
    # Print rows
    for i in "${!TOOL_NAMES[@]}"; do
        local color=${STATUS_COLORS[$i]}
        printf "${color}%-${max_name_len}s %-${max_req_len}s %-${max_cur_len}s %-${max_result_len}s${NC}\n" \
            "${TOOL_NAMES[$i]}" \
            "${REQUIRED_VERSIONS[$i]}" \
            "${CURRENT_VERSIONS[$i]}" \
            "${RESULTS[$i]}"
    done
    echo ""
}

# Start checking
echo -e "${BLUE}${BOLD}========================================${NC}"
echo -e "${BLUE}${BOLD}Checking Prerequisites${NC}"
echo -e "${BLUE}${BOLD}========================================${NC}\n"

# Check Docker (REQUIRED)
if check_command docker; then
    DOCKER_VERSION=$(docker --version 2>&1 | awk '{print $3}' | sed 's/,//')
    
    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        add_result "Docker" "Required" "$DOCKER_VERSION" "PASS" "$GREEN"
    else
        add_result "Docker" "Required" "$DOCKER_VERSION (daemon not running)" "FAIL" "$RED"
    fi
else
    add_result "Docker" "Required" "Not installed" "FAIL" "$RED"
fi

# Check Docker Compose (REQUIRED)
if check_command docker-compose || docker compose version &> /dev/null; then
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_VERSION=$(docker compose version 2>&1 | awk '{print $4}' | sed 's/v//')
        add_result "Docker Compose" "Required" "$DOCKER_COMPOSE_VERSION" "PASS" "$GREEN"
    elif check_command docker-compose; then
        DOCKER_COMPOSE_VERSION=$(docker-compose --version 2>&1 | awk '{print $3}' | sed 's/,//')
        add_result "Docker Compose" "Required" "$DOCKER_COMPOSE_VERSION" "PASS" "$GREEN"
    else
        add_result "Docker Compose" "Required" "Not installed" "FAIL" "$RED"
    fi
else
    add_result "Docker Compose" "Required" "Not installed" "FAIL" "$RED"
fi

# Check Terraform >= 1.5.0 (REQUIRED)
if check_command terraform; then
    # Try to actually run terraform to check if it's executable (not wrong architecture)
    if terraform version >/dev/null 2>&1; then
        TERRAFORM_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)
        if [ -z "$TERRAFORM_VERSION" ]; then
            TERRAFORM_VERSION=$(terraform version 2>/dev/null | head -n1 | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | sed 's/v//' | head -n1)
        fi
        
        if [ -n "$TERRAFORM_VERSION" ] && check_version "1.5.0" "$TERRAFORM_VERSION"; then
            add_result "Terraform" ">= 1.5.0" "$TERRAFORM_VERSION" "PASS" "$GREEN"
        elif [ -n "$TERRAFORM_VERSION" ]; then
            add_result "Terraform" ">= 1.5.0" "$TERRAFORM_VERSION" "FAIL" "$RED"
        else
            add_result "Terraform" ">= 1.5.0" "Unknown version" "FAIL" "$RED"
        fi
    else
        # Terraform binary exists but can't execute (wrong architecture)
        add_result "Terraform" ">= 1.5.0" "Wrong architecture (Exec format error)" "FAIL" "$RED"
    fi
else
    add_result "Terraform" ">= 1.5.0" "Not installed" "FAIL" "$RED"
fi

# Check AWS CLI (REQUIRED)
if check_command aws; then
    # Try to actually run aws to check if it's executable (not wrong architecture)
    if aws --version >/dev/null 2>&1; then
        AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2)
        if [ -z "$AWS_VERSION" ]; then
            AWS_VERSION=$(aws --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
        fi
        
        # Check AWS credentials
        if aws sts get-caller-identity &> /dev/null; then
            AWS_REGION=$(aws configure get region 2>/dev/null)
            if [ -n "$AWS_REGION" ]; then
                add_result "AWS CLI" "Required" "$AWS_VERSION (configured)" "PASS" "$GREEN"
            else
                add_result "AWS CLI" "Required" "$AWS_VERSION (no region set)" "WARN" "$YELLOW"
            fi
        else
            add_result "AWS CLI" "Required" "$AWS_VERSION (not configured)" "WARN" "$YELLOW"
        fi
    else
        # AWS CLI binary exists but can't execute (wrong architecture)
        add_result "AWS CLI" "Required" "Wrong architecture (Exec format error)" "FAIL" "$RED"
    fi
else
    add_result "AWS CLI" "Required" "Not installed" "FAIL" "$RED"
fi

# Check kubectl (Optional - only needed for Kubernetes deployment)
if check_command kubectl; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>&1 | tr '\n' ' ' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | sed 's/v//')
    if [ -z "$KUBECTL_VERSION" ]; then
        KUBECTL_VERSION=$(kubectl version --client 2>&1 | tr '\n' ' ' | grep -oE 'GitVersion:"v[^"]+"' | cut -d'"' -f2 | sed 's/v//')
    fi
    if [ -z "$KUBECTL_VERSION" ]; then
        KUBECTL_VERSION="Unknown"
    fi
    
    # Check if kubectl can connect to a cluster (optional check)
    if kubectl cluster-info &> /dev/null 2>&1; then
        add_result "kubectl" "Optional" "$KUBECTL_VERSION" "PASS" "$GREEN"
    else
        add_result "kubectl" "Optional" "$KUBECTL_VERSION (not configured)" "WARN" "$YELLOW"
    fi
else
    add_result "kubectl" "Optional" "Not installed" "WARN" "$YELLOW"
fi

# Check Helm 3.x (Optional - only needed for Kubernetes deployment)
if check_command helm; then
    HELM_VERSION=$(helm version --short 2>&1 | sed 's/v//' | awk '{print $1}')
    HELM_MAJOR=$(echo "$HELM_VERSION" | cut -d. -f1)
    
    if [ "$HELM_MAJOR" -ge 3 ]; then
        add_result "Helm" "Optional" "$HELM_VERSION" "PASS" "$GREEN"
    else
        add_result "Helm" "Optional" "$HELM_VERSION" "WARN" "$YELLOW"
    fi
else
    add_result "Helm" "Optional" "Not installed" "WARN" "$YELLOW"
fi

# Check Python 3.x (Optional - Python deps are in Dockerfile)
if check_command python3; then
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
    
    # Since Python is optional and dependencies are in Docker, any Python 3.x is acceptable
    if [ "$PYTHON_MAJOR" -ge 3 ]; then
        add_result "Python" "Optional" "$PYTHON_VERSION" "PASS" "$GREEN"
    else
        add_result "Python" "Optional" "$PYTHON_VERSION" "WARN" "$YELLOW"
    fi
else
    add_result "Python" "Optional" "Not installed" "WARN" "$YELLOW"
fi

# Check Git (Optional - only needed for version control)
if check_command git; then
    GIT_VERSION=$(git --version | awk '{print $3}')
    add_result "Git" "Optional" "$GIT_VERSION" "PASS" "$GREEN"
else
    add_result "Git" "Optional" "Not installed" "WARN" "$YELLOW"
fi

# Print table
print_table

# Print summary
echo -e "${BOLD}Summary:${NC}"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
echo -e "  ${RED}Failed: $FAILED${NC}"
echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

# Print installation instructions for failed tools
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}${BOLD}Installation Instructions:${NC}"
    echo ""
    
    for i in "${!TOOL_NAMES[@]}"; do
        if [ "${RESULTS[$i]}" = "FAIL" ]; then
            case "${TOOL_NAMES[$i]}" in
                "Docker")
                    echo -e "${RED}  • Docker:${NC} https://docs.docker.com/get-docker/"
                    ;;
                "Docker Compose")
                    echo -e "${RED}  • Docker Compose:${NC} Usually included with Docker Desktop"
                    ;;
                "Terraform")
                    echo -e "${RED}  • Terraform:${NC} https://www.terraform.io/downloads"
                    ;;
                "AWS CLI")
                    echo -e "${RED}  • AWS CLI:${NC} https://aws.amazon.com/cli/"
                    ;;
                "Python")
                    echo -e "${YELLOW}  • Python 3.11+ (Optional):${NC} https://www.python.org/downloads/"
                    echo -e "     ${YELLOW}Note: Python dependencies are installed in Dockerfile.${NC}"
                    ;;
                "kubectl")
                    echo -e "${YELLOW}  • kubectl (Optional):${NC} https://kubernetes.io/docs/tasks/tools/"
                    ;;
                "Helm")
                    echo -e "${YELLOW}  • Helm (Optional):${NC} https://helm.sh/docs/intro/install/"
                    ;;
                "Git")
                    echo -e "${YELLOW}  • Git (Optional):${NC} https://git-scm.com/downloads"
                    ;;
            esac
        fi
    done
    echo ""
fi

# Print configuration instructions for warnings
if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}Configuration Notes:${NC}"
    echo ""
    
    for i in "${!TOOL_NAMES[@]}"; do
        if [ "${RESULTS[$i]}" = "WARN" ]; then
            case "${TOOL_NAMES[$i]}" in
                "Docker")
                    echo -e "${YELLOW}  • Docker:${NC} Start Docker Desktop or Docker service"
                    ;;
                "Docker Compose")
                    echo -e "${YELLOW}  • Docker Compose:${NC} Usually starts with Docker Desktop"
                    ;;
                "AWS CLI")
                    echo -e "${YELLOW}  • AWS CLI:${NC} Run: aws configure"
                    ;;
                "kubectl")
                    echo -e "${YELLOW}  • kubectl:${NC} Run: aws eks update-kubeconfig --region <region> --name <cluster-name>"
                    ;;
            esac
        fi
    done
    echo ""
fi

# Exit with appropriate code
if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ All prerequisites are met!${NC}"
        exit 0
    else
        echo -e "${YELLOW}${BOLD}⚠ All required prerequisites are installed, but some optional configurations need attention.${NC}"
        exit 0
    fi
else
    echo -e "${RED}${BOLD}✗ Some prerequisites are missing. Please install the required tools before proceeding.${NC}"
    echo ""
    echo -e "${BLUE}${BOLD}Would you like to install the missing prerequisites automatically?${NC}"
    echo -e "${YELLOW}This will install: Docker, Docker Compose, Terraform, and AWS CLI${NC}"
    echo ""
    read -p "Run 'make install' to install prerequisites? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Running 'make install'...${NC}"
        make install
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}${BOLD}✓ Installation complete!${NC}"
            echo -e "${BLUE}Re-running prerequisite check...${NC}"
            echo ""
            ./scripts/check-prerequisites.sh
            exit $?
        else
            echo -e "${RED}${BOLD}✗ Installation failed. Please install prerequisites manually.${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Installation skipped. Please install prerequisites manually or run 'make install' later.${NC}"
        exit 1
    fi
fi
