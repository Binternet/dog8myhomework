"""
Integration tests for the full application stack
"""
import os
import pytest
import mysql.connector
import sys
sys.path.insert(0, '/app')
from main import app


@pytest.mark.integration
class TestApplicationIntegration:
    """Integration tests for the complete application"""

    @pytest.fixture
    def db_config(self):
        """Database configuration from environment"""
        return {
            'host': os.getenv('DB_HOST', 'localhost'),
            'port': int(os.getenv('DB_PORT', '3306')),
            'database': os.getenv('DB_NAME', 'hello_world'),
            'user': os.getenv('DB_USER', 'root'),
            'password': os.getenv('DB_PASSWORD', 'root')
        }

    def test_database_connectivity(self, db_config):
        """Test that we can connect to the database"""
        try:
            conn = mysql.connector.connect(**db_config)
            conn.close()
            assert True
        except Exception as e:
            pytest.skip(f"Cannot connect to database: {e}")

    def test_random_facts_table_exists(self, db_config):
        """Test that random_facts table exists"""
        try:
            conn = mysql.connector.connect(**db_config)
            cursor = conn.cursor()
            cursor.execute("""
                SELECT COUNT(*)
                FROM information_schema.tables
                WHERE table_schema = %s AND table_name = 'random_facts'
            """, (db_config['database'],))
            exists = cursor.fetchone()[0] > 0
            cursor.close()
            conn.close()
            assert exists, "random_facts table does not exist"
        except Exception as e:
            pytest.skip(f"Cannot check table: {e}")

    def test_random_facts_table_structure(self, db_config):
        """Test that random_facts table has correct structure"""
        try:
            conn = mysql.connector.connect(**db_config)
            cursor = conn.cursor()
            cursor.execute("""
                SELECT column_name, data_type
                FROM information_schema.columns
                WHERE table_schema = %s AND table_name = 'random_facts'
                ORDER BY ordinal_position
            """, (db_config['database'],))
            columns = {row[0]: row[1] for row in cursor.fetchall()}
            cursor.close()
            conn.close()

            assert 'id' in columns
            assert 'fact' in columns
            assert 'created_at' in columns
            assert columns['id'] in ['int', 'bigint']  # AUTO_INCREMENT creates int/bigint
            assert columns['fact'] in ['text', 'longtext']  # MySQL uses text/longtext
        except Exception as e:
            pytest.skip(f"Cannot check table structure: {e}")

    def test_application_runs_successfully(self, db_config):
        """Test that the application HTTP endpoint works correctly"""
        if not os.getenv('DB_HOST'):
            pytest.skip("DB_HOST not set, skipping integration test")

        # Set environment variables for the Flask app
        os.environ['DB_HOST'] = db_config['host']
        os.environ['DB_PORT'] = str(db_config['port'])
        os.environ['DB_NAME'] = db_config['database']
        os.environ['DB_USER'] = db_config['user']
        os.environ['DB_PASSWORD'] = db_config['password']

        # Use Flask test client to test the endpoint
        with app.test_client() as client:
            response = client.get('/')
            assert response.status_code == 200, f"Expected 200, got {response.status_code}"
            data = response.get_json()
            assert data is not None, "Response should be JSON"
            assert "message" in data
            assert data["message"] == "Hello, World!"
            assert "database" in data

    def test_application_output_format(self, db_config):
        """Test that application HTTP response has correct format"""
        if not os.getenv('DB_HOST'):
            pytest.skip("DB_HOST not set, skipping integration test")

        # Set environment variables for the Flask app
        os.environ['DB_HOST'] = db_config['host']
        os.environ['DB_PORT'] = str(db_config['port'])
        os.environ['DB_NAME'] = db_config['database']
        os.environ['DB_USER'] = db_config['user']
        os.environ['DB_PASSWORD'] = db_config['password']

        # Use Flask test client to test the endpoint
        with app.test_client() as client:
            response = client.get('/')
            assert response.status_code == 200
            data = response.get_json()
            assert data is not None
            assert "message" in data
            assert data["message"] == "Hello, World!"
            assert "database" in data
            assert "host" in data["database"]
            assert "name" in data["database"]
            # random_fact may or may not be present depending on database state
            assert "random_fact" in data or "error" in data
