terraform {
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

resource "aws_security_group" "flask_sg" {
    name = "flask_security_group"

    ingress {
        from_port = 5000
        to_port = 5000
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "tls_private_key" "terraform_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "aws_key_pair" "generated_key" {
    key_name   = "terraform-key"
    public_key = tls_private_key.terraform_key.public_key_openssh
}

resource "local_file" "private_key" {
    content         = tls_private_key.terraform_key.private_key_pem
    filename        = "terraform-key.pem"
    file_permission = "0600"
}

resource "aws_instance" "flask_server" {
    ami               = var.ami_id
    instance_type     = var.instance_type
    security_groups   = [aws_security_group.flask_sg.name]
    key_name          = aws_key_pair.generated_key.key_name

    tags = {
        Name = "Flask-Terraform-Server"
    }

    # Wait for SSH to become available before running provisioners.
    provisioner "remote-exec" {
        inline = [
            "echo 'Waiting for SSH...'",
            "sleep 30"
        ]
        connection {
            type        = "ssh"
            user        = "ubuntu"
            private_key = tls_private_key.terraform_key.private_key_pem
            host        = self.public_ip
            timeout     = "5m"
        }
    }

    provisioner "file" {
        source      = "app/app.py"
        destination = "/home/ubuntu/app.py"

        connection {
            type        = "ssh"
            user        = "ubuntu"
            private_key = tls_private_key.terraform_key.private_key_pem
            host        = self.public_ip
            timeout     = "5m"
        }
    }

    # Run Flask app automatically after setup
    provisioner "remote-exec" {
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y python3-pip python3-venv python3-full",
            # Create and activate virtual environment
            "python3 -m venv /home/ubuntu/flask-env",
            # Install Flask in the virtual environment
            "/home/ubuntu/flask-env/bin/pip install flask",
            # Change permissions to allow execution if needed
            "chmod +x /home/ubuntu/app.py",
            # Ensure no previous python process is running on port 5000
            "sudo fuser -k 5000/tcp || true",
            # Run the Flask app using the virtual environment's python as a background systemd service so it survives reboots and auto starts
            "echo '[Unit]' | sudo tee /etc/systemd/system/flask-app.service",
            "echo 'Description=Flask App Auto Start' | sudo tee -a /etc/systemd/system/flask-app.service",
            "echo '[Service]' | sudo tee -a /etc/systemd/system/flask-app.service",
            "echo 'User=ubuntu' | sudo tee -a /etc/systemd/system/flask-app.service",
            "echo 'WorkingDirectory=/home/ubuntu' | sudo tee -a /etc/systemd/system/flask-app.service",
            "echo 'ExecStart=/home/ubuntu/flask-env/bin/python3 /home/ubuntu/app.py' | sudo tee -a /etc/systemd/system/flask-app.service",
            "echo 'Restart=always' | sudo tee -a /etc/systemd/system/flask-app.service",
            "echo '[Install]' | sudo tee -a /etc/systemd/system/flask-app.service",
            "echo 'WantedBy=multi-user.target' | sudo tee -a /etc/systemd/system/flask-app.service",
            "sudo systemctl daemon-reload",
            "sudo systemctl enable flask-app",
            "sudo systemctl start flask-app"
        ]
        connection {
            type        = "ssh"
            user        = "ubuntu"
            private_key = tls_private_key.terraform_key.private_key_pem
            host        = self.public_ip
            timeout     = "5m"
        }
    }
}