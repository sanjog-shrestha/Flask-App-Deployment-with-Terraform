# Terraform outputs.
#
# These outputs are intended to help you discover the deployed endpoints
# (ALB DNS name, Flask URL, and instance public IP).

# Output block to provide the public URL for accessing the Flask app
output "flask_app_url" {
  # The URL combines the public IP of the EC2 instance with Flask's default port 5000
  value = "http://${aws_instance.flask_server.public_ip}:5000"
}

# ALB DNS name for use with the load balancer (if you route traffic through it).
output "alb_dns_name" {
  description = "The DNS name of th Application Load Balaner"
  value       = aws_lb.flask_alb.dns_name
}

# Direct public IP of the EC2 instance (useful for SSH and debugging).
output "ec2_public_ip" {
  description = "Direct public IP of the EC2 instance (ssh only)"
  value       = aws_instance.flask_server.public_ip
}