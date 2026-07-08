#!/usr/bin/env python3
"""Deterministic whole-share position sizer for a_r_l_psx_advisor.

Given free cash, a commission reserve, and a set of picks (symbol, live price,
target weight), compute EXACT whole-share unit counts that:
  - never exceed the investable budget (cash minus the commission reserve),
  - respect the target weights as closely as whole shares allow,
  - then greedily top up with the leftover so as little cash as possible sits idle.

This removes all arithmetic from the model so the unit counts are reproducible
and never an LLM guess. stdlib only.

Input: JSON on stdin (or a file path as argv[1]):
  {
    "cash": 200000,
    "commission_pct": 0.6,        # optional, default 0.6 (reserve for brokerage+fees+slippage)
    "picks": [
      {"symbol": "HUBC", "price": 234.49, "weight": 0.18, "why": "..."},
      ...
    ]
  }
Weights need not sum to 1; they are normalized. "why" is optional, echoed through.

Output: a markdown table + a JSON block on stdout. Exit 1 on bad input.
"""
import json
import sys


def load_input():
    if len(sys.argv) > 1 and sys.argv[1] not in ("-", ""):
        with open(sys.argv[1]) as f:
            return json.load(f)
    return json.load(sys.stdin)


def size(data):
    cash = float(data["cash"])
    commission_pct = float(data.get("commission_pct", 0.6))
    picks = data["picks"]
    if not picks:
        raise ValueError("no picks provided")
    for p in picks:
        if float(p["price"]) <= 0:
            raise ValueError(f"non-positive price for {p.get('symbol')}")

    budget = cash * (1.0 - commission_pct / 100.0)
    wsum = sum(float(p.get("weight", 0)) for p in picks)
    if wsum <= 0:
        # equal-weight fallback
        for p in picks:
            p["weight"] = 1.0 / len(picks)
        wsum = 1.0

    rows = []
    for p in picks:
        price = float(p["price"])
        w = float(p.get("weight", 0)) / wsum
        target_value = budget * w
        units = int(target_value // price)  # floor; never overshoot the target
        rows.append({
            "symbol": p["symbol"],
            "price": price,
            "weight": w,
            "target_value": target_value,
            "units": units,
            "why": p.get("why", ""),
        })

    def total_cost():
        return sum(r["units"] * r["price"] for r in rows)

    # Greedy top-up: spend the leftover on the most underweight affordable pick.
    # Bounded loop; each iteration either buys a share or breaks.
    guard = 0
    while guard < 100000:
        guard += 1
        remaining = budget - total_cost()
        affordable = [r for r in rows if r["price"] <= remaining]
        if not affordable:
            break
        # largest absolute PKR deficit vs its target; tie-break = cheaper share.
        affordable.sort(key=lambda r: (-(r["target_value"] - r["units"] * r["price"]), r["price"]))
        affordable[0]["units"] += 1

    invested = total_cost()
    leftover = cash - invested
    return rows, cash, commission_pct, budget, invested, leftover


def fmt(n):
    return f"{n:,.0f}"


def main():
    try:
        data = load_input()
        rows, cash, commission_pct, budget, invested, leftover = size(data)
    except Exception as e:  # noqa: BLE001 - surface any bad input plainly
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print("| Symbol | Price | Units | Cost (PKR) | Weight |")
    print("|--------|------:|------:|-----------:|-------:|")
    for r in rows:
        cost = r["units"] * r["price"]
        actual_w = (cost / invested * 100) if invested else 0
        print(f"| **{r['symbol']}** | {r['price']:.2f} | **{r['units']}** | "
              f"{fmt(cost)} | {actual_w:.1f}% |")
    print(f"| **TOTAL** | | | **{fmt(invested)}** | 100% |")
    print()
    print(f"Cash: {fmt(cash)} PKR | Invested: {fmt(invested)} PKR | "
          f"Leftover: {fmt(leftover)} PKR (reserve ~{commission_pct:.2f}% for commission + fees).")
    print()
    out = {
        "cash": cash,
        "commission_pct": commission_pct,
        "investable_budget": round(budget, 2),
        "invested": round(invested, 2),
        "leftover": round(leftover, 2),
        "positions": [
            {"symbol": r["symbol"], "price": r["price"], "units": r["units"],
             "cost": round(r["units"] * r["price"], 2), "why": r["why"]}
            for r in rows
        ],
    }
    print("```json")
    print(json.dumps(out, indent=2))
    print("```")


if __name__ == "__main__":
    main()
