# Selection method, sizing rules, and report format

## 1. Read the circumstances, then tilt
Translate the live data into a sector tilt. Defaults, override with judgment:

| Signal (live) | Read | Tilt toward | Tilt away from |
|---|---|---|---|
| Index near/at all-time high, after a big run | Hot, downside risk | Dividends, defensives, ETF ballast; stagger entry | High-beta cyclicals at full weight |
| Index well below high / recovering | Cheaper, more upside | Quality cyclicals (cement, autos), select banks | Over-defensive cash drag |
| Policy rate high but peaking/falling | NIMs near peak; cyclicals helped by cheaper money later | Banks now, then cyclicals | Adding banks late after rates fall |
| Rate still rising | Banks earn more; growth pressured | Banks, low-leverage names | Highly leveraged / long-duration growth |
| Crude falling fast | Eases inflation; helps power/cement/airlines | Power (HUBC), cement, fertilizer | Pure E&P, OMC (inventory losses) |
| Crude rising | Inflation/FX pressure | E&P (OGDC/PPL/MARI) | Power, OMC margins, importers |
| IMF on track, reserves rebuilding, PKR stable | Macro tailwind, risk-on ok | Broad blue chips | Excess caution |

**`risk` input** shifts the mix: `income` overweights HUBC + Islamic banks + ETF; `growth` overweights cement/IT/autos; `balanced` blends. When the index is near a high, nudge `balanced` toward income regardless.

## 2. Pick the names (6-8 by default)
- Honor the `shariah` lean. If halal, draw from the Shariah-Yes rows; include a conventional name only if it is clearly superior and flag it explicitly.
- **Diversify across sectors.** Do not put two names that move together (e.g. two cement, or OGDC+PPL) at full weight. One foot per theme is usually enough.
- Each name needs a **one-line, specific reason** tied to today (a yield number, an analyst target, a catalyst), not a generic "good company".
- Always consider one **ETF slice** (MZNPETF) as ballast, especially near highs.
- Prefer liquid blue chips so the order fills; avoid thin small caps for a lump-sum buy.

## 3. Assign weights, then SIZE WITH THE SCRIPT
- Give the defensive/income core the larger weights; the cyclical/growth and single-commodity names smaller weights. A reasonable near-highs default: anchor ~16-20%, mid positions ~12-15%, the satellite/commodity name ~10-12%, ETF ~15%.
- Reserve **~0.6%** of cash for brokerage commission + fees + slippage (the script's `commission_pct`). PSX commission is roughly 0.15% but add headroom so the user never overdraws.
- **Never compute units by hand.** Feed `{cash, commission_pct, picks:[{symbol,price,weight,why}]}` to `scripts/size_portfolio.py` and use its unit counts and totals verbatim. It floors to whole shares, then greedily spends the leftover to minimize idle cash while respecting weights.

## 4. Entry guidance
- If the index is near an all-time high, advise staggering: deploy ~60% now, hold ~40% for dips over the coming weeks. Say this in the report.
- Recommend limit orders near the quoted price (prices move intraday; a single share may shift).

## 5. Report format

### In mdnest (`latest.md` and the dated `*-buy-report.md`)
```
# PSX Buy Report, <cash> PKR free cash
**Date:** <human date> (prices live <date>; verify before buying)
**Not financial advice.** Research-backed plan, not a guarantee.

## Market right now (one breath)
- KSE-100 <level> (<chg%>) ... 1mo/YoY trend, distance from ATH.
- Macro: rate, CPI, PKR/USD, IMF, reserves (each dated).
- Global: crude level+direction, Fed, geopolitics.
- Read: <one line on the tilt this drove>. Since last run: <delta if known>.

## BUY LIST (exact units, total ~<invested> PKR)
<the script's markdown table: Symbol | Price | Units | Cost | Weight, + TOTAL>
Why each:  <one line per symbol>
**Leftover ~<n> PKR** reserved for commission + fees.

## How to deploy
- Stagger / limit-order guidance.

## Caveats / data quality
- Stale or unverified names excluded; single-stock + market-near-high risk; etc.

---
*Sources: ... Refresh weekly for prices, quarterly for fundamentals.*
```

### In chat
The same, trimmed to: one-line market read, the buy table with units, total + leftover, 2-3 caveats, and the mdnest path written. This is the payload the user acts on without asking anything further.
