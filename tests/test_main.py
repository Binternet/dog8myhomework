"""
Unit tests for main.py application
"""
import os
import sys
import pytest
from unittest.mock import Mock, patch

# Add src to path before importing main
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

# Import after path modification - noqa to suppress E402
from main import get_db_connection, init_database, get_random_fact  # noqa: E402


@pytest.fixture(autouse=True)
def cleanup_env():
    """Fixture to clean up DB environment variables after each test"""
    # Save original values
    original_env = {
        'DB_HOST': os.environ.get('DB_HOST'),
        'DB_PORT': os.environ.get('DB_PORT'),
        'DB_NAME': os.environ.get('DB_NAME'),
        'DB_USER': os.environ.get('DB_USER'),
        'DB_PASSWORD': os.environ.get('DB_PASSWORD'),
    }

    yield

    # Restore or remove environment variables
    for key, value in original_env.items():
        if value is not None:
            os.environ[key] = value
        elif key in os.environ:
            del os.environ[key]


class TestDatabaseConnection:
    """Tests for database connection functionality"""

    @patch('main.mysql.connector.connect')
    def test_get_db_connection_success(self, mock_connect):
        """Test successful database connection"""
        mock_conn = Mock()
        mock_connect.return_value = mock_conn

        conn = get_db_connection()

        assert conn == mock_conn
        mock_connect.assert_called_once()

    @patch('main.mysql.connector.connect')
    def test_get_db_connection_with_env_vars(self, mock_connect):
        """Test database connection with environment variables"""
        mock_conn = Mock()
        mock_connect.return_value = mock_conn

        # Save original values
        original_host = os.environ.get('DB_HOST')
        original_port = os.environ.get('DB_PORT')
        original_name = os.environ.get('DB_NAME')
        original_user = os.environ.get('DB_USER')
        original_password = os.environ.get('DB_PASSWORD')

        try:
            os.environ['DB_HOST'] = 'test-host'
            os.environ['DB_PORT'] = '3307'
            os.environ['DB_NAME'] = 'test_db'
            os.environ['DB_USER'] = 'test_user'
            os.environ['DB_PASSWORD'] = 'test_pass'

            get_db_connection()

            mock_connect.assert_called_once_with(
                host='test-host',
                port=3307,
                database='test_db',
                user='test_user',
                password='test_pass'
            )
        finally:
            # Restore original values
            if original_host is not None:
                os.environ['DB_HOST'] = original_host
            elif 'DB_HOST' in os.environ:
                del os.environ['DB_HOST']

            if original_port is not None:
                os.environ['DB_PORT'] = original_port
            elif 'DB_PORT' in os.environ:
                del os.environ['DB_PORT']

            if original_name is not None:
                os.environ['DB_NAME'] = original_name
            elif 'DB_NAME' in os.environ:
                del os.environ['DB_NAME']

            if original_user is not None:
                os.environ['DB_USER'] = original_user
            elif 'DB_USER' in os.environ:
                del os.environ['DB_USER']

            if original_password is not None:
                os.environ['DB_PASSWORD'] = original_password
            elif 'DB_PASSWORD' in os.environ:
                del os.environ['DB_PASSWORD']

    @patch('main.mysql.connector.connect')
    def test_get_db_connection_failure(self, mock_connect):
        """Test database connection failure"""
        # Import Error from mysql.connector to raise the correct exception type
        from mysql.connector import Error
        mock_connect.side_effect = Error("Connection failed")

        # Patch sys.exit to avoid actually exiting and verify it's called
        with patch('main.sys.exit') as mock_exit:
            get_db_connection()
            mock_exit.assert_called_once_with(1)


class TestDatabaseInitialization:
    """Tests for database initialization"""

    @patch('main.get_db_connection')
    def test_init_database_success(self, mock_get_conn):
        """Test successful database initialization"""
        mock_conn = Mock()
        mock_cursor = Mock()
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        init_database()

        assert mock_cursor.execute.called
        assert mock_conn.commit.called
        mock_cursor.close.assert_called_once()
        mock_conn.close.assert_called_once()

    @patch('main.get_db_connection')
    def test_init_database_creates_table(self, mock_get_conn):
        """Test that init_database creates the random_facts table"""
        mock_conn = Mock()
        mock_cursor = Mock()
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        init_database()

        # Check that CREATE TABLE was called
        create_table_calls = [
            call for call in mock_cursor.execute.call_args_list
            if 'CREATE TABLE' in str(call)
        ]
        assert len(create_table_calls) > 0

    @patch('main.get_db_connection')
    def test_init_database_rollback_on_error(self, mock_get_conn):
        """Test that init_database rolls back on error"""
        from mysql.connector import Error
        mock_conn = Mock()
        mock_cursor = Mock()
        # Raise Error to match the exception type in the code
        mock_cursor.execute.side_effect = Error("Database error")
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        with pytest.raises(Error):
            init_database()

        assert mock_conn.rollback.called


class TestRandomFact:
    """Tests for random fact retrieval"""

    @patch('main.get_db_connection')
    def test_get_random_fact_success(self, mock_get_conn):
        """Test successful random fact retrieval"""
        mock_conn = Mock()
        mock_cursor = Mock()
        mock_cursor.fetchone.return_value = ("Test fact",)
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        fact = get_random_fact()

        assert fact == "Test fact"
        mock_cursor.execute.assert_called_once()
        mock_cursor.close.assert_called_once()
        mock_conn.close.assert_called_once()

    @patch('main.get_db_connection')
    def test_get_random_fact_no_results(self, mock_get_conn):
        """Test random fact retrieval when no facts exist"""
        mock_conn = Mock()
        mock_cursor = Mock()
        mock_cursor.fetchone.return_value = None
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        fact = get_random_fact()

        assert fact is None

    @patch('main.get_db_connection')
    def test_get_random_fact_handles_error(self, mock_get_conn):
        """Test random fact retrieval handles database errors gracefully"""
        from mysql.connector import Error
        mock_conn = Mock()
        mock_cursor = Mock()
        # Raise Error to match the exception type in the code
        mock_cursor.execute.side_effect = Error("Database error")
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        fact = get_random_fact()

        assert fact is None


class TestIntegration:
    """Integration tests (require database)"""

    @pytest.mark.integration
    def test_database_connection_real(self):
        """Integration test: Test real database connection"""
        # Skip if no database configured
        if not os.getenv('DB_HOST'):
            pytest.skip("DB_HOST not set, skipping integration test")

        conn = get_db_connection()
        assert conn is not None
        conn.close()

    @pytest.mark.integration
    def test_init_database_real(self):
        """Integration test: Test real database initialization"""
        if not os.getenv('DB_HOST'):
            pytest.skip("DB_HOST not set, skipping integration test")

        init_database()
        # If we get here without exception, initialization succeeded

    @pytest.mark.integration
    def test_get_random_fact_real(self):
        """Integration test: Test real random fact retrieval"""
        if not os.getenv('DB_HOST'):
            pytest.skip("DB_HOST not set, skipping integration test")

        fact = get_random_fact()
        # Fact can be None if database is empty, which is valid
        assert fact is None or isinstance(fact, str)
