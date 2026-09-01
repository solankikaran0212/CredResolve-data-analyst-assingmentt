# Collections Recovery — Forensic Analysis & Golden Dataset

Independent rebuild of the collections numbers to answer four questions from leadership:
**What happened? Why? Is the reported "+11% MoM recovery" real? Where should the ₹10 Cr go?**

## TL;DR
1. **The "+11% MoM" is not real.** It is a single cherry-picked month-pair (Feb→Mar). Recovery has been **flat all year** — January (₹18.72 Cr) and July (₹18.72 Cr) are within **0.01%** of each other; mean ₹18.1 Cr/mo, CV 4.1%.
2. **Collections activity does not measurably drive recovery.** Accounts reached live (RPC) pay at 44.7% vs 43.9% for those not reached (χ² p=0.19); no dose-response with call attempts (r=0.006, p=0.30). Recovery is **borrower-driven / exogenous**.
3. **Don't commit the ₹10 Cr to any growth lever yet.** "More of the same" (agents/telephony/field) buys ≈₹0 incremental. Spend **₹30–40 L first on a randomized holdout** to measure true lift; if forced to allocate, pick **AI-voice/digital automation as a cost play**.

Before any of this could be trusted, several real data-quality traps had to be corrected (duplicate payments, `payment_reference` reuse, agent identity collapse, naive timezones, disposition synonyms).

## Repository layout
```
collections_analysis/
├── README.md                        ← you are here
├── reports/
│   ├── executive_memo.md            ← 2-page memo (What/Why/Confidence/Action/₹ impact)
│   └── data_quality_report.md       ← every trap: detected, quantified, treated (A–G)
├── golden/
│   ├── build_golden.py              ← reproducible Raw→Reject→Golden pipeline (runs)
│   └── out/                         ← golden outputs + lineage.json
│       ├── golden_payments.csv          (de-duped, in-window, is_recovery flag)
│       ├── golden_agents.csv            (30k rows → 1k resolved agents)
│       ├── golden_account_metrics.csv   (1 row/account: recovery + contact features)
│       ├── golden_monthly_metrics.csv   (8 months of independent metrics)
│       ├── lineage.json                 (raw→reject→golden row counts)
│       └── dashboard_data.json
├── sql/
│   ├── 01_golden_layer.sql          ← cleaning, dedup, entity resolution (Databricks SQL)
│   └── 02_metrics_and_forensics.sql ← metric definitions + forensic/causal-null queries
├── notebook/
│   └── analysis.ipynb               ← the reasoning, step by step (executes clean)
├── dashboard/
│   └── executive_dashboard.html     ← one 60-second screen (self-contained, no CDN)
└── architecture/
    └── architecture.svg             ← production medallion design (contracts, late data, monitoring)
```

## How to reproduce
```bash
# 1. Point the pipeline at your raw CSVs (default: /home/claude/data), then:
python golden/build_golden.py          # writes golden/out/ + prints raw→reject→golden lineage

# 2. Walk the reasoning:
jupyter notebook notebook/analysis.ipynb   # set RAW to your raw path in cell 1

# 3. SQL path (Databricks): run sql/01_golden_layer.sql then sql/02_metrics_and_forensics.sql
```

## Method notes
- **Recovery** = `payment_status = 'SUCCESS'`, de-duplicated on **`payment_id`** (never `payment_reference`).
- **Analysis window** locked to **2026-01 … 2026-08** (payment coverage). August is partial (data ends the 8th) and is excluded from trend comparisons.
- Methods are deliberately **simple and transparent** (rates, χ², point-biserial correlation) — no black-box models — so every conclusion is auditable.

## Reading order for a reviewer
`reports/executive_memo.md` → `dashboard/executive_dashboard.html` → `notebook/analysis.ipynb` → `reports/data_quality_report.md` → `sql/` + `golden/` → `architecture/architecture.svg`.
