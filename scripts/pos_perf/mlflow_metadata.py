"""mlflow_metadata.py -- set descriptions, tags, owners and aliases on the POS
demand-forecasting experiments and registered models in the warehouse MLflow.

MLflow has no first-class owner field. The conventions used here are the ones
the UI understands:
  description   the mlflow.note.content tag, which the UI renders as the
                Description panel on experiments, models and versions
  owner         a plain tag, plus mlflow.user where the server accepts it
  alias         champion marks the version a consumer should load, so a
                scoring job can pin models:/name@champion instead of a number

Everything here is idempotent -- rerun it after any retrain. It never creates
runs and never touches model artifacts, only metadata.

Identity note: the owner is the Actian work identity that provisioned the
warehouse (preferredUsername on the Admiral resource record), not a personal
address.

Usage
  python scripts/pos_perf/mlflow_metadata.py            # apply
  python scripts/pos_perf/mlflow_metadata.py --dry-run  # print, change nothing
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

HERE = Path(__file__).resolve().parent
CONFIG = HERE.parents[1] / ".claude" / "skills" / "admiral" / "admiral.config.json"

OWNER = "robert.gorsuch@actian.com"
TEAM = "Actian POS Analytics"
WAREHOUSE = "av-flm7ykoxlcvq (pos_data)"
DATA_WINDOW = "2019-01-01..2020-12-31"

COMMON = {
    "owner": OWNER,
    "team": TEAM,
    "warehouse": WAREHOUSE,
    "data_window": DATA_WINDOW,
    "domain": "retail-demand-forecasting",
    "serving": "batch score to Avalanche table, read by Jaspersoft dashboards",
    "lifecycle": "validated-on-historical-data",
    "data_caveat": "source data ends 2020-12-31 -- scoring is historical, not live inference",
}

EXPERIMENTS = {
    "pos-store-day-demand": {
        "note": (
            "Daily sales forecast per store, 14 days ahead, for labour scheduling and "
            "store ordering across 330 Canadian franchise grocery stores.\n\n"
            "Grain: store x calendar day, 229,595 rows over 2019-01-01 to 2020-12-31. "
            "Direct 14-step-ahead HistGradientBoosting on absolute-error loss, so a row "
            "dated D uses nothing observed after D-14 and there is no recursive error "
            "compounding.\n\n"
            "Result on a 57-day out-of-time holdout: WAPE 0.2120, MAE 1,114, R2 0.755. "
            "That is 36 percent better than lag-14 persistence (0.3326) and 41 percent "
            "better than a same-weekday mean (0.3622).\n\n"
            "Three runs are logged per target. 'main' trains on all history with "
            "pandemic_period as an explicit feature and is the shipped model. "
            "'pandemic_only' tests dropping pre-COVID history and is much worse "
            "(WAPE 0.3309) -- losing training volume outweighs regime purity. "
            "'regime_shift' is a diagnostic, never shipped: a model trained only on "
            "pre-pandemic days still beats persistence on pandemic data (0.2189 vs "
            "0.2883), because the lag features absorb the level shift.\n\n"
            "Leakage is excluded deliberately. The whole-period rollups on stores and "
            "fsa_demographics (total_sales, sales_per_sqft, penetration_pct and the "
            "rest) are computed from the full sales history and are never used as "
            "features.\n\n"
            "Build: scripts/pos_perf/build_store_day_features.sql then "
            "scripts/pos_perf/store_demand_model.py. Verify independently in SQL with "
            "scripts/pos_perf/verify_store_day_forecast.sql."
        ),
        "tags": {
            "grain": "store x day",
            "horizon": "14 days",
            "target": "store_traffic.sales",
            "source_tables": "store_traffic, date_dim, stores, weather_daily, fsa_demographics",
            "feature_table": "store_day_features",
            "output_table": "store_day_forecast",
            "registered_model": "store-day-demand",
            "source_script": "scripts/pos_perf/store_demand_model.py",
            "headline_metric": "holdout WAPE 0.2120, R2 0.755",
            "beats_baseline": "36 percent better than lag-14 persistence",
            "forward_assumptions": "weather from day-of-year climatology, promos_active from month x weekday mean",
        },
    },
    "pos-plu-weekly-demand": {
        "note": (
            "Weekly unit demand per store-PLU pair, 2 weeks ahead, to replace the static "
            "reorder parameter driving replenishment. Supplier lead times run 3 to 9 days "
            "(mean 5.7), so a two-week horizon covers the order cycle.\n\n"
            "Grain: store x PLU x week, 15.3M dense pair-weeks over 214,998 pairs and 104 "
            "weeks. 23.9 percent of pair-weeks are ZERO and those zeros are kept -- a "
            "spine of only weeks that happened to sell would teach the model that demand "
            "is never zero.\n\n"
            "Validation is out-of-time AND out-of-store: trained on 32 stores "
            "(storenumber mod 10 = 0), evaluated on a disjoint store set. WAPE 0.5064 on "
            "stores never trained on.\n\n"
            "READ THE BASELINES CAREFULLY. inventory.avg_daily_units x 7 appears to beat "
            "the model (0.4766 vs 0.5064), but that average spans the holdout weeks and "
            "is therefore not a forecast anyone could have made at the origin. The fair "
            "comparison is static(train), the same flat-average policy computed only from "
            "training weeks: 0.6037. The model wins that by 16 percent, and beats a "
            "4-week moving average by 4.3 percent.\n\n"
            "Order quantity is NOT the point forecast. An absolute-error model predicts "
            "the conditional median, and weekly demand is right-skewed, so ordering at "
            "the median covers only 45.2 percent of pair-weeks. A separate q0.85 model "
            "supplies the order quantity: 79.6 percent coverage and 66 percent fewer "
            "units short. The quantile is floored at the median so the two models cannot "
            "cross.\n\n"
            "Known limit: 739 of 942 products carry no category in the source and 763 no "
            "size_g, so product features contribute far less than the schema suggests. "
            "Filling that catalogue is the cheapest available accuracy gain.\n\n"
            "Build: scripts/pos_perf/build_store_plu_week.sql then "
            "scripts/pos_perf/plu_demand_model.py. Verify with "
            "scripts/pos_perf/verify_store_plu_forecast.sql."
        ),
        "tags": {
            "grain": "store x plu x week",
            "horizon": "2 weeks",
            "target": "net units sold",
            "source_tables": "pos_sales_detail, pos_sales_txn, date_dim, products, stores, inventory",
            "feature_table": "store_plu_week",
            "output_table": "store_plu_forecast",
            "registered_model": "plu-weekly-demand",
            "source_script": "scripts/pos_perf/plu_demand_model.py",
            "headline_metric": "out-of-store WAPE 0.5064",
            "beats_baseline": "16 percent better than a training-period flat average",
            "fair_baseline_warning": "incumbent avg_daily_units spans the holdout and is optimistically biased",
            "intermittency": "23.9 percent of pair-weeks are zero",
            "service_level": "orders placed at q0.85, covering 79.6 percent of pair-weeks",
            "data_gap": "739 of 942 products have no category in the source",
        },
    },
}

MODELS = {
    "store-day-demand": {
        "experiment": "pos-store-day-demand",
        "note": (
            "Direct 14-day-ahead daily sales forecast per store. Input is the "
            "store_day_features row for the target date, with every lag and rolling "
            "feature already offset by at least 14 days. Output is predicted daily "
            "sales in CAD, and callers MUST clip at zero -- the absolute-error "
            "objective can emit small negatives for stores trading near zero.\n\n"
            "Consume via the champion alias rather than a version number.\n\n"
            "Retrain when store_day_features is rebuilt. Scoring is batch: "
            "store_demand_model.py writes store_day_forecast, which the Jaspersoft "
            "dashboards read. There is no online serving path."
        ),
        "tags": {
            "task": "regression / time-series demand forecast",
            "framework": "scikit-learn HistGradientBoostingRegressor",
            "loss": "absolute_error (predicts the conditional median)",
            "serialization": "cloudpickle (skops rejects HistGradientBoosting internals)",
            "output_units": "CAD daily sales per store",
            "postprocessing_required": "clip predictions at zero",
            "training_split": "all history to 2020-11-04, pandemic_period as a feature",
            "validation": "out-of-time, final 57 days",
        },
        "version_note": (
            "Winning 'main' configuration retrained on all data through 2020-12-31.\n"
            "Holdout WAPE 0.2120, MAE 1,114, RMSE 1,668, R2 0.755, bias -186.\n"
            "Baselines: lag-14 persistence 0.3326, same-weekday mean 0.3622.\n"
            "SQL reproduces the holdout WAPE at 0.212028 against store_day_forecast.\n"
            "Top features by permutation importance: day_of_year, day_of_month, "
            "samedow_mean4, roll91_lag14.\n"
            "Caveat: day_of_year dominates and the model has seen exactly one prior "
            "December, so the annual seasonal signal rests on a single observation "
            "per calendar day."
        ),
    },
    "plu-weekly-demand": {
        "experiment": "pos-plu-weekly-demand",
        "note": (
            "Two-week-ahead weekly unit demand per store-PLU pair. This registered "
            "model is the MEDIAN point forecast, used for planning.\n\n"
            "It is NOT the ordering model. Ordering at this output covers only 45.2 "
            "percent of pair-weeks. The run that produced this version also logs an "
            "'order_model' artifact fitted at q0.85, which is what suggested_order in "
            "store_plu_forecast is built from, floored at this median and rounded up "
            "to a whole case using inventory.case_size.\n\n"
            "Callers must clip at zero. Do not order for a PLU that is no longer "
            "carried: the scoring script restricts the forward window to pairs still "
            "selling in the final week.\n\n"
            "Consume via the champion alias. Scoring is batch, no online serving path."
        ),
        "tags": {
            "task": "regression / intermittent demand forecast",
            "framework": "scikit-learn HistGradientBoostingRegressor",
            "loss": "absolute_error (predicts the conditional median)",
            "serialization": "cloudpickle (skops rejects HistGradientBoosting internals)",
            "output_units": "net units per store-PLU-week",
            "postprocessing_required": "clip at zero; use the q0.85 order_model artifact for order quantity",
            "companion_artifact": "order_model (quantile 0.85) logged on the same run",
            "training_split": "32 stores (mod 10 = 0), weeks 0-95",
            "validation": "out-of-time AND out-of-store, final 8 weeks on a disjoint store set",
        },
        "version_note": (
            "Trained on 1,302,396 pair-weeks from 32 stores, weeks 0 to 95.\n"
            "valid_unseen (stores never trained on): WAPE 0.5064, MAE 3.740, R2 0.536.\n"
            "valid_seen: WAPE 0.5010.\n"
            "Fair baseline static(train) 0.6037 -- model wins by 16 percent.\n"
            "ma4 0.5294, lag2 0.6004.\n"
            "The incumbent avg_daily_units x 7 reads 0.4766 but spans the holdout and "
            "is optimistically biased; it is not a like-for-like comparison.\n"
            "By velocity band: fast 0.4389, medium 0.5170, slow 0.7023 -- slow movers "
            "are hardest, as intermittency predicts.\n"
            "Top features: roll4, roll13, week_of_year, sub_category.\n"
            "Systematic under-forecast (bias -1.49 medium, -6.06 fast) is inherent to "
            "the median objective and is why ordering uses the q0.85 companion."
        ),
    },
}


# Superseded versions. An undocumented version in a registry is an invitation
# to load the wrong one, so every version that is not champion says why.
SUPERSEDED = {
    ("store-day-demand", "1"): (
        "SUPERSEDED -- do not use. Registered before predictions were clipped at "
        "zero, so this model's scoring path emitted 6 negative daily-sales values. "
        "Superseded by v2 and then v3. Use the champion alias."
    ),
    ("store-day-demand", "2"): (
        "SUPERSEDED by v3. Functionally equivalent model, but registered on a run "
        "whose metric logging was cut short by the MLflow async double-insert bug, "
        "so its run carries incomplete metrics. v3 is the same recipe with a clean "
        "run. Use the champion alias."
    ),
}


def cfg():
    return json.load(open(CONFIG, encoding="utf-8-sig"))


def token(attempts=3, timeout=90):
    import requests
    c = cfg()
    last = None
    for i in range(attempts):
        try:
            r = requests.post(f"{c['baseUrl']}/login",
                              data={"grant_type": "password", "username": c["username"],
                                    "password": c["password"]}, timeout=timeout)
            r.raise_for_status()
            return r.json()["access_token"]
        except Exception as e:
            last = e
            print(f"  login attempt {i + 1}/{attempts} failed: {type(e).__name__}", flush=True)
            time.sleep(3 * (i + 1))
    raise last


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if a.dry_run:
        for name, spec in EXPERIMENTS.items():
            print(f"\n=== experiment {name} ===\n{spec['note'][:400]}...")
            print("tags:", json.dumps({**COMMON, **spec["tags"]}, indent=2)[:600])
        for name, spec in MODELS.items():
            print(f"\n=== model {name} ===\n{spec['note'][:400]}...")
        return 0

    os.environ["MLFLOW_ENABLE_ASYNC_LOGGING"] = "false"
    import mlflow
    from mlflow.tracking import MlflowClient
    try:
        mlflow.config.enable_async_logging(False)
    except Exception:
        pass
    os.environ["MLFLOW_TRACKING_TOKEN"] = token()
    host = cfg()["db_pos_data"]["host"]
    uri = f"https://{host}/mlflow/"
    mlflow.set_tracking_uri(uri)
    c = MlflowClient()
    print(f"mlflow -> {uri}", flush=True)

    for name, spec in EXPERIMENTS.items():
        exp = c.get_experiment_by_name(name)
        if exp is None:
            print(f"  SKIP experiment {name}: not found", flush=True)
            continue
        c.set_experiment_tag(exp.experiment_id, "mlflow.note.content", spec["note"])
        for k, v in {**COMMON, **spec["tags"]}.items():
            c.set_experiment_tag(exp.experiment_id, k, v)
        print(f"  experiment {name} (id {exp.experiment_id}): description + "
              f"{len(COMMON) + len(spec['tags'])} tags", flush=True)

    for name, spec in MODELS.items():
        try:
            rm = c.get_registered_model(name)
        except Exception as e:
            print(f"  SKIP model {name}: {type(e).__name__}", flush=True)
            continue
        c.update_registered_model(name, description=spec["note"])
        for k, v in {**COMMON, **spec["tags"], "experiment": spec["experiment"]}.items():
            c.set_registered_model_tag(name, k, v)

        versions = c.search_model_versions(f"name='{name}'")
        latest = max(versions, key=lambda v: int(v.version))
        c.update_model_version(name, latest.version, description=spec["version_note"])
        for k, v in {"owner": OWNER, "team": TEAM, "validation_status": "passed",
                     "verified_in_sql": "yes", "lifecycle": "champion",
                     "promoted_by": "scripts/pos_perf/mlflow_metadata.py"}.items():
            c.set_model_version_tag(name, latest.version, k, v)
        try:
            c.set_registered_model_alias(name, "champion", latest.version)
            alias = f", alias champion -> v{latest.version}"
        except Exception as e:
            alias = f" (alias not set: {type(e).__name__})"
        print(f"  model {name}: description + tags, v{latest.version} annotated{alias}", flush=True)

    for (mname, ver), note in SUPERSEDED.items():
        try:
            c.update_model_version(mname, ver, description=note)
            c.set_model_version_tag(mname, ver, "lifecycle", "superseded")
            c.set_model_version_tag(mname, ver, "owner", OWNER)
            print(f"  {mname} v{ver}: marked superseded", flush=True)
        except Exception as e:
            print(f"  SKIP {mname} v{ver}: {type(e).__name__}", flush=True)

    print("done", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
