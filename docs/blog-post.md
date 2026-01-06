# From AKS Alert to Jira Ticket: Automate the Boring Part with Azure SRE Agent

Most teams I talk to already have this figured out:

- Alerts configured for the issues they care about
- KQL queries they run to diagnose each alert type
- A ticket workflow to get fixes into production

The problem isn't knowing *what* to do. It's doing it at 2am. Or doing it for the 50th time this month.

You get the alert. You run the same queries. You write up the same findings. You create the ticket. The fix goes through CI/CD. Done.

The middle part - the triage and ticket creation - that's just process. And process can be automated.

## The Setup Most Teams Already Have

Here's what a typical AKS monitoring setup looks like:

**Alerts in Azure Monitor:**
- High CPU/Memory on nodes
- Pod restarts and OOMKilled events  
- Error spikes in container logs
- Failed Kubernetes jobs

**Diagnostic queries in Log Analytics:**
- `ContainerLogV2` for application errors
- `KubeEvents` for cluster-level failures
- `Perf` for resource metrics

**Fix workflow:**
- Jira ticket with diagnosis and remediation steps
- Dev team picks it up
- PR → merge → deploy

The alert fires. Someone triages. Ticket gets created. Fix ships.

SRE Agent automates the triage-to-ticket part. Your team still owns the fix.

## How It Works

When an alert fires, SRE Agent:

1. Receives the alert context (which resource, what triggered it)
2. Runs your diagnostic queries against Log Analytics
3. Summarizes findings and identifies likely cause
4. Creates a Jira ticket with everything the dev team needs

No context switching. No manual query running. The ticket lands in your backlog ready for action.

## Setting It Up

### Step 1: Create the SRE Agent

In Azure Portal, create a new SRE Agent. Pick a name, done. No infrastructure to manage.

### Step 2: Grant Reader Access

The agent needs to query your Log Analytics workspace. Assign Reader role to its managed identity:

```bash
az role assignment create \
  --assignee <agent-managed-identity-id> \
  --role "Reader" \
  --scope /subscriptions/<subscription-id>
```

### Step 3: Connect to Your Alerts

Link your Azure Monitor alerts to the SRE Agent. When alerts fire, they'll trigger the agent automatically.

For AKS, you probably already have alerts like:
- Node CPU > 80%
- Container restarts > 3 in 15 minutes
- Error count > threshold in ContainerLogV2

These become the triggers.

### Step 4: Connect Jira via MCP

MCP (Model Context Protocol) lets the agent talk to external tools. Add your Jira connection:

```json
{
  "mcpServers": {
    "jira": {
      "url": "https://your-team.atlassian.net",
      "projectKey": "OPS",
      "issueType": "Task"
    }
  }
}
```

Now the agent can create tickets in your project.

### Step 5: Create the Subagent

This is where you define what the agent does. Create a subagent with instructions like:

```
When an alert triggers:
1. Query Log Analytics for errors and events related to the alert
2. Identify the root cause based on patterns
3. Create a Jira ticket with:
   - What happened (summary)
   - Evidence from logs
   - Recommended fix
   - Affected resources
```

Assign it the tools it needs:
- `QueryLogAnalyticsByWorkspaceId` - to run KQL
- `CreateJiraIssue` (via MCP) - to create tickets

That's it. Five steps.

## Example: OOMKilled Alert → Jira Ticket

Here's what happens when a pod gets OOMKilled:

**Alert fires:** `aks-pod-restarts` threshold exceeded

**Agent runs queries:**
```kql
KubeEvents
| where Reason == "OOMKilled"
| where TimeGenerated > ago(1h)
| project TimeGenerated, Name, Namespace

Perf
| where ObjectName == "Container" and CounterName == "memoryWorkingSetBytes"
| summarize MaxMem = max(CounterValue) by ContainerName
```

**Agent creates ticket:**

> **[OPS-1234] Pod aks-journal OOMKilled - memory limit increase needed**
>
> **What happened:** Pod restarted 4 times in 30 minutes due to OOM.
>
> **Evidence:**
> - Memory peaked at 512Mi (limit: 512Mi)  
> - First kill: 02:45 UTC, Last kill: 03:12 UTC
> - Correlates with Redis connection errors
>
> **Recommended fix:** Increase memory limit to 768Mi in deployment.yaml
>
> **Resources:** aks-journal, namespace: aks-journal-app

The dev team sees the ticket in their sprint. They update the manifest. PR gets merged. CI/CD deploys the fix.

One tool. One workflow. No 2am login required.

## Why Keep It In One Place

Some teams spread incident response across multiple tools - PagerDuty for alerts, Slack for discussion, Confluence for runbooks, Jira for tracking. Context gets lost. Handoffs fail.

With this setup:
- Alert triggers the agent
- Agent does the diagnosis
- Ticket captures everything in one place
- Your existing CI/CD handles the fix

The team that owns the service owns the fix. They see a well-written ticket, not a raw alert.

## The Flow

```
Alert (Azure Monitor)
       │
       ▼
  SRE Agent
       │
       ├── Queries Log Analytics
       │
       ├── Analyzes patterns
       │
       └── Creates Jira ticket (via MCP)
              │
              ▼
       Dev team picks up
              │
              ▼
       Fix via CI/CD
```

## Try It

The sample app in this repo is a journal app running on AKS with Redis. Deploy it with:

```bash
azd up
```

Then trigger a test:
```bash
curl http://<app-ip>/api/simulate/error
```

Watch the ticket appear in Jira.

---

Your alerts already tell you something's wrong. Your queries already tell you why. SRE Agent just connects the dots and creates the ticket - so your team can fix it through the workflow they already use.
