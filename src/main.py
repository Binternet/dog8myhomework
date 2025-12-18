#!/usr/bin/env python3
"""
Hello World application with MySQL database
"""
import mysql.connector
from mysql.connector import Error
import os
import sys
import logging
from flask import Flask, jsonify

# Configure logging to print to stdout with detailed format
# Remove any existing handlers first
root_logger = logging.getLogger()
for handler in root_logger.handlers[:]:
    root_logger.removeHandler(handler)

# Create stdout handler
stdout_handler = logging.StreamHandler(sys.stdout)
stdout_handler.setLevel(logging.DEBUG)
formatter = logging.Formatter(
    '%(asctime)s.%(msecs)03d [%(levelname)s] %(name)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
stdout_handler.setFormatter(formatter)

# Configure root logger
root_logger.setLevel(logging.DEBUG)
root_logger.addHandler(stdout_handler)

# Configure Flask's logger to also use stdout
flask_logger = logging.getLogger('werkzeug')
flask_logger.setLevel(logging.INFO)
flask_logger.addHandler(stdout_handler)

# Get logger for this module
log = logging.getLogger(__name__)


def get_db_connection():
    """Get MySQL database connection"""
    log.debug("get_db_connection() called")
    db_host = os.getenv('DB_HOST', 'localhost')
    db_port = os.getenv('DB_PORT', '3306')
    db_name = os.getenv('DB_NAME', 'hello_world')
    db_user = os.getenv('DB_USER', 'root')
    db_password = os.getenv('DB_PASSWORD', 'root')

    log.debug(f"Connecting to database: host={db_host}, port={db_port}, database={db_name}, user={db_user}")
    log.debug(f"Connection timeout set to 10 seconds")
    try:
        log.debug("Attempting mysql.connector.connect()...")
        log.debug(f"Connection parameters: host={db_host}, port={db_port}, database={db_name}, user={db_user}")
        
        conn = mysql.connector.connect(
            host=db_host,
            port=int(db_port),
            database=db_name,
            user=db_user,
            password=db_password,
            connection_timeout=10,  # Connection timeout in seconds
            autocommit=False,
            raise_on_warnings=False
        )
        log.debug("Database connection established successfully")
        return conn
    except Error as e:
        log.debug(f"Database connection error: {type(e).__name__}: {e}")
        print(f"Error connecting to database: {e}", flush=True)
        raise  # Raise exception instead of sys.exit() so it can be caught
    except Exception as e:
        log.debug(f"Unexpected error in get_db_connection(): {type(e).__name__}: {e}")
        import traceback
        log.debug(f"Traceback: {traceback.format_exc()}")
        raise


def init_database():
    """Initialize the MySQL database and create tables"""
    log.debug("init_database() called")
    try:
        log.debug("Getting database connection...")
        conn = get_db_connection()
        log.debug("Database connection obtained, creating cursor...")
        cursor = conn.cursor()
        log.debug("Cursor created")

        # Create random_facts table if it doesn't exist
        log.debug("Executing CREATE TABLE IF NOT EXISTS...")
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS random_facts (
                id INT AUTO_INCREMENT PRIMARY KEY,
                fact TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        log.debug("CREATE TABLE executed, committing...")
        conn.commit()
        log.debug("Database initialized successfully")
        print("Database initialized successfully", flush=True)
        
        # Populate facts if database is empty
        log.debug("Checking if facts need to be populated...")
        try:
            populate_facts()
        except Exception as e:
            log.warning(f"Failed to populate facts: {type(e).__name__}: {e}", exc_info=True)
            # Don't fail initialization if fact population fails
    except Error as e:
        log.debug(f"Database Error in init_database(): {e}")
        print(f"Error initializing database: {e}", flush=True)
        if 'conn' in locals():
            conn.rollback()
        raise
    except Exception as e:
        log.debug(f"Unexpected error in init_database(): {type(e).__name__}: {e}")
        raise
    finally:
        if 'cursor' in locals():
            log.debug("Closing cursor...")
            cursor.close()
        if 'conn' in locals():
            log.debug("Closing database connection...")
            conn.close()
            log.debug("Database connection closed")


def populate_facts():
    """Populate the database with random facts if the table is empty"""
    log.debug("populate_facts() called")
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if facts already exist
        log.debug("Checking if facts already exist...")
        cursor.execute('SELECT COUNT(*) FROM random_facts')
        fact_count = cursor.fetchone()[0]
        log.debug(f"Found {fact_count} facts in database")
        
        if fact_count > 0:
            log.debug("Facts already exist, skipping population")
            return
        
        # Populate with default facts
        log.debug("No facts found, populating database...")
        facts = [
            "The first computer bug was an actual bug - a moth found in the Harvard Mark II computer in 1947.",
            "A group of flamingos is called a 'flamboyance'.",
            "Octopuses have three hearts and blue blood.",
            "Honey never spoils - archaeologists have found 3000-year-old honey that's still edible.",
            "Bananas are berries, but strawberries aren't.",
            "A day on Venus is longer than its year.",
            "Sharks have been around longer than trees.",
            "Wombat poop is cube-shaped.",
            "A single cloud can weigh more than a million pounds.",
            "The human brain uses about 20% of the body's total energy.",
            "Dolphins have names for each other.",
            "A group of owls is called a 'parliament'.",
            "The first email was sent in 1971.",
            "There are more possible games of chess than atoms in the observable universe.",
            "A 'jiffy' is an actual unit of time - 1/100th of a second."
        ]
        
        log.debug(f"Inserting {len(facts)} facts into database...")
        insert_query = 'INSERT INTO random_facts (fact) VALUES (%s)'
        cursor.executemany(insert_query, [(fact,) for fact in facts])
        conn.commit()
        log.info(f"Successfully populated database with {len(facts)} facts")
        print(f"Database populated with {len(facts)} facts", flush=True)
    except Error as e:
        log.error(f"Database Error in populate_facts(): {e}", exc_info=True)
        if conn:
            conn.rollback()
        raise
    except Exception as e:
        log.error(f"Unexpected error in populate_facts(): {type(e).__name__}: {e}", exc_info=True)
        raise
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


def get_random_fact():
    """Retrieve a random fact from the database"""
    log.debug("get_random_fact() called")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        log.debug("Executing SELECT query...")
        cursor.execute('SELECT fact FROM random_facts ORDER BY RAND() LIMIT 1')
        result = cursor.fetchone()
        if result:
            log.debug(f"Random fact retrieved: {result[0][:50]}...")
            return result[0]
        else:
            log.debug("No random facts found in database")
            return None
    except Error as e:
        log.debug(f"Database Error retrieving random fact: {e}")
        print(f"Error retrieving random fact: {e}", flush=True)
        return None
    except Exception as e:
        log.debug(f"Unexpected error in get_random_fact(): {type(e).__name__}: {e}")
        return None
    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'conn' in locals():
            conn.close()


app = Flask(__name__)


@app.route('/')
def hello_world():
    """HTTP endpoint that returns Hello World with a random fact"""
    log.debug("HTTP request received at / endpoint")
    db_host = os.getenv('DB_HOST', 'localhost')
    db_name = os.getenv('DB_NAME', 'hello_world')
    log.debug(f"Environment: DB_HOST={db_host}, DB_NAME={db_name}")

    try:
        # Initialize database (idempotent) - with timeout handling
        db_init_error = None
        log.debug("Attempting database initialization...")
        try:
            init_database()
            log.debug("Database initialization completed successfully")
        except Exception as e:
            db_init_error = str(e)
            log.debug(f"Database initialization failed: {db_init_error}")
            # Log the error but continue - readiness probe needs 200 response

        # Get a random fact (non-blocking - if it fails, continue without fact)
        random_fact = None
        log.debug("Attempting to get random fact...")
        try:
            random_fact = get_random_fact()
            log.debug(f"Random fact retrieval {'succeeded' if random_fact else 'returned None'}")
        except Exception as e:
            log.debug(f"Exception getting random fact: {type(e).__name__}: {e}")
            pass  # Continue without random fact if query fails

        # Check for VERSION file (added during build from git commit hash)
        log.debug("Checking for VERSION file...")
        version = None
        # VERSION file should be in the same directory as main.py (or in the app root)
        version_file_path = os.path.join(os.path.dirname(__file__), 'VERSION')
        log.debug(f"Checking VERSION file at: {version_file_path}")
        # Also check in the app root directory
        if not os.path.exists(version_file_path):
            version_file_path = '/app/VERSION'
            log.debug(f"VERSION file not found, checking: {version_file_path}")
        if os.path.exists(version_file_path):
            log.debug(f"VERSION file found at: {version_file_path}")
            try:
                with open(version_file_path, 'r') as f:
                    version = f.read().strip()
                log.debug(f"VERSION file read successfully: {version}")
            except Exception as e:
                log.debug(f"Error reading VERSION file: {e}")
                pass  # If we can't read it, just skip it
        else:
            log.debug("VERSION file not found")

        log.debug("Building response JSON...")
        response = {
            "message": "Hello, World!",
            "database": {
                "host": db_host,
                "name": db_name
            }
        }

        if version:
            response["version"] = version

        if db_init_error:
            response["error"] = f"Database initialization failed: {db_init_error}"
            response["status"] = "degraded"
        else:
            response["status"] = "healthy"

        if random_fact:
            response["random_fact"] = random_fact
        else:
            if not db_init_error:
                response["random_fact"] = "No facts found in database. Please run the installation script to populate facts."

        log.debug("Returning HTTP 200 response")
        # Always return 200 for readiness probe - include error in response body if needed
        return jsonify(response), 200
    except Exception as e:
        log.debug(f"Unexpected exception in hello_world(): {type(e).__name__}: {e}")
        import traceback
        log.debug(f"Traceback: {traceback.format_exc()}")
        return jsonify({
            "message": "Hello, World!",
            "error": str(e),
            "database": {
                "host": db_host,
                "name": db_name
            }
        }), 500


def main():
    """Main function - starts the Flask web server"""
    log.debug("=" * 70)
    log.debug("main() function called - Application starting")
    log.debug("=" * 70)
    
    db_host = os.getenv('DB_HOST', 'localhost')
    db_name = os.getenv('DB_NAME', 'hello_world')
    log.debug(f"Environment variables: DB_HOST={db_host}, DB_NAME={db_name}")

    print("Starting Hello World application...", flush=True)
    print(f"Connecting to MySQL database: {db_name} at {db_host}", flush=True)
    print("HTTP server will be available on port 80", flush=True)
    log.debug("Initial print statements completed")

    # Initialize database on startup (non-blocking - don't fail if DB is not ready)
    # The endpoint will handle DB initialization on each request
    log.debug("Starting database initialization attempt...")
    try:
        init_database()
        log.debug("Database initialization succeeded in main()")
        print("Database initialized successfully", flush=True)
    except Exception as e:
        log.debug(f"Database initialization failed in main(): {type(e).__name__}: {e}")
        print(f"Warning: Could not initialize database on startup: {e}", flush=True)
        print("Application will continue - database will be initialized on first request", flush=True)
    log.debug("Database initialization attempt completed (success or failure)")

    # Start Flask server - this must not be blocked by database issues
    port = int(os.getenv('PORT', '80'))
    log.debug(f"Preparing to start Flask server on port {port}")
    print(f"Starting Flask server on 0.0.0.0:{port}...", flush=True)
    log.debug("About to call app.run()...")
    
    try:
        log.debug(f"Calling app.run(host='0.0.0.0', port={port}, debug=False)")
        app.run(host='0.0.0.0', port=port, debug=False)
        log.debug("app.run() returned (this should not happen normally)")
    except Exception as e:
        log.debug(f"Fatal error in app.run(): {type(e).__name__}: {e}")
        import traceback
        log.debug(f"Traceback: {traceback.format_exc()}")
        print(f"Fatal error starting Flask server: {e}", flush=True)
        sys.exit(1)


if __name__ == "__main__":
    log.debug("Script executed as main - entering main() function")
    try:
        main()
    except Exception as e:
        log.debug(f"Fatal exception in __main__: {type(e).__name__}: {e}")
        import traceback
        log.debug(f"Traceback: {traceback.format_exc()}")
        print(f"Fatal error: {e}", flush=True)
        sys.exit(1)
