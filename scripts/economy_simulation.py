import math
import numpy as np
import pandas as pd
from pathlib import Path

OUT_DIR = Path("outputs")
OUT_DIR.mkdir(parents=True, exist_ok=True)

RNG_SEED = 42
N_SIM_USERS = 200_000

# --- Baselines (AB control) ---
CONTROL_USERS = 457
CONTROL_IAP_REVENUE = 284.50
CONTROL_ADS_REVENUE = 28.658343

BASE_IAP_ARPU = CONTROL_IAP_REVENUE / CONTROL_USERS
BASE_ADS_ARPU = CONTROL_ADS_REVENUE / CONTROL_USERS
BASE_ARPU_WEEK = BASE_IAP_ARPU + BASE_ADS_ARPU

BASE_COMPLETION = 0.4846
BASE_WEEKLY_SESSIONS = 3.969365
BASE_AD_IMPRESSIONS_PER_SESSION = 6.42 / BASE_WEEKLY_SESSIONS
BASE_PAYER_RATE_WEEK = 34 / CONTROL_USERS

# A/B deltas at +20% reward
AB_LIFT_COMPLETION = +0.0506
AB_LIFT_SESSIONS = -0.1418
AB_LIFT_IAP_REV = -0.1966

# Model assumptions
BASE_LEVELS_PER_SESSION = 1.05
BETA_NEED = 1.25

# Guardrails
GUARD_MIN_COMPLETION_LIFT = 2.0
GUARD_MIN_ARPU_LIFT = -2.0
GUARD_MIN_SESSIONS_LIFT = -3.0

# Sink realism knobs
SINK_NEED_ELASTICITY = 0.25     # was 0.65 (too strong)
SINK_FRICTION_SESS = 0.18       # sink increases friction -> sessions down a bit

# Reward sessions effect softening
REWARD_SESS_SOFTEN = 0.75       # <1 => less aggressive sessions drop


def logistic(x):
    return 1 / (1 + np.exp(-x))


def calibrate_beta0(target_rate, need):
    lo, hi = -20.0, 20.0
    for _ in range(60):
        mid = (lo + hi) / 2
        p = logistic(mid + BETA_NEED * need).mean()
        if p < target_rate:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def simulate_week(rng, reward_multiplier, sink_multiplier=1.0,
                  targeted=False, target_share=0.35,
                  reward_mult_target=1.20, reward_mult_non=1.00):
    n = N_SIM_USERS

    # reward per user
    if targeted:
        is_target = rng.random(n) < target_share
        reward = np.where(is_target, reward_mult_target, reward_mult_non)
    else:
        reward = np.full(n, reward_multiplier)

    # completion uplift (calibrated at 1.20)
    a = AB_LIFT_COMPLETION / math.log(1.20)
    p_complete = BASE_COMPLETION * (1 + a * np.log(reward))
    p_complete = np.clip(p_complete, 0.05, 0.95)

    # sessions impact from reward (softened)
    b = (AB_LIFT_SESSIONS * REWARD_SESS_SOFTEN) / math.log(1.20)
    lambda_sessions = BASE_WEEKLY_SESSIONS * (1 + b * np.log(reward))

    # add sink friction: sink>1 reduces sessions slightly
    lambda_sessions *= (1 - SINK_FRICTION_SESS * (sink_multiplier - 1.0))
    lambda_sessions = np.clip(lambda_sessions, 0.3, 20.0)

    sessions = rng.poisson(lambda_sessions)
    levels_per_session = np.clip(rng.poisson(BASE_LEVELS_PER_SESSION, n), 1, 10)

    level_starts = sessions * levels_per_session
    level_completes = rng.binomial(level_starts, p_complete)

    # ads
    ads_impressions = rng.poisson(np.maximum(sessions * BASE_AD_IMPRESSIONS_PER_SESSION, 0))
    rev_per_imp = BASE_ADS_ARPU / (BASE_WEEKLY_SESSIONS * BASE_AD_IMPRESSIONS_PER_SESSION)
    ads_revenue = ads_impressions * rev_per_imp

    # need proxy
    need = (1 - (level_completes / np.maximum(level_starts, 1))) * level_starts
    need = np.nan_to_num(need)

    # sink increases effective need a bit (NOT huge)
    need_effective = need * (1 + SINK_NEED_ELASTICITY * (sink_multiplier - 1.0))
    need_effective = np.clip(need_effective, 0.0, None)

    beta0 = calibrate_beta0(BASE_PAYER_RATE_WEEK, need)  # calibrated at baseline
    p_payer = logistic(beta0 + BETA_NEED * need_effective)

    # spend baseline (NO sink spend boost!)
    base_spend_per_payer = BASE_IAP_ARPU / max(BASE_PAYER_RATE_WEEK, 1e-6)

    # reward erosion on spend (calibrated to IAP rev drop at 1.20)
    c = AB_LIFT_IAP_REV / math.log(1.20)
    spend_erosion = np.clip(1 + c * np.log(reward), 0.2, 2.0)

    is_payer = rng.random(n) < p_payer
    spend = np.zeros(n)
    spend[is_payer] = rng.gamma(shape=2.0, scale=base_spend_per_payer / 2.0, size=is_payer.sum()) * spend_erosion[is_payer]

    total_starts = level_starts.sum()
    total_completes = level_completes.sum()

    return {
        "reward_multiplier_avg": float(reward.mean()),
        "sink_multiplier": float(sink_multiplier),
        "sessions_per_user": float(sessions.mean()),
        "completion_rate": float(total_completes / max(total_starts, 1)),
        "ads_arpu": float(ads_revenue.sum() / n),
        "iap_arpu": float(spend.sum() / n),
        "total_arpu": float((ads_revenue.sum() + spend.sum()) / n),
        "payer_rate": float(is_payer.mean()),
        "scenario": None,
    }


def add_lifts(df):
    base = df[df["scenario"] == "global_1.00_sink_1.00"].iloc[0]

    def lift(col):
        return 100.0 * (df[col] - base[col]) / (base[col] if base[col] != 0 else np.nan)

    df["lift_completion_pct"] = lift("completion_rate")
    df["lift_sessions_pct"] = lift("sessions_per_user")
    df["lift_total_arpu_pct"] = lift("total_arpu")

    df["ship_candidate"] = (
        (df["lift_completion_pct"] >= GUARD_MIN_COMPLETION_LIFT) &
        (df["lift_total_arpu_pct"] >= GUARD_MIN_ARPU_LIFT) &
        (df["lift_sessions_pct"] >= GUARD_MIN_SESSIONS_LIFT)
    )
    return df


def main():
    rng = np.random.default_rng(RNG_SEED)

    reward_grid = [1.00, 1.05, 1.10, 1.15, 1.20]
    sink_grid = [1.00, 1.02, 1.04, 1.06, 1.08]

    rows = []

    # baseline
    k = simulate_week(rng, 1.00, 1.00)
    k["scenario"] = "global_1.00_sink_1.00"
    rows.append(k)

    # global grid
    for r in reward_grid:
        for s in sink_grid:
            if r == 1.00 and s == 1.00:
                continue
            k = simulate_week(rng, r, s, targeted=False)
            k["scenario"] = f"global_{r:.2f}_sink_{s:.2f}"
            rows.append(k)

    # targeted grid (smaller reward on a segment)
    targeted_setups = [
        {"target_share": 0.35, "reward_mult_target": 1.20, "reward_mult_non": 1.00},
        {"target_share": 0.35, "reward_mult_target": 1.15, "reward_mult_non": 1.00},
        {"target_share": 0.25, "reward_mult_target": 1.20, "reward_mult_non": 1.00},
    ]
    for s in sink_grid:
        for t in targeted_setups:
            k = simulate_week(
                rng, 1.00, s,
                targeted=True,
                target_share=t["target_share"],
                reward_mult_target=t["reward_mult_target"],
                reward_mult_non=t["reward_mult_non"]
            )
            k["scenario"] = f"targeted_share{t['target_share']:.2f}_t{t['reward_mult_target']:.2f}_sink_{s:.2f}"
            rows.append(k)

    df = pd.DataFrame(rows)
    df = add_lifts(df)

    out_csv = OUT_DIR / "economy_simulation_sensitivity_v3_realistic_sink.csv"
    df.to_csv(out_csv, index=False)

    best = df.sort_values(
        ["ship_candidate", "lift_total_arpu_pct", "lift_completion_pct"],
        ascending=[False, False, False]
    ).head(15)

    print("\n=== TOP 15 SCENARIOS (ship_candidate, ARPU lift, completion lift) ===")
    print(best[[
        "scenario", "reward_multiplier_avg", "sink_multiplier",
        "completion_rate", "sessions_per_user", "total_arpu",
        "lift_completion_pct", "lift_sessions_pct", "lift_total_arpu_pct",
        "ship_candidate"
    ]].round(4).to_string(index=False))

    ships = df[df["ship_candidate"]].sort_values("lift_total_arpu_pct", ascending=False)
    print(f"\nShip candidates found: {len(ships)}")
    if len(ships) > 0:
        print(ships[[
            "scenario", "lift_completion_pct", "lift_sessions_pct", "lift_total_arpu_pct"
        ]].round(4).head(20).to_string(index=False))

    print(f"\nSaved: {out_csv}")


if __name__ == "__main__":
    main()
