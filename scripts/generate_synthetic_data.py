from __future__ import annotations

import os
from pathlib import Path
import numpy as np
import pandas as pd


# -----------------------------
# Global config
# -----------------------------
SEED = 42
rng = np.random.default_rng(SEED)

N_USERS = 2000

START_DATE = pd.Timestamp("2025-10-01")
END_DATE = pd.Timestamp("2025-12-31")
DAYS = int((END_DATE - START_DATE).days) + 1

TEST_START = pd.Timestamp("2025-11-10")
TEST_END = pd.Timestamp("2025-12-08")
TEST_NAME = "reward_20pct_uplift"

BASE_REWARD = 100
VARIANT_REWARD_MULT = 1.20

REWARDED_ECPM = 12.0
INTER_ECPM = 6.0


def sigmoid(x):
    return 1 / (1 + np.exp(-x))


def project_root() -> Path:

    return Path(__file__).resolve().parents[1]


def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def minutes_random(n: int) -> pd.TimedeltaIndex:
    return pd.to_timedelta(rng.integers(0, 24 * 60, size=n), unit="m")


def main():
    root = project_root()
    out_dir = root / "data"
    ensure_dir(out_dir)

    print("📌 Project root:", root)
    print("📌 Output dir  :", out_dir)

    # -----------------------------
    # USERS
    # -----------------------------
    user_ids = np.arange(1, N_USERS + 1, dtype=np.int64)

    weights = np.linspace(1.0, 1.8, DAYS)
    weights = weights / weights.sum()

    install_day_offsets = rng.choice(np.arange(DAYS), size=N_USERS, p=weights)
    install_dates = START_DATE + pd.to_timedelta(install_day_offsets, unit="D")

    countries = rng.choice(["TR", "US", "DE", "BR", "GB"], size=N_USERS, p=[0.45, 0.20, 0.12, 0.13, 0.10])
    platforms = rng.choice(["iOS", "Android"], size=N_USERS, p=[0.45, 0.55])

    skill = rng.normal(0.0, 1.0, size=N_USERS)

    spender_propensity = sigmoid(
        rng.normal(-1.2, 0.9, size=N_USERS)
        + 0.25 * (countries == "US")
        + 0.10 * (platforms == "iOS")
    )

    ad_affinity = sigmoid(rng.normal(0.0, 1.0, size=N_USERS))

    users = pd.DataFrame(
        {
            "user_id": user_ids,
            "install_ts": install_dates + minutes_random(N_USERS),
            "country": countries,
            "platform": platforms,
            "trait_skill": skill,
            "trait_spender_propensity": spender_propensity,
            "trait_ad_affinity": ad_affinity,
        }
    )

    # -----------------------------
    # A/B ASSIGNMENTS (robust)
    # -----------------------------
    # eligible users installed up to TEST_END
    eligible = users["install_ts"].dt.floor("D") <= TEST_END
    ab = users.loc[eligible, ["user_id", "install_ts"]].copy()

    # exposure probability
    install_day_floor = ab["install_ts"].dt.floor("D")
    exposure_p = np.where(install_day_floor < TEST_START, 0.55, 0.85)
    exposed = rng.random(size=len(ab)) < exposure_p
    ab = ab.loc[exposed].copy().reset_index(drop=True)

    ab["experiment_name"] = TEST_NAME
    ab["variant"] = rng.choice(["control", "variant"], size=len(ab), p=[0.5, 0.5])

    # ✅ Assign timestamp: Series-safe & length-safe (NO Index arithmetic traps)
    # assign_day = max(install_day, TEST_START) at day resolution
    install_day_series = ab["install_ts"].dt.floor("D")  # Series[datetime64[ns]]
    assign_day_series = install_day_series.where(install_day_series >= TEST_START, TEST_START)

    ab["assign_ts"] = assign_day_series + minutes_random(len(ab))

    ab = ab[["user_id", "experiment_name", "variant", "assign_ts"]]

    # -----------------------------
    # EVENTS
    # -----------------------------
    install_day_floor_users = users["install_ts"].dt.floor("D")
    ab_variant_map = ab.set_index("user_id")["variant"].to_dict()
    user_variant = np.array([ab_variant_map.get(int(uid), None) for uid in user_ids], dtype=object)

    event_rows = []

    for i, uid in enumerate(user_ids):
        inst_day = install_day_floor_users.iloc[i]
        platform = users["platform"].iloc[i]
        country = users["country"].iloc[i]
        trait_skill = float(users["trait_skill"].iloc[i])
        trait_ad_affinity = float(users["trait_ad_affinity"].iloc[i])

        base = 0.55 + 0.08 * (platform == "iOS") + 0.06 * sigmoid(trait_skill)
        base += 0.05 * (country == "US")
        base = float(np.clip(base, 0.15, 0.85))

        decay = 0.18 + 0.05 * (trait_skill < -0.5)
        decay = float(np.clip(decay, 0.12, 0.28))

        v = user_variant[i]
        variant_ret_penalty = 0.02 if v == "variant" else 0.0

        horizon_days = min(30, int((END_DATE - inst_day).days) + 1)
        if horizon_days <= 0:
            continue

        t = np.arange(horizon_days)
        p_active = base * np.exp(-decay * t) - variant_ret_penalty
        p_active = np.clip(p_active, 0.0, 0.95)

        active_days = rng.random(size=horizon_days) < p_active
        if not active_days.any():
            continue

        level = int(max(1, 1 + rng.poisson(1)))
        soft_currency = int(rng.integers(50, 200))

        for d, is_active in enumerate(active_days):
            if not is_active:
                continue

            day = inst_day + pd.Timedelta(days=int(d))
            if day < START_DATE or day > END_DATE:
                continue

            n_sessions = int(np.clip(rng.poisson(1.8 + 0.2 * trait_ad_affinity), 1, 6))
            for s in range(n_sessions):
                session_start = day + pd.to_timedelta(int(rng.integers(0, 24 * 60)), unit="m")
                session_id = f"{uid}-{day.strftime('%Y%m%d')}-{s}"

                event_rows.append((session_start, int(uid), session_id, "session_start", None, None, None))

                n_levels = int(np.clip(rng.poisson(1.6 + 0.3 * sigmoid(trait_skill)), 1, 5))
                for _ in range(n_levels):
                    level_start_ts = session_start + pd.to_timedelta(int(rng.integers(1, 12)), unit="m")
                    event_rows.append((level_start_ts, int(uid), session_id, "level_start", level, None, None))

                    win_p = sigmoid(0.6 * trait_skill - 0.15 * (level / 20))
                    completed = rng.random() < win_p

                    level_end_ts = level_start_ts + pd.to_timedelta(int(rng.integers(1, 6)), unit="m")
                    if completed:
                        in_test_window = (TEST_START <= day <= TEST_END)
                        reward_mult = VARIANT_REWARD_MULT if (v == "variant" and in_test_window) else 1.0

                        reward = int(BASE_REWARD * reward_mult * (1 + 0.02 * min(level, 50)))
                        soft_currency += reward

                        event_rows.append((level_end_ts, int(uid), session_id, "level_complete", level, reward, soft_currency))
                        level += 1
                    else:
                        event_rows.append((level_end_ts, int(uid), session_id, "level_fail", level, 0, soft_currency))

                session_end = session_start + pd.to_timedelta(int(rng.integers(5, 25)), unit="m")
                event_rows.append((session_end, int(uid), session_id, "session_end", None, None, None))

    events = pd.DataFrame(
        event_rows,
        columns=["event_ts", "user_id", "session_id", "event_name", "level", "currency_delta", "currency_balance"],
    )

    # -----------------------------
    # PURCHASES
    # -----------------------------
    last_level = (
        events.loc[events["event_name"] == "level_complete"]
        .groupby("user_id")["level"]
        .max()
        .reindex(user_ids)
        .fillna(1)
        .values
    )

    purchase_rows = []
    for i, uid in enumerate(user_ids):
        prop = float(users["trait_spender_propensity"].iloc[i])
        lvl = float(last_level[i])
        country = users["country"].iloc[i]

        is_payer = rng.random() < np.clip(
            0.06 + 0.12 * prop + 0.02 * (lvl > 15) + 0.03 * (country == "US"),
            0,
            0.35,
        )
        if not is_payer:
            continue

        n_p = int(np.clip(rng.poisson(1.1 + 1.2 * prop), 1, 6))
        user_events = events.loc[events["user_id"] == int(uid)]
        if user_events.empty:
            continue

        candidate_ts = user_events["event_ts"].values
        buy_ts = rng.choice(candidate_ts, size=n_p, replace=True)

        for ts in buy_ts:
            price = float(rng.choice([1.99, 2.99, 4.99, 9.99, 19.99], p=[0.30, 0.25, 0.25, 0.15, 0.05]))
            purchase_rows.append((pd.to_datetime(ts), int(uid), price, "IAP", f"pack_{int(price * 100)}"))

    purchases = pd.DataFrame(purchase_rows, columns=["purchase_ts", "user_id", "revenue_usd", "purchase_type", "sku"])

    # -----------------------------
    # ADS EVENTS
    # -----------------------------
    ad_rows = []
    for i, uid in enumerate(user_ids):
        affinity = float(users["trait_ad_affinity"].iloc[i])
        user_sessions = events[(events["user_id"] == int(uid)) & (events["event_name"] == "session_start")]
        if user_sessions.empty:
            continue

        n_sessions = len(user_sessions)
        rewarded_per_session = rng.poisson(lam=0.55 + 0.9 * affinity, size=n_sessions)
        inter_per_session = rng.poisson(lam=0.35 + 0.5 * affinity, size=n_sessions)

        for j, sess_ts in enumerate(user_sessions["event_ts"].values):
            base_ts = pd.to_datetime(sess_ts)

            for _ in range(int(rewarded_per_session[j])):
                ts = base_ts + pd.to_timedelta(int(rng.integers(1, 15)), unit="m")
                rev = float(max(0.0, rng.normal(REWARDED_ECPM / 1000, 0.001)))
                ad_rows.append((ts, int(uid), "rewarded", rev, "placement_rewarded_default"))

            for _ in range(int(inter_per_session[j])):
                ts = base_ts + pd.to_timedelta(int(rng.integers(1, 15)), unit="m")
                rev = float(max(0.0, rng.normal(INTER_ECPM / 1000, 0.0008)))
                ad_rows.append((ts, int(uid), "interstitial", rev, "placement_interstitial_default"))

    ads = pd.DataFrame(ad_rows, columns=["ad_ts", "user_id", "ad_format", "ad_revenue_usd", "placement"])

    # -----------------------------
    # Inject a few tracking issues
    # -----------------------------
    if len(events) > 0:
        mask_drop = (events["event_name"] == "level_complete") & (rng.random(len(events)) < 0.008)
        events = events.loc[~mask_drop].copy()

    if len(purchases) > 0:
        extra = purchases.sample(min(50, len(purchases)), random_state=SEED).copy()
        extra["purchase_ts"] = extra["purchase_ts"] - pd.to_timedelta(rng.integers(1, 5, size=len(extra)), unit="D")
        purchases = pd.concat([purchases, extra], ignore_index=True)

    # -----------------------------
    # Save
    # -----------------------------
    users.to_csv(out_dir / "users.csv", index=False)
    ab.to_csv(out_dir / "ab_assignments.csv", index=False)
    events.to_csv(out_dir / "events.csv", index=False)
    purchases.to_csv(out_dir / "purchases.csv", index=False)
    ads.to_csv(out_dir / "ads_events.csv", index=False)

    print("\n✅ Data generated:")
    print(f"- users         : {len(users):,}")
    print(f"- ab_assignments: {len(ab):,}")
    print(f"- events        : {len(events):,}")
    print(f"- purchases     : {len(purchases):,}")
    print(f"- ads_events    : {len(ads):,}")
    print(f"\n📁 Saved under  : {out_dir}")


if __name__ == "__main__":
    main()
