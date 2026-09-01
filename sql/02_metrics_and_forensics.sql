-- =====================================================================
-- 02_metrics_and_forensics.sql
-- Independent metric definitions + the forensic queries behind the memo.
-- Depends on views/tables from 01_golden_layer.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- METRIC DEFINITIONS (challenging the reported ones)
--   contact_rate    = distinct accounts with an ANSWERED call / distinct targeted
--   rpc_rate        = ANSWERED calls / total calls          (right-party proxy)
--   ptp_rate        = PTPs created / total calls
--   ptp_kept_rate   = PTP status='KEPT' / total PTP
--   recovery        = SUM(amount) WHERE payment_status='SUCCESS', de-duped
--   recovery_per_targeted = recovery / distinct targeted accounts
-- Rationale: recovery counts money that actually settled (not FAILED/PENDING/
-- REVERSED), de-duped on payment_id; denominators use the TARGETED population
-- so shrinking the population cannot flatter the ratio.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW monthly_metrics AS
WITH mrec AS (
  SELECT date_trunc('month', event_at) AS ym,
         SUM(amount) AS recovery, COUNT(*) AS pay_events
  FROM clean_payments WHERE is_recovery = 1 GROUP BY 1),
mcall AS (
  SELECT date_trunc('month', event_at) AS ym,
         COUNT(*) AS calls, SUM(is_rpc) AS answered
  FROM clean_calls GROUP BY 1),
mptp AS (
  SELECT date_trunc('month', event_at) AS ym,
         COUNT(*) AS ptp,
         SUM(CASE WHEN status='KEPT' THEN 1 ELSE 0 END) AS ptp_kept
  FROM raw.promises_to_pay
  WHERE event_at >= DATE'2026-01-01' AND event_at < DATE'2026-09-01' GROUP BY 1),
mtgt AS (
  SELECT date_trunc('month', target_date) AS ym,
         COUNT(DISTINCT account_id) AS targeted
  FROM raw.daily_targeting
  WHERE target_date >= DATE'2026-01-01' AND target_date < DATE'2026-09-01' GROUP BY 1)
SELECT g.ym, t.targeted, c.calls, c.answered, p.ptp, p.ptp_kept, g.recovery,
       c.answered / c.calls                       AS answer_rate,
       p.ptp      / c.calls                        AS ptp_rate,
       p.ptp_kept / p.ptp                          AS ptp_kept_rate,
       g.recovery / t.targeted                     AS recovery_per_targeted,
       g.recovery / LAG(g.recovery) OVER (ORDER BY g.ym) - 1 AS recovery_mom
FROM mrec g
JOIN mcall c ON g.ym=c.ym JOIN mptp p ON g.ym=p.ym JOIN mtgt t ON g.ym=t.ym
ORDER BY g.ym;

-- =====================================================================
-- FORENSICS
-- =====================================================================

-- (A) Duplicate payments: exact retries vs reference reuse
SELECT 'dup_payment_id_rows'  AS check, COUNT(*)-COUNT(DISTINCT payment_id) AS n FROM raw.payments
UNION ALL
SELECT 'refs_used_on_multiple_accounts',
       COUNT(*) FROM (SELECT payment_reference FROM raw.payments
                      GROUP BY payment_reference HAVING COUNT(DISTINCT account_id) > 1);

-- (E) Agent identity: employee_code is not unique
SELECT employee_code, COUNT(DISTINCT agent_id) AS agent_ids
FROM raw.agents GROUP BY employee_code HAVING agent_ids > 1
ORDER BY agent_ids DESC LIMIT 10;

-- (C) Timezone: mean call hour identical across zones => naive timestamps
SELECT timezone, ROUND(AVG(HOUR(event_at)),2) AS mean_hour,
       ROUND(AVG(CASE WHEN HOUR(event_at) < 6 THEN 1 ELSE 0 END),3) AS share_before_6am
FROM raw.calls GROUP BY timezone;

-- (Q3) The "11%" claim: only Feb->Mar hits it; Jan vs Jul is flat
SELECT ym, ROUND(recovery/1e7,2) AS recovery_cr, ROUND(recovery_mom*100,1) AS mom_pct
FROM monthly_metrics;

-- (Causal null) Does contact move recovery? Compare pay rates by RPC / dose
SELECT rpc, COUNT(*) AS accounts, ROUND(AVG(paid_flag),4) AS pay_rate,
       ROUND(AVG(recovered),0) AS avg_recovered
FROM golden.account_metrics GROUP BY rpc;

SELECT CASE WHEN n_attempts=0 THEN '0'
            WHEN n_attempts<=2 THEN '1-2'
            WHEN n_attempts<=5 THEN '3-5'
            WHEN n_attempts<=10 THEN '6-10' ELSE '10+' END AS attempt_bin,
       COUNT(*) AS accounts, ROUND(AVG(paid_flag),4) AS pay_rate
FROM golden.account_metrics
GROUP BY 1 ORDER BY MIN(n_attempts);
