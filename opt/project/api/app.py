import os
import mysql.connector
from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)  # Enable Cross-Origin requests for the frontend

def get_db_connection():
    """Establishes connection to the MySQL database."""
    try:
        conn = mysql.connector.connect(
            host=os.environ.get('DB_HOST'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD'),
            database=os.environ.get('DB_NAME')
        )
        return conn
    except mysql.connector.Error as err:
        print(f"Error connecting to database: {err}")
        return None

@app.route('/balance/<string:account_number>', methods=['GET'])
def get_balance(account_number):
    """Fetches balance for a given account number."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({"error": "Database connection failed"}), 500

    cursor = conn.cursor(dictionary=True)
    
    # Use the 'formatted_balance' column we created
    query = "SELECT full_name, formatted_balance FROM accounts WHERE account_number = %s"
    
    try:
        cursor.execute(query, (account_number,))
        account = cursor.fetchone()
        
        if account:
            return jsonify(account)
        else:
            return jsonify({"error": "Account not found"}), 404
            
    except mysql.connector.Error as err:
        return jsonify({"error": f"Database query failed: {err}"}), 500
        
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)