FROM python:3.11-slim

# Install curl, wget, vim, nano, and netcat for health checks, testing, and debugging
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    vim \
    nano \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./

# Copy tests directory
COPY tests/ ./tests/

# Copy pytest configuration
COPY pytest.ini ./

# Expose port 80 for HTTP traffic
EXPOSE 80

# Run the application
CMD ["python", "main.py"]

