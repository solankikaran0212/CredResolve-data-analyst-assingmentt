-- =====================================================================
-- 01_golden_layer.sql   (Databricks SQL / Spark SQL)
-- Raw -> Clean -> Golden.  Reproducible; window-locked to 2026-01..2026-08.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PAYMENTS: de-dup on payment_id (NOT payment_reference), SUCCESS = recovery
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW clean_payments AS
WITH ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY payment_id
                            ORDER BY event_at) AS rn         -- kill exact retries
  FROM raw.payments
  WHERE event_at >= DATE'2026-01-01' AND event_at < DATE'2026-09-01'
)
SELECT
  payment_id, account_id, borrower_id, event_at,
  payment_reference,                                          -- kept but NEVER a key
  amount, payment_status, payment_method, provider_id,
  CASE WHEN payment_status = 'SUCCESS' THEN 1 ELSE 0 END AS is_recovery
FROM ranked
WHERE rn = 1;                                                 -- 25,500 -> 25,000

-- Guardrail: payment_reference is reused; prove it is not unique before anyone tries.
-- SELECT payment_reference, COUNT(DISTINCT account_id) a
-- FROM clean_payments GROUP BY 1 HAVING a > 1;   -- returns 3,407 rows

-- ---------------------------------------------------------------------
-- AGENTS: resolve 30k messy rows to 1k agent_id (latest updated_at)
-- employee_code / name / vendor / team are corrupted and dropped as keys
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW dim_agent AS
SELECT agent_id, employee_code, agent_name, vendor_id, team, status,
       joined_at, updated_at
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY agent_id
                               ORDER BY updated_at DESC) AS rn
  FROM raw.agents
)
WHERE rn = 1;                                                 -- 30,000 -> 1,000

-- ---------------------------------------------------------------------
-- DISPOSITIONS: unify synonym codes (PTP == PROMISE_TO_PAY)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW clean_dispositions AS
SELECT disposition_id, account_id, borrower_id, event_at, call_id, agent_id,
       CASE WHEN disposition_code = 'PTP' THEN 'PROMISE_TO_PAY'
            ELSE disposition_code END AS disposition_code_std,
       disposition_version
FROM raw.call_dispositions;

-- ---------------------------------------------------------------------
-- CALLS: keep event_at for daily grain; expose best-effort UTC.
-- WARNING: event_at is naive -> do NOT trust HOUR() for calling-time analysis.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW clean_calls AS
SELECT c.*,
       CASE c.timezone
         WHEN 'Asia/Kolkata' THEN c.event_at - INTERVAL 330 MINUTE
         WHEN 'Asia/Dubai'   THEN c.event_at - INTERVAL 240 MINUTE
         ELSE c.event_at END                    AS event_at_utc_best_effort,
       CASE WHEN c.call_status = 'ANSWERED' THEN 1 ELSE 0 END AS is_rpc
FROM raw.calls c
WHERE c.event_at >= DATE'2026-01-01' AND c.event_at < DATE'2026-09-01';

-- ---------------------------------------------------------------------
-- GOLDEN: one row per account with recovery + contact features
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE golden.account_metrics AS
WITH rec AS (
  SELECT account_id, SUM(amount) AS recovered
  FROM clean_payments WHERE is_recovery = 1 GROUP BY account_id
),
att AS (
  SELECT account_id, COUNT(*) AS n_attempts FROM raw.call_attempts GROUP BY account_id
),
rpc AS (
  SELECT DISTINCT account_id FROM clean_calls WHERE is_rpc = 1
),
contact AS (
  SELECT account_id FROM raw.calls
  UNION SELECT account_id FROM raw.whatsapp_events
  UNION SELECT account_id FROM raw.sms_events
  UNION SELECT account_id FROM raw.field_visits
)
SELECT a.account_id, a.borrower_id, a.risk_segment, a.loan_type, a.dpd,
       a.status, a.principal_amount, a.outstanding_amount, a.timezone,
       COALESCE(r.recovered, 0)                    AS recovered,
       CASE WHEN r.recovered > 0 THEN 1 ELSE 0 END AS paid_flag,
       COALESCE(t.n_attempts, 0)                   AS n_attempts,
       CASE WHEN rp.account_id IS NOT NULL THEN 1 ELSE 0 END AS rpc,
       CASE WHEN ct.account_id IS NOT NULL THEN 1 ELSE 0 END AS any_contact
FROM raw.accounts a
LEFT JOIN rec r      ON a.account_id = r.account_id
LEFT JOIN att t      ON a.account_id = t.account_id
LEFT JOIN rpc rp     ON a.account_id = rp.account_id
LEFT JOIN (SELECT DISTINCT account_id FROM contact) ct ON a.account_id = ct.account_id;
