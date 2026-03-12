# Terraform block: Global Terraform settings (remote state + provider requirements).
terraform {
  # Terraform Cloud settings: which org/workspace stores state and runs.
  cloud {
    workspaces {
      name = "flask-ec2-dev"
    }
  }
  # Provider requirements: pins which providers this config needs.
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    tls = {
      source = "hashicorp/tls"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

# Locals block: Reusable values shared across resources (common tags here).
locals {
  common_tags = {
    Project     = "Flask-Terraform-Example"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Security Group resource: Allows inbound traffic on port 5000 (Flask) and port 22 (SSH) from anywhere,
# and permits all outbound traffic.
resource "aws_security_group" "flask_sg" {
  name = "flask_security_group"

  # Allow inbound traffic to Flask app on port 5000 from any IP
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound SSH access on port 22 from any IP (should ideally be restricted)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "Flask-Security-Group"
    }
  )
}

# TLS Private Key resource: Generates a local RSA private key to be used for EC2 SSH access.
resource "tls_private_key" "terraform_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
  # No tags for TLS local resource
}

# AWS Key Pair resource: Registers the generated public key with AWS as an EC2 key pair.
resource "aws_key_pair" "generated_key" {
  key_name   = "terraform-key"
  public_key = tls_private_key.terraform_key.public_key_openssh

  tags = merge(
    local.common_tags,
    {
      Name = "Flask-Terraform-Key"
    }
  )
}

# Local file resource: Stores the generated private key securely on disk for SSH access.
resource "local_file" "private_key" {
  content         = tls_private_key.terraform_key.private_key_pem
  filename        = "terraform-key.pem"
  file_permission = "0600"
  # No tags for local file resource
}

# EC2 Instance resource: Provisions an Ubuntu VM, attaches security group, key, and provisions the Flask app.
resource "aws_instance" "flask_server" {
  ami             = var.ami_id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.flask_sg.name]
  key_name        = aws_key_pair.generated_key.key_name

  tags = merge(
    local.common_tags,
    {
      Name = "Flask-Terraform-Server"
    }
  )

  # Remote-exec provisioner: Waits for SSH to become available before executing further setup.
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for SSH...'",
      "sleep 30"
    ]
    # Connection block: How Terraform connects to the instance for remote actions.
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.terraform_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }

  # File provisioner: Uploads app.py from the local system to the instance's home directory.
  provisioner "file" {
    source      = "app/app.py"
    destination = "/home/ubuntu/app.py"

    # Connection block: SSH details for the file transfer.
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.terraform_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }

  # Remote-exec provisioner: Sets up Python environment and systemd service to run the Flask app on boot.
  provisioner "remote-exec" {
    inline = [
      # Update package list and install necessary Python packages
      "sudo apt-get update",
      "sudo apt-get install -y python3-pip python3-venv python3-full",
      # Create and activate virtual environment for Flask
      "python3 -m venv /home/ubuntu/flask-env",
      # Install Flask in the virtual environment
      "/home/ubuntu/flask-env/bin/pip install flask",
      # Ensure the app.py script is executable
      "chmod +x /home/ubuntu/app.py",
      # Kill any process that might be using port 5000 (Flask default)
      "sudo fuser -k 5000/tcp || true",
      # Create systemd service unit file for Flask app
      "echo '[Unit]' | sudo tee /etc/systemd/system/flask-app.service",
      "echo 'Description=Flask App Auto Start' | sudo tee -a /etc/systemd/system/flask-app.service",
      "echo '[Service]' | sudo tee -a /etc/systemd/system/flask-app.service",
      "echo 'User=ubuntu' | sudo tee -a /etc/systemd/system/flask-app.service",
      "echo 'WorkingDirectory=/home/ubuntu' | sudo tee -a /etc/systemd/system/flask-app.service",
      "echo 'ExecStart=/home/ubuntu/flask-env/bin/python3 /home/ubuntu/app.py' | sudo tee -a /etc/systemd/system/flask-app.service",
      "echo 'Restart=always' | sudo tee -a /etc/systemd/system/flask-app.service",
      "echo '[Install]' | sudo tee -a /etc/systemd/system/flask-app.service",
      "echo 'WantedBy=multi-user.target' | sudo tee -a /etc/systemd/system/flask-app.service",
      # Reload systemd, enable and start the Flask app service
      "sudo systemctl daemon-reload",
      "sudo systemctl enable flask-app",
      "sudo systemctl start flask-app"
    ]
    # Connection block: SSH details for running remote commands.
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.terraform_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }
}