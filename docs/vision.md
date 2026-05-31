# DB Monitoring Platform Vision

## Mission

Build a modern database observability platform that replaces existing database monitoring capabilities provided by DPA and PRTG while introducing intelligent alerting, incident correlation, forecasting, security drift detection, configuration drift detection, and AI-assisted operational insights.

## Core Principles

- Everything is an Asset
- Everything is Policy Driven
- Events → Alerts → Incidents
- AI Never Touches Assets
- Zero Trust AI

## Key Features

### Database Health Scorecard

Every database is assigned a composite health score out of 10. The default score is 10/10. Signals across security, performance, and growth automatically deduct from the score when thresholds are breached.

In Grafana, users click on a database to see its current score. Clicking the score opens a drill-down view showing each deduction with the contributing metric inline — for example:

- `-1 Local account with elevated rights — sa account enabled`
- `-1 High plan changes — 847 recompiles in last 24h`
- `-1 High growth rate — 42 GB added in last 7 days`

The scoring signal library starts with the MVP signals and grows continuously as new rules are added.

**MVP Scoring Signals:**
- Local database account with elevated rights (-1)
- High plan changes / recompile rate (-1)
- High database growth rate (-1)

### AI Natural Language Query

Users can ask the platform plain-English questions such as:

> *"What is going on in my database world and what should my priority be today?"*

The AI returns a prioritized, plain-English briefing across all databases — summarizing health scores, active incidents, drift detections, and top anomalies. This is available as an interactive prompt in Grafana and is the engine behind the daily digest.

### Daily Digest

Every morning the platform automatically runs the AI briefing and delivers it as an email digest. The digest summarizes overnight activity, current health scores, top issues, and recommended priorities — giving DBAs and leadership a clear picture of the database estate without opening a dashboard.

## MVP Goals

Environment:
- Azure VM
- SQL Server Developer Edition
- Stack Overflow Database
- HammerDB workload

Demonstrate:
- Inventory
- Collection framework
- Grafana dashboards
- Database health scorecard (10/10 default, 3 scoring signals)
- Smart CPU alerting
- Security drift detection
- Configuration drift detection
- AI natural language query ("what's going on in my database world?")
- Daily digest (email)
