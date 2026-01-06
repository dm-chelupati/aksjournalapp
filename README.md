# AKS Journal App

A simple journal application running on AKS with Redis, demonstrating Azure SRE Agent for automated alert triage and Jira ticket creation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Azure Cloud                                      │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        Resource Group                                  │   │
│  │                                                                        │   │
│  │  ┌─────────────────┐     ┌─────────────────┐     ┌────────────────┐  │   │
│  │  │   AKS Cluster   │     │  Azure Cache    │     │  Log Analytics │  │   │
│  │  │                 │────▶│   for Redis     │     │   Workspace    │  │   │
│  │  │  ┌───────────┐  │     │                 │     │                │  │   │
│  │  │  │  Journal  │  │     │  - Entry cache  │     │ - Container    │  │   │
│  │  │  │   App     │  │     │  - Session data │     │   Insights     │  │   │
│  │  │  │  Pods x3  │  │     │  - TLS 1.2      │     │ - App logs     │  │   │
│  │  │  └───────────┘  │     └─────────────────┘     │ - Alerts       │  │   │
│  │  │                 │              │               └───────┬────────┘  │   │
│  │  │  - Auto-scaling │              │                       │           │   │
│  │  │  - Health probes│              │                       │           │   │
│  │  └────────┬────────┘              │                       │           │   │
│  │           │                       │                       │           │   │
│  │           └───────────────────────┴───────────────────────┘           │   │
│  │                                   │                                    │   │
│  │                          Diagnostic Logs                               │   │
│  │                                   │                                    │   │
│  │                    ┌──────────────▼──────────────┐                    │   │
│  │                    │       Azure Monitor          │                    │   │
│  │                    │                              │                    │   │
│  │                    │  ┌────────────────────────┐ │                    │   │
│  │                    │  │     Alert Rules        │ │                    │   │
│  │                    │  │  - High CPU/Memory     │ │                    │   │
│  │                    │  │  - Pod Restarts        │ │                    │   │
│  │                    │  │  - Container Errors    │ │                    │   │
│  │                    │  │  - OOMKilled           │ │                    │   │
│  │                    │  └────────────┬───────────┘ │                    │   │
│  │                    └───────────────┼─────────────┘                    │   │
│  │                                    │                                   │   │
│  │                    ┌───────────────▼───────────────┐                  │   │
│  │                    │      Azure SRE Agent          │                  │   │
│  │                    │                               │                  │   │
│  │                    │  - Queries Log Analytics      │                  │   │
│  │                    │  - Creates Jira tickets       │                  │   │
│  │                    └───────────────────────────────┘                  │   │
│  │                                                                        │   │
│  └────────────────────────────────────────────────────────────────────────┘   │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (v2.50+)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Docker](https://www.docker.com/products/docker-desktop)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Azure subscription

## Quick Start

### 1. Deploy to Azure

```bash
azd init
azd up
```

### 2. Access the App

```bash
kubectl get svc -n aks-journal-app
curl http://<EXTERNAL-IP>/health
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/ready` | GET | Readiness probe |
| `/live` | GET | Liveness probe |
| `/api/journals/:userId` | GET | List user's journal entries |
| `/api/journals/:userId` | POST | Create new entry |
| `/api/journals/:userId/:entryId` | GET | Get specific entry |
| `/api/journals/:userId/:entryId` | PUT | Update entry |
| `/api/journals/:userId/:entryId` | DELETE | Delete entry |
| `/api/simulate/error` | GET | Trigger test error |
| `/api/simulate/memory` | GET | Simulate memory pressure |

## Alert Rules

- High CPU (> 80%)
- High Memory (> 80%)
- Pod Restarts
- Container Errors
- OOMKilled Events

## Testing Alerts

### Simulating Redis Credential Expiry (Realistic Failure Scenario)

This simulates a common production issue: **Redis access keys were rotated in Azure, but the application wasn't updated with the new credentials.**

**Step 1: Inject wrong Redis password**
```bash
kubectl create secret generic redis-secret \
  --from-literal=REDIS_PASSWORD="WRONG_EXPIRED_KEY_12345" \
  -n aks-journal-app \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Step 2: Delete pods to pick up the new (wrong) secret**
```bash
kubectl delete pods -n aks-journal-app -l app=aks-journal
```

**Step 3: Test the app - should show degraded state**
```bash
# Health check shows Redis disconnected
curl http://<EXTERNAL-IP>/health
# Returns: {"status":"degraded","checks":{"redis":"disconnected"}}

# API operations fail
curl http://<EXTERNAL-IP>/api/journals/john
# Returns: {"error":"Failed to retrieve journal entries"}
```

**Step 4: Generate load to trigger alerts**
```bash
# Run in a loop to generate errors for alerting
while true; do
  curl -s http://<EXTERNAL-IP>/api/journals/john
  curl -s -X POST http://<EXTERNAL-IP>/api/journals/john \
    -H "Content-Type: application/json" \
    -d '{"title": "Test", "content": "This will fail"}'
  sleep 2
done
```

**What happens:**
- Pods stay running (app handles Redis failures gracefully)
- Health endpoint returns `degraded` status
- All journal read/write operations fail with 500 errors
- Error logs are sent to Log Analytics
- Azure Monitor alerts fire for container errors
- **Azure SRE Agent** can query logs, diagnose the issue, and create a Jira ticket

**To restore (fix the issue):**
```bash
# Get the correct Redis key
REDIS_KEY=$(az redis list-keys --resource-group rg-aks-journal \
  --name <redis-name> --query "primaryKey" -o tsv)

# Update the secret with correct password
kubectl create secret generic redis-secret \
  --from-literal=REDIS_PASSWORD="$REDIS_KEY" \
  -n aks-journal-app \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods
kubectl rollout restart deployment/aks-journal -n aks-journal-app
```

### Other Test Scenarios

```bash
# Simulate application errors
curl http://<EXTERNAL-IP>/api/simulate/error

# Simulate memory pressure
curl "http://<EXTERNAL-IP>/api/simulate/memory?size=100"
```

## Project Structure

```
aks-alert-app/
├── azure.yaml              # azd config
├── infra/                  # Bicep templates
├── src/api/                # Journal app
├── k8s/                    # Kubernetes manifests
└── docs/blog-post.md       # SRE Agent blog
```

## Cleanup

```bash
azd down
```
