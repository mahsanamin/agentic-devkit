# Candidate universe + data sources

A starting watchlist of fundamentally strong, liquid PSX names by sector. This is a
**candidate pool, not a buy list** — each run picks from it (and may add a strong
name it encounters). Shariah column is the default screen; verify if in doubt.
Liquidity matters: prefer index/blue-chip names so a 200k order fills cleanly.

| Sector | Symbols (ticker) | Shariah | Notes |
|--------|------------------|:-------:|-------|
| Islamic banks | MEBL (Meezan), BAHL (Bank AL-Habib), BAFL (Bank Al-Falah) | Yes | Win on high rates (fat NIMs); MEBL is the bellwether. |
| Conventional banks | UBL, MCB, HBL | No | Dividend leaders; only if clearly better and flag as conventional. |
| Power / Gencos | HUBC (Hub Power), KEL (K-Electric) | Yes | HUBC = high-yield defensive cash cow; KEL = growth, no dividend. |
| Fertilizer | ENGRO, EFERT, FFC (Fauji Fert), FATIMA | Yes | Domestic demand, defensive; ENGRO is diversified (fert/power/telecom). |
| Cement | LUCK (Lucky), DGKC, MLCF, FCCL | Yes | Cyclical; wins on growth budgets, infra, lower coal/fuel. |
| E&P (oil & gas) | MARI, OGDC, PPL, POL | Yes | Commodity-sensitive; MARI is gas-weighted so least crude-linked. |
| Oil marketing (OMC) | PSO, APL | Yes | Margin pressure when crude falls fast; watch inventory losses. |
| Tech / IT | SYS (Systems), AIRLINK, AVN (Avanceon) | verify | IT-export growth story; Shariah status varies, confirm per name. |
| Autos | INDU (Indus/Toyota), MTL (Millat), HCAR (Honda) | verify | Rate-sensitive demand; confirm Shariah. |
| Shariah ETF | MZNPETF (Meezan Pakistan ETF), NITGETF, UBLPETF | Yes (MZNPETF) | Passive index ballast; good near all-time highs. |

## Seed sites (polite, read-only)
Pass these to the a_sag_crawler agent; it discovers more itself.

- **PSX data portal** — https://dps.psx.com.pk/  (per-symbol: `https://dps.psx.com.pk/company/<SYM>`, ETF: `https://dps.psx.com.pk/etf/<SYM>`) — most authoritative live quote.
- **Sarmaaya** — https://sarmaaya.pk/stocks  — prices, yields, P/E, Shariah screen.
- **Mettis Global** — https://mettisglobal.news/  — market news, macro.
- **Business Recorder** — https://markets.brecorder.com/  — KSE-100 live, sector news.
- **Profit / Pakistan Today** — https://profit.pakistantoday.com.pk/  — analysis, broker views.
- **Trading Economics** — https://tradingeconomics.com/pakistan/  — macro series (rate, CPI, FX, reserves) + crude.
- **Investing.com** — https://www.investing.com/indices/karachi-100  — index + equities.
- **SBP** — https://www.sbp.org.pk/  — policy rate, reserves (official).
- **PSX Shariah list** — https://www.psx.com.pk/psx/resources-and-tools/shariah-compliant-investment

## Data-quality discipline
- Every price must be dated. A quote older than the current trading day is **stale** for sizing.
- Macro series lag (CPI ~3 weeks, reserves monthly, IMF reviews quarterly) — that is fine for context; label them with their date and do not call them "today".
- If a chosen name has no same-day quote, re-fetch it or swap it out. Never size on stale data.
