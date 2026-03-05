# 🐍 Flask App Deployment with Terraform (AWS EC2)

## 📌 Overview

This project demonstrates how to deploy a **Flask web application** on an **AWS EC2** instance using **HashiCorp Terraform** Infrastructure as Code (IaC).

Terraform provisions and configures all required AWS resources automatically — including SSH key generation, security groups, and a self-healing systemd service — enabling repeatable and version-controlled application deployments.

The infrastructure includes:
- AWS EC2 instance (Ubuntu)
- Security group with Flask and SSH access
- Auto-generated RSA key pair
- Python virtual environment setup
- Systemd service for auto-start on reboot

This project highlights cloud automation, remote provisioning, and DevOps deployment practices.

---

## 🏗️ Architecture

```
User Browser
     ↓ (port 5000)
AWS Security Group
     ↓
EC2 Instance (Ubuntu)
└── systemd: flask-app.service
    └── flask-env (venv)
        └── app.py
```

> 📸 **Architecture Screenshot:**
> ![Architecture](./screenshots/architecture.png)

---

## ☁️ AWS Deployment

### Provisioned Resources

| Resource | Description |
|---|---|
| Security Group | Allows inbound TCP on ports 22 (SSH) and 5000 (Flask) |
| RSA Key Pair | Auto-generated 4096-bit key, saved locally as `terraform-key.pem` |
| EC2 Instance | Ubuntu server tagged `Flask-Terraform-Server` |
| Python venv | Isolated Flask environment at `/home/ubuntu/flask-env` |
| Systemd Service | `flask-app.service` — starts on boot, restarts on failure |

> 📸 **AWS Console Screenshot:**
> ![AWS Console](./screenshots/aws-console.png)

---

## 📂 Repository Structure

```
terraform-flask-ec2/
├── main.tf              # Core Terraform config (EC2, SG, key pair, provisioners)
├── variables.tf         # Input variable definitions (AMI ID, instance type)
├── output.tf            # Terraform output values (public IP)
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
terraform plan -var="ami_id=ami-XXXXXXXXXXXXXXXXX"
```

**6. Apply Infrastructure**
```bash
terraform apply -var="ami_id=ami-XXXXXXXXXXXXXXXXX"
```

---

## 🔍 Terraform Deployment Output

After a successful `terraform apply`, you will see:

```
public_ip = "xx.xx.xx.xx"
```

> 📸 **Deployment Screenshot:**
> ![Deployment Output](./screenshots/deployment-output.png)

---

## 🌐 Application Validation

Once Terraform completes deployment:

1. Copy the `public_ip` from the output
2. Open your browser and navigate to:
```
http://<public-ip>:5000
```
3. Verify the Flask application loads successfully

> 📸 **App Screenshot:**
> ![Live App](./screenshots/app-live.png)

---

## 🔐 Security Notes

- `terraform-key.pem` is auto-generated locally. **Never commit it to version control.**
- Add the following to your `.gitignore`:
```
terraform-key.pem
.terraform/
terraform.tfstate
terraform.tfstate.backup
```
- Ports `22` and `5000` are open to `0.0.0.0/0` by default. **For production, restrict these to trusted IP ranges.**

---

## 📊 Infrastructure Summary

| Component | Service Used |
|---|---|
| Application Hosting | Amazon EC2 (Ubuntu) |
| Infrastructure Provisioning | Terraform |
| Key Management | Terraform TLS Provider |
| Process Management | Linux systemd |
| Authentication | AWS CLI |
| Development Environment | VS Code |

---

## 🧠 Key Concepts Demonstrated

- Terraform AWS + TLS + Local provider usage
- Infrastructure as Code principles
- Remote provisioning via SSH
- Python virtual environment management
- Systemd service configuration
- Cloud security group configuration

---

## 🏁 Project Outcomes

This project demonstrates the ability to:

- Deploy cloud infrastructure using Terraform
- Automate application setup on a remote EC2 instance
- Structure Terraform configurations effectively
- Implement auto-healing services with systemd
- Manage SSH keys programmatically through IaC

---

## 🔮 Future Improvements

Potential enhancements:

- [ ] Add Application Load Balancer (ALB)
- [ ] HTTPS using AWS Certificate Manager
- [ ] Custom domain with Route 53
- [ ] CI/CD pipeline with GitHub Actions
- [ ] Terraform remote state with S3 + DynamoDB
- [ ] Auto Scaling Group for high availability
- [ ] CloudWatch monitoring and alerting
- [ ] Replace provisioners with Packer AMI baking

---

## 📄 Author

**Sanjog Shrestha**

---

## 📜 License

This project is intended for educational and portfolio purposes.
