# Billing alarm

Five minutes. Do it on **every** AWS account you own, including the new one,
on the day you create it.

---

## Why this is on the list at all

AWS Free Tier changed in July 2025. It is no longer twelve months of free
hours — it is **six months, or $200 of credits, whichever runs out first**.

There is no warning when they run out. Nothing stops. The instance keeps
running, the database keeps running, and the cost — roughly **$28–35 a month**
for what we have — starts landing on the card.

Without an alarm, the first time you find out is the statement.

---

## Set it

1. **Billing and Cost Management** → **Budgets** → **Create budget**.
2. **Customize (advanced)** → **Cost budget**.
3. Period **Monthly**, **Recurring**, budget type **Fixed**.
4. Amount: **$40**. High enough not to nag, low enough to catch a mistake.
5. Name: `sathiyaa-monthly`.
6. **Add alert threshold** — add three:

   | Threshold | Of | Meaning |
   |---|---|---|
   | 50% | Actual | Normal month, halfway |
   | 90% | Actual | Approaching the limit |
   | 100% | **Forecasted** | AWS predicts you will exceed it |

   The forecasted one is the useful alarm. It fires on the trajectory, days
   before the money is actually spent.

7. Email: your own. Add a second address if anyone else should know.
8. Create.

---

## Also watch the credits

**Billing → Credits** shows what is left and when it expires. Put a calendar
reminder **two weeks before that date**. That is when a decision is needed
about whether the run rate is worth it, and it is a much better time to have
that conversation than the day after.

---

## Separately, on Google Cloud

The Maps key gets its own budget — see [MAPS-GOOGLE.md](MAPS-GOOGLE.md) step 5.
Different provider, different console, different card. Both need one.
