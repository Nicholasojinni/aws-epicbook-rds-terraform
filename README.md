# Deploy EpicBook Application on AWS with RDS Using Terraform

This project provisions a complete AWS infrastructure using Terraform and deploys the EpicBook Node.js bookstore application connected to an Amazon RDS MySQL database in a private subnet.

---

## Architecture

```
Internet
    |
Internet Gateway
    |
Public Subnet (10.0.1.0/24)
    |
Security Group (SSH + HTTP)
    |
EC2 Instance (Ubuntu 22.04)
    Node.js + Nginx + PM2
    mysql-client
    |
Security Group (MySQL 3306 — EC2 only)
    |
Private Subnet (10.0.2.0/24 + 10.0.3.0/24)
    |
RDS MySQL 8.0 (db.t3.micro)
    |
VPC (10.0.0.0/16)
```

---

## Resources Provisioned

| Resource | Name | Description |
|---|---|---|
| VPC | epicbook-vpc | Custom VPC (10.0.0.0/16) |
| Public Subnet | epicbook-public-subnet | EC2 subnet (10.0.1.0/24) |
| Private Subnet x2 | epicbook-private-subnet-1/2 | RDS subnets across 2 AZs |
| Internet Gateway | epicbook-igw | Internet access for EC2 |
| Route Table | epicbook-public-rt | Routes public traffic through IGW |
| NAT Gateway | epicbook-nat | Outbound internet for private subnets |
| Security Group (EC2) | epicbook-ec2-sg | Allows SSH (22) and HTTP (80) |
| Security Group (RDS) | epicbook-rds-sg | Allows MySQL (3306) from EC2 only |
| EC2 Instance | epicbook-server | Ubuntu 22.04, t2.micro |
| RDS Subnet Group | epicbook-rds-subnet-group | Subnet group for RDS |
| RDS MySQL | epicbook-db | MySQL 8.0, db.t3.micro, private subnet |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) (v1.0+)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (v2)
- An active [AWS Account](https://aws.amazon.com/free)
- AWS credentials configured via `aws configure`

---

## Quick Start

### Step 1 — Clone the repository

```bash
git clone https://github.com/Nicholasojinni/aws-epicbook-rds-terraform.git
cd aws-epicbook-rds-terraform
```

### Step 2 — Generate SSH key pair

```bash
ssh-keygen -t rsa -b 2048 -f epicbook-key -N ""
chmod 400 epicbook-key
```

### Step 3 — Configure AWS credentials

```bash
aws configure
aws sts get-caller-identity
```

### Step 4 — Initialize and deploy

```bash
terraform init
terraform plan
terraform apply
```

Type `yes` when prompted. **RDS takes 5–10 minutes** to provision — this is normal.

Save the outputs:
- `ec2_public_ip`
- `rds_endpoint` (remove the `:3306` from the end when using as DB_HOST)
- `ssh_command`

### Step 5 — SSH into EC2

```bash
ssh -i epicbook-key ubuntu@<ec2_public_ip>
```

### Step 6 — Install dependencies

```bash
sudo apt update && sudo apt upgrade -y
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
source ~/.nvm/nvm.sh
nvm install v17
sudo apt install -y git nginx mysql-client
```

### Step 7 — Clone and configure the application

```bash
git clone https://github.com/pravinmishraaws/theepicbook.git
cd theepicbook
```

Update `config/config.json` with your RDS details:

```json
{
  "development": {
    "username": "admin",
    "password": "EpicBook1234Secure",
    "database": "bookstore",
    "host": "epicbook-db.xxxxxxxxx.us-east-1.rds.amazonaws.com",
    "dialect": "mysql",
    "port": 3306
  }
}
```

> The `host` value is your RDS endpoint **without** the `:3306` port suffix.

### Step 8 — Initialize the database

```bash
mysql -h <rds_endpoint_without_port> -u admin -p
```

Inside MySQL:
```sql
CREATE DATABASE bookstore;
EXIT;
```

Run the SQL seed files:
```bash
mysql -h <rds_endpoint> -u admin -p bookstore < db/BuyTheBook_Schema.sql
mysql -h <rds_endpoint> -u admin -p bookstore < db/author_seed.sql
mysql -h <rds_endpoint> -u admin -p bookstore < db/books_seed.sql
```

### Step 9 — Install dependencies and start the app

```bash
npm install
sudo npm install -g pm2
pm2 start server.js --name epicbook
pm2 startup
pm2 save
```

### Step 10 — Configure Nginx reverse proxy

```bash
sudo nano /etc/nginx/conf.d/epicbook.conf
```

Paste:
```nginx
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
```

### Step 11 — Visit the app

```
http://<ec2_public_ip>
```

### Step 12 — Destroy resources when done

```bash
exit
terraform destroy
```

> **Important:** RDS instances are expensive if left running. Always destroy after completing lab work.

---

## Outputs

| Output | Description |
|---|---|
| `ec2_public_ip` | Public IP of the EpicBook EC2 server |
| `rds_endpoint` | RDS MySQL endpoint (use as DB_HOST without `:3306`) |
| `ssh_command` | Ready-to-use SSH connection command |

---

## Security Design

The RDS security group only allows inbound traffic on port 3306 from the EC2 security group ID — not from an IP address or CIDR range. This means only the application server can reach the database regardless of IP changes, which is a production-grade security pattern.

---

## Common Errors and Fixes

| Error | Fix |
|---|---|
| `InvalidParameter: MasterUserPassword` | RDS password cannot contain `@` — use alphanumeric characters only |
| `502 Bad Gateway` | Node.js app not running — run `pm2 start server.js` |
| `ER_ACCESS_DENIED_ERROR` | Check `config/config.json` has correct credentials and host |
| RDS takes too long | Wait — RDS provisioning takes up to 10 minutes |
| `Cannot connect to MySQL` | Verify EC2 security group allows outbound to RDS security group |

---

## Project Structure

```
aws-epicbook-rds-terraform/
├── main.tf         # All infrastructure resources
├── .gitignore      # Excludes Terraform binaries, state files, and keys
└── README.md       # This file
```

---

## Author

**Nicholas Ojinni**
DevOps Micro Internship (DMI) — Cohort 2 | Group 3
LinkedIn: (https://www.linkedin.com/in/ojinni-oluwafemi11/)
GitHub: (https://github.com/Nicholasojinni)

---

## Resources

- [EpicBook Repository](https://github.com/pravinmishraaws/theepicbook)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [DevOps Micro Internship](https://pravinmishra.com/dmi)