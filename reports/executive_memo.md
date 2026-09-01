# Executive Memo — Collections Recovery Review
**To:** Leadership Team   **From:** Data Analytics   **Re:** Is recovery really up 11% MoM, and where the ₹10 Cr should go
**Analysis window:** Jan–Aug 2026 (payment coverage) · 30,000 accounts · ₹131.6 Cr recovered · independent re-build of the numbers

---

## 1. What happened
**Recovery is flat, not up 11%.** After rebuilding recovery from raw payments (SUCCESS payments only, de-duplicated on `payment_id`), monthly recovery has moved sideways all year:

| | Jan | Feb | Mar | Apr | May | Jun | Jul |
|---|---|---|---|---|---|---|---|
| Recovery (₹ Cr) | 18.72 | 17.01 | 18.89 | 17.51 | 18.43 | 17.56 | 18.72 |
| MoM % | – | −9% | **+11%** | −7% | +5% | −5% | +7% |

January recovery (₹18.72 Cr) and July recovery (₹18.72 Cr) are **within 0.01% of each other**. Mean monthly recovery is ₹18.1 Cr with a coefficient of variation of just 4.1% — this is a flat line with noise, not a trend. The reported **"+11% MoM" is a single cherry-picked month-pair (Feb→Mar)**, and February was itself an unusually low month, so March is a rebound, not an improvement. Every core operating metric tells the same story: answer rate ~20%, PTP rate ~19–21%, PTP-kept rate ~25% — all flat month over month. (August looks like a −75% collapse only because the data ends on the 8th; it is a partial month and should never be compared to full months.)

## 2. Why it happened
The month-to-month wiggles are **statistical noise around a flat mean**. No segment, DPD band, geography, channel, campaign, vendor, or agent cohort shows a genuine sustained trend. The single most important finding sits underneath all of this:

> **Collections activity has no measurable effect on whether an account pays.**

Accounts that reached a live person (RPC) paid at **44.7%** vs **43.9%** for those that did not — a gap that is not statistically significant (χ² p = 0.19). Payment probability is essentially identical whether an account received 1–2 call attempts or 6–10 (43.9% → 44.7%; correlation with attempts r = 0.006, p = 0.30). Borrower characteristics (risk segment, DPD, loan type) barely move it either (43–45% across the board). In this data, **recovery is driven by the borrower, not by what the collections operation does** — which means any report attributing recovery to a specific campaign, channel, or agent is measuring *who was targeted*, not *what worked*.

**Evidence grading:** Flat recovery = **Fact**. "+11% is a cherry-pick" = **Fact**. "Activity does not drive recovery" = **Strong Evidence** (consistent across contact, RPC, and dose-response tests, but bounded by the fact that <0.1% of accounts were a true no-contact control). Everything else = **Correlation / Hypothesis**.

## 3. How confident are we
**High** on the first two conclusions — they survive de-duplication, status filtering, timezone caveats, and multiple cross-checks. **Medium** on "activity doesn't drive recovery": the effect is statistically zero *in the observed range*, but because almost every account was contacted, we cannot rule out a small effect that only a randomized holdout could detect. We also had to correct real data-quality problems before trusting any number (see §5).

## 4. What we should do with the ₹10 Cr
**Do not commit ₹10 Cr to any of the six growth levers yet — the data cannot justify it.** Pouring money into more agents, more telephony, or more field visits buys more *activity*, and activity is exactly the thing we have shown does not move recovery. The expected incremental recovery from "more of the same" is, on the current evidence, **≈ ₹0**.

**Recommended sequence:**

**Step 1 — Spend ₹30–40 L now on a randomized holdout experiment (highest-ROI action available).** Randomly assign ~3% of eligible accounts to a no-contact / minimal-contact control for 10–12 weeks and measure the true lift of the operation. This is the only way to convert a ₹10 Cr guess into a ₹10 Cr decision. Everything below stays a hypothesis until this runs.

**Step 2 — If forced to allocate immediately, choose (3) AI-voice / digital automation — as a *cost* play, not a *volume* play.** Since recovery is flat and borrower-driven, the lever with a defensible ROI is **cost per ₹ recovered**, not incremental recovery. Human calling produces no measurable lift over far cheaper WhatsApp/SMS/automated voice, yet costs the most per contact. Migrating a share of the ~150k monthly human-touch interactions to automation protects current recovery while cutting servicing cost.

| | Estimate | Basis / assumption |
|---|---|---|
| Incremental recovery | ₹0 (hold flat) | Activity shown not to drive recovery |
| Cost saved (annual) | **₹4–7 Cr/yr** | Automating ~40% of human calling at materially lower cost/contact |
| Investment | ₹10 Cr (platform + rollout) | One-time build + first-year run |
| Payback | **18–30 months** | On cost savings alone |
| Downside | Recovery dips 1–3% | *If* a small undetected human-touch effect exists (≈ ₹2–5 Cr/yr) → run Step 1 first to bound this |
| Confidence | Medium, wide | Cost data is proxied; validate before full commit |

The theoretically "correct" lever is **(4) better borrower targeting**, because the borrower is the only thing that predicts payment — but in *this* dataset even borrower signal is weak, so targeting gains would be modest and should also be proven in the Step 1 experiment before funding.

## 5. What we had to fix before trusting the numbers (data-quality impact)
| Issue | Impact if uncorrected |
|---|---|
| 500 exact-duplicate payment rows | Inflated recovery by ₹2.5 Cr (~2%) |
| `payment_reference` reused across accounts | Naive de-dup would have **deleted 17% of real recovery** |
| FAILED/PENDING/REVERSED counted as paid | Overstates recovery by ~30% of payment events |
| Agent identity: 30k rows → 1k real agents | Agent & agent-tenure analysis unusable without resolution |
| Naive timestamps ignore 3 timezones | ~25% of calls mis-bucketed by hour → calling-time analysis invalid |
| Disposition synonyms (PTP vs PROMISE_TO_PAY) | Splits the same outcome across two codes |

**Bottom line:** The 11% improvement is not real; recovery has been flat all year; and the operation's activity is not what drives recovery. Before spending ₹10 Cr, spend ₹30–40 L to measure what actually works.
