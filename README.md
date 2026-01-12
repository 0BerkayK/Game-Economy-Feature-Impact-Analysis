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
- Weekly Performance & Anomaly Detection
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








