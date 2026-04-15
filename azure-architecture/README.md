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

| Assumption | Rationale |
|------------|-----------|
| Azure is the sole cloud provider | Per assessment requirements |
| Multi-region is not required initially | Single-region with zone redundancy keeps costs manageable; DR section covers multi-region expansion |
| Primary region is **East US 2** | Strong availability zone support, paired with Central US for DR |
| Team size is 3–5 engineers | Influences operational ownership model and automation requirements |
| Data volume is moderate (< 10 TB initially) | Affects storage tier and Trino cluster sizing |
| Compliance requirements follow SOC 2 / ISO 27001 patterns | Standard enterprise controls without HIPAA/PCI specifics |
| GitHub is the VCS and CI/CD platform | Aligns with the existing repository on GitHub |

---

## 1. Core Azure Services Selection

### 1.1 Compute and Orchestration

**Selected: Azure Kubernetes Service (AKS)**

| Aspect | Detail |
|--------|--------|
| **Local equivalent** | Docker Compose orchestrating 11 containers |
| **Azure service** | AKS with system + user node pools |
| **Why AKS over alternatives** | Trino runs as a coordinator + worker cluster that benefits from Kubernetes-native scaling, health management, and pod affinity. Azure Container Apps lacks the fine-grained pod placement and HPA customization Trino needs. Container Instances lack orchestration. VMs require manual lifecycle management. |
| **Node pools** | **System pool**: 2× Standard_D4s_v5 (for Kubernetes system pods, OAuth2 Proxy, monitoring agents). **Trino pool**: 3–5× Standard_E8s_v5 (memory-optimized for Trino workers). **Metabase pool**: 2× Standard_D2s_v5. |
| **Kubernetes version** | Latest stable LTS channel with automatic upgrades |

**Trino Deployment Model:**
- **Coordinator**: 1 replica (StatefulSet) on the Trino node pool
- **Workers**: 3–5 replicas (Deployment) with Horizontal Pod Autoscaler (HPA) based on CPU and active query count
- Deployed via the official [Trino Helm chart](https://trinodb.github.io/charts/)

**Why not Azure Container Apps?**
Container Apps provides simpler serverless scaling, but Trino's coordinator-worker topology, memory-heavy workloads, and need for pod anti-affinity rules make AKS the better fit. Container Apps could serve Metabase, but consolidating on AKS simplifies networking and secrets management.

### 1.2 Storage

**Selected: Azure Data Lake Storage Gen2 (ADLS Gen2)**

| Aspect | Detail |
|--------|--------|
| **Local equivalent** | MinIO (S3-compatible object storage) |
| **Azure service** | ADLS Gen2 (Storage Account with hierarchical namespace enabled) |
| **Why ADLS Gen2** | Native S3-compatible API via Azure Blob, hierarchical namespace for efficient directory operations, integrated with Azure RBAC and Private Endpoints, hot/cool/archive tiering for cost optimization |
| **Containers** | `datalake` (Parquet/analytics data), `warehouse` (staging/raw data) — mirrors the MinIO buckets |
| **File format** | Apache Parquet (columnar, compressed) — same as local implementation |

**Storage Account Configuration:**
- Hierarchical namespace: **Enabled** (ADLS Gen2)
- Redundancy: **ZRS** (Zone-Redundant Storage) for production, LRS for dev
- Access tier: **Hot** for active data, lifecycle policies to move to **Cool** after 90 days
- Soft delete: 30-day retention for blob and container recovery

### 1.3 Databases

**Selected: Azure Database for PostgreSQL Flexible Server + Azure Database for MySQL Flexible Server**

| Local Service | Azure Service | Configuration |
|---------------|---------------|---------------|
| PostgreSQL 16 (logistics) | Azure Database for PostgreSQL — Flexible Server | General Purpose, 2 vCores, 8 GB RAM, 128 GB storage, zone-redundant HA |
| MySQL 8.0 (warehouse) | Azure Database for MySQL — Flexible Server | General Purpose, 2 vCores, 8 GB RAM, 128 GB storage, zone-redundant HA |
| MySQL 8.0 (metastore-db) | Azure Database for MySQL — Flexible Server | Burstable, 1 vCore, 2 GB RAM (Hive Metastore is lightweight) |

**Why Flexible Server over Single Server?**
- Zone-redundant HA with automatic failover
- Start/stop capability for non-production environments (cost savings)
- Better Burstable tier for the metastore DB
- Flexible maintenance windows

### 1.4 Networking

```
┌──────────────────────────────────────────────────────────────────────────┐
│  VNet: datawave-vnet (10.0.0.0/16)                                       │
│                                                                          │
│  ┌─────────────────────┐  ┌──────────────────────┐  ┌────────────────┐  │
│  │ aks-subnet          │  │ data-subnet          │  │ appgw-subnet   │  │
│  │ 10.0.0.0/20         │  │ 10.0.16.0/24         │  │ 10.0.17.0/24   │  │
│  │                     │  │                      │  │                │  │
│  │ AKS nodes           │  │ PostgreSQL (PE)      │  │ App Gateway    │  │
│  │ (Trino, Metabase,   │  │ MySQL (PE)           │  │ + WAF v2       │  │
│  │  OAuth2 Proxy)      │  │ Metastore MySQL (PE) │  │                │  │
│  └─────────────────────┘  └──────────────────────┘  └────────────────┘  │
│                                                                          │
│  ┌─────────────────────┐  ┌──────────────────────┐                      │
│  │ storage-subnet      │  │ keyvault-subnet      │                      │
│  │ 10.0.18.0/24        │  │ 10.0.19.0/24         │                      │
│  │                     │  │                      │                      │
│  │ ADLS Gen2 (PE)      │  │ Key Vault (PE)       │                      │
│  └─────────────────────┘  └──────────────────────┘                      │
└──────────────────────────────────────────────────────────────────────────┘
```

| Component | Detail |
|-----------|--------|
| **VNet** | `datawave-vnet` — 10.0.0.0/16 |
| **Subnets** | AKS (10.0.0.0/20), data (10.0.16.0/24), App Gateway (10.0.17.0/24), storage (10.0.18.0/24), Key Vault (10.0.19.0/24) |
| **NSGs** | Per-subnet NSGs: data-subnet allows ingress only from aks-subnet on specific DB ports (5432, 3306). App Gateway subnet allows 443 from Internet. |
| **Private Endpoints** | All databases, ADLS Gen2, and Key Vault are accessed via Private Endpoints — no public IP exposure |
| **Application Gateway** | Azure Application Gateway v2 with WAF, TLS termination, path-based routing to Trino UI (`:4180` via OAuth2 Proxy) and Metabase |
| **DNS** | Azure Private DNS Zones for all PE-backed services (e.g., `privatelink.postgres.database.azure.com`) |

**Mapping to Local Network Segmentation:**

| Local Network | Azure Equivalent |
|---------------|-----------------|
| `frontend` (Trino, Metabase, OAuth2 Proxy, Keycloak) | `aks-subnet` + `appgw-subnet` — AKS pods + Application Gateway |
| `datasources` (PostgreSQL, MySQL, MinIO, Hive Metastore) | `data-subnet` + `storage-subnet` — Private Endpoints only reachable from AKS |

### 1.5 Secrets and Configuration

**Selected: Azure Key Vault + Managed Identities + AKS Secrets Store CSI Driver**

| Aspect | Detail |
|--------|--------|
| **Local equivalent** | Plaintext environment variables in `docker-compose.yml` |
| **Azure service** | Azure Key Vault (Premium SKU with HSM-backed keys) |
| **Secret injection** | AKS Secrets Store CSI Driver mounts Key Vault secrets as files or env vars in pods — no secrets in Helm values or Git |
| **Identity** | AKS workload identity (federated credentials) — each pod identity maps to a Key Vault access policy. No shared service principals. |
| **Configuration** | Azure App Configuration for non-secret settings (Trino catalog configs, feature flags). Key Vault references for secrets. |

**Secrets stored in Key Vault:**
- Database connection strings (PostgreSQL, MySQL, Metastore DB)
- ADLS Gen2 storage account keys (or use Managed Identity for ABFS access)
- Keycloak / Entra ID OIDC client secret
- Trino internal communication shared secret
- OAuth2 Proxy cookie secret

### 1.6 Monitoring and Observability

**Selected: Azure Monitor + Prometheus + Grafana (Azure Managed Grafana)**

| Layer | Tool | Purpose |
|-------|------|---------|
| **Infrastructure** | Azure Monitor + Container Insights | Node/pod CPU, memory, disk, network. AKS cluster health. |
| **Application** | Prometheus (AKS addon) + Trino JMX metrics | Query latency, active queries, worker utilization, queue depth |
| **Dashboards** | Azure Managed Grafana | Unified dashboards pulling from Prometheus and Azure Monitor |
| **Logs** | Azure Log Analytics workspace | Centralized log aggregation from all AKS pods and Azure PaaS services |
| **Alerting** | Azure Monitor Alerts + Action Groups | PagerDuty/email/Teams integration for critical alerts |
| **Uptime** | Application Insights availability tests | Synthetic heartbeat probes for Trino, Metabase, and OAuth2 Proxy endpoints |

**Key Alerts:**

| Alert | Condition | Severity |
|-------|-----------|----------|
| Trino coordinator down | Pod restart count > 2 in 5 min | Critical (Sev 0) |
| Query latency P95 > 30s | Prometheus `trino_execution_time` | Warning (Sev 2) |
| Worker pool < 2 nodes | HPA replica count < min | Critical (Sev 1) |
| Database connection failures | Connection error rate > 5% | Critical (Sev 1) |
| ADLS Gen2 throttling | HTTP 429 count > 10/min | Warning (Sev 2) |
| Certificate expiry < 14 days | App Gateway cert check | Warning (Sev 2) |

### 1.7 CI/CD and Infrastructure as Code

**Selected: Terraform + GitHub Actions**

| Aspect | Detail |
|--------|--------|
| **IaC** | Terraform with Azure Provider (azurerm). Modules for: AKS, networking, databases, storage, Key Vault, monitoring. |
| **State management** | Terraform state in Azure Storage Account (blob backend) with state locking via Azure lease |
| **CI/CD** | GitHub Actions — separate workflows for infrastructure (Terraform) and application (Helm/Docker) |
| **Container registry** | Azure Container Registry (ACR) — AKS pulls images via managed identity. Custom Trino images (with connector plugins) stored here. |
| **GitOps (optional)** | ArgoCD or Flux on AKS for Kubernetes manifest reconciliation |

**Why Terraform over Bicep?**
- Team familiarity — Terraform is more widely known
- Multi-cloud portability if needed in the future
- Mature module ecosystem for AKS patterns
- State management and drift detection are more explicit

**Pipeline Structure:**

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

| Component | HA Strategy | RTO | RPO |
|-----------|-------------|-----|-----|
| **AKS** | 3 availability zones, system + user node pools across zones | < 5 min (pod rescheduling) | 0 (stateless pods) |
| **Trino Coordinator** | Single replica with fast restart (liveness/readiness probes, 30s startup). Kubernetes reschedules on node failure. | < 2 min | 0 (stateless) |
| **Trino Workers** | 3+ replicas spread across zones via pod anti-affinity | 0 (remaining workers absorb) | 0 (stateless) |
| **PostgreSQL** | Zone-redundant HA with automatic failover (standby in different AZ) | < 60s (automatic failover) | 0 (synchronous replication) |
| **MySQL** | Zone-redundant HA with automatic failover | < 60s | 0 (synchronous replication) |
| **ADLS Gen2** | ZRS (3 copies across zones) | 0 | 0 |
| **Metabase** | 2 replicas on separate nodes, stateless (metadata in PostgreSQL) | < 1 min | 0 |
| **Application Gateway** | Zone-redundant by default (v2 SKU) | 0 | N/A |

### 2.2 Scaling Strategy

| Component | Scaling Type | Trigger | Range |
|-----------|-------------|---------|-------|
| **Trino workers** | HPA (horizontal pod) | CPU > 70% or active queries > 10 per worker | 3–10 pods |
| **AKS Trino node pool** | Cluster Autoscaler | Pending pods due to insufficient resources | 3–8 nodes |
| **Metabase** | HPA | CPU > 80% | 2–4 pods |
| **PostgreSQL** | Vertical (manual) | Connection saturation, CPU > 80% sustained | Scale vCores |
| **MySQL** | Vertical (manual) | Connection saturation, CPU > 80% sustained | Scale vCores |
| **ADLS Gen2** | Automatic (Azure managed) | N/A — effectively unlimited throughput | N/A |

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

- **Data source independence**: A PostgreSQL outage does not affect MySQL or Hive queries. Trino returns partial results or targeted errors.
- **Namespace isolation**: Trino, Metabase, and monitoring run in separate Kubernetes namespaces with distinct RBAC and resource quotas.
- **Pod Disruption Budgets**: Trino workers have a PDB of `minAvailable: 2` to survive voluntary disruptions (node upgrades, scaling).

### 2.4 Backup and Recovery

| Data Store | Backup Method | Frequency | Retention | Recovery |
|------------|--------------|-----------|-----------|----------|
| **PostgreSQL** | Azure automated backups (point-in-time restore) | Continuous | 35 days | PITR to any second within retention |
| **MySQL** | Azure automated backups (point-in-time restore) | Continuous | 35 days | PITR to any second within retention |
| **Metastore DB** | Azure automated backups | Continuous | 35 days | PITR |
| **ADLS Gen2** | Soft delete + blob versioning | Continuous | 30-day soft delete, 90-day versioning | Self-service restore via portal or CLI |
| **Key Vault** | Azure built-in soft delete + purge protection | Continuous | 90 days | Recover deleted secrets/keys |
| **AKS / Helm** | Velero for Kubernetes resource backup | Daily | 30 days | Restore namespaces and persistent volumes |
| **Terraform state** | Azure Blob versioning + cross-region replication | Per-apply | 90 days | Restore from blob version |

### 2.5 Disaster Recovery

| Scenario | Strategy | RTO | RPO |
|----------|----------|-----|-----|
| **Single AZ failure** | Zone-redundant resources automatically fail over | < 5 min | 0 |
| **Full region failure** | Geo-restore databases to paired region (Central US). Deploy AKS via Terraform in DR region. ADLS Gen2 GRS replication. | < 4 hours | < 1 hour |
| **Data corruption** | Point-in-time restore for databases. Blob versioning for ADLS Gen2 | < 1 hour | Per-second (PITR) |

**DR Runbook (Region Failure):**
1. Detect via Azure Service Health alerts
2. Trigger GitHub Actions DR workflow
3. `terraform apply -var region=centralus` to provision DR infrastructure
4. Geo-restore databases from latest backup
5. Helm deploy applications to DR AKS cluster
6. Update DNS (Azure Front Door or Traffic Manager) to point to DR region
7. Validate with smoke tests

### 2.6 Upgrade and Rollback Strategy

| Component | Upgrade Strategy | Rollback |
|-----------|-----------------|----------|
| **AKS** | Node image auto-upgrade (stable channel). Control plane upgrades via Terraform with maintenance window. | Revert Terraform to previous version |
| **Trino** | Rolling update via Helm. New image tag → Helm `upgrade`. Workers drained gracefully (finish active queries). | `helm rollback trino <revision>` |
| **Metabase** | Rolling update, 1 pod at a time | `helm rollback metabase <revision>` |
| **Databases** | Minor versions auto-applied by Azure. Major versions tested in staging first. | Point-in-time restore if upgrade fails |
| **Terraform** | Plan reviewed in PR → apply on merge. State versioning allows rollback. | `terraform apply` with previous commit |

### 2.7 Observability and Alerting

See [Section 1.6](#16-monitoring-and-observability) for tooling details.

**Alerting Escalation:**

| Severity | Response | Channel |
|----------|----------|---------|
| Sev 0 (Critical) | Page on-call engineer immediately | PagerDuty → phone call |
| Sev 1 (High) | Acknowledge within 15 min | PagerDuty → Slack alert |
| Sev 2 (Warning) | Review within 4 hours | Slack channel notification |
| Sev 3 (Info) | Review in next business day | Email digest |

### 2.8 Capacity Management

- **Monthly capacity review**: Dashboard showing resource utilization trends (CPU, memory, storage, query volume)
- **Right-sizing**: Azure Advisor recommendations for underutilized resources
- **Cost controls**: Azure Budgets with alerts at 80% and 100% of monthly spend
- **Reserved instances**: 1-year RIs for database compute (30–40% savings) once baseline is established
- **AKS node pool auto-scaling**: Cluster Autoscaler prevents over-provisioning while meeting demand

---

## 3. Security Design

### 3.1 Identity and Access Management

```
┌──────────────────────────────────────┐
│         Microsoft Entra ID           │
│     (Azure Active Directory)         │
│                                      │
│  Users ──┬── Groups ──── Roles       │
│           │                          │
│     ┌─────┴──────┐                   │
│     │ App Regs   │                   │
│     │            │                   │
│     │ trino-sso  │ ← OIDC client     │
│     │ metabase   │ ← OIDC client     │
│     └────────────┘                   │
└──────────────────────────────────────┘
```

| Aspect | Implementation |
|--------|---------------|
| **Identity Provider** | Microsoft Entra ID (replaces local Keycloak) |
| **User authentication** | OIDC via Entra ID — OAuth2 Proxy in front of Trino UI, Metabase native OIDC support |
| **Service authentication** | AKS Workload Identity (federated credentials) — each pod gets its own Entra ID identity |
| **RBAC** | Azure RBAC for infrastructure. Kubernetes RBAC for pod-level access. Trino system access control for query-level authorization. |
| **MFA** | Enforced via Entra ID Conditional Access policies |
| **Privileged access** | Azure PIM (Privileged Identity Management) for just-in-time admin access |

**Local-to-Azure Identity Mapping:**

| Local (Docker Compose) | Azure |
|------------------------|-------|
| Keycloak (OIDC IdP) | Microsoft Entra ID |
| OAuth2 Proxy | OAuth2 Proxy on AKS (same component, using Entra ID as provider) |
| Plaintext passwords in env vars | Key Vault + Managed Identity |
| No MFA | Conditional Access with MFA enforcement |

### 3.2 Secret Management

| Secret | Storage | Access Method |
|--------|---------|---------------|
| DB connection strings | Key Vault | Secrets Store CSI Driver → pod env var |
| ADLS storage key | Not needed — Managed Identity ABFS access | Workload Identity |
| OIDC client secret | Key Vault | Secrets Store CSI Driver |
| Trino internal secret | Key Vault | Secrets Store CSI Driver |
| TLS certificates | Key Vault (managed certificates) | App Gateway integration |

**Key Principles:**
- **Zero secrets in Git** — all secrets in Key Vault, referenced by name in Helm values
- **Rotation** — Key Vault supports automatic rotation policies; pods reload via CSI driver sync
- **Audit** — Key Vault diagnostic logs sent to Log Analytics for secret access auditing

### 3.3 Network Isolation

| Control | Implementation |
|---------|---------------|
| **Public exposure** | Only Application Gateway has a public IP (HTTPS 443). All other services are private. |
| **Private Endpoints** | PostgreSQL, MySQL, ADLS Gen2, Key Vault, ACR — all accessed via Private Endpoints within the VNet |
| **NSG rules** | `data-subnet`: allow inbound only from `aks-subnet` on ports 5432/3306. `appgw-subnet`: allow 443 from Internet, deny all else. |
| **AKS network policy** | Calico network policies restrict pod-to-pod traffic. Only Trino pods can reach database Private Endpoints. Metabase can only reach Trino. (Mirrors local `frontend` / `datasources` network segmentation.) |
| **No SSH** | AKS nodes have no public IP. Access via `kubectl exec` or Azure Bastion for emergency. |

### 3.4 Encryption

| Layer | Implementation |
|-------|---------------|
| **In transit** | TLS 1.2+ everywhere. App Gateway terminates external TLS. Internal AKS traffic optionally encrypted via service mesh (Istio) or Trino internal TLS. |
| **At rest** | Azure-managed encryption for all PaaS services (PostgreSQL, MySQL, ADLS Gen2, Key Vault). SSE with Microsoft-managed keys (or CMK via Key Vault for enhanced control). |
| **Database** | Transparent Data Encryption (TDE) enabled by default on Azure Database services |
| **Backups** | Encrypted with same keys as source data |

### 3.5 Least-Privilege Principles

| Actor | Access Scope |
|-------|-------------|
| **Trino pod** | Read-only to PostgreSQL, MySQL (data sources). Read-write to ADLS Gen2 (for `CREATE TABLE AS`). Read to Key Vault (own secrets only). |
| **Metabase pod** | Connect to Trino only. No direct database or storage access. |
| **OAuth2 Proxy pod** | Upstream to Trino only. Read to Key Vault (OIDC secret). |
| **CI/CD service principal** | Scoped to resource group. Cannot read Key Vault secrets — only manage infrastructure. |
| **Developers** | Read access to AKS (via Entra ID + K8s RBAC). No direct database access — use Trino. |
| **On-call engineers** | PIM-elevated access for incident response (time-limited, audit-logged) |

---

## 4. Data Platform Design

### 4.1 SQL Federation Architecture on Azure

```
┌─────────────────────────────────────────────────────────────┐
│                         AKS Cluster                         │
│                                                             │
│   ┌─────────────┐     ┌──────────────────────────────────┐  │
│   │  Metabase   │────▶│   Trino Coordinator              │  │
│   │  (BI UI)    │     │   ┌────────┐ ┌────────┐         │  │
│   └─────────────┘     │   │Worker 1│ │Worker 2│ ...      │  │
│                       │   └───┬────┘ └───┬────┘         │  │
│                       └───────┼──────────┼──────────────┘  │
│                               │          │                  │
│   ┌───────────────────────────┼──────────┼──────────────┐  │
│   │           Trino Connectors                          │  │
│   │   ┌────────────┐  ┌──────────┐  ┌────────────────┐  │  │
│   │   │ PostgreSQL │  │  MySQL   │  │  Hive / ADLS   │  │  │
│   │   │ Connector  │  │Connector │  │  Connector     │  │  │
│   │   └─────┬──────┘  └────┬─────┘  └───────┬────────┘  │  │
│   └─────────┼──────────────┼────────────────┼───────────┘  │
│             │ PE           │ PE             │ PE            │
└─────────────┼──────────────┼────────────────┼──────────────┘
              ▼              ▼                ▼
   ┌──────────────┐  ┌──────────┐   ┌──────────────────┐
   │ Azure DB for │  │Azure DB  │   │  ADLS Gen2       │
   │ PostgreSQL   │  │for MySQL │   │  (Data Lake)     │
   │ (Logistics)  │  │(Warehouse│   │                  │
   └──────────────┘  └──────────┘   └────────┬─────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │ Hive Metastore    │
                                    │ (on AKS or Azure  │
                                    │  DB for MySQL)    │
                                    └───────────────────┘
```

### 4.2 Connector Configuration

| Connector | Azure Target | Connection Method |
|-----------|-------------|-------------------|
| **PostgreSQL** | Azure Database for PostgreSQL Flexible Server | JDBC via Private Endpoint. Credentials from Key Vault. SSL enforced. |
| **MySQL** | Azure Database for MySQL Flexible Server | JDBC via Private Endpoint. Credentials from Key Vault. SSL enforced. |
| **Hive** | ADLS Gen2 via `abfs://` protocol | Azure ABFS connector. Authentication via Managed Identity (preferred) or storage account key from Key Vault. Metastore backed by Azure DB for MySQL. |

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

| Aspect | Detail |
|--------|--------|
| **Deployment** | Hive Metastore runs as a pod in AKS (same image as local) |
| **Backend DB** | Azure Database for MySQL Flexible Server (Burstable tier) — replaces the local `metastore-db` container |
| **Storage** | Points to ADLS Gen2 via `abfs://datalake@datawavestorage.dfs.core.windows.net/` |
| **Alternative** | Azure HDInsight Metastore or AWS Glue-equivalent (Azure Purview) for managed catalog — evaluate if operational overhead of self-hosted Hive Metastore grows |

### 4.4 Future Data Source Extensibility

Trino's plugin architecture makes adding new data sources straightforward:

| Future Source | Trino Connector | Azure Service |
|---------------|----------------|---------------|
| Azure Cosmos DB | `cosmosdb` connector | Cosmos DB with Private Endpoint |
| Azure Synapse Analytics | `sqlserver` connector | Synapse Dedicated SQL Pool |
| Elasticsearch / OpenSearch | `elasticsearch` connector | Azure Cognitive Search or self-hosted |
| MongoDB | `mongodb` connector | Azure Cosmos DB for MongoDB |
| Delta Lake | `delta-lake` connector | ADLS Gen2 with Delta format |
| Apache Iceberg | `iceberg` connector | ADLS Gen2 with Iceberg table format |

**Adding a new source requires:**
1. Create the Azure PaaS resource via Terraform
2. Store credentials in Key Vault
3. Add a Trino catalog `.properties` file to the Helm chart
4. Rolling restart of Trino workers (zero-downtime via Kubernetes rolling update)

---

## 5. Deployment Model

### 5.1 Environment Strategy

| Environment | Purpose | Infrastructure | Cost Optimization |
|-------------|---------|---------------|-------------------|
| **dev** | Development and experimentation | Single-node AKS, Burstable DB tiers, LRS storage | Auto-shutdown outside business hours |
| **staging** | Pre-production validation, load testing | Mirrors prod topology at smaller scale (2 workers) | Spot instances for Trino workers |
| **prod** | Production workloads | Full HA: 3+ workers, zone-redundant DBs, ZRS storage | Reserved instances for steady-state |

All three environments are deployed from the **same Terraform modules** with different `tfvars` files:

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

| Aspect | Detail |
|--------|--------|
| **Tool** | Terraform (azurerm provider) |
| **State** | Azure Storage Account with blob locking. Separate state file per environment. |
| **Modules** | Reusable modules for each Azure resource group (AKS, databases, networking, etc.) |
| **Validation** | `terraform plan` on every PR. `terraform apply` on merge to `main`. |
| **Drift detection** | Scheduled `terraform plan` runs (nightly) to detect manual changes |
| **Policy** | Azure Policy assignments via Terraform to enforce tagging, allowed SKUs, and encryption requirements |

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

| Role | Responsibility |
|------|---------------|
| **Platform Team (2–3 engineers)** | AKS cluster, Terraform modules, CI/CD pipelines, monitoring, security baseline, Trino upgrades |
| **Data Engineering Team** | Trino catalog configuration, query optimization, new data source onboarding, Metabase dashboards |
| **On-Call Rotation** | Shared between Platform and Data Engineering. Pager for Sev 0/1 alerts. Weekly handoff. |
| **Security Review** | Platform team runs quarterly security audits. Dependency scanning in CI. Azure Defender for Cloud. |

---

## 6. Architecture Diagram

### 6.1 Full Azure Architecture

```
                          ┌─────────────────────┐
                          │     Internet         │
                          └──────────┬──────────┘
                                     │ HTTPS (443)
                          ┌──────────▼──────────┐
                          │  Azure Application   │
                          │  Gateway + WAF v2    │
                          │  (TLS termination)   │
                          └──────────┬──────────┘
                                     │
                    ┌────────────────┬┴───────────────────┐
                    │                │                     │
          ┌─────────▼──────┐ ┌──────▼────────┐ ┌─────────▼────────┐
          │  OAuth2 Proxy  │ │   Metabase    │ │  Grafana         │
          │  (SSO gateway) │ │   (BI tool)   │ │  (Dashboards)    │
          │  /trino/*      │ │   /metabase   │ │  /grafana        │
          └───────┬────────┘ └──────┬────────┘ └──────────────────┘
                  │                  │
          ┌───────▼──────────────────▼─────────────────────────────┐
          │                 AKS Cluster                             │
          │      ┌──────────────────────────────────────┐          │
          │      │ Namespace: trino                     │          │
          │      │  ┌───────────────────┐               │          │
          │      │  │ Trino Coordinator │               │          │
          │      │  └────────┬──────────┘               │          │
          │      │     ┌─────┼─────┐                    │          │
          │      │  ┌──▼──┐┌─▼───┐┌▼────┐              │          │
          │      │  │ W1  ││ W2  ││ W3  │  ← HPA       │          │
          │      │  │AZ-1 ││AZ-2 ││AZ-3 │              │          │
          │      │  └──┬──┘└──┬──┘└──┬──┘              │          │
          │      └─────┼──────┼──────┼─────────────────┘          │
          │            │      │      │                             │
          │      ┌─────┼──────┼──────┼─────────────────┐          │
          │      │ Namespace: metastore                 │          │
          │      │  ┌──▼──────▼──────▼──┐               │          │
          │      │  │  Hive Metastore   │               │          │
          │      │  └────────┬──────────┘               │          │
          │      └───────────┼──────────────────────────┘          │
          └──────────────────┼─────────────────────────────────────┘
                             │ Private Endpoints
          ┌──────────────────┼─────────────────────────────────────┐
          │                  │       Azure PaaS Layer               │
          │    ┌─────────────┼──────────┬────────────────┐         │
          │    │             │          │                 │         │
          │ ┌──▼───────────┐│┌─────────▼──────┐┌────────▼──────┐  │
          │ │  Azure DB    │││  Azure DB      ││ ADLS Gen2     │  │
          │ │  PostgreSQL  │││  MySQL         ││ (Data Lake)   │  │
          │ │  (Logistics) │││  (Warehouse)   ││               │  │
          │ │  Zone-HA     │││  Zone-HA       ││ ZRS           │  │
          │ └──────────────┘│└────────────────┘└───────────────┘  │
          │                 │                                      │
          │ ┌───────────────▼───┐  ┌──────────────┐               │
          │ │  Azure DB MySQL   │  │  Azure Key   │               │
          │ │  (Metastore DB)   │  │  Vault       │               │
          │ │  Burstable        │  │  (Secrets)   │               │
          │ └───────────────────┘  └──────────────┘               │
          └────────────────────────────────────────────────────────┘

          ┌────────────────────────────────────────────────────────┐
          │                   Operations Layer                     │
          │  ┌───────────────┐ ┌──────────┐ ┌──────────────────┐  │
          │  │ Azure Monitor │ │   Log    │ │  Azure Managed   │  │
          │  │ + Container   │ │Analytics │ │  Grafana         │  │
          │  │   Insights    │ │Workspace │ │                  │  │
          │  └───────────────┘ └──────────┘ └──────────────────┘  │
          │  ┌───────────────┐ ┌──────────────────┐               │
          │  │ Azure Alerts  │ │  Microsoft       │               │
          │  │ + Action      │ │  Entra ID        │               │
          │  │   Groups      │ │  (SSO / RBAC)    │               │
          │  └───────────────┘ └──────────────────┘               │
          └────────────────────────────────────────────────────────┘

          ┌────────────────────────────────────────────────────────┐
          │                   CI/CD Layer                           │
          │  ┌──────────────┐ ┌──────────┐ ┌──────────────────┐   │
          │  │ GitHub       │ │ Azure    │ │  Terraform       │   │
          │  │ Actions      │ │ Container│ │  State (Blob)    │   │
          │  │ (Pipelines)  │ │ Registry │ │                  │   │
          │  └──────────────┘ └──────────┘ └──────────────────┘   │
          └────────────────────────────────────────────────────────┘
```

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

| # | Local Component | Azure Component | Migration Notes |
|---|----------------|-----------------|-----------------|
| 1 | Docker Compose | AKS (Kubernetes) | Compose services → Helm charts. Health checks → liveness/readiness probes. |
| 2 | Trino (container) | Trino on AKS (Helm chart) | Same Trino image. Coordinator + workers as separate deployments. |
| 3 | PostgreSQL (container) | Azure DB for PostgreSQL Flexible Server | `pg_dump` + `pg_restore` for data migration. Update JDBC URL in catalog config. |
| 4 | MySQL (container) | Azure DB for MySQL Flexible Server | `mysqldump` + `mysql` import. Update JDBC URL. |
| 5 | MinIO (container) | ADLS Gen2 | Migrate Parquet files via `azcopy`. Switch Trino connector from `hive.s3.*` to `hive.azure.abfs.*`. |
| 6 | Hive Metastore (container) | Hive Metastore on AKS | Same image, backend DB moves to Azure DB for MySQL. Storage URIs change from `s3a://` to `abfs://`. |
| 7 | Metastore DB (container) | Azure DB for MySQL (Burstable) | Schema auto-created by Hive Metastore on first start. |
| 8 | Metabase (container) | Metabase on AKS | Same image. Internal PostgreSQL for metadata → can use Azure DB for PostgreSQL. |
| 9 | Keycloak (container) | Microsoft Entra ID | No self-hosted IdP needed. Register OAuth2 app in Entra ID. |
| 10 | OAuth2 Proxy (container) | OAuth2 Proxy on AKS | Same image. Change `--provider` from `keycloak-oidc` to `azure`. Configure Entra ID tenant/client IDs. |
| 11 | Docker networks (frontend/datasources) | VNet subnets + NSGs + Kubernetes Network Policies | Same isolation model: Metabase → Trino only. Trino → data sources. |

---

## Trade-offs and Future Improvements

### Trade-offs

| Decision | Trade-off |
|----------|-----------|
| **AKS over Container Apps** | More operational overhead (cluster upgrades, node management) but provides fine-grained control for Trino's worker topology and memory requirements |
| **Self-hosted Hive Metastore** | Operational burden vs. no Azure-native equivalent (unlike AWS Glue). Could evaluate Azure Purview or Unity Catalog in future. |
| **Terraform over Bicep** | Slightly less Azure-native integration, but better multi-cloud portability and wider team familiarity |
| **Single region** | Lower cost and complexity, but full region failure requires manual DR activation. Multi-region active-active would eliminate this at 2× cost. |
| **Zone-redundant HA (databases)** | ~2× cost of non-HA tiers, but eliminates single-AZ failure risk for critical data stores |
| **Managed Identity over service principals** | No credential rotation needed, but slightly more complex initial setup with workload identity federation |

### Future Improvements

| Improvement | Benefit | Effort |
|-------------|---------|--------|
| **Apache Iceberg table format** | ACID transactions, time travel, schema evolution for the data lake | Medium |
| **Azure Purview integration** | Unified data catalog, lineage tracking, data governance | Medium |
| **Query result caching** | Redis or Azure Cache for Redis to cache frequent Trino queries | Low |
| **Multi-region active-active** | Zero-downtime DR, lower latency for global users | High |
| **Trino fault-tolerant execution** | Retry failed query tasks without restarting the full query | Low (config change) |
| **Cost allocation tags** | Tag all resources by team/project for chargeback reporting | Low |
| **Azure Confidential Computing** | Encrypt data in use for highly sensitive workloads | High |
| **Service mesh (Istio)** | mTLS between all pods, traffic observability, circuit breaking | Medium |

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
