# Game-Economy-Feature-Impact-Analysis
A data-driven approach to economy balancing and feature impact forecasting in a F2P mobile game

``` bash

joker_games_case_study/
│
├── data/
│   ├── events.csv
│   ├── users.csv
│   ├── purchases.csv
│   ├── ads_events.csv
│   └── ab_assignments.csv
│
├── sql/
│   ├── 01_event_validation.sql ## veri kalitesi + event completeness + duplicate + timestamp tutarlılık
│   ├── 02_funnel_analysis.sql ## install → session → level_start→ level_complete funnel, kırık noktalar
│   ├── 03_kpi_weekly.sql ## purchase’ların session/event ile ilişki tutarsızlıkları
│
├── notebooks/
│   ├── 01_data_validation.ipynb
│   ├── 02_kpi_analysis.ipynb
│   ├── 03_ab_test_analysis.ipynb
│   ├── 04_economy_simulation.ipynb
│
├── dashboards/
│   └── weekly_game_health.pbix (or tableau/looker)
│
├── report/
│   └── joker_games_case_study.pdf
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





Weekly Health Summary (Week of 2025-12-08)

Weekly active users increased to 331 (+14% WoW), while sessions per user stayed stable at ~3.64 and avg session duration held at 14.75 minutes, indicating engagement quality remained consistent.
Total revenue peaked at $262.3, driven primarily by IAP ($243.6). Ads revenue also improved to $18.7 with rising impressions.
Core economy health remained stable: level completion rate was 0.506, within our guardrail band (0.49–0.52).
D1 retention averaged 0.47 and D7 was 0.16; no immediate retention regression observed.
Next actions: validate IAP uplift drivers (SKU mix, offer exposure), keep economy guardrails, and monitor for monetization/retention trade-offs.

Executive Summary

The +20% reward variant improved level completion by +5.1%, confirming a positive progression impact.
However, it caused a significant monetization and engagement regression: ARPU -23.7%, Total Revenue -18.7%, and Sessions/User -14.2%, while D1 retention remained flat.
Conclusion: Do not ship the change as-is.
Next step is a targeted reward strategy (early levels / low-skill segments) combined with economy sinks, followed by a new experiment to preserve completion gains without sacrificing revenue.


Economy Simulation (Monte Carlo + Sensitivity)

I simulated weekly player behavior under different reward multipliers to quantify progression vs monetization trade-offs observed in the A/B test.
A global +20% reward scenario reproduced the experiment outcome: completion increased by ~+5.1%, while sessions per user dropped ~-14% and total ARPU declined ~-18.7%.
A targeted rollout (35% of users at +20%) improved completion modestly (+1.6%) but still decreased ARPU (-4.5%) and sessions (-4.7%), failing predefined guardrails.
Conclusion: reward buffs must be paired with sink balancing and/or applied selectively (e.g., early levels, fail-recovery, low-skill segments) to preserve monetization.

