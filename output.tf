output "flask_app_url" {
    value = "http://${aws_instance.flask_server.public_ip}:5000"
}