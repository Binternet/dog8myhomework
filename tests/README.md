# Test Suite

This directory contains automated tests for the hello-world application at multiple levels.

## Test Structure

- **`test_main.py`** - Unit tests for the application code
- **`test_integration.py`** - Integration tests for the full application stack

Note: Terraform and Helm validation are handled by separate validation scripts:
- `make validate-terraform` - Validates Terraform configuration
- `make validate-helm` - Validates Helm charts

## Running Tests

### All Tests
```bash
make test
# or
./scripts/run-tests.sh
# or
pytest
```

Note: `make test` runs all tests including linting, unit tests, integration tests, validation, and local app tests.

### Unit Tests Only
```bash
make test-unit
# or
pytest tests/test_main.py
```

### Integration Tests
```bash
# Set database environment variables first
export DB_HOST=localhost
export DB_PORT=3306
export DB_USER=root
export DB_PASSWORD=your_password
export DB_NAME=hello_world

make test-integration
# or
pytest tests/test_integration.py -m integration
```

### Infrastructure Validation
```bash
# Terraform validation
make validate-terraform
# or
./scripts/validate-terraform.sh

# Helm validation
make validate-helm
# or
./scripts/validate-helm.sh
```

## Test Markers

Tests are marked with pytest markers:
- `@pytest.mark.integration` - Integration tests that require external services
- `@pytest.mark.unit` - Unit tests (default)

Run only unit tests:
```bash
pytest -m "not integration"
```

Run only integration tests:
```bash
pytest -m integration
```

## Test Coverage

To run tests with coverage:
```bash
pytest --cov=src --cov-report=html
```

## Prerequisites

Install test dependencies:
```bash
pip install -r requirements.txt
```

Required tools:
- Python 3.11+
- pytest
- MySQL (for integration tests)

Note: Terraform and Helm validation scripts require Terraform and Helm to be installed on the host machine.

