# Output block to provide the public URL for accessing the Flask app
output "flask_app_url" {
    # The URL combines the public IP of the EC2 instance with Flask's default port 5000
    value = "http://${aws_instance.flask_server.public_ip}:5000"
}