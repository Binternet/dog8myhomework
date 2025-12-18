#!/bin/bash
# Populates the MySQL database with random facts using Docker Compose.

# Docker-based database installation script
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
echo -e "${BLUE}Docker Database Installation${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

# Start MySQL
echo -e "${BLUE}Starting MySQL...${NC}"
$DOCKER_COMPOSE up -d mysql

echo -e "\n${BLUE}Waiting for MySQL to be ready...${NC}"
timeout=30
counter=0
while ! $DOCKER_COMPOSE exec -T mysql mysqladmin ping -h localhost -u root -proot > /dev/null 2>&1; do
    sleep 1
    counter=$((counter + 1))
    if [ $counter -ge $timeout ]; then
        echo -e "${RED}MySQL failed to start within $timeout seconds${NC}"
        $DOCKER_COMPOSE logs mysql
        exit 1
    fi
done
echo -e "${GREEN}✓ MySQL is ready${NC}"

# Populate database with facts
echo -e "\n${BLUE}Populating database with random facts...${NC}"
$DOCKER_COMPOSE run -T --rm -e DB_HOST=mysql -e DB_USER=root -e DB_PASSWORD=root -e DB_NAME=hello_world app python << 'PYTHON_SCRIPT'
import mysql.connector
from mysql.connector import Error
import os

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

try:
    conn = mysql.connector.connect(
        host=os.getenv('DB_HOST', 'mysql'),
        port=int(os.getenv('DB_PORT', '3306')),
        database=os.getenv('DB_NAME', 'hello_world'),
        user=os.getenv('DB_USER', 'root'),
        password=os.getenv('DB_PASSWORD', 'root')
    )
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
    echo -e "\n${BLUE}You can now start the application with:${NC}"
    echo -e "  ${YELLOW}make docker-up${NC}"
else
    echo -e "${RED}✗ Failed to populate database${NC}"
    exit 1
fi

