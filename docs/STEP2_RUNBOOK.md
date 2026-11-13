# Step 2 Runbook: Manual Cloud Deployment Guide (AWS Console — ap-southeast-2)

A click-by-click manual AWS Console walkthrough to build the decoupled production-style Notes application in **Asia Pacific (Sydney) `ap-southeast-2`**.

> [!IMPORTANT]
> **Prerequisites Before Starting:**
> 1. An active AWS account with administrative access.
> 2. Region set to **Asia Pacific (Sydney) `ap-southeast-2`** in the top-right navigation bar of the AWS Management Console.
> 3. Zero hardcoded secrets: Database credentials will be stored in AWS Systems Manager Parameter Store or Secrets Manager.
> 4. Do not run automated cloud scripts or Terraform in this step; execute strictly via the AWS Console.

---

## 📋 Table of Contents
1. [Item 1: VPC, Subnets, Internet Gateway, NAT Gateway & Route Tables](#item-1-vpc-subnets-internet-gateway-nat-gateway--route-tables)
2. [Item 2: Security Groups (`sg-alb`, `sg-app`, `sg-db`)](#item-2-security-groups-sg-alb-sg-app-sg-db)
3. [Item 3: RDS PostgreSQL Database (Single-AZ, db.t3.micro, Private)](#item-3-rds-postgresql-database-single-az-dbt3micro-private)
4. [Item 4: IAM Role & Launch Template with User-Data Script](#item-4-iam-role--launch-template-with-user-data-script)
5. [Item 5: Target Group & Application Load Balancer](#item-5-target-group--application-load-balancer)
6. [Item 6: Auto Scaling Group (Min 2, Max 4, CPU Target Tracking)](#item-6-auto-scaling-group-min-2-max-4-cpu-target-tracking)
7. [Item 7: S3 Frontend Bucket & CloudFront Dual-Origin Distribution](#item-7-s3-frontend-bucket--cloudfront-dual-origin-distribution)
8. [🔄 Teardown Checklist (Reverse Order)](#-teardown-checklist-reverse-order)

---

## Item 1: VPC, Subnets, Internet Gateway, NAT Gateway & Route Tables

### Step-by-Step Instructions
1. Open the **VPC Console** at [https://ap-southeast-2.console.aws.amazon.com/vpc/home?region=ap-southeast-2](https://ap-southeast-2.console.aws.amazon.com/vpc/home?region=ap-southeast-2).
2. Click **Create VPC**.
3. Under **Resources to create**, select **VPC and more** (this auto-generates subnets, route tables, and gateways cleanly).
4. Configure the parameters:
   - **Name tag auto-generation:** `notes-vpc`
   - **IPv4 CIDR block:** `10.0.0.0/16`
   - **Number of Availability Zones (AZs):** `2`
   - **Customize AZs:** Select `ap-southeast-2a` and `ap-southeast-2b`.
   - **Number of public subnets:** `2` (`10.0.1.0/24` in `ap-southeast-2a`, `10.0.2.0/24` in `ap-southeast-2b`).
   - **Number of private subnets:** `4`
     - Private App Subnet 1: `10.0.10.0/24` (`ap-southeast-2a`)
     - Private App Subnet 2: `10.0.11.0/24` (`ap-southeast-2b`)
     - Private DB Subnet 1: `10.0.20.0/24` (`ap-southeast-2a`)
     - Private DB Subnet 2: `10.0.21.0/24` (`ap-southeast-2b`)
   - **NAT Gateways:** Select **In 1 AZ** (Learning budget: provisions 1 NAT Gateway in Public Subnet A).
   - **VPC Endpoints:** Select **None** (optional for this stage).
   - **DNS hostnames:** Check **Enable DNS hostnames**.
   - **DNS resolution:** Check **Enable DNS resolution**.
5. Click **Create VPC**. Wait ~60 seconds for AWS to create subnets, NAT Gateway, Elastic IP, and route tables.

### 🔍 How to Verify
* Go to **VPC** $\to$ **Your VPCs**: Confirm `notes-vpc` displays state **Available**.
* Go to **VPC** $\to$ **NAT Gateways**: Confirm 1 NAT Gateway exists in `notes-vpc-subnet-public1-ap-southeast-2a` with status **Available**.
* Go to **VPC** $\to$ **Route Tables**:
  - The Public Route Table has a destination `0.0.0.0/0` targeted to the **Internet Gateway** (`igw-...`).
  - The Private Route Tables have a destination `0.0.0.0/0` targeted to the **NAT Gateway** (`nat-...`).

---

## Item 2: Security Groups (`sg-alb`, `sg-app`, `sg-db`)

All ingress rules must reference peer security group IDs to guarantee least-privilege traffic flow.

### Step-by-Step Instructions
1. Navigate to **VPC** $\to$ **Security Groups**.

#### 2.1 Create ALB Security Group (`sg-alb`)
* Click **Create security group**.
* **Security group name:** `notes-sg-alb`
* **Description:** `Permits public HTTP/HTTPS ingress to ALB`
* **VPC:** Select `notes-vpc`.
* **Inbound rules:**
  - Rule 1: Type `HTTPS` (Port 443), Source `Anywhere-IPv4` (`0.0.0.0/0`).
  - Rule 2: Type `HTTP` (Port 80), Source `Anywhere-IPv4` (`0.0.0.0/0`).
* **Outbound rules:** Default (All traffic).
* Click **Create security group**. Note its ID (e.g. `sg-0aaa111`).

#### 2.2 Create Backend EC2 Security Group (`sg-app`)
* Click **Create security group**.
* **Security group name:** `notes-sg-app`
* **Description:** `Permits ingress on port 8000 strictly from ALB`
* **VPC:** Select `notes-vpc`.
* **Inbound rules:**
  - Type `Custom TCP`, Port `8000`, Source: Select **Custom**, search and select `notes-sg-alb` (its Security Group ID).
* **Outbound rules:**
  - Leave Default (All traffic to allow OS package updates via NAT and connection to RDS).
* Click **Create security group**. Note its ID (e.g. `sg-0bbb222`).

#### 2.3 Create RDS Database Security Group (`sg-db`)
* Click **Create security group**.
* **Security group name:** `notes-sg-db`
* **Description:** `Permits PostgreSQL 5432 ingress strictly from backend EC2`
* **VPC:** Select `notes-vpc`.
* **Inbound rules:**
  - Type `PostgreSQL` (Port 5432), Source: Select **Custom**, search and select `notes-sg-app`.
* **Outbound rules:** Delete all rules (the database needs zero outbound initiated connections).
* Click **Create security group**.

### 🔍 How to Verify
* In **Security Groups** view, select `notes-sg-app` $\to$ **Inbound rules**: Verify source column displays `notes-sg-alb` ID (NOT an IP address).
* Select `notes-sg-db` $\to$ **Inbound rules**: Verify source column displays `notes-sg-app` ID.

---

## Item 3: RDS PostgreSQL Database (Single-AZ, db.t3.micro, Private)

### Step-by-Step Instructions
1. Open the **Amazon RDS Console** at [https://ap-southeast-2.console.aws.amazon.com/rds/home?region=ap-southeast-2](https://ap-southeast-2.console.aws.amazon.com/rds/home?region=ap-southeast-2).

#### 3.1 Create DB Subnet Group
* Click **Subnet groups** in the left sidebar $\to$ **Create DB Subnet Group**.
* **Name:** `notes-db-subnet-group`
* **Description:** `Private subnets for RDS PostgreSQL`
* **VPC:** Select `notes-vpc`.
* **Add subnets:**
  - Availability Zones: Choose `ap-southeast-2a` and `ap-southeast-2b`.
  - Subnets: Select the two private DB subnets (`10.0.20.0/24` and `10.0.21.0/24`).
* Click **Create**.

#### 3.2 Create Database Instance
* Click **Databases** $\to$ **Create database**.
* **Choose a database creation method:** Standard create.
* **Engine options:** PostgreSQL.
* **Engine Version:** PostgreSQL 16.x.
* **Templates:** **Free tier** (or Dev/Test).
* **Settings:**
  - **DB instance identifier:** `notes-db`
  - **Master username:** `notes_admin`
  - **Master password:** Choose **Self managed** and generate a strong 24-character password (e.g. `NotesCloud2026!DbSecret#`).
* **Instance configuration:**
  - **DB instance class:** Burstable classes $\to$ `db.t3.micro`.
* **Storage:**
  - **Storage type:** General Purpose SSD (`gp3`).
  - **Allocated storage:** `20` GiB.
  - **Storage autoscaling:** Uncheck (prevent runaway costs).
* **Connectivity:**
  - **Compute resource:** Don't connect to an EC2 compute resource (we handle SG manually).
  - **Network type:** IPv4.
  - **Virtual Private Cloud (VPC):** `notes-vpc`.
  - **DB Subnet group:** `notes-db-subnet-group`.
  - **Public access:** **No** (Critical: guarantees zero internet access).
  - **VPC security group:** Choose **Select existing** $\to$ Remove `default`, add `notes-sg-db`.
  - **Availability Zone:** `ap-southeast-2a` (Single-AZ).
  - **Database port:** `5432`.
* **Database authentication:** Password authentication.
* **Additional configuration:**
  - **Initial database name:** `notes_db`
  - **Enable automated backups:** Check (Retention period: 7 days).
  - **Encryption:** Enable encryption (`aws/rds`).
* Click **Create database**. (Takes ~5-8 minutes to provision).

#### 3.3 Save Database URL in AWS SSM Parameter Store
1. Open **Systems Manager** $\to$ **Parameter Store**.
2. Click **Create parameter**:
   - **Name:** `/notes-app/DATABASE_URL`
   - **Tier:** Standard
   - **Type:** **SecureString**
   - **KMS key source:** My current account (`alias/aws/ssm`)
   - **Value:** `postgresql://notes_admin:<your_password>@<rds_endpoint>:5432/notes_db`
     *(Replace `<rds_endpoint>` with the Endpoint string from RDS details once status is Available)*.
3. Click **Create parameter**.

### 🔍 How to Verify
* On the RDS console, confirm `notes-db` status transitions to **Available**.
* Under **Connectivity & security**, verify:
  - **Endpoint:** Present (e.g., `notes-db.cxxxx.ap-southeast-2.rds.amazonaws.com`).
  - **Publicly accessible:** **No**.
  - **Security groups:** `notes-sg-db (active)`.

---

## Item 4: IAM Role & Launch Template with User-Data Script

### Step-by-Step Instructions

#### 4.1 Create EC2 Instance Role for Parameter Store Access
1. Open the **IAM Console** $\to$ **Roles** $\to$ **Create role** (or reuse existing `arn:aws:iam::494166748737:instance-profile/EC2-SSM-Role`).
2. **Trusted entity type:** AWS service.
3. **Use case:** EC2 $\to$ Click **Next**.
4. **Permissions policies:**
   - Attach `AmazonSSMManagedInstanceCore` (allows AWS Systems Manager Session Manager access).
   - Click **Create policy** in a new tab:
     - Service: `SSM`
     - Action: `GetParameter`, `GetParameters`
     - Resource: `arn:aws:ssm:ap-southeast-2:<your_account_id>:parameter/notes-app/*`
     - Policy Name: `NotesAppSSMReadPolicy`
     - Click **Create policy**.
   - Return to Role tab, refresh, and select `NotesAppSSMReadPolicy`.
5. **Role name:** `notes-ec2-instance-role` $\to$ Click **Create role**.

#### 4.2 Create Launch Template
1. Open the **EC2 Console** at [https://ap-southeast-2.console.aws.amazon.com/ec2/home?region=ap-southeast-2](https://ap-southeast-2.console.aws.amazon.com/ec2/home?region=ap-southeast-2).
2. In left sidebar, select **Launch Templates** $\to$ **Create launch template**.
3. **Launch template name:** `notes-api-template`
4. **Template version description:** `v1 FastAPI backend template`
5. **Auto Scaling guidance:** Check **Provide guidance to help me set up a template that I can use with EC2 Auto Scaling**.
6. **Application and OS Images (AMI):**
   - Select **Amazon Linux** $\to$ **Amazon Linux 2023 AMI** (`ami-062900c135ab91582`, 64-bit x86_64, Free tier eligible).
7. **Instance type:** `t3.micro`.
8. **Key pair:** Proceed without a key pair (access is managed via AWS SSM Session Manager for security).
9. **Network settings:**
   - **Subnet:** Do not include in launch template (ASG will supply private subnets).
   - **Security groups:** Select existing security group $\to$ `notes-sg-app`.
10. **Advanced details:**
    - **IAM instance profile:** Select `notes-ec2-instance-role` (or `EC2-SSM-Role`).
    - **Detailed CloudWatch monitoring:** Leave disabled (optional).
    - **User data:** Paste the exact contents of [`deploy/user-data.sh`](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/deploy/user-data.sh).
11. Click **Create launch template**.

### 🔍 How to Verify
* In **Launch Templates**, confirm `notes-api-template` is listed with default version `1`.
* Expand details: Verify IAM instance profile is `notes-ec2-instance-role` and Security Group is `notes-sg-app`.

---

## Item 5: Target Group & Application Load Balancer

### Step-by-Step Instructions

#### 5.1 Create Target Group
1. Open **EC2 Console** $\to$ **Target Groups** (under Load Balancing).
2. Click **Create target group**.
3. **Basic configuration:**
   - **Target type:** Instances.
   - **Target group name:** `notes-api-tg`
   - **Protocol:** `HTTP`
   - **Port:** `8000`
   - **IP address type:** IPv4
   - **VPC:** Select `notes-vpc`.
   - **Protocol version:** HTTP1.
4. **Health checks:**
   - **Health check protocol:** `HTTP`
   - **Health check path:** `/health` (Our fast, DB-independent shallow check; `/health/ready` can also be used).
   - **Advanced health check settings:**
     - Port: `Traffic port`
     - Healthy threshold: `2`
     - Unhealthy threshold: `2`
     - Timeout: `5` seconds
     - Interval: `15` seconds
     - Success codes: `200`
5. Click **Next** $\to$ Skip registering targets (ASG will register instances automatically) $\to$ Click **Create target group**.

#### 5.2 Create Application Load Balancer
1. Go to **EC2 Console** $\to$ **Load Balancers** $\to$ **Create load balancer**.
2. Under **Application Load Balancer**, click **Create**.
3. **Basic configuration:**
   - **Load balancer name:** `notes-alb`
   - **Scheme:** **Internet-facing**
   - **IP address type:** IPv4
4. **Network mapping:**
   - **VPC:** `notes-vpc`
   - **Mappings (select both public subnets):**
     - `ap-southeast-2a`: Select `notes-vpc-subnet-public1-ap-southeast-2a`.
     - `ap-southeast-2b`: Select `notes-vpc-subnet-public2-ap-southeast-2b`.
5. **Security groups:**
   - Remove `default`.
   - Select `notes-sg-alb`.
6. **Listeners and routing:**
   - **Listener HTTP:80:**
     - Default action: Forward to Target group `notes-api-tg`.
     *(Note: If you have an ACM SSL Certificate, add an HTTPS:443 listener forwarding to `notes-api-tg` and set port 80 to redirect to 443).*
7. Click **Create load balancer**. (Takes ~2 minutes to become Active).

### 🔍 How to Verify
* In **Load Balancers**, verify `notes-alb` state is **Active**.
* Copy the **DNS name** (e.g. `notes-alb-123456789.ap-southeast-2.elb.amazonaws.com`).
* In **Target Groups**, click `notes-api-tg`: Confirm health check path is `/health` on port 8000.

---

## Item 6: Auto Scaling Group (Min 2, Max 4, CPU Target Tracking)

### Step-by-Step Instructions
1. Open **EC2 Console** $\to$ **Auto Scaling Groups** (left sidebar).
2. Click **Create Auto Scaling group**.
3. **Step 1: Choose launch template or configuration:**
   - **Auto Scaling group name:** `notes-asg`
   - **Launch template:** Select `notes-api-template` (Version: `Default (1)`).
   - Click **Next**.
4. **Step 2: Choose instance types and network:**
   - **VPC:** Select `notes-vpc`.
   - **Availability Zones and subnets:** Select the two **private app subnets**:
     - `notes-vpc-subnet-private1-ap-southeast-2a` (`10.0.10.0/24`)
     - `notes-vpc-subnet-private2-ap-southeast-2b` (`10.0.11.0/24`)
   - Click **Next**.
5. **Step 3: Configure advanced options:**
   - **Load balancing:** Select **Attach to an existing load balancer**.
   - **Choose target groups:** Select `notes-api-tg`.
   - **Health checks:**
     - Select **Turn on Elastic Load Balancing health checks** (ALB informs ASG to replace unhealthy instances).
     - **Health check grace period:** `300` seconds (allows user-data script to install dependencies and boot).
   - Click **Next**.
6. **Step 4: Configure group size and scaling policies:**
   - **Group size:**
     - **Desired capacity:** `2`
     - **Min capacity:** `2`
     - **Max capacity:** `4`
   - **Automatic scaling:** Select **Target tracking scaling policy**:
     - **Scaling policy name:** `notes-cpu-tracking`
     - **Metric type:** `Average CPU utilization`
     - **Target value:** `65` (%)
     - **Warm-up time:** `120` seconds
   - Click **Next**.
7. **Step 5: Notifications:** Click **Next** (optional).
8. **Step 6: Tags:** Add key `Name`, value `notes-api-worker` $\to$ Click **Next**.
9. Click **Create Auto Scaling group**.

### 🔍 How to Verify
* Go to **Auto Scaling Groups** $\to$ Select `notes-asg` $\to$ **Instance management**: Confirm 2 EC2 instances are launched in private subnets with status **InService**.
* Go to **EC2** $\to$ **Target Groups** $\to$ Select `notes-api-tg` $\to$ **Targets**: Confirm both targets transition from `Initial` to **Healthy** (HTTP 200 on `/health`).
* In your terminal or browser, test the ALB DNS directly:
  ```bash
  curl http://<ALB_DNS_NAME>/health
  ```
  Expected Output:
  ```json
  {"status":"healthy","service":"notes-api","timestamp":"..."}
  ```

---

## Item 7: S3 Frontend Bucket & CloudFront Dual-Origin Distribution

### Step-by-Step Instructions

#### 7.1 Build and Upload Static Frontend to S3
1. Build production static bundle locally:
   ```powershell
   cd frontend
   npm run build
   ```
   *(Creates static files inside `frontend/dist/`)*.
2. Open the **Amazon S3 Console** at [https://s3.console.aws.amazon.com/s3/](https://s3.console.aws.amazon.com/s3/).
3. Click **Create bucket**:
   - **Bucket name:** `notes-frontend-app-<your_account_id>` (Must be globally unique).
   - **AWS Region:** `ap-southeast-2` (Sydney).
   - **Object Ownership:** ACLs disabled (recommended).
   - **Block Public Access:** **Block all public access** (Checked! CloudFront will use Origin Access Control).
   - **Bucket Versioning:** Optional / Enabled.
   - **Default encryption:** SSE-S3.
   - Click **Create bucket**.
4. Open the created bucket $\to$ Click **Upload** $\to$ Upload all contents of `frontend/dist/` (`index.html`, `assets/`, etc.).
   *(Or run: `powershell -File deploy/step2/deploy-frontend-s3.ps1 -BucketName notes-frontend-app-<your_account_id> -AwsRegion ap-southeast-2`)*.

#### 7.2 Create CloudFront Distribution with Two Origins
1. Open the **CloudFront Console** at [https://us-east-1.console.aws.amazon.com/cloudfront/v4/home](https://us-east-1.console.aws.amazon.com/cloudfront/v4/home).
2. Click **Create distribution**.

**Origin 1: S3 Bucket (Default Origin):**
- **Origin domain:** Select your S3 bucket `notes-frontend-app-<account_id>.s3.ap-southeast-2.amazonaws.com`.
- **Origin access:** Select **Origin access control settings (recommended)**.
  - Click **Create control setting** $\to$ Name: `notes-s3-oac` $\to$ Click **Create**.
  - *(After creation, AWS will provide an S3 bucket policy prompt—we will paste it into S3 in the verify step)*.

**Default Cache Behavior (`*`):**
- **Viewer protocol policy:** `Redirect HTTP to HTTPS`.
- **Allowed HTTP methods:** `GET, HEAD, OPTIONS`.
- **Cache key and origin requests:** Select **Cache policy and origin request policy (recommended)**:
  - Cache policy: `CachingOptimized`.

**Web Application Firewall (WAF):**
- Select **Do not enable security protections** (Learning budget).

**Settings:**
- **Default root object:** `index.html`.
- Click **Create distribution**. Note your **Distribution Domain Name** (e.g. `d111222333.cloudfront.net`).

#### 7.3 Add Second Origin (ALB) and Path Behaviors
1. Select the created distribution $\to$ Go to **Origins** tab $\to$ Click **Create origin**:
   - **Origin domain:** Select your ALB (`notes-alb-123456789.ap-southeast-2.elb.amazonaws.com`).
   - **Protocol:** `HTTP only` (or HTTPS if ACM cert attached).
   - **HTTP port:** `80`.
   - **Name:** `ALB-NotesAPI-Origin`.
   - Click **Create origin**.
2. Go to **Behaviors** tab $\to$ Click **Create behavior** (for `/api/*`):
   - **Path pattern:** `/api/*`
   - **Origin and origin groups:** Select `ALB-NotesAPI-Origin`.
   - **Viewer protocol policy:** `Redirect HTTP to HTTPS`.
   - **Allowed HTTP methods:** `GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE`.
   - **Cache key and origin requests:**
     - Cache policy: `CachingDisabled` (Ensures dynamic API calls are not cached).
     - Origin request policy: `AllViewerExceptHostHeader`.
   - Click **Create behavior**.
3. Click **Create behavior** again (for `/health*`):
   - **Path pattern:** `/health*`
   - **Origin and origin groups:** Select `ALB-NotesAPI-Origin`.
   - **Viewer protocol policy:** `Redirect HTTP to HTTPS`.
   - **Allowed HTTP methods:** `GET, HEAD`.
   - **Cache policy:** `CachingDisabled`.
   - Click **Create behavior**.
4. Go to **Error pages** tab $\to$ Click **Create custom error response**:
   - **HTTP error code:** `403: Forbidden`
   - **Customize error response:** Yes
   - **Response page path:** `/index.html`
   - **HTTP Response code:** `200: OK`
   - Click **Create**. (Repeat for HTTP `404: Not Found`).

#### 7.4 Apply Origin Access Control (OAC) Policy to S3
1. In CloudFront, copy the yellow banner S3 Bucket Policy (or generate standard OAC policy).
2. Go to **S3 Console** $\to$ Select `notes-frontend-app-...` $\to$ **Permissions** tab $\to$ **Bucket policy** $\to$ Click **Edit**.
3. Paste policy granting CloudFront read access to `arn:aws:s3:::notes-frontend-app-*/*`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": {
       "Sid": "AllowCloudFrontServicePrincipalReadOnly",
       "Effect": "Allow",
       "Principal": {
         "Service": "cloudfront.amazonaws.com"
       },
       "Action": "s3:GetObject",
       "Resource": "arn:aws:s3:::<your_bucket_name>/*",
       "Condition": {
         "StringEquals": {
           "AWS:SourceArn": "arn:aws:cloudfront::<account_id>:distribution/<distribution_id>"
         }
       }
     }
   }
   ```
4. Click **Save changes**.

### 🔍 How to Verify
* Open your browser and navigate to the CloudFront distribution domain:
  `https://<distribution_id>.cloudfront.net/`
  1. The **Cloud Notes** React frontend loads securely over HTTPS.
  2. The system health badges display:
     - `API: Healthy (200)`
     - `DB: Connected`
  3. Create a note titled `"Live Cloud Deployment"`, body `"Testing AWS CloudFront to ALB to EC2 to RDS"`.
  4. Edit the note, and then delete it.
* Verify the `/health` endpoint:
  ```bash
  curl https://<distribution_id>.cloudfront.net/health
  ```
  Returns `HTTP 200 {"status":"healthy","service":"notes-api"}`.

---

## 🔄 Teardown Checklist (Reverse Order)

To eliminate ongoing AWS charges when you finish testing, delete resources in the exact reverse order of creation:

1. **CloudFront Distribution:**
   - In CloudFront Console, select the distribution $\to$ Click **Disable**.
   - Wait ~3 minutes for status to change to **Disabled** $\to$ Click **Delete**.
2. **S3 Frontend Bucket:**
   - In S3 Console, select `notes-frontend-app-...` $\to$ Click **Empty** (confirm deletion of all files).
   - Click **Delete bucket**.
3. **Auto Scaling Group:**
   - In EC2 Console $\to$ **Auto Scaling Groups** $\to$ Select `notes-asg` $\to$ Click **Delete**.
   - Confirm deletion. (This automatically terminates all running EC2 worker instances).
4. **Launch Template:**
   - In EC2 Console $\to$ **Launch Templates** $\to$ Select `notes-api-template` $\to$ **Actions** $\to$ **Delete template**.
5. **Application Load Balancer & Target Group:**
   - In EC2 Console $\to$ **Load Balancers** $\to$ Select `notes-alb` $\to$ **Actions** $\to$ **Delete**.
   - In **Target Groups** $\to$ Select `notes-api-tg` $\to$ **Actions** $\to$ **Delete**.
6. **RDS PostgreSQL Database:**
   - In RDS Console $\to$ **Databases** $\to$ Select `notes-db` $\to$ **Actions** $\to$ **Delete**.
   - Uncheck **Create final snapshot**, check **I acknowledge that upon instance deletion...**, type `delete me` $\to$ Click **Delete**.
   - Go to **Subnet groups** $\to$ Delete `notes-db-subnet-group`.
7. **SSM Parameter Store:**
   - In Systems Manager $\to$ **Parameter Store** $\to$ Delete `/notes-app/DATABASE_URL`.
8. **Security Groups:**
   - Wait for ALB and RDS deletion to finish completely.
   - In VPC Console $\to$ **Security Groups**:
     1. Delete `notes-sg-db`.
     2. Delete `notes-sg-app`.
     3. Delete `notes-sg-alb`.
9. **NAT Gateway & Elastic IP:**
   - In VPC Console $\to$ **NAT Gateways** $\to$ Select the NAT Gateway $\to$ **Actions** $\to$ **Delete NAT gateway**.
   - Go to **Elastic IPs** $\to$ Select the allocated NAT EIP $\to$ **Actions** $\to$ **Release Elastic IP address** *(Critical: unattached EIPs incur hourly charges)*.
10. **VPC & Subnets:**
    - In VPC Console $\to$ **Your VPCs** $\to$ Select `notes-vpc` $\to$ **Actions** $\to$ **Delete VPC**.
    - Confirm deletion. (Deletes the VPC, subnets, route tables, and Internet Gateway simultaneously).

