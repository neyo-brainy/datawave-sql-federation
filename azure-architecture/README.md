# Azure Production Architecture Proposal

## DataWave Industries — SQL Federation Platform on Azure

This document presents a production-grade Azure architecture for the DataWave Industries SQL Federation Platform. It maps every component from the local Docker Compose proof-of-concept to managed Azure services, with detailed coverage of reliability, security, data platform design, and deployment strategy.

---

## Table of Contents

- [Assumptions](#assumptions)
- [1. Core Azure Services Selection](#1-core-azure-services-selection)
- [2. Reliability and Operational Design](#2-reliability-and-operational-design)
- [3. Security Design](#3-security-design)
- [4. Data Platform Design](#4-data-platform-design)
- [5. Deployment Model](#5-deployment-model)
- [6. Architecture Diagram](#6-architecture-diagram)
- [Local-to-Azure Mapping](#local-to-azure-mapping)
- [Trade-offs and Future Improvements](#trade-offs-and-future-improvements)

---

## Assumptions

- **Azure is the sole cloud provider** — per assessment requirements.
- **Single-region deployment initially** — East US 2 with zone redundancy. The DR section covers multi-region expansion.
- **Primary region is East US 2** — strong availability zone support, paired with Central US for disaster recovery.
- **Team size is 3–5 engineers** — influences the operational ownership model and automation requirements.
- **Data volume is moderate (< 10 TB initially)** — affects storage tier and Trino cluster sizing.
- **Compliance follows SOC 2 / ISO 27001 patterns** — standard enterprise controls without HIPAA/PCI specifics.
- **GitHub is the VCS and CI/CD platform** — aligns with the existing repository.

---

## 1. Core Azure Services Selection

### 1.1 Compute and Orchestration

**Selected: Azure Kubernetes Service (AKS)**

The local Docker Compose environment orchestrates 11 containers. In Azure, this maps to **AKS with system and user node pools**.

**Why AKS over alternatives?** Trino runs as a coordinator + worker cluster that benefits from Kubernetes-native scaling, health management, and pod affinity. Azure Container Apps lacks the fine-grained pod placement and HPA customization Trino needs. Container Instances lack orchestration. VMs require manual lifecycle management.

**Node pool sizing:**

- **System pool** — 2× Standard_D4s_v5 for Kubernetes system pods, OAuth2 Proxy, and monitoring agents
- **Trino pool** — 3–5× Standard_E8s_v5 (memory-optimized) for Trino workers
- **Metabase pool** — 2× Standard_D2s_v5

AKS uses the latest stable LTS channel with automatic upgrades.

**Trino Deployment Model:**
- **Coordinator**: 1 replica (StatefulSet) on the Trino node pool
- **Workers**: 3–5 replicas (Deployment) with Horizontal Pod Autoscaler (HPA) based on CPU and active query count
- Deployed via the official [Trino Helm chart](https://trinodb.github.io/charts/)

**Why not Azure Container Apps?**
Container Apps provides simpler serverless scaling, but Trino's coordinator-worker topology, memory-heavy workloads, and need for pod anti-affinity rules make AKS the better fit. Container Apps could serve Metabase, but consolidating on AKS simplifies networking and secrets management.

### 1.2 Storage

**Selected: Azure Data Lake Storage Gen2 (ADLS Gen2)**

Locally, MinIO provides S3-compatible object storage. In Azure, this maps to **ADLS Gen2** — a Storage Account with hierarchical namespace enabled.

**Why ADLS Gen2?** Native S3-compatible API via Azure Blob, hierarchical namespace for efficient directory operations, integrated with Azure RBAC and Private Endpoints, and hot/cool/archive tiering for cost optimization.

**Configuration:**

- **Containers** — `datalake` (Parquet/analytics data) and `warehouse` (staging/raw data), mirroring the MinIO buckets
- **File format** — Apache Parquet (columnar, compressed), same as local
- **Redundancy** — ZRS (Zone-Redundant Storage) for production, LRS for dev
- **Access tier** — Hot for active data; lifecycle policies move to Cool after 90 days
- **Soft delete** — 30-day retention for blob and container recovery

### 1.3 Databases

**Selected: Azure Database for PostgreSQL Flexible Server + Azure Database for MySQL Flexible Server**

Each local database container maps to a managed Flexible Server instance:

- **PostgreSQL 16 (logistics)** → Azure Database for PostgreSQL Flexible Server — General Purpose, 2 vCores, 8 GB RAM, 128 GB storage, zone-redundant HA
- **MySQL 8.0 (warehouse)** → Azure Database for MySQL Flexible Server — General Purpose, 2 vCores, 8 GB RAM, 128 GB storage, zone-redundant HA
- **MySQL 8.0 (metastore-db)** → Azure Database for MySQL Flexible Server — Burstable, 1 vCore, 2 GB RAM (Hive Metastore is lightweight)

**Why Flexible Server over Single Server?** Zone-redundant HA with automatic failover, start/stop for non-production (cost savings), better Burstable tier for the metastore DB, and flexible maintenance windows.

### 1.4 Networking

<img width="700" height="390" alt="image" src="https://github.com/user-attachments/assets/af0661d0-2a84-4a81-801a-af21009deae5" />



The VNet `datawave-vnet` uses a `/16` address space (10.0.0.0/16) divided into five subnets:

- **aks-subnet (10.0.0.0/20)** — AKS nodes running Trino, Metabase, and OAuth2 Proxy
- **data-subnet (10.0.16.0/24)** — Private Endpoints for PostgreSQL, MySQL, and Metastore DB
- **appgw-subnet (10.0.17.0/24)** — Azure Application Gateway v2 with WAF, handling TLS termination and path-based routing to Trino UI and Metabase
- **storage-subnet (10.0.18.0/24)** — Private Endpoint for ADLS Gen2
- **keyvault-subnet (10.0.19.0/24)** — Private Endpoint for Key Vault

**NSG rules** are per-subnet: the data-subnet allows ingress only from aks-subnet on specific DB ports (5432, 3306); the App Gateway subnet allows 443 from the Internet and denies everything else.

**Private Endpoints** are used for all databases, ADLS Gen2, and Key Vault — no public IP exposure.

**Azure Private DNS Zones** handle name resolution for all Private Endpoint-backed services (e.g., `privatelink.postgres.database.azure.com`).

**Mapping to local network segmentation:**

- The local `frontend` network (Trino, Metabase, OAuth2 Proxy, Keycloak) maps to `aks-subnet` + `appgw-subnet`
- The local `datasources` network (PostgreSQL, MySQL, MinIO, Hive Metastore) maps to `data-subnet` + `storage-subnet` — reachable only from AKS

### 1.5 Secrets and Configuration

**Selected: Azure Key Vault + Managed Identities + AKS Secrets Store CSI Driver**

Locally, secrets are plaintext environment variables in `docker-compose.yml`. In Azure, **Azure Key Vault (Premium SKU with HSM-backed keys)** stores all sensitive values.

**Secret injection** works through the AKS Secrets Store CSI Driver, which mounts Key Vault secrets as files or environment variables in pods — no secrets in Helm values or Git.

**Identity** is handled by AKS workload identity (federated credentials). Each pod identity maps to a Key Vault access policy, eliminating shared service principals.

**Non-secret configuration** (Trino catalog configs, feature flags) lives in Azure App Configuration with Key Vault references for any sensitive values.

**Secrets stored in Key Vault:**

- Database connection strings (PostgreSQL, MySQL, Metastore DB)
- ADLS Gen2 storage account keys (or use Managed Identity for ABFS access)
- Entra ID OIDC client secret
- Trino internal communication shared secret
- OAuth2 Proxy cookie secret

### 1.6 Monitoring and Observability

**Selected: Azure Monitor + Prometheus + Grafana (Azure Managed Grafana)**

The monitoring stack is organized in layers:

- **Infrastructure** — Azure Monitor + Container Insights for node/pod CPU, memory, disk, network, and AKS cluster health
- **Application** — Prometheus (AKS addon) + Trino JMX metrics for query latency, active queries, worker utilization, and queue depth
- **Dashboards** — Azure Managed Grafana pulling from Prometheus and Azure Monitor for unified visibility
- **Logs** — Azure Log Analytics workspace for centralized log aggregation from all AKS pods and Azure PaaS services
- **Alerting** — Azure Monitor Alerts + Action Groups with PagerDuty/email/Teams integration
- **Uptime** — Application Insights availability tests running synthetic heartbeat probes for Trino, Metabase, and OAuth2 Proxy

**Key alerts configured:**

- **Trino coordinator down** (Sev 0) — Pod restart count > 2 in 5 minutes
- **Query latency P95 > 30s** (Sev 2) — Prometheus `trino_execution_time` metric
- **Worker pool < 2 nodes** (Sev 1) — HPA replica count below minimum
- **Database connection failures** (Sev 1) — Connection error rate > 5%
- **ADLS Gen2 throttling** (Sev 2) — HTTP 429 count > 10/min
- **Certificate expiry < 14 days** (Sev 2) — App Gateway cert check

### 1.7 CI/CD and Infrastructure as Code

**Selected: Terraform + GitHub Actions**

- **IaC** — Terraform with the Azure Provider (azurerm), using modules for AKS, networking, databases, storage, Key Vault, and monitoring
- **State management** — Terraform state in an Azure Storage Account (blob backend) with state locking via Azure lease
- **CI/CD** — GitHub Actions with separate workflows for infrastructure (Terraform) and application (Helm/Docker)
- **Container registry** — Azure Container Registry (ACR). AKS pulls images via managed identity. Custom Trino images (with connector plugins) are stored here.
- **GitOps (optional)** — ArgoCD or Flux on AKS for Kubernetes manifest reconciliation

**Why Terraform over Bicep?** Team familiarity — Terraform is more widely known. Multi-cloud portability if needed in the future. Mature module ecosystem for AKS patterns. State management and drift detection are more explicit.

**Pipeline structure:**

```
main branch push
├── terraform-plan → terraform-apply (infrastructure)
│   ├── VNet, subnets, NSGs
│   ├── AKS cluster
│   ├── Databases (PostgreSQL, MySQL)
│   ├── ADLS Gen2 Storage Account
│   ├── Key Vault + secrets
│   └── Azure Monitor resources
│
└── helm-deploy (application)
    ├── Build + push Trino image → ACR
    ├── Helm upgrade: Trino (coordinator + workers)
    ├── Helm upgrade: Metabase
    ├── Helm upgrade: Hive Metastore
    ├── Helm upgrade: OAuth2 Proxy
    └── Smoke tests (query validation)
```

---

## 2. Reliability and Operational Design

### 2.1 High Availability

Every component is designed for zone-redundant availability:

- **AKS** — 3 availability zones, system + user node pools spread across zones. RTO < 5 min (pod rescheduling), RPO 0 (stateless pods).
- **Trino Coordinator** — Single replica with fast restart (liveness/readiness probes, 30s startup). Kubernetes reschedules on node failure. RTO < 2 min.
- **Trino Workers** — 3+ replicas spread across zones via pod anti-affinity. Remaining workers absorb if one fails. RPO 0 (stateless).
- **PostgreSQL** — Zone-redundant HA with automatic failover (standby in different AZ). RTO < 60s, RPO 0 (synchronous replication).
- **MySQL** — Zone-redundant HA with automatic failover. RTO < 60s, RPO 0.
- **ADLS Gen2** — ZRS (3 copies across zones). Effectively zero RTO and RPO.
- **Metabase** — 2 replicas on separate nodes, stateless (metadata in PostgreSQL). RTO < 1 min.
- **Application Gateway** — Zone-redundant by default (v2 SKU).

### 2.2 Scaling Strategy

- **Trino workers** — Horizontal Pod Autoscaler (HPA) triggered by CPU > 70% or active queries > 10 per worker. Scales between 3–10 pods.
- **AKS Trino node pool** — Cluster Autoscaler adds nodes when pods are pending due to insufficient resources. Range: 3–8 nodes.
- **Metabase** — HPA triggered by CPU > 80%. Scales between 2–4 pods.
- **PostgreSQL / MySQL** — Vertical scaling (manual) when connection saturation or sustained CPU > 80%. Scale vCores as needed.
- **ADLS Gen2** — Automatic (Azure managed), effectively unlimited throughput.

### 2.3 Failure Isolation

```
Blast Radius Containment:

Application Gateway → (failure here) → users lose access, data safe
    │
    ├── OAuth2 Proxy → (failure) → SSO unavailable, direct Trino CLI still works
    ├── Metabase → (failure) → BI UI down, Trino CLI/API unaffected
    │
    └── Trino Coordinator → (failure) → all queries fail, data safe
         ├── Worker 1 (AZ-1) → (failure) → other workers absorb
         ├── Worker 2 (AZ-2)
         ├── Worker 3 (AZ-3)
         │
         ├── PostgreSQL (AZ-1/AZ-2) → (failure) → PG queries fail, MySQL + Hive queries unaffected
         ├── MySQL (AZ-1/AZ-2) → (failure) → MySQL queries fail, PG + Hive queries unaffected
         └── ADLS Gen2 (ZRS) → (failure) → highly unlikely, 3-zone redundancy
```

**Key isolation principles:**

- **Data source independence** — A PostgreSQL outage does not affect MySQL or Hive queries. Trino returns partial results or targeted errors.
- **Namespace isolation** — Trino, Metabase, and monitoring run in separate Kubernetes namespaces with distinct RBAC and resource quotas.
- **Pod Disruption Budgets** — Trino workers have a PDB of `minAvailable: 2` to survive voluntary disruptions (node upgrades, scaling).

### 2.4 Backup and Recovery

- **PostgreSQL / MySQL / Metastore DB** — Azure automated backups with continuous point-in-time restore (PITR). 35-day retention. Recovery to any second within the retention window.
- **ADLS Gen2** — Soft delete (30-day retention) + blob versioning (90 days). Self-service restore via portal or CLI.
- **Key Vault** — Built-in soft delete + purge protection. 90-day retention for recovering deleted secrets and keys.
- **AKS / Helm** — Velero for Kubernetes resource backup. Daily snapshots with 30-day retention. Restores full namespaces and persistent volumes.
- **Terraform state** — Azure Blob versioning + cross-region replication. Retained for 90 days per apply.

### 2.5 Disaster Recovery

Three scenarios addressed:

1. **Single AZ failure** — Zone-redundant resources automatically fail over. RTO < 5 min, RPO 0.
2. **Full region failure** — Geo-restore databases to paired region (Central US). Deploy AKS via Terraform in DR region. ADLS Gen2 GRS replication. RTO < 4 hours, RPO < 1 hour.
3. **Data corruption** — Point-in-time restore for databases. Blob versioning for ADLS Gen2. RTO < 1 hour, RPO per-second (PITR).

**DR Runbook (Region Failure):**
1. Detect via Azure Service Health alerts
2. Trigger GitHub Actions DR workflow
3. `terraform apply -var region=centralus` to provision DR infrastructure
4. Geo-restore databases from latest backup
5. Helm deploy applications to DR AKS cluster
6. Update DNS (Azure Front Door or Traffic Manager) to point to DR region
7. Validate with smoke tests

### 2.6 Upgrade and Rollback Strategy

- **AKS** — Node image auto-upgrade (stable channel). Control plane upgrades via Terraform with maintenance window. Rollback by reverting Terraform to the previous version.
- **Trino** — Rolling update via Helm. New image tag → `helm upgrade`. Workers drained gracefully (finish active queries). Rollback with `helm rollback trino <revision>`.
- **Metabase** — Rolling update, 1 pod at a time. Rollback with `helm rollback metabase <revision>`.
- **Databases** — Minor versions auto-applied by Azure. Major versions tested in staging first. Rollback via point-in-time restore if an upgrade fails.
- **Terraform** — Plan reviewed in PR → apply on merge. State versioning allows rollback via `terraform apply` with the previous commit.

### 2.7 Observability and Alerting

See [Section 1.6](#16-monitoring-and-observability) for tooling details.

**Alerting escalation:**

- **Sev 0 (Critical)** — Page on-call engineer immediately via PagerDuty phone call
- **Sev 1 (High)** — Acknowledge within 15 min via PagerDuty → Slack alert
- **Sev 2 (Warning)** — Review within 4 hours via Slack channel notification
- **Sev 3 (Info)** — Review next business day via email digest

### 2.8 Capacity Management

- **Monthly capacity review** — Dashboard showing resource utilization trends (CPU, memory, storage, query volume)
- **Right-sizing** — Azure Advisor recommendations for underutilized resources
- **Cost controls** — Azure Budgets with alerts at 80% and 100% of monthly spend
- **Reserved instances** — 1-year RIs for database compute (30–40% savings) once baseline is established
- **AKS node pool auto-scaling** — Cluster Autoscaler prevents over-provisioning while meeting demand

---

## 3. Security Design

### 3.1 Identity and Access Management

<img width="493" height="337" alt="image" src="https://github.com/user-attachments/assets/9a41c8b0-2b80-4da5-8856-c585efe496f8" />


**Identity Provider** — Microsoft Entra ID replaces the local Keycloak container. It provides OIDC authentication for both the Trino Web UI (via OAuth2 Proxy) and Metabase (native OIDC support).

**Service authentication** uses AKS Workload Identity with federated credentials. Each pod gets its own Entra ID identity — no shared service principals.

**RBAC** operates at three tiers: Azure RBAC for infrastructure, Kubernetes RBAC for pod-level access, and Trino system access control for query-level authorization.

**MFA** is enforced via Entra ID Conditional Access policies. **Privileged access** uses Azure PIM (Privileged Identity Management) for just-in-time admin access.

**Local-to-Azure identity mapping:**

- Keycloak (OIDC IdP) → Microsoft Entra ID
- OAuth2 Proxy → OAuth2 Proxy on AKS (same component, using Entra ID as provider)
- Plaintext passwords in env vars → Key Vault + Managed Identity
- No MFA → Conditional Access with MFA enforcement

### 3.2 Secret Management

All secrets are stored in Azure Key Vault and injected into pods via the Secrets Store CSI Driver:

- **DB connection strings** — Key Vault → CSI Driver → pod env var
- **ADLS storage key** — Not needed; Managed Identity handles ABFS access via Workload Identity
- **OIDC client secret** — Key Vault → CSI Driver
- **Trino internal secret** — Key Vault → CSI Driver
- **TLS certificates** — Key Vault (managed certificates) → App Gateway integration

**Key principles:**

- **Zero secrets in Git** — all secrets in Key Vault, referenced by name in Helm values
- **Rotation** — Key Vault supports automatic rotation policies; pods reload via CSI driver sync
- **Audit** — Key Vault diagnostic logs sent to Log Analytics for secret access auditing

### 3.3 Network Isolation

- **Public exposure** — Only Application Gateway has a public IP (HTTPS 443). All other services are private.
- **Private Endpoints** — PostgreSQL, MySQL, ADLS Gen2, Key Vault, ACR are all accessed via Private Endpoints within the VNet.
- **NSG rules** — `data-subnet` allows inbound only from `aks-subnet` on ports 5432/3306. `appgw-subnet` allows 443 from Internet, denies all else.
- **AKS network policy** — Calico network policies restrict pod-to-pod traffic. Only Trino pods can reach database Private Endpoints. Metabase can only reach Trino. This mirrors the local `frontend` / `datasources` network segmentation.
- **No SSH** — AKS nodes have no public IP. Access via `kubectl exec` or Azure Bastion for emergency.

### 3.4 Encryption

- **In transit** — TLS 1.2+ everywhere. App Gateway terminates external TLS. Internal AKS traffic optionally encrypted via service mesh (Istio) or Trino internal TLS.
- **At rest** — Azure-managed encryption for all PaaS services (PostgreSQL, MySQL, ADLS Gen2, Key Vault). SSE with Microsoft-managed keys, or CMK via Key Vault for enhanced control.
- **Database** — Transparent Data Encryption (TDE) enabled by default on Azure Database services.
- **Backups** — Encrypted with the same keys as source data.

### 3.5 Least-Privilege Principles

Each actor has the minimum access required:

- **Trino pod** — Read-only to PostgreSQL and MySQL (data sources). Read-write to ADLS Gen2 (for `CREATE TABLE AS`). Read to Key Vault (own secrets only).
- **Metabase pod** — Connect to Trino only. No direct database or storage access.
- **OAuth2 Proxy pod** — Upstream to Trino only. Read to Key Vault (OIDC secret).
- **CI/CD service principal** — Scoped to resource group. Cannot read Key Vault secrets — only manages infrastructure.
- **Developers** — Read access to AKS (via Entra ID + K8s RBAC). No direct database access — use Trino.
- **On-call engineers** — PIM-elevated access for incident response (time-limited, audit-logged).

---

## 4. Data Platform Design

### 4.1 SQL Federation Architecture on Azure

<img width="600" height="650" alt="image" src="https://github.com/user-attachments/assets/a3d7e8c4-285e-4261-8788-065923b68dc7" />



### 4.2 Connector Configuration

Each Trino connector connects to its Azure PaaS target via Private Endpoint:

- **PostgreSQL connector** → Azure Database for PostgreSQL Flexible Server. JDBC via Private Endpoint, credentials from Key Vault, SSL enforced.
- **MySQL connector** → Azure Database for MySQL Flexible Server. JDBC via Private Endpoint, credentials from Key Vault, SSL enforced.
- **Hive connector** → ADLS Gen2 via `abfs://` protocol. Authentication via Managed Identity (preferred) or storage account key from Key Vault. Metastore backed by Azure DB for MySQL.

**Trino Catalog Configuration (Azure):**

```properties
# postgresql.properties
connector.name=postgresql
connection-url=jdbc:postgresql://datawave-pg.postgres.database.azure.com:5432/logistics?sslmode=require
connection-user=${ENV:PG_USER}
connection-password=${ENV:PG_PASSWORD}

# mysql.properties
connector.name=mysql
connection-url=jdbc:mysql://datawave-mysql.mysql.database.azure.com:3306/warehouse?useSSL=true
connection-user=${ENV:MYSQL_USER}
connection-password=${ENV:MYSQL_PASSWORD}

# hive.properties
connector.name=hive
hive.metastore.uri=thrift://hive-metastore.trino.svc.cluster.local:9083
hive.azure.abfs.storage-account=datawavestorage
hive.azure.abfs.access-key=${ENV:ADLS_ACCESS_KEY}
```

### 4.3 Hive Metastore on Azure

The Hive Metastore runs as a pod in AKS (same image as local), with its backend DB moved to **Azure Database for MySQL Flexible Server (Burstable tier)** — replacing the local `metastore-db` container. Storage points to ADLS Gen2 via `abfs://datalake@datawavestorage.dfs.core.windows.net/`.

If the operational overhead of a self-hosted Hive Metastore grows, evaluate Azure HDInsight Metastore or Azure Purview as managed catalog alternatives.

### 4.4 Future Data Source Extensibility

Trino's plugin architecture makes adding new data sources straightforward. Potential future sources:

- **Azure Cosmos DB** — via the `cosmosdb` connector, with Cosmos DB on a Private Endpoint
- **Azure Synapse Analytics** — via the `sqlserver` connector, targeting a Synapse Dedicated SQL Pool
- **Elasticsearch / OpenSearch** — via the `elasticsearch` connector, using Azure Cognitive Search or a self-hosted cluster
- **MongoDB** — via the `mongodb` connector, targeting Azure Cosmos DB for MongoDB
- **Delta Lake** — via the `delta-lake` connector, reading Delta format from ADLS Gen2
- **Apache Iceberg** — via the `iceberg` connector, reading Iceberg tables from ADLS Gen2

**Adding a new source requires:**
1. Create the Azure PaaS resource via Terraform
2. Store credentials in Key Vault
3. Add a Trino catalog `.properties` file to the Helm chart
4. Rolling restart of Trino workers (zero-downtime via Kubernetes rolling update)

---

## 5. Deployment Model

### 5.1 Environment Strategy

Three environments are deployed from the **same Terraform modules** with different `tfvars` files:

- **dev** — Development and experimentation. Single-node AKS, Burstable DB tiers, LRS storage. Auto-shutdown outside business hours for cost savings.
- **staging** — Pre-production validation and load testing. Mirrors prod topology at smaller scale (2 workers). Spot instances for Trino workers.
- **prod** — Production workloads. Full HA with 3+ workers, zone-redundant databases, ZRS storage. Reserved instances for steady-state cost optimization.

```
terraform/
├── modules/
│   ├── aks/
│   ├── networking/
│   ├── databases/
│   ├── storage/
│   ├── keyvault/
│   └── monitoring/
├── environments/
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
└── main.tf
```

### 5.2 IaC Approach

**Terraform (azurerm provider)** manages all infrastructure:

- **State** — Azure Storage Account with blob locking. Separate state file per environment.
- **Modules** — Reusable modules for each Azure resource group (AKS, databases, networking, etc.).
- **Validation** — `terraform plan` on every PR. `terraform apply` on merge to `main`.
- **Drift detection** — Scheduled `terraform plan` runs (nightly) detect manual changes.
- **Policy** — Azure Policy assignments via Terraform enforce tagging, allowed SKUs, and encryption requirements.

### 5.3 Release Process

```
Feature branch
    │
    ▼
Pull Request
    ├── Terraform plan (infrastructure changes)
    ├── Docker build + push to ACR (application changes)
    ├── Helm diff (preview Kubernetes changes)
    └── Automated tests (lint, security scan, unit tests)
    │
    ▼
Merge to main
    ├── Deploy to staging
    │   ├── Terraform apply (staging)
    │   ├── Helm upgrade (staging)
    │   └── Integration tests + smoke tests
    │       ├── Verify Trino catalogs
    │       ├── Run cross-source federation query
    │       └── Verify SSO flow
    │
    ▼ (manual approval gate)
    │
    ├── Deploy to prod
    │   ├── Terraform apply (prod)
    │   ├── Helm upgrade (prod) — rolling update
    │   └── Post-deploy validation
    │       ├── Synthetic query tests
    │       └── Dashboard health checks
    │
    ▼
Monitor for 30 minutes → auto-rollback if error rate > 1%
```

### 5.4 Operational Ownership Model

- **Platform Team (2–3 engineers)** — Owns AKS cluster, Terraform modules, CI/CD pipelines, monitoring, security baseline, and Trino upgrades.
- **Data Engineering Team** — Owns Trino catalog configuration, query optimization, new data source onboarding, and Metabase dashboards.
- **On-Call Rotation** — Shared between Platform and Data Engineering. Pager for Sev 0/1 alerts with weekly handoff.
- **Security Review** — Platform team runs quarterly security audits. Dependency scanning in CI. Azure Defender for Cloud enabled.

---

## 6. Architecture Diagram

### 6.1 Full Azure Architecture

<img width="800" height="2200" alt="image" src="https://github.com/user-attachments/assets/9f4b39e3-7be0-4369-a6e7-d7ed6ed06e1f" />


### 6.2 Network Flow Diagram

```
Internet → App Gateway (public IP, WAF, TLS)
              │
              ├──/trino──→ OAuth2 Proxy ──→ Entra ID (OIDC) ──→ Trino UI
              ├──/metabase──→ Metabase pod
              └──/grafana──→ Grafana pod
                                    │
                           AKS Internal Network
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
              Private EP      Private EP      Private EP
                    │               │               │
              PostgreSQL        MySQL          ADLS Gen2
              (Flexible)      (Flexible)       (Storage)
```

### 6.3 Local-to-Azure Component Mapping

Each local Docker Compose component maps directly to an Azure service:

1. **Docker Compose** → **AKS (Kubernetes)** — Compose services become Helm charts. Health checks become liveness/readiness probes.
2. **Trino (container)** → **Trino on AKS (Helm chart)** — Same Trino image. Coordinator + workers as separate deployments.
3. **PostgreSQL (container)** → **Azure DB for PostgreSQL Flexible Server** — `pg_dump` + `pg_restore` for data migration. Update JDBC URL in catalog config.
4. **MySQL (container)** → **Azure DB for MySQL Flexible Server** — `mysqldump` + `mysql` import. Update JDBC URL.
5. **MinIO (container)** → **ADLS Gen2** — Migrate Parquet files via `azcopy`. Switch Trino connector from `hive.s3.*` to `hive.azure.abfs.*`.
6. **Hive Metastore (container)** → **Hive Metastore on AKS** — Same image, backend DB moves to Azure DB for MySQL. Storage URIs change from `s3a://` to `abfs://`.
7. **Metastore DB (container)** → **Azure DB for MySQL (Burstable)** — Schema auto-created by Hive Metastore on first start.
8. **Metabase (container)** → **Metabase on AKS** — Same image. Internal PostgreSQL for metadata can use Azure DB for PostgreSQL.
9. **Keycloak (container)** → **Microsoft Entra ID** — No self-hosted IdP needed. Register an OAuth2 app in Entra ID.
10. **OAuth2 Proxy (container)** → **OAuth2 Proxy on AKS** — Same image. Change `--provider` from `keycloak-oidc` to `azure`. Configure Entra ID tenant/client IDs.
11. **Docker networks (frontend/datasources)** → **VNet subnets + NSGs + Kubernetes Network Policies** — Same isolation model: Metabase → Trino only, Trino → data sources.

---

## Trade-offs and Future Improvements

### Trade-offs

- **AKS over Container Apps** — More operational overhead (cluster upgrades, node management) but provides fine-grained control for Trino's worker topology and memory requirements.
- **Self-hosted Hive Metastore** — Operational burden vs. no Azure-native equivalent (unlike AWS Glue). Could evaluate Azure Purview or Unity Catalog in the future.
- **Terraform over Bicep** — Slightly less Azure-native integration, but better multi-cloud portability and wider team familiarity.
- **Single region** — Lower cost and complexity, but full region failure requires manual DR activation. Multi-region active-active would eliminate this at 2× cost.
- **Zone-redundant HA (databases)** — ~2× cost of non-HA tiers, but eliminates single-AZ failure risk for critical data stores.
- **Managed Identity over service principals** — No credential rotation needed, but slightly more complex initial setup with workload identity federation.

### Future Improvements

- **Apache Iceberg table format** (Medium effort) — ACID transactions, time travel, and schema evolution for the data lake.
- **Azure Purview integration** (Medium) — Unified data catalog, lineage tracking, and data governance.
- **Query result caching** (Low) — Redis or Azure Cache for Redis to cache frequent Trino queries.
- **Multi-region active-active** (High) — Zero-downtime DR and lower latency for global users.
- **Trino fault-tolerant execution** (Low, config change) — Retry failed query tasks without restarting the full query.
- **Cost allocation tags** (Low) — Tag all resources by team/project for chargeback reporting.
- **Azure Confidential Computing** (High) — Encrypt data in use for highly sensitive workloads.
- **Service mesh (Istio)** (Medium) — mTLS between all pods, traffic observability, and circuit breaking.

---

## Cost Estimate (Monthly — Production)

| Service | SKU | Est. Monthly Cost |
|---------|-----|-------------------|
| AKS (system pool: 2× D4s_v5) | Pay-as-you-go | ~$280 |
| AKS (Trino pool: 3× E8s_v5) | Pay-as-you-go | ~$730 |
| AKS (Metabase pool: 2× D2s_v5) | Pay-as-you-go | ~$140 |
| Azure DB PostgreSQL (GP 2 vCore, HA) | Zone-redundant | ~$260 |
| Azure DB MySQL — Warehouse (GP 2 vCore, HA) | Zone-redundant | ~$230 |
| Azure DB MySQL — Metastore (Burstable 1 vCore) | Standard | ~$25 |
| ADLS Gen2 (1 TB, ZRS, hot tier) | Pay-as-you-go | ~$45 |
| Application Gateway v2 + WAF | Standard | ~$250 |
| Key Vault | Premium | ~$5 |
| Azure Monitor + Log Analytics (50 GB/month) | Pay-as-you-go | ~$130 |
| Azure Managed Grafana | Standard | ~$15 |
| ACR (Standard) | Standard | ~$20 |
| **Total** | | **~$2,130/month** |

> Costs can be reduced ~30% with 1-year Reserved Instances for AKS nodes and databases, and further with dev/staging auto-shutdown schedules.
