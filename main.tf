# Flask + AWS infrastructure definition.
#
# This configuration provisions:
# - An EC2 instance that installs and runs a Flask app via `systemd`
# - An internet-facing Application Load Balancer (ALB) with a listener
# - Security groups to control inbound traffic to the ALB and EC2 instance
#
# VPC and subnet configuration created below (not provided via variables).

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

# VPC resource
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "Flask-VPC" })
}

# Internet Gateway for the VPC
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "Flask-IGW" })
}

# Two public subnets in different AZs for ALB high-availability
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, { Name = "Flask-Public-Subnet-A" })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, { Name = "Flask-Public-Subnet-B" })
}

# Data source for availability zones
data "aws_availability_zones" "available" {}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "Flask-Public-RT" })
}

# Route table associations for the public subnets
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Security group for the public Application Load Balancer (ALB).
# Allows inbound HTTP (port 80) and all outbound traffic.
resource "aws_security_group" "alb_sg" {
  name        = "alb_security_group"
  description = "Allow HTTP inbound to ALB from the internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "ALB-Security-Group" })
}
# Security Group resource: Allows inbound traffic on port 5000 (Flask) and port 22 (SSH) from anywhere,
# and permits all outbound traffic.
resource "aws_security_group" "flask_sg" {
  name        = "flask_security_group"
  description = "Allow Flask Traffic from ALB & SSH from anywhere"
  vpc_id      = aws_vpc.main.id

  # Allow inbound traffic to Flask app on port 5000 only from ALB SG
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
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
  ami                    = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.flask_sg.id]
  key_name               = aws_key_pair.generated_key.key_name
  # Place EC2 in the first public subnet
  subnet_id              = aws_subnet.public_a.id

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

# Internet-facing Application Load Balancer.
resource "aws_lb" "flask_alb" {
  name                       = "flask-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  enable_deletion_protection = false
  tags                       = merge(local.common_tags, { Name = "Flask-ALB" })
}

# Target group that routes traffic to the EC2 instance on port 5000.
resource "aws_lb_target_group" "flask_tg" {
  name     = "flask-target-group"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "5000"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = merge(local.common_tags, { Name = "Flask-Target-Group" })
}

# Attach the EC2 instance to the target group.
resource "aws_lb_target_group_attachment" "flask_tg_attachment" {
  target_group_arn = aws_lb_target_group.flask_tg.arn
  target_id        = aws_instance.flask_server.id
  port             = 5000
}

# ALB listener that forwards incoming HTTP (port 80) to the target group.
resource "aws_lb_listener" "flask_listener" {
  load_balancer_arn = aws_lb.flask_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_tg.arn
  }

  tags = merge(local.common_tags, { Name = "Flask-ALB-Listener" })
}