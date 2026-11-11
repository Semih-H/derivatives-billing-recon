"""
Synthetic data generator for derivatives-billing-recon.
AI-assisted (generated with Claude). All companies, people and figures are fictional.
Run:  python generate_data.py   -> writes CSVs to ./data
"""
import os
import numpy as np
import pandas as pd

rng = np.random.default_rng(42)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
os.makedirs(OUT, exist_ok=True)
AS_OF = pd.Timestamp("2026-11-10")

# ---------------------------------------------------------------- reference data
clearers = pd.DataFrame({
    "clearer_code": ["NBS", "HAL", "MER", "TAR", "VAL"],
    "clearer_name": ["Northbridge Securities", "Halcyon Bank", "Meridian Capital Markets",
                     "Tamsin & Rowe", "Valemont Bank"],
    "payment_terms_days": [30, 30, 30, 30, 30],
})
weights = [0.30, 0.25, 0.20, 0.15, 0.10]

products = pd.DataFrame([
    # product_code, product_name, exchange, instrument_type, asset_class, rate
    ("SR3",  "3M SOFR Future",            "CME",   "Future", "Fixed income", 0.45),
    ("ZN",   "10Y T-Note Future",         "CME",   "Future", "Fixed income", 0.60),
    ("OZN",  "10Y T-Note Option",         "CME",   "Option", "Fixed income", 0.85),
    ("I",    "3M Euribor Future",         "ICE",   "Future", "Fixed income", 0.40),
    ("SO3",  "3M SONIA Future",           "ICE",   "Future", "Fixed income", 0.40),
    ("FGBL", "Euro-Bund Future",          "Eurex", "Future", "Fixed income", 0.55),
    ("OGBL", "Euro-Bund Option",          "Eurex", "Option", "Fixed income", 0.90),
    ("FESX", "Euro Stoxx 50 Future",      "Eurex", "Future", "Equity",       0.35),
    ("OESX", "Euro Stoxx 50 Option",      "Eurex", "Option", "Equity",       0.75),
], columns=["product_code", "product_name", "exchange", "instrument_type",
            "asset_class", "rate_per_contract_eur"])

accounts = {c: [f"{c}-ACC-{i:02d}" for i in range(1, 4)] for c in clearers.clearer_code}

# ---------------------------------------------------------------- internal trades
bdays = pd.bdate_range("2026-07-01", "2026-10-30")
N = 2000
t = pd.DataFrame({
    "trade_date": np.sort(rng.choice(bdays, N)),
    "clearer_code": rng.choice(clearers.clearer_code, N, p=weights),
    "product_code": rng.choice(products.product_code, N,
                               p=[.16, .12, .08, .14, .08, .14, .08, .12, .08]),
})
t["account"] = [rng.choice(accounts[c]) for c in t.clearer_code]
t["contracts"] = np.clip(np.round(rng.lognormal(5.0, 0.9, N) / 10) * 10, 10, 5000).astype(int)
t = t.merge(products[["product_code", "rate_per_contract_eur"]], on="product_code")
t = t.sort_values(["trade_date", "clearer_code"]).reset_index(drop=True)
t.insert(0, "trade_id", [f"T{d:%Y%m}{i:05d}" for i, d in zip(range(1, N + 1), t.trade_date)])
t["fee_eur"] = (t.contracts * t.rate_per_contract_eur).round(2)
internal = t[["trade_id", "trade_date", "clearer_code", "account", "product_code",
              "contracts", "rate_per_contract_eur", "fee_eur"]].copy()

# ---------------------------------------------------------------- clearer statement (with planted breaks)
stmt = internal.copy()
ids = rng.permutation(internal.trade_id.values)
plan = {"MISSING_IN_CLEARER": 20, "QTY_MISMATCH": 15, "RATE_MISMATCH": 20, "REALLOCATION": 15}
key_rows, pos = [], 0
picked = {}
for k, n in plan.items():
    picked[k] = ids[pos:pos + n]; pos += n

stmt = stmt.set_index("trade_id")
for tid in picked["QTY_MISMATCH"]:
    old = stmt.at[tid, "contracts"]
    new = int(old + rng.choice([-1, 1]) * max(10, round(old * rng.uniform(.1, .5) / 10) * 10))
    new = max(new, 10) if new != old else old + 10
    stmt.at[tid, "contracts"] = new
    key_rows.append((tid, "QTY_MISMATCH", f"internal {old} vs clearer {new} contracts"))
for tid in picked["RATE_MISMATCH"]:
    old = stmt.at[tid, "rate_per_contract_eur"]
    new = round(old - rng.choice([0.05, 0.10, 0.15]), 2)
    stmt.at[tid, "rate_per_contract_eur"] = new
    key_rows.append((tid, "RATE_MISMATCH", f"internal {old:.2f} vs clearer {new:.2f} EUR/contract"))
for i, tid in enumerate(picked["REALLOCATION"]):
    c, a = stmt.at[tid, "clearer_code"], stmt.at[tid, "account"]
    if i < 9:   # moved to another account at the same clearer
        new_a = rng.choice([x for x in accounts[c] if x != a])
        stmt.at[tid, "account"] = new_a
        key_rows.append((tid, "REALLOCATION", f"account {a} -> {new_a} (same clearer)"))
    else:       # given up to a different clearer
        new_c = rng.choice([x for x in clearers.clearer_code if x != c])
        new_a = rng.choice(accounts[new_c])
        stmt.at[tid, "clearer_code"], stmt.at[tid, "account"] = new_c, new_a
        key_rows.append((tid, "REALLOCATION", f"clearer {c}/{a} -> {new_c}/{new_a}"))
stmt["fee_eur"] = (stmt.contracts * stmt.rate_per_contract_eur).round(2)
for tid in picked["MISSING_IN_CLEARER"]:
    key_rows.append((tid, "MISSING_IN_CLEARER", "on internal blotter, not on clearer statement"))
stmt = stmt.drop(index=picked["MISSING_IN_CLEARER"]).reset_index()

# trades on the clearer statement that we never booked
extra = internal.sample(10, random_state=7).copy()
extra["trade_id"] = [f"X{d:%Y%m}{90000 + i}" for i, d in enumerate(extra.trade_date)]
for tid in extra.trade_id:
    key_rows.append((tid, "MISSING_INTERNAL", "on clearer statement, not on internal blotter"))
stmt = pd.concat([stmt, extra], ignore_index=True).sort_values(["trade_date", "trade_id"])
stmt.insert(0, "stmt_line_id", [f"S{i:06d}" for i in range(1, len(stmt) + 1)])
stmt = stmt[["stmt_line_id", "trade_id", "trade_date", "clearer_code", "account",
             "product_code", "contracts", "rate_per_contract_eur", "fee_eur"]]

answer_trades = pd.DataFrame(key_rows, columns=["trade_id", "break_type", "detail"]).sort_values("trade_id")

# ---------------------------------------------------------------- invoices (billed from internal blotter)
issue = {"2026-07": "2026-08-03", "2026-08": "2026-09-01", "2026-09": "2026-10-01", "2026-10": "2026-11-02"}
internal["billing_month"] = internal.trade_date.dt.strftime("%Y-%m")
inv = internal.groupby(["clearer_code", "billing_month"], as_index=False).agg(
    trade_count=("trade_id", "count"), amount_eur=("fee_eur", "sum"))
inv["amount_eur"] = inv.amount_eur.round(2)
inv["issue_date"] = pd.to_datetime(inv.billing_month.map(issue))
inv["due_date"] = inv.issue_date + pd.Timedelta(days=30)
inv.insert(0, "invoice_id", "INV-" + inv.billing_month.str.replace("-", "") + "-" + inv.clearer_code)
inv = inv[["invoice_id", "clearer_code", "billing_month", "trade_count", "amount_eur", "issue_date", "due_date"]]
internal = internal.drop(columns="billing_month")
A = inv.set_index("invoice_id").amount_eur

# ---------------------------------------------------------------- payments (cash received)
P = []
def pay(inv_id, date, amount, ref=None):
    P.append((inv_id if ref is None else ref, date, round(amount, 2)))
cash_key = []
for c in ["NBS", "HAL", "MER", "VAL"]:
    pay(f"INV-202607-{c}", ["2026-08-28", "2026-09-01", "2026-08-31", "2026-09-02"][["NBS", "HAL", "MER", "VAL"].index(c)], A[f"INV-202607-{c}"])
short = round(A["INV-202607-TAR"] * 0.06, 2)
pay("INV-202607-TAR", "2026-09-02", A["INV-202607-TAR"] - short)
cash_key.append(("INV-202607-TAR", "SHORT_PAID", f"paid {A['INV-202607-TAR'] - short:.2f} of {A['INV-202607-TAR']:.2f}; clearer disputes Eurex option rates"))
pay("INV-202608-NBS", "2026-09-29", A["INV-202608-NBS"])
pay("INV-202608-HAL", "2026-10-20", A["INV-202608-HAL"])
cash_key.append(("INV-202608-HAL", "PAID_LATE", "due 2026-10-01, paid 2026-10-20 (promise kept)"))
cash_key.append(("INV-202608-MER", "UNPAID_OVERDUE", "nothing received; promise for 2026-10-20 broken"))
pay("INV-202608-TAR", "2026-09-30", A["INV-202608-TAR"])
half = round(A["INV-202608-VAL"] * 0.5, 2)
pay("INV-202608-VAL", "2026-10-15", half)
cash_key.append(("INV-202608-VAL", "SHORT_PAID", f"one instalment of {half:.2f} received; promised full payment by 2026-10-15 (broken)"))
pay("INV-202609-NBS", "2026-10-30", A["INV-202609-NBS"])
pay(None, "2026-11-05", A["INV-202609-HAL"], ref="")   # unapplied cash, no reference
cash_key.append(("INV-202609-HAL", "UNAPPLIED_CASH_MATCH", "looks unpaid, but unreferenced payment of the exact amount arrived 2026-11-05"))
cash_key.append(("INV-202609-MER", "UNPAID_OVERDUE", "nothing received"))
pay("INV-202609-TAR", "2026-10-29", A["INV-202609-TAR"])
cash_key.append(("INV-202609-VAL", "UNPAID_OVERDUE", "nothing received; open promise for 2026-11-15 (not yet broken)"))
pay("INV-202610-NBS", "2026-11-09", A["INV-202610-NBS"])
pays = pd.DataFrame(P, columns=["invoice_id", "payment_date", "amount_eur"])
pays["clearer_code"] = pays.invoice_id.str[-3:]
pays.loc[pays.invoice_id == "", "clearer_code"] = "HAL"
pays.insert(0, "payment_id", [f"PAY-{i:04d}" for i in range(1, len(pays) + 1)])
pays["payment_reference"] = np.where(pays.invoice_id == "", "HALCYON BANK FEES SETTLEMENT", pays.invoice_id)
pays = pays[["payment_id", "clearer_code", "invoice_id", "payment_reference", "payment_date", "amount_eur"]]
unapplied_id = pays.loc[pays.invoice_id == "", "payment_id"].iloc[0]
cash_key.append((unapplied_id, "UNAPPLIED_CASH", "payment with no invoice reference; amount matches INV-202609-HAL"))

# ---------------------------------------------------------------- collection log
L = [
    ("TAR", "INV-202607-TAR", "2026-09-08", "Email", "Priya Nandakumar", "Disputed",
     "", "", "Short-paid; says Eurex option rates differ from their schedule"),
    ("HAL", "INV-202608-HAL", "2026-10-06", "Call", "Oskar Lind", "Promised",
     "2026-10-20", A["INV-202608-HAL"], "Approval delayed internally"),
    ("MER", "INV-202608-MER", "2026-10-05", "Call", "Daniel Okafor", "Promised",
     "2026-10-20", A["INV-202608-MER"], "Will pay in next payment run"),
    ("VAL", "INV-202608-VAL", "2026-10-08", "Call", "Marta Kowalczyk", "Promised",
     "2026-10-15", A["INV-202608-VAL"], "Promised full amount"),
    ("MER", "INV-202608-MER", "2026-10-23", "Email", "Daniel Okafor", "No response", "", "", "Reminder sent"),
    ("MER", "INV-202609-MER", "2026-11-03", "Email", "Daniel Okafor", "No response", "", "", "Reminder sent"),
    ("HAL", "INV-202609-HAL", "2026-11-03", "Call", "Oskar Lind", "Says paid",
     "", "", "Says payment sent 2026-11-05 without invoice reference"),
    ("VAL", "INV-202609-VAL", "2026-11-04", "Call", "Marta Kowalczyk", "Promised",
     "2026-11-15", A["INV-202609-VAL"], "Promised full amount"),
]
log = pd.DataFrame(L, columns=["clearer_code", "invoice_id", "contact_date", "channel", "contact_person",
                               "outcome", "promised_date", "promised_amount_eur", "notes"])
log.insert(0, "log_id", [f"LOG-{i:03d}" for i in range(1, len(log) + 1)])
log["promised_amount_eur"] = log.promised_amount_eur.apply(lambda x: f"{x:.2f}" if x != "" else "")
cash_key += [("INV-202608-MER", "BROKEN_PROMISE", "promised 2026-10-20, nothing received"),
             ("INV-202608-VAL", "BROKEN_PROMISE", "promised full amount by 2026-10-15, only half received")]
answer_cash = pd.DataFrame(cash_key, columns=["item_id", "issue_type", "detail"])

# ---------------------------------------------------------------- write
def w(df, name):
    df = df.copy()
    for col in df.columns:
        if pd.api.types.is_datetime64_any_dtype(df[col]):
            df[col] = df[col].dt.strftime("%Y-%m-%d")
    df.to_csv(os.path.join(OUT, name), index=False)
w(clearers, "clearers.csv"); w(products, "rate_card.csv")
w(internal, "internal_trades.csv"); w(stmt, "clearer_statement.csv")
w(inv, "invoices.csv"); w(pays, "payments.csv"); w(log, "collection_log.csv")
w(answer_trades, "answer_key_trades.csv"); w(answer_cash, "answer_key_cash.csv")
print("as of", AS_OF.date(), "| trades", len(internal), "| stmt", len(stmt), "| invoices", len(inv),
      "| payments", len(pays), "| log", len(log), "| trade breaks", len(answer_trades), "| cash items", len(answer_cash))
