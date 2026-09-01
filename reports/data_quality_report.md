# Data Quality Report — Collections Dataset

Every issue below was **detected**, **quantified**, and given a **treatment rule** that is implemented in `golden/build_golden.py`. Issues are ordered by business impact.

## Summary: Raw → Rejected/Corrected → Golden

| Table | Raw rows | Action | Golden rows |
|---|---|---|---|
| payments | 25,500 | drop 500 exact dup rows; keep in-window | 25,000 events / **17,534 recovery (SUCCESS)** |
| agents | 30,000 | resolve to `agent_id` (latest `updated_at`) | **1,000** agents |
| accounts | 30,000 | de-dup on `account_id` | 30,000 |
| call_dispositions | 35,000 | standardise `PTP → PROMISE_TO_PAY` | 35,000 |
| **Recovery total** | ₹1.341 Cr gross | remove dup inflation | **₹131.6 Cr clean** |

---

## A. Duplicate payments — CONFIRMED (two different problems, opposite treatments)
**Detection.** `payment_id` had 25,500 rows but 25,000 unique IDs → 500 IDs appear twice; 97% of those pairs are byte-identical across all columns → classic ingestion retries.
**Treatment.** De-duplicate on `payment_id` (keep first). Removes 500 rows / **₹2.5 Cr of phantom recovery (~2%)**.
**Trap avoided.** `payment_reference` looks like a natural key but is **reused across 3,407 references spanning multiple accounts, amounts and dates**. De-duplicating on it would have destroyed ~**17% of legitimate recovery**. Rule: *never* de-dup payments on `payment_reference`.

## B. Attribution error — CONFIRMED (structural)
**Detection.** Payments carry no `campaign_id` or `call_id`; any channel/campaign attribution must be inferred (last-touch). We tested whether contact even predicts payment and found it does not (see §Statistical). Therefore last-touch attribution assigns credit to whichever interaction happened to be most recent, not to a cause.
**Treatment.** Do not attribute recovery to campaign/channel/agent in the golden layer. Report recovery at account and portfolio level; treat any channel-level "conversion" as correlational only.

## C. Timezone problems — CONFIRMED
**Detection.** `accounts`, `calls`, `agent_sessions`, `vendor_telephony` declare three zones (UTC, Asia/Kolkata +5:30, Asia/Dubai +4), but `event_at` is a **naive timestamp**: mean call hour is 11.5 for *all three* zones, ~25% of calls fall in "00:00–05:59", and 30,191 `account_status_history` rows are `recorded_at` *before* `event_at` by ≤1 day (an offset artifact).
**Treatment.** Keep `event_at` for daily/monthly volume (robust to ≤5.5h shifts). Expose a best-effort UTC column, and **flag intraday (calling-hour) analysis as unreliable** — proper local-time reconstruction would move ~half of events across hour boundaries.

## D. Vendor / disposition code changes — CONFIRMED (synonyms, not a clean cutover)
**Detection.** `call_dispositions.disposition_version ∈ {legacy, v1, v2}`. Codes `PTP` and `PROMISE_TO_PAY` both appear in **all three** versions at similar volume → they are synonyms coexisting, not a versioned rename.
**Treatment.** Standardise `PTP → PROMISE_TO_PAY` before computing PTP/contact metrics. `vendor_telephony` mappings were checked and are stable across the window.

## E. Agent identity — CONFIRMED (severe)
**Detection.** `agents` has 30,000 rows but only **1,000 distinct `agent_id`**. `employee_code` is not an identity: `EMP00001` maps to 30 different `agent_id`s with different names, vendors and teams. Within a single `agent_id`, name/vendor/team/`joined_at` all conflict.
**Treatment.** `agent_id` is the only trustworthy key; resolve the dimension to the latest `updated_at` per `agent_id`. **Consequence:** "agent tenure" cannot be computed reliably (`joined_at` is corrupted), so agent-tenure conclusions are withheld.

## F. Portfolio mix change — CHECKED, NOT PRESENT
Risk segment, loan type and DPD are near-uniform and **stable across all months**; monthly targeted volume is flat (~5,600/mo). No evidence the business acquired a fundamentally different portfolio. So mix is *not* an explanation for any apparent change.

## G. Denominator manipulation — CHECKED, NOT PRESENT
Targeted-account counts and `account_status_history` events are stable month to month; no cohort of unsuccessful accounts silently drops out of the population. Conversion denominators are intact.

## Other issues
- **Out-of-window leakage:** a stray `2025-12` call record; excluded by the window filter.
- **Payment status mix:** 70% SUCCESS, 15% FAILED, 10% PENDING, 5% REVERSED. Only SUCCESS is recovery.
- **`outstanding > principal`** on 43% of accounts — plausible (accrued interest/fees), retained.

## Statistical robustness check (why the "cleaning" conclusions hold)
- RPC vs no-RPC payment rate: 44.7% vs 43.9%, χ² p = 0.19 (not significant).
- Attempts vs payment: point-biserial r = 0.006, p = 0.30 (no dose-response).
- Recovery Jan vs Jul: +0.01%. Full-month recovery CV: 4.1%.

These are transparent, reproducible tests (no black-box models), consistent with the assignment's preference for explainable methods.
