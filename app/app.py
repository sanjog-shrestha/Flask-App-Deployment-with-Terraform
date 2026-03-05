# Import the Flask class from the flask module
from flask import Flask

# Create the Flask application instance
app = Flask(__name__)

# Define the route for the root URL ('/')
@app.route('/')
def home():
    # Return a simple greeting message
    return "Hello, from Flask deployed with Terraform!"

# Check if this script is being run directly (and not imported)
if __name__ == '__main__':
    # Start the Flask application, listening on all interfaces at port 5000
    app.run(host='0.0.0.0', port=5000)