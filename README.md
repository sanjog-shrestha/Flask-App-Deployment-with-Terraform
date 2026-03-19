# 🐍 Flask App Deployment with Terraform (AWS EC2 + ALB)

## 📌 Overview

This project demonstrates how to deploy a Flask web application on an AWS EC2 instance using HashiCorp Terraform Infrastructure as Code (IaC).
Terraform provisions and configures all required AWS resources automatically — including VPC networking, SSH key generation, security groups, an Application Load Balancer, and a self-healing systemd service — enabling repeatable and version-controlled application deployments.

The infrastructure includes:

- Custom VPC with public subnets across 2 Availability Zones
- AWS EC2 instance (Ubuntu)
- Application Load Balancer (ALB) as the public entry point
- Dedicated security groups for ALB and EC2 (least-privilege model)
- Auto-generated RSA key pair
- Python virtual environment setup
- Systemd service for auto-start on reboot
- Terraform Cloud remote state with workspace locking

This project highlights cloud automation, remote provisioning, load balancing, and DevOps deployment practices.

---

## 🏗️ Architecture

```
User Browser
     ↓ HTTP :80
AWS ALB (alb_sg — port 80 public)
     ↓ HTTP :5000 (ALB SG only)
EC2 Instance (flask_sg — Ubuntu)
└── systemd: flask-app.service
    └── flask-env (venv)
        └── app.py
```

> 📸 **Architecture Screenshot:**
<img width="1024" height="1536" alt="image" src="https://github.com/user-attachments/assets/0f79c4d8-208e-4482-bc7a-5fc62b1e8a83" />

---

## ☁️ AWS Deployment

### Provisioned Resources

| Resource | Description |
|---|---|
| VPC | Custom VPC with CIDR 10.0.0.0/16, DNS enabled |
| Internet Gateway | Allows public subnets to route to the internet |
| Public Subnet A | AZ[0] — CIDR 10.0.1.0/24, public IP on launch |
| Public Subnet B | AZ[1] — CIDR 10.0.2.0/24, public IP on launch |
| Route Table | Routes 0.0.0.0/0 to the Internet Gateway |
| ALB Security Group | Allows inbound TCP port 80 from 0.0.0.0/0 |
| EC2 Security Group | Port 5000 from ALB SG only; port 22 for SSH |
| RSA Key Pair | Auto-generated 4096-bit key, saved as `terraform-key.pem` |
| EC2 Instance | Ubuntu server tagged `Flask-Terraform-Server` |
| Application Load Balancer | Internet-facing ALB across both public subnets |
| ALB Target Group | HTTP:5000 with health check on `/` |
| ALB Listener | Port 80 — forwards to target group |
| Python venv | Isolated Flask environment at `/home/ubuntu/flask-env` |
| Systemd Service | `flask-app.service` — starts on boot, restarts on failure |

> 📸 **AWS Console Screenshot:**
<img width="1617" height="671" alt="image" src="https://github.com/user-attachments/assets/e827e7a3-ca54-4f0d-ba41-af6058d2f159" />

---

## 📂 Repository Structure

```
terraform-flask-ec2/
├── main.tf              # Core Terraform config (EC2, SG, ALB, key pair, provisioners)
├── variables.tf         # Input variable definitions (AMI ID, instance type)
├── vpc.tf               # VPC, subnets, internet gateway, route tables
├── output.tf            # Terraform output values (ALB URL, EC2 IP)
├── app/
│   └── app.py           # Flask application
└── terraform-key.pem    # Auto-generated SSH key (do NOT commit)
```

---

## ⚙️ Terraform Design Approach

### 1️⃣ Infrastructure as Code

Terraform is used to define AWS infrastructure declaratively.

Benefits include:
- Version-controlled infrastructure
- Repeatable deployments
- Automated provisioning
- Reduced manual configuration errors

### 2️⃣ Automated SSH Key Management

Terraform generates an RSA 4096-bit key pair at apply time using the `tls` provider, registers the public key with AWS, and saves the private key locally — no manual key creation required.

### 3️⃣ Remote Provisioning via SSH

Terraform uses `remote-exec` and `file` provisioners to:
- Upload `app.py` to the server
- Install Python 3, pip, and venv
- Configure and start a **systemd service** that keeps Flask running across reboots

### 4️⃣ Terraform Cloud Remote State

Terraform state is stored remotely in HashiCorp Terraform Cloud instead of a local `terraform.tfstate` file.
This is configured via the `cloud {}` block inside the `terraform {}` block in `main.tf`:

```hcl
terraform {
  cloud {
    workspaces {
      name = "flask-ec2-dev"
    }
  }

  required_providers {
    aws   = { source = "hashicorp/aws" }
    tls   = { source = "hashicorp/tls" }
    local = { source = "hashicorp/local" }
  }
}
```

The organisation name is intentionally omitted from the file and supplied via an environment variable to avoid hardcoding it in version control:

**macOS / Linux:**
```bash
export TF_CLOUD_ORGANIZATION="your-org-name"
```

**Windows (PowerShell):**
```powershell
$env:TF_CLOUD_ORGANIZATION="your-org-name"
```

**To persist across all future PowerShell sessions on Windows:**
```powershell
[System.Environment]::SetEnvironmentVariable("TF_CLOUD_ORGANIZATION", "your-org-name", "User")
```

> 📸 **Terraform Cloud Workspace Screenshot:**
<img width="1918" height="827" alt="image" src="https://github.com/user-attachments/assets/6d2ff48b-e6b8-43f2-ab3f-2c1cabf6e085" />
<br><br>

|  | Before | After |
|---|---|---|
| State location | `terraform.tfstate` on local disk | Terraform Cloud (`flask-ec2-dev` workspace) |
| State locking | None | Automatic — concurrent runs are blocked |
| State history | Lost on accidental delete | Full version history in Terraform Cloud UI |
| CI/CD ready | No | Yes — any runner with a token can access it |

### 5️⃣ Application Load Balancer

Traffic no longer reaches the EC2 instance directly. An internet-facing ALB sits in front of the EC2 instance and is the sole public entry point on port 80. The EC2 security group restricts port 5000 to traffic originating from the ALB security group only, removing direct internet exposure of the Flask process.

Key ALB components provisioned by Terraform:

| Component | Detail |
|---|---|
| `aws_lb` | Internet-facing, spans both public subnets |
| `aws_lb_target_group` | HTTP:5000, health check on `/` every 30s |
| `aws_lb_target_group_attachment` | Registers the EC2 instance as a target |
| `aws_lb_listener` | Port 80 — forwards to target group |

### 6️⃣ Custom VPC & Networking

All resources are deployed into a dedicated VPC rather than the AWS default VPC. Two public subnets are created across different Availability Zones using the `aws_availability_zones` data source, making the configuration portable across any AWS region without hardcoding AZ names.

| Resource | CIDR / Detail |
|---|---|
| VPC | 10.0.0.0/16 |
| Public Subnet A | 10.0.1.0/24 — AZ[0] |
| Public Subnet B | 10.0.2.0/24 — AZ[1] |
| Internet Gateway | Attached to VPC |
| Route Table | 0.0.0.0/0 → IGW, associated to both subnets |

---

## 🚀 Deployment Instructions

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with valid credentials
- Ubuntu AMI ID for your target AWS region

> **Tip:** Find your Ubuntu 22.04 LTS AMI at [Ubuntu's EC2 Locator](https://cloud-images.ubuntu.com/locator/ec2/)

### Steps

**1. Clone the repository**
```bash
git clone https://github.com/your-username/terraform-flask-ec2.git
cd terraform-flask-ec2
```

**2. Ensure your Flask app binds correctly**

`app/app.py` must include:
```python
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

**3. Initialize Terraform**
```bash
terraform init
```

**4. Validate Configuration**
```bash
terraform validate
```

**5. Review Execution Plan**
```bash
terraform plan
```

**6. Apply Infrastructure**
```bash
terraform apply
```

> No `-var` flags are required. The VPC, subnets, and all networking are created automatically by `vpc.tf`.

---

## 🔍 Terraform Deployment Output

After a successful `terraform apply`, you will see:

```
flask_app_url     = "http://<alb-dns-name>"
alb_dns_name      = "<alb-dns-name>.eu-west-2.elb.amazonaws.com"
ec2_public_ip     = "xx.xx.xx.xx"
vpc_id            = "vpc-XXXXXXXXXXXXXXXXX"
public_subnet_ids = [
  "subnet-XXXXXXXX",
  "subnet-YYYYYYYY",
]
```

> 📸 **Deployment Screenshot:**
<img width="795" height="438" alt="image" src="https://github.com/user-attachments/assets/31e6f8d2-c8de-402a-ae7e-2bffb039b1b9" />

---

## 🌐 Application Validation

Once Terraform completes deployment:

1. Copy the `flask_app_url` from the output
2. Open your browser and navigate to:
```
http://<alb-dns-name>
```
3. Verify the Flask application loads successfully

> ⚠️ The ALB may take 60–90 seconds to complete its initial health checks before marking the target as healthy.

> 📸 **App Screenshot:**
<img width="1918" height="1012" alt="image" src="https://github.com/user-attachments/assets/0ad23b0b-690f-42a5-acf8-08a9f76fad5a" />

---

## 🔐 Security Notes

- `terraform-key.pem` is auto-generated locally. **Never commit it to version control.**
- The `TF_CLOUD_ORGANIZATION` environment variable keeps your org name out of source code.
- Port 5000 on the EC2 instance is **no longer publicly accessible** — it accepts traffic from the ALB security group only.
- Port 22 (SSH) remains open to `0.0.0.0/0`. **Restrict this to trusted IP ranges in production.**
- Add the following to your `.gitignore`:
```
terraform-key.pem
.terraform/
.terraform.lock.hcl
terraform.tfstate
terraform.tfstate.backup
```

---

## 📊 Infrastructure Summary

| Component | Service Used |
|---|---|
| Application Hosting | Amazon EC2 (Ubuntu) |
| Load Balancing | AWS Application Load Balancer |
| Networking | AWS VPC, Subnets, IGW, Route Tables |
| Infrastructure Provisioning | Terraform |
| Remote State | Terraform Cloud |
| Key Management | Terraform TLS Provider |
| Process Management | Linux systemd |
| Authentication | AWS CLI |
| Development Environment | VS Code |

---

## 🧠 Key Concepts Demonstrated

- Terraform AWS + TLS + Local provider usage
- Infrastructure as Code principles
- Custom VPC and subnet provisioning
- Application Load Balancer integration
- Least-privilege security group design
- Remote provisioning via SSH
- Terraform Cloud remote state and workspace locking
- Python virtual environment management
- Systemd service configuration

---

## 🏁 Project Outcomes

This project demonstrates the ability to:

- Deploy cloud infrastructure using Terraform
- Design and provision custom VPC networking
- Implement an Application Load Balancer as a managed entry point
- Harden network security using layered security groups
- Automate application setup on a remote EC2 instance
- Structure Terraform configurations effectively across multiple files
- Implement auto-healing services with systemd
- Manage SSH keys programmatically through IaC
- Configure Terraform Cloud remote state for team-ready, CI/CD-ready deployments

---

## 🔮 Future Improvements

Potential enhancements:

- [x] Add Application Load Balancer (ALB)
- [x] Custom VPC and subnet provisioning
- [ ] HTTPS using AWS Certificate Manager
- [ ] Custom domain with Route 53
- [ ] CI/CD pipeline with GitHub Actions
- [ ] Auto Scaling Group for high availability
- [ ] CloudWatch monitoring and alerting
- [ ] Replace provisioners with Packer AMI baking

---

## 📄 Author

**Sanjog Shrestha**

---

## 📜 License

This project is intended for educational and portfolio purposes.
