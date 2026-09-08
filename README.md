# Terraform + Database Reliability Assessment

A production-oriented reference implementation for the DevOps assessment covering:

- AWS infrastructure design with Terraform: Internet → ALB → ECS/Fargate → private RDS
- Separate `dev` and `prod` Terraform environments
- Local PostgreSQL with Docker Compose
- SQL migrations and deterministic seed data
- Query optimization with indexing and `EXPLAIN (ANALYZE, BUFFERS)`
- Timestamped PostgreSQL backups
- Restore into a fresh local database
- GitHub Actions Terraform formatting, validation and plan

> **No AWS deployment is required.** Terraform is designed to be reviewed with formatting, initialization, validation and a plan. Database work runs entirely locally.

## Repository layout

```text
.
├── .github/workflows/terraform.yml
├── database/
│   ├── migrations/001_create_tables.sql
│   └── seed/001_seed_data.sql
├── infra/
│   ├── modules/
│   │   ├── network/
│   │   ├── ecs/
│   │   └── rds/
│   └── envs/
│       ├── dev/
│       └── prod/
├── scripts/
│   ├── backup.sh
│   └── restore.sh
├── docker-compose.yml
└── README.md
```

## Prerequisites

- Docker + Docker Compose v2
- Terraform >= 1.6
- Git
- Bash (Linux/macOS/WSL/Git Bash)

---

# Part 1 — Local PostgreSQL

## 1. Start PostgreSQL

```bash
docker compose up -d
docker compose ps
```

Wait until the database reports `healthy`.

Default local connection:

```text
Host: localhost
Port: 5432
Database: bookings
User: postgres
Password: postgres
```

The migration and seed SQL files are mounted into PostgreSQL's `/docker-entrypoint-initdb.d/`, so they execute automatically when the database volume is initialized for the first time.

## 2. Verify tables and seed data

```bash
docker compose exec postgres psql -U postgres -d bookings -c '\dt'
```

Check row counts:

```bash
docker compose exec postgres psql -U postgres -d bookings -c \
"SELECT COUNT(*) AS hotel_bookings FROM hotel_bookings;
 SELECT COUNT(*) AS booking_events FROM booking_events;"
```

The seed contains more than 100 bookings, multiple cities, organizations, statuses and booking events.

> If you change migration/seed files after the database has already been initialized, recreate the local volume:
>
> ```bash
> docker compose down -v
> docker compose up -d
> ```

---

# Part 2 — Query optimization

The assessment query is:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

The migration creates:

```sql
CREATE INDEX idx_hotel_bookings_city_created_at
ON hotel_bookings (city, created_at);
```

### Why this index?

The query filters first on equality (`city`) and then on a range (`created_at`).

The composite index:

```text
(city, created_at)
```

lets PostgreSQL efficiently narrow the candidate rows before performing the aggregation.

`org_id` and `status` are grouping columns rather than selective predicates, so putting them before the filter columns would generally be less useful for this query.

Run the query plan:

```bash
docker compose exec postgres psql -U postgres -d bookings -c \
"EXPLAIN (ANALYZE, BUFFERS)
 SELECT org_id, status, COUNT(*), SUM(amount)
 FROM hotel_bookings
 WHERE city = 'delhi'
   AND created_at >= NOW() - INTERVAL '30 days'
 GROUP BY org_id, status;"
```

For a small dataset PostgreSQL may still choose a sequential scan because it can be cheaper. That is normal. The important part is that the index matches the query's filtering pattern and can become valuable as the table grows.

---

# Part 3 — Backup

Create a timestamped compressed PostgreSQL dump:

```bash
./scripts/backup.sh
```

Backups are written to:

```text
backups/
└── bookings_YYYYMMDD_HHMMSS.sql.gz
```

The script checks that the database container is running and uses `pg_dump` from the running PostgreSQL container.

---

# Part 4 — Restore into a fresh database

Run:

```bash
./scripts/restore.sh backups/bookings_YYYYMMDD_HHMMSS.sql.gz
```

The restore script:

1. Creates a temporary restore database.
2. Loads the selected dump.
3. Verifies the expected tables.
4. Compares booking/event row counts with the source database.
5. Removes the temporary database.

Example verification output:

```text
Restore completed successfully.
hotel_bookings rows: 120
booking_events rows: 180
```

The restore database is intentionally separate from `bookings`, so the original local database is not overwritten.

---

# Part 5 — Terraform

## Architecture

```text
                         Internet
                            |
                            v
                  +-------------------+
                  |        ALB        |
                  |   Public Subnets  |
                  +---------+---------+
                            |
                            | HTTP
                            v
                  +-------------------+
                  |   ECS Fargate     |
                  |  Private Subnets  |
                  +---------+---------+
                            |
                            | PostgreSQL 5432
                            v
                  +-------------------+
                  |       RDS         |
                  |  Private Subnets  |
                  +-------------------+
```

Security-group flow:

```text
Internet
   |
   | TCP 80
   v
ALB Security Group
   |
   | TCP 80
   v
ECS Security Group
   |
   | TCP 5432
   v
RDS Security Group
```

RDS has no public IP and its security group only permits PostgreSQL traffic originating from the ECS security group.

## Terraform environment structure

```text
infra/
├── modules/
│   ├── network/
│   ├── ecs/
│   └── rds/
└── envs/
    ├── dev/
    └── prod/
```

The environments use the same reusable modules but have independent configuration.

### Dev

- Smaller RDS instance
- Single NAT gateway
- Shorter backup retention
- Deletion protection disabled
- Smaller ECS task

### Prod

- Larger RDS instance
- NAT gateway per AZ
- Longer backup retention
- Deletion protection enabled
- Multi-AZ RDS
- Larger ECS task

## Terraform validation

### Dev

```bash
cd infra/envs/dev

terraform fmt -recursive
terraform init
terraform validate
terraform plan -refresh=false -var-file=dev.tfvars
```

### Prod

```bash
cd infra/envs/prod

terraform fmt -recursive
terraform init
terraform validate
terraform plan -refresh=false -var-file=prod.tfvars
```

The environments use Terraform's local backend so `terraform init` and configuration validation do not require an existing S3 state bucket.

For a real AWS deployment, the local backend can be replaced with an S3 backend with locking and a dedicated state-management strategy.

## AWS resources represented

### Network

- VPC
- Internet Gateway
- Public subnets
- Private subnets
- Public route table
- Private route tables
- NAT Gateway(s)
- Elastic IP(s)

### ALB

- Application Load Balancer
- Target group
- HTTP listener
- ALB security group

### ECS

- ECS cluster
- Fargate task definition
- ECS service
- IAM execution role
- ECS security group

The sample application uses the public `nginx:alpine` image as a placeholder backend.

### RDS

- PostgreSQL RDS instance
- DB subnet group
- RDS security group
- Encryption at rest
- Backup retention
- Deletion protection
- Multi-AZ setting controlled by environment

---

# Part 6 — GitHub Actions

The workflow at `.github/workflows/terraform.yml` runs on Terraform-related
pull requests and pushes.

It performs:

terraform fmt -check
        |
terraform init -backend=false
        |
terraform validate

The workflow validates both the `dev` and `prod` Terraform configurations.

Terraform plan is intentionally not executed in CI because a plan requires
AWS provider authentication and this assessment does not require an AWS
deployment.

For local plan validation, AWS credentials must be configured:

cd infra/envs/dev
terraform plan -refresh=false -var-file=dev.tfvars

cd ../prod
terraform plan -refresh=false -var-file=prod.tfvars

---

# Design decisions

## Why PostgreSQL?

The supplied assessment schema uses PostgreSQL-oriented types and syntax such as `UUID`, `JSONB` and `BIGSERIAL`. PostgreSQL therefore provides the closest match to the requested schema.

## Why private RDS?

The database should not be directly reachable from the internet. The RDS security group allows port 5432 only from the ECS security group.

## Why separate Terraform modules?

The network, ECS and RDS layers are independently reusable. Environment-specific configuration stays in `envs/dev` and `envs/prod`.

## Why local Terraform state for this assessment?

An S3 backend would require a pre-existing AWS bucket and locking configuration before `terraform init` can run. Since actual AWS deployment is explicitly not required, local state keeps the repository immediately runnable while still providing independent backend configuration per environment.

## Production hardening opportunities

For an actual production deployment, I would additionally consider:

- S3 remote Terraform state with locking
- AWS Secrets Manager for database credentials
- HTTPS/ACM on the ALB
- WAF
- CloudWatch logging and alarms
- ECS autoscaling
- RDS enhanced monitoring
- KMS customer-managed keys where appropriate
- VPC endpoints to reduce NAT dependency
- stricter egress rules
- image scanning and immutable container tags
- automated database restore testing

---

# Cleanup

Stop local PostgreSQL:

```bash
docker compose down
```

Remove the database volume too:

```bash
docker compose down -v
```

Terraform state can be removed from each environment with:

```bash
rm -f infra/envs/dev/terraform.tfstate*
rm -f infra/envs/prod/terraform.tfstate*
```

---

# Submission checklist

- [x] Terraform AWS infrastructure
- [x] Reusable Terraform modules
- [x] Dev environment
- [x] Prod environment
- [x] Separate backend configuration
- [x] Docker Compose PostgreSQL
- [x] SQL migration
- [x] 100+ seed bookings
- [x] Multiple cities/organizations/statuses
- [x] Booking events
- [x] Query index
- [x] Query plan verification
- [x] Timestamped backup
- [x] Fresh-database restore
- [x] Restore verification
- [x] GitHub Actions
- [x] README setup and verification instructions
