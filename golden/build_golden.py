"""
build_golden.py  --  Collections "Golden Dataset" pipeline
-----------------------------------------------------------
Raw CSVs  ->  Reject / Correct  ->  Golden analytical layer.

Design decisions (documented in reports/data_quality_report):
  * Recovery = payments.payment_status == 'SUCCESS' only.
  * Payment de-duplication key = payment_id (exact ingestion retries).
    payment_reference is NOT a key (it is reused across accounts) and
    must never be used to de-dup, or ~17% of real recovery is destroyed.
  * Agent identity = agent_id (the only stable key). employee_code /
    name / vendor / team are corrupted; resolve dim to latest updated_at.
  * Disposition synonyms unified: PTP -> PROMISE_TO_PAY.
  * Timestamps are naive and ignore the stated timezone. We keep event_at
    as-is for volume trends and expose a best-effort UTC column, but flag
    that intraday (calling-hour) analysis is unreliable.
  * Analysis window locked to 2026-01 .. 2026-08 (payment coverage).
Outputs (in ./golden/out):
  golden_payments.csv, golden_agents.csv, golden_accounts.csv,
  golden_account_metrics.csv, golden_monthly_metrics.csv, lineage.json
"""
import pandas as pd, numpy as np, json, os
RAW = "/home/claude/data"
OUT = "/home/claude/collections_analysis/golden/out"
os.makedirs(OUT, exist_ok=True)
TZ = {"UTC": 0, "Asia/Kolkata": 5.5, "Asia/Dubai": 4.0}
lineage = {}

def log(stage, table, n, note=""):
    lineage.setdefault(table, []).append({"stage": stage, "rows": int(n), "note": note})
    print(f"{table:22s} {stage:16s} {n:>8,}  {note}")

# ---------------------------------------------------------------- PAYMENTS
p = pd.read_csv(f"{RAW}/payments.csv", parse_dates=["event_at"])
log("raw", "payments", len(p))
# 1. drop exact ingestion duplicates (same payment_id)
dup_extra = p.duplicated(subset=["payment_id"], keep="first").sum()
p = p.drop_duplicates(subset=["payment_id"], keep="first")
log("reject_dup_id", "payments", dup_extra, "exact retry rows removed")
# 2. keep only in-window
p = p[(p.event_at >= "2026-01-01") & (p.event_at < "2026-09-01")]
# 3. recovery flag
p["is_recovery"] = (p.payment_status == "SUCCESS").astype(int)
recov = p[p.is_recovery == 1]
log("golden_all_events", "payments", len(p))
log("golden_recovery", "payments", len(recov),
    f"SUCCESS only; recovery=Rs {recov.amount.sum():,.0f}")
p.to_csv(f"{OUT}/golden_payments.csv", index=False)

# ---------------------------------------------------------------- AGENTS
a = pd.read_csv(f"{RAW}/agents.csv", parse_dates=["joined_at", "updated_at"])
log("raw", "agents", len(a))
agent_dim = (a.sort_values("updated_at")
               .drop_duplicates("agent_id", keep="last")
               .reset_index(drop=True))
log("golden_resolved", "agents", len(agent_dim),
    "agent_id = source of truth (latest updated_at)")
agent_dim.to_csv(f"{OUT}/golden_agents.csv", index=False)

# ---------------------------------------------------------------- ACCOUNTS
acc = pd.read_csv(f"{RAW}/accounts.csv", parse_dates=["opened_at"])
log("raw", "accounts", len(acc))
acc = acc.drop_duplicates("account_id")
log("golden", "accounts", len(acc))

# ---------------------------------------------------------------- DISPOSITIONS (synonyms)
cd = pd.read_csv(f"{RAW}/call_dispositions.csv", parse_dates=["event_at"])
cd["disposition_code_std"] = cd.disposition_code.replace({"PTP": "PROMISE_TO_PAY"})
log("raw", "call_dispositions", len(cd))
log("golden_std", "call_dispositions", len(cd), "PTP->PROMISE_TO_PAY unified")

# ---------------------------------------------------------------- CONTACT FEATURES per account
def acct_set(f, q=None):
    d = pd.read_csv(f"{RAW}/{f}", usecols=lambda c: c in ("account_id", "call_status"))
    if q: d = d.query(q)
    return set(d.account_id.unique())
called   = acct_set("calls.csv")
answered = acct_set("calls.csv", "call_status=='ANSWERED'")
wa = acct_set("whatsapp_events.csv"); sm = acct_set("sms_events.csv")
fv = acct_set("field_visits.csv")
att = pd.read_csv(f"{RAW}/call_attempts.csv", usecols=["account_id"]).groupby("account_id").size()

rec_by_acct = recov.groupby("account_id").amount.sum().rename("recovered")
am = acc[["account_id","borrower_id","risk_segment","loan_type","dpd",
          "status","principal_amount","outstanding_amount","timezone"]].copy()
am = am.merge(rec_by_acct, on="account_id", how="left")
am["recovered"] = am.recovered.fillna(0.0)
am["paid_flag"] = (am.recovered > 0).astype(int)
am["n_attempts"] = am.account_id.map(att).fillna(0).astype(int)
am["voice_contacted"] = am.account_id.isin(called).astype(int)
am["rpc"] = am.account_id.isin(answered).astype(int)
am["any_contact"] = am.account_id.isin(called | wa | sm | fv).astype(int)
am.to_csv(f"{OUT}/golden_account_metrics.csv", index=False)
log("golden", "account_metrics", len(am), "1 row/account with recovery+contact features")

# ---------------------------------------------------------------- MONTHLY METRICS
def M(s): return s.dt.to_period("M").astype(str)
recov = recov.assign(ym=M(recov.event_at))
mrec = recov.groupby("ym").agg(recovery=("amount","sum"),
                               pay_accounts=("account_id","nunique"),
                               pay_events=("payment_id","size"))
c = pd.read_csv(f"{RAW}/calls.csv", parse_dates=["event_at"]); c["ym"]=M(c.event_at)
c = c[c.ym.between("2026-01","2026-08")]
mcall = c.groupby("ym").agg(calls=("call_id","size"),
        answered=("call_status", lambda x:(x=="ANSWERED").sum()))
ptp = pd.read_csv(f"{RAW}/promises_to_pay.csv", parse_dates=["event_at"]); ptp["ym"]=M(ptp.event_at)
ptp = ptp[ptp.ym.between("2026-01","2026-08")]
mptp = ptp.groupby("ym").agg(ptp=("ptp_id","size"),
        ptp_kept=("status", lambda x:(x=="KEPT").sum()))
dt = pd.read_csv(f"{RAW}/daily_targeting.csv", parse_dates=["target_date"]); dt["ym"]=M(dt.target_date)
dt = dt[dt.ym.between("2026-01","2026-08")]
mtgt = dt.groupby("ym").account_id.nunique().rename("targeted")
mm = pd.concat([mtgt, mcall, mptp, mrec], axis=1)
mm["answer_rate"] = mm.answered/mm.calls
mm["ptp_rate"] = mm.ptp/mm.calls
mm["ptp_kept_rate"] = mm.ptp_kept/mm.ptp
mm["recovery_per_targeted"] = mm.recovery/mm.targeted
mm["recovery_mom_pct"] = mm.recovery.pct_change()*100
mm.round(4).to_csv(f"{OUT}/golden_monthly_metrics.csv")
log("golden", "monthly_metrics", len(mm), "8 months of independent metrics")

with open(f"{OUT}/lineage.json", "w") as f:
    json.dump(lineage, f, indent=2)
print("\nDONE. Golden outputs in", OUT)
