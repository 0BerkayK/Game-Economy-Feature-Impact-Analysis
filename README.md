# Game-Economy-Feature-Impact-Analysis
A data-driven approach to economy balancing and feature impact forecasting in a F2P mobile game. This project is a full end-to-end game analytics & economy case study designed to mirror the responsibilities of a Data Analyst / Game Economist role at a free-to-play mobile game studio.


The goal is to:

-Validate data quality

-Analyze player funnels and weekly KPIs

-Evaluate an A/B test impacting progression and monetization

-Run economy simulations (Monte Carlo + sensitivity analysis)

-Make a clear ship / no-ship decision based on guardrails

Final outcome:
A flat reward increase improves progression but introduces unacceptable monetization and engagement trade-offs.
Decision: DO NOT SHIP the change in its current form.

``` bash

/
│
├── data/
│   ├── users.csv
│   ├── events.csv
│   ├── purchases.csv
│   ├── ads_events.csv
│   └── ab_assignments.csv
│
├── sql/
│   ├── 01_event_validation.sql
│   ├── 02_funnel_analysis.sql
│   ├── 03_kpi_weekly.sql
│   └── 04_ab_test_evaluation.sql
│   
│
├── scripts/
│   ├── run_sql.py
│   ├── generate_synthetic_data.py
│   └── economy_simulation.py
│
├── outputs/
│   ├── economy_simulation_sensitivity.csv
│   ├── economy_simulation_sensitivity_v2_sink.csv
│   └── economy_simulation_sensitivity_v3_realistic_sink.csv
│
└── README.md

```

- Data Validation & Tracking Debug
- Core KPI Framework(Product & Economy)
- Weekly Performance 
- A/B Test Analysis
- Economy Simulation
- Ads Monetization Trade-off Analysis
- Final Recommendation

| Field        | KPI                     |
| ------------ | ----------------------- |
| Engagement   | D1 / D7 Retention       |
| Monetization | ARPDAU, ARPPU           |
| Economy      | Currency Earn vs Spend  |
| Ads          | Ads per DAU, Ads ARPDAU |


📁 Data Files (/data)
users.csv

User-level metadata

Used to define install cohorts and retention windows

events.csv

Core gameplay telemetry

Key events:

session_start, session_end

level_start, level_complete

Backbone for funnel, retention, and engagement analysis

purchases.csv

In-app purchase transactions

Used for:

ARPU

IAP revenue

Payer rate

ads_events.csv

Ad impression-level data

Used for:

Ads ARPU

Ads vs engagement trade-off

ab_assignments.csv

Experiment assignment table

Fields:

user_id

experiment_name

variant

assign_ts


🧩 SQL Analysis (/sql)
01_event_validation.sql

Purpose: Data quality & tracking validation

Checks:

Null or missing critical fields

Timestamp ranges

Broken or impossible event sequences

Why this matters:

Any downstream KPI or A/B result is meaningless without trusted telemetry.

02_funnel_analysis.sql

Purpose: Progression funnel diagnostics

Analyzes:

Install → first level start

Level start → level complete

Identifies anomalies such as:

Level starts without completion

Time ordering issues

Output includes:

Debug samples (DEBUG_LEVEL_START_NO_COMPLETE)

Funnel drop-off ratios

03_kpi_weekly.sql

Purpose: Weekly game health monitoring

KPIs:

Weekly Active Users

Sessions per user

Avg session duration

Level completion rate

Ads & IAP revenue

ARPWAU

D1 / D7 retention

Why weekly:

Weekly aggregation smooths daily noise and aligns with product review cycles.

04_ab_test_evaluation.sql

Purpose: A/B test evaluation (reward +20%)

Primary KPI:

Level completion rate

Secondary KPIs:

Sessions per user

ARPU (IAP + Ads)

Ads impressions

D1 retention (guardrail)

Key result:

Completion +5.06%

ARPU -23.66%

Sessions/user -14.18%

📊 Outputs (/outputs)
economy_simulation_sensitivity.csv

Initial reward-only sensitivity

economy_simulation_sensitivity_v2_sink.csv

Reward + sink combinations (overpowered sink)

economy_simulation_sensitivity_v3_realistic_sink.csv

Realistic sink modeling

Final, production-grade decision table


## Final Decision & Recommendation
Decision

❌ Do NOT ship reward-based progression tuning as-is.

Reason

Flat reward increases reduce friction too broadly

Sessions drop → ads revenue drops

Need collapses → IAP demand drops

Sink balancing cannot fully recover losses

Recommendation

Decouple rewards from economy

Test situational, non-currency rewards

Fail recovery

Temporary power-ups

Checkpoints

Test economy levers (sinks/pricing) independently


