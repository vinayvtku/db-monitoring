---
name: azure-db-monitoring
user-invocable: true
description: "Workspace skill for shaping and iterating Azure database monitoring solutions in the db-monitoring project using Azure Monitor, Log Analytics, and cloud-native telemetry."
---

# Azure Database Monitoring Skill

## When to use
- Designing or reviewing Azure database monitoring for this project
- Defining telemetry, alerts, dashboards, and observability for Azure SQL, PostgreSQL, Cosmos DB, MySQL, or managed database services
- Generating Azure Monitor, Log Analytics, Bicep/ARM/Terraform, or workbook guidance
- Validating that monitoring covers availability, performance, errors, saturation, and cost

## What this skill does
- Clarifies monitoring goals and Azure DB service scope
- Identifies the right metrics, diagnostic settings, and log sources
- Recommends alert rules, action groups, and escalation logic
- Proposes dashboards, workbooks, and operational runbooks
- Highlights security, scalability, cost, and maintainability tradeoffs

## Microsoft-approved architecture guidance
- Aligns recommendations with Microsoft Azure Architecture Center and the Azure Well-Architected Framework.
- Uses Microsoft-approved patterns for Azure SQL, Azure Database for PostgreSQL, Cosmos DB, Azure Monitor, and Log Analytics.
- Prioritizes Azure-native observability services: Metrics, Log Analytics, Diagnostic Settings, Application Insights, Workbooks, and Alerts.
- References official guidance where applicable:
  - Azure Architecture Center: https://learn.microsoft.com/azure/architecture/
  - Azure Well-Architected Framework: reliability, performance efficiency, security, cost optimization, and operational excellence
  - Azure database monitoring patterns for SQL Database, PostgreSQL, Cosmos DB, and managed instances
- When generating output, explicitly compare the solution to Microsoft-approved patterns and note any deviations or assumptions.

## Workflow
1. Clarify the target Azure database services and deployment model.
2. Capture the monitoring objectives and SLOs.
3. Select Azure Monitor data sources: metrics, diagnostics logs, query store, and custom telemetry.
4. Define alerting strategy: metric alerts, log alerts, and suppression policies.
5. Design dashboards, workbooks, and on-call/response guidance.
6. Review the final solution for coverage, cost, and operational resilience.

## Decision points
- Azure Monitor built-in metrics vs Log Analytics query-based alerts
- Managed diagnostics settings vs custom instrumentation
- Single workspace vs per-environment Log Analytics workspaces
- Alert sensitivity, suppression intervals, and escalation targets

## Quality criteria
- Includes concrete Azure configuration examples
- Covers key alert categories: availability, latency, errors, capacity
- Mentions cost and retention tradeoffs explicitly
- Uses Azure-native services and project-specific terminology where possible
- Produces actionable implementation guidance or code snippets

## Example prompts
- "Define Azure DB monitoring for Azure SQL and PostgreSQL in this project."
- "Review my Azure database alerting strategy and identify gaps."
- "Generate Bicep snippets for diagnostics settings, metric alerts, and a Log Analytics workspace."
