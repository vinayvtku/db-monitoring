# Architecture Overview

## High Level Architecture

Assets
→ Service Bus
→ Collector Workers
→ Event Hub
→ Ingestion Workers
→ PostgreSQL Flexible Server
→ Grafana

AI Layer

Incidents
→ Investigation Engine
→ AI Context
→ Azure OpenAI

Health Scorecard Layer

Collected Metrics + Drift Signals
→ Scoring Engine
→ PostgreSQL (score + deductions stored per database)
→ Grafana (score displayed on database view, drill-down on click)

AI Query Layer

User Prompt / Scheduled Digest Trigger
→ AI Context Builder (health scores, incidents, drift signals, anomalies)
→ Azure OpenAI
→ Natural Language Response (Grafana UI or Email Digest)

## Technology Stack

- Azure PostgreSQL Flexible Server
- Grafana
- Azure Container Apps
- Service Bus
- Event Hub
- Azure Key Vault
- Azure OpenAI
- pgvector
- SMTP / Email Service (daily digest delivery)
