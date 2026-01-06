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

```bash
# Simulate errors
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
