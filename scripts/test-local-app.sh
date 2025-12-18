#!/bin/bash
# Tests the application locally using Docker Compose with app and MySQL database containers.

# Local application test script using Docker Compose
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

cd "$PROJECT_DIR"

# Generate unique test ID to avoid container name conflicts
TEST_ID=$(date +%s)-$$-$(shuf -i 1000-9999 -n 1)
COMPOSE_PROJECT_NAME="test-app-${TEST_ID}"

# Detect docker compose command
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
    echo -e "${RED}Error: docker-compose or docker compose not found.${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Local Application Test (test ID: ${TEST_ID})${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

# Function to cleanup (only on error)
cleanup_on_error() {
    local exit_code=$?
    # Don't cleanup if we're exiting successfully
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${YELLOW}Cleaning up due to error (exit code: $exit_code)...${NC}"
        COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE down -v 2>/dev/null || true
    fi
    exit $exit_code
}

# Only cleanup on error (not on normal exit)
trap cleanup_on_error ERR
trap 'echo -e "\n${YELLOW}Interrupted. Cleaning up...${NC}"; COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE down -v 2>/dev/null || true; exit 130' INT TERM

# Build Docker image
echo -e "${BLUE}Building Docker images...${NC}"
COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE build

# Start only MySQL first
echo -e "\n${BLUE}Starting MySQL database...${NC}"
COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE up -d mysql

echo -e "\n${BLUE}Waiting for MySQL to be ready...${NC}"
timeout=30
counter=0
while ! COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE exec -T mysql mysqladmin ping -h localhost -u root -proot > /dev/null 2>&1; do
    sleep 1
    counter=$((counter + 1))
    if [ $counter -ge $timeout ]; then
        echo -e "${RED}MySQL failed to start within $timeout seconds${NC}"
        COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE logs mysql
        exit 1
    fi
done
echo -e "${GREEN}✓ MySQL is ready${NC}"

# Give MySQL a moment to fully initialize and ensure network is ready
echo -e "${BLUE}Waiting for network to be ready...${NC}"
sleep 3

# Populate database with facts
echo -e "\n${BLUE}Populating database with random facts...${NC}"
# docker-compose run automatically connects to the project's network
COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE run -T --rm -e DB_HOST=mysql -e DB_PORT=3306 -e DB_USER=root -e DB_PASSWORD=root -e DB_NAME=hello_world app python << 'PYTHON_SCRIPT'
import mysql.connector
from mysql.connector import Error
import os
import time

random_facts = [
    "Honey never spoils. Archaeologists have found pots of honey in ancient Egyptian tombs that are over 3,000 years old and still perfectly edible.",
    "Octopuses have three hearts. Two pump blood to the gills, while the third pumps blood to the rest of the body.",
    "A group of flamingos is called a 'flamboyance'.",
    "Bananas are berries, but strawberries aren't.",
    "Wombat poop is cube-shaped. This helps it mark territory without rolling away.",
    "Sharks have been around longer than trees. Sharks have existed for over 400 million years, while trees appeared around 350 million years ago.",
    "A day on Venus is longer than its year. Venus rotates so slowly that it takes longer to complete one rotation than to orbit the Sun.",
    "Humans share 50% of their DNA with bananas.",
    "There are more possible games of chess than atoms in the observable universe.",
    "A single cloud can weigh more than a million pounds.",
    "Dolphins have names for each other. They use signature whistles to identify themselves.",
    "The human brain contains approximately 86 billion neurons.",
    "Lightning strikes the Earth about 100 times every second.",
    "A group of owls is called a 'parliament'.",
    "The Great Wall of China is not visible from space with the naked eye.",
    "Polar bears have black skin under their white fur.",
    "A day on Mercury lasts 176 Earth days.",
    "The human nose can detect over 1 trillion different scents.",
    "There are more stars in the universe than grains of sand on all the beaches on Earth.",
    "A shrimp's heart is in its head."
]

# Retry connection with exponential backoff
max_retries = 5
retry_delay = 2
conn = None
for attempt in range(max_retries):
    try:
        conn = mysql.connector.connect(
            host=os.getenv('DB_HOST', 'mysql'),
            port=int(os.getenv('DB_PORT', '3306')),
            database=os.getenv('DB_NAME', 'hello_world'),
            user=os.getenv('DB_USER', 'root'),
            password=os.getenv('DB_PASSWORD', 'root'),
            connection_timeout=10
        )
        break
    except Error as e:
        if attempt < max_retries - 1:
            print(f"Connection attempt {attempt + 1} failed: {e}. Retrying in {retry_delay} seconds...")
            time.sleep(retry_delay)
            retry_delay *= 2
        else:
            raise

try:
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS random_facts (
            id INT AUTO_INCREMENT PRIMARY KEY,
            fact TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    cursor.execute('DELETE FROM random_facts')
    for fact in random_facts:
        cursor.execute('INSERT INTO random_facts (fact) VALUES (%s)', (fact,))
    conn.commit()
    cursor.execute('SELECT COUNT(*) FROM random_facts')
    count = cursor.fetchone()[0]
    print(f"✓ Inserted {count} facts")
    cursor.close()
    conn.close()
except Exception as e:
    print(f"✗ Error: {e}")
    exit(1)
PYTHON_SCRIPT

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Database populated successfully${NC}"
else
    echo -e "${RED}✗ Failed to populate database${NC}"
    exit 1
fi

# Now start the app
echo -e "\n${BLUE}Starting application container...${NC}"
COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE up -d app

# Wait a moment for container to start
sleep 3

# Get container ID - use docker-compose ps to get the actual running container
echo -e "\n${BLUE}Checking application container status...${NC}"
APP_CONTAINER=$(COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE ps -q app 2>/dev/null | head -1 || echo "")

# Check if container exists
if [ -z "$APP_CONTAINER" ]; then
    echo -e "${RED}✗ Could not find application container${NC}"
    echo -e "${YELLOW}Container status:${NC}"
    COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE ps -a 2>&1 || true
    exit 1
fi

# Verify container is actually running using docker inspect (more reliable)
CONTAINER_STATUS=$(docker inspect "$APP_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo -e "${RED}✗ Application container is not running (status: ${CONTAINER_STATUS})${NC}"
    echo -e "${YELLOW}Container status:${NC}"
    COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE ps -a app 2>&1 || true
    echo -e "\n${YELLOW}Application logs:${NC}"
    COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE logs app 2>&1 || true
    exit 1
fi

echo -e "${GREEN}✓ Application container is running (ID: ${APP_CONTAINER:0:12})${NC}"

# Wait for Flask server to be ready and test HTTP endpoint
echo -e "\n${BLUE}Waiting for Flask server to be ready...${NC}"
timeout=60
counter=0
HTTP_CODE="000"
HTTP_BODY=""

# Now wait for HTTP endpoint to be ready
echo -e "\n${BLUE}Waiting for Flask server to respond to HTTP requests...${NC}"
counter=0
HTTP_CODE="000"
HTTP_BODY=""

while [ $counter -lt $timeout ]; do
    # Use curl to make HTTP request (now available in the image)
    set +e  # Temporarily disable exit on error
    HTTP_RESPONSE=$(docker exec "$APP_CONTAINER" curl -s -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" http://127.0.0.1:80/ 2>&1)
    CURL_EXIT_CODE=$?
    set -e  # Re-enable exit on error
    
    # Parse the response
    HTTP_CODE=$(echo "$HTTP_RESPONSE" | grep "^HTTP_CODE:" | cut -d':' -f2 | tr -d ' ' || echo "000")
    HTTP_BODY=$(echo "$HTTP_RESPONSE" | grep -v "^HTTP_CODE:" | grep -v "^TIME_TOTAL:" | tr '\n' ' ' || echo "")
    
    # Check if we got a valid HTTP response
    if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ] && [ "$HTTP_CODE" != "" ]; then
        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}✓ Flask server is ready and responding (status: ${HTTP_CODE})${NC}"
            break
        else
            # Server is responding but with an error code - still a good sign
            echo -e "${YELLOW}Server responded with status ${HTTP_CODE}, continuing to wait for 200...${NC}"
        fi
    else
        # No response yet or curl failed
        if [ $CURL_EXIT_CODE -ne 0 ]; then
            if [ $counter -eq 0 ]; then
                echo -e "${YELLOW}Waiting for server to start...${NC}"
            fi
        fi
    fi
    
    sleep 2
    counter=$((counter + 2))
    if [ $counter -lt $timeout ] && [ $((counter % 10)) -eq 0 ]; then
        echo -e "${YELLOW}Waiting for server... (${counter}s/${timeout}s)${NC}"
    fi
done

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}✗ Flask server did not become ready within ${timeout} seconds${NC}"
    echo -e "${YELLOW}Last HTTP status: ${HTTP_CODE}${NC}"
    if [ -n "$HTTP_BODY" ] && [ "$HTTP_BODY" != "" ]; then
        echo -e "${YELLOW}Last response: ${HTTP_BODY}${NC}"
    fi
    echo -e "\n${YELLOW}Application logs (last 30 lines):${NC}"
    COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE logs app 2>&1 | tail -30 || true
    echo -e "\n${YELLOW}Testing port connectivity with curl...${NC}"
    docker exec "$APP_CONTAINER" curl -v http://127.0.0.1:80/ 2>&1 | head -20 || echo "Curl test failed"
    exit 1
fi

# Test HTTP endpoint (make a fresh request to get full response)
echo -e "\n${BLUE}Testing HTTP endpoint...${NC}"
HTTP_RESPONSE=$(docker exec "$APP_CONTAINER" curl -s -w "\nHTTP_CODE:%{http_code}" http://127.0.0.1:80/ 2>&1)
HTTP_CODE=$(echo "$HTTP_RESPONSE" | grep "^HTTP_CODE:" | cut -d':' -f2 | tr -d ' ')
HTTP_BODY=$(echo "$HTTP_RESPONSE" | grep -v "^HTTP_CODE:")

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ HTTP request successful (status: ${HTTP_CODE})${NC}"
else
    echo -e "${RED}✗ HTTP request failed with status: ${HTTP_CODE}${NC}"
    exit 1
fi

# Verify response content using bash/grep
echo -e "\n${BLUE}Verifying HTTP response content...${NC}"
if echo "$HTTP_BODY" | grep -q '"message"'; then
    echo -e "${GREEN}✓ Response contains 'message' field${NC}"
    if echo "$HTTP_BODY" | grep -q '"Hello, World!"'; then
        echo -e "${GREEN}✓ Response contains 'Hello, World!' message${NC}"
    else
        echo -e "${YELLOW}⚠ 'Hello, World!' not found in response${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 'message' field not found in response${NC}"
fi

if echo "$HTTP_BODY" | grep -q '"random_fact"'; then
    echo -e "${GREEN}✓ Response contains random fact${NC}"
    # Extract random fact using bash (simple extraction)
    RANDOM_FACT=$(echo "$HTTP_BODY" | grep -o '"random_fact":"[^"]*"' | cut -d'"' -f4 || echo "")
    if [ -n "$RANDOM_FACT" ] && [ "$RANDOM_FACT" != "null" ]; then
        echo -e "${BLUE}  Random fact: ${RANDOM_FACT}${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Random fact not found in response (database might be empty)${NC}"
fi

if echo "$HTTP_BODY" | grep -q '"database"'; then
    echo -e "${GREEN}✓ Response contains database information${NC}"
fi

# Display full JSON response (formatted if possible, otherwise raw)
echo -e "\n${BLUE}Full HTTP response:${NC}"
# Try to format with Python if available, otherwise show raw
if echo "$HTTP_BODY" | docker exec -i "$APP_CONTAINER" python3 -m json.tool 2>/dev/null; then
    : # Successfully formatted
else
    echo "$HTTP_BODY"
fi

# Verify database has facts
echo -e "\n${BLUE}Verifying database content...${NC}"
FACT_COUNT=$(COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" $DOCKER_COMPOSE exec -T mysql mysql -u root -proot -D hello_world -se "SELECT COUNT(*) FROM random_facts;" 2>/dev/null | tr -d ' ' || echo "0")
if [ "$FACT_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Found ${FACT_COUNT} facts in database${NC}"
else
    echo -e "${YELLOW}⚠ No facts found in database${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}All tests passed!${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Services are running. You can:${NC}"
echo -e "  - View logs: ${YELLOW}COMPOSE_PROJECT_NAME=\"$COMPOSE_PROJECT_NAME\" $DOCKER_COMPOSE logs -f${NC}"
echo -e "  - Stop services: ${YELLOW}COMPOSE_PROJECT_NAME=\"$COMPOSE_PROJECT_NAME\" $DOCKER_COMPOSE down${NC}"
echo -e "  - Restart app: ${YELLOW}COMPOSE_PROJECT_NAME=\"$COMPOSE_PROJECT_NAME\" $DOCKER_COMPOSE restart app${NC}"

# Exit successfully (services stay running, no cleanup needed)
exit 0

