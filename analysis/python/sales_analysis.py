"""
Sales Performance Analysis — Python Pipeline
=============================================
Builds the enriched fact table and every KPI used in the three dashboards.

Inputs (CSV):
  fact_table.csv          - one row per order line
  customers_table.csv     - Customer ID, name, Gender, Location, Date of Birth
  products_table.csv      - Product ID, name, Category, Sales Price, Cost Price
  sales_persons_table.csv - Sales Person ID, name, Store Name  (Sales Person ID == Store ID)
  monthly_store_targets.csv - Store ID, Month, Monthly Target

Run:  python sales_analysis.py /path/to/csv/folder
"""

import sys
import pandas as pd
import numpy as np

# ----------------------------------------------------------------------
# 1. LOAD
# ----------------------------------------------------------------------
def load_data(folder):
    f = lambda name: pd.read_csv(f"{folder.rstrip('/')}/{name}")
    fact = f("fact_table.csv")
    cust = f("customers_table.csv")
    prod = f("products_table.csv")
    sp   = f("sales_persons_table.csv")
    tgt  = f("monthly_store_targets.csv")

    fact["Order Date"]    = pd.to_datetime(fact["Order Date"])
    cust["Date of Birth"] = pd.to_datetime(cust["Date of Birth"])
    tgt["Month"]          = pd.to_datetime(tgt["Month"])

    # Both customers and sales persons carry "Date of Birth" -> avoid a merge collision
    cust = cust.rename(columns={"Date of Birth": "Cust DOB"})
    sp   = sp.drop(columns=["Date of Birth"])
    return fact, cust, prod, sp, tgt


# ----------------------------------------------------------------------
# 2. BUILD ENRICHED FACT TABLE
# ----------------------------------------------------------------------
def build_fact(fact, cust, prod, sp):
    df = (fact
          .merge(prod, on="Product ID",      how="left")
          .merge(cust, on="Customer ID",     how="left")
          .merge(sp,   on="Sales Person ID", how="left"))

    # Core money metrics. Revenue is on NET units (sold minus returned),
    # so returns are already reflected in revenue and profit.
    df["Net Quantity"]  = df["Quantity Sold"] - df["Quantity Returned"]
    df["Revenue"]       = df["Net Quantity"] * df["Sales Price"]
    df["COGS"]          = df["Net Quantity"] * df["Cost Price"]
    df["Profit"]        = df["Revenue"] - df["COGS"]
    df["Gross Revenue"] = df["Quantity Sold"] * df["Sales Price"]

    # Customer age as of end of the analysis year
    ref = pd.Timestamp("2023-12-31")
    df["Age"] = ((ref - df["Cust DOB"]).dt.days / 365.25).astype(int)
    bins   = [0, 25, 35, 45, 55, 65, 200]
    labels = ["Under 25", "25-34", "35-44", "45-54", "55-64", "65+"]
    df["Age Group"] = pd.cut(df["Age"], bins=bins, labels=labels, right=False)

    # Date dimensions
    df["Month"]      = df["Order Date"].dt.to_period("M").dt.to_timestamp()
    df["MonthName"]  = df["Order Date"].dt.strftime("%b")
    df["MonthNum"]   = df["Order Date"].dt.month
    df["Weekday"]    = df["Order Date"].dt.day_name()
    df["WeekdayNum"] = df["Order Date"].dt.weekday          # Mon=0 .. Sun=6
    df["Quarter"]    = "Q" + df["Order Date"].dt.quarter.astype(str)
    df["IsWeekend"]  = df["WeekdayNum"].isin([5, 6])
    df["Store Name"] = df["Store Name"].fillna("Unknown")
    return df


# ----------------------------------------------------------------------
# 3. DASHBOARD 1 — CUSTOMER & PRODUCT
# ----------------------------------------------------------------------
def customer_and_product(df):
    out = {}

    # Profit & revenue by gender
    out["gender"] = (df.groupby("Gender", observed=True)
                       .agg(Profit=("Profit", "sum"), Revenue=("Revenue", "sum"))
                       .reset_index())

    # Profit, revenue & average spend by age group
    age = (df.groupby("Age Group", observed=True)
             .agg(Profit=("Profit", "sum"),
                  Revenue=("Revenue", "sum"),
                  Orders=("Order Date", "count"))
             .reset_index())
    age["Avg Spend"] = age["Revenue"] / age["Orders"]
    out["age_group"] = age

    # Profitability over time + month-over-month growth
    ptime = (df.groupby("Month")
               .agg(Profit=("Profit", "sum"), Revenue=("Revenue", "sum"))
               .reset_index()
               .sort_values("Month"))
    ptime["MoM Growth"] = ptime["Profit"].pct_change().fillna(0)
    out["profit_over_time"] = ptime

    # Profit by weekday
    out["weekday"] = (df.groupby(["WeekdayNum", "Weekday"])
                        .agg(Profit=("Profit", "sum"))
                        .reset_index()
                        .sort_values("WeekdayNum"))

    # Product-level table -> top sellers, most profitable, highest return rate
    p = (df.groupby("Product Name")
           .agg(Profit=("Profit", "sum"),
                Revenue=("Revenue", "sum"),
                QtySold=("Quantity Sold", "sum"),
                QtyReturned=("Quantity Returned", "sum"))
           .reset_index())
    p["Return Rate"] = p["QtyReturned"] / p["QtySold"]
    out["top_profit"]  = p.sort_values("Profit",      ascending=False).head(10)
    out["top_selling"] = p.sort_values("QtySold",     ascending=False).head(10)
    out["top_returns"] = p.sort_values("Return Rate", ascending=False).head(10)
    return out


# ----------------------------------------------------------------------
# 4. DASHBOARD 2 — STORE BUDGET VS REVENUE
# ----------------------------------------------------------------------
def store_budget(df, sp, tgt):
    out = {}
    sp = sp.copy()
    sp["Store ID"] = sp["Sales Person ID"]   # 1:1 mapping in this dataset

    store_rev = (df.groupby("Store Name")
                   .agg(Revenue=("Revenue", "sum"))
                   .reset_index())
    store_tgt = (tgt.groupby("Store ID")
                    .agg(Target=("Monthly Target", "sum"))
                    .reset_index()
                    .merge(sp[["Store ID", "Store Name"]], on="Store ID"))

    bvr = store_rev.merge(store_tgt[["Store Name", "Target"]], on="Store Name", how="left")
    bvr["Variance"]     = bvr["Revenue"] - bvr["Target"]
    bvr["% to Target"]  = bvr["Revenue"] / bvr["Target"]
    out["store_bvr"] = bvr.sort_values("Revenue", ascending=False)

    # Month-by-month total revenue vs target
    month_rev = df.groupby("Month").agg(Revenue=("Revenue", "sum")).reset_index()
    month_tgt = tgt.groupby("Month").agg(Target=("Monthly Target", "sum")).reset_index()
    mbm = (month_rev.merge(month_tgt, on="Month", how="outer")
                    .sort_values("Month").fillna(0))
    mbm["Variance"] = mbm["Revenue"] - mbm["Target"]
    out["month_by_month"] = mbm
    return out


# ----------------------------------------------------------------------
# 5. DASHBOARD 3 — REVENUE ANALYSIS
# ----------------------------------------------------------------------
def revenue_analysis(df):
    out = {}

    # Quarterly revenue vs the quarterly average
    q = df.groupby("Quarter").agg(Revenue=("Revenue", "sum")).reset_index()
    q["Avg Revenue"] = q["Revenue"].mean()
    out["quarterly"] = q

    # Weekday vs weekend revenue
    ww = (df.groupby("IsWeekend")
            .agg(Revenue=("Revenue", "sum"))
            .reset_index())
    ww["Type"] = ww["IsWeekend"].map({True: "Weekend", False: "Weekday"})
    out["weekday_weekend"] = ww[["Type", "Revenue"]]

    # Monthly revenue vs target reuses the Dashboard-2 month-by-month table
    return out


# ----------------------------------------------------------------------
# 6. HEADLINE KPIs
# ----------------------------------------------------------------------
def headline_kpis(df):
    return {
        "Total Revenue":      df["Revenue"].sum(),
        "Total Profit":       df["Profit"].sum(),
        "Profit Margin":      df["Profit"].sum() / df["Revenue"].sum(),
        "Total Units Sold":   df["Quantity Sold"].sum(),
        "Total Returned":     df["Quantity Returned"].sum(),
        "Overall Return Rate": df["Quantity Returned"].sum() / df["Quantity Sold"].sum(),
    }


# ----------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------
def main(folder):
    fact, cust, prod, sp, tgt = load_data(folder)
    df = build_fact(fact, cust, prod, sp)

    kpis = headline_kpis(df)
    d1   = customer_and_product(df)
    d2   = store_budget(df, sp, tgt)
    d3   = revenue_analysis(df)

    print("\n=== HEADLINE KPIs ===")
    for k, v in kpis.items():
        print(f"  {k:<20} {v:,.2f}")

    print("\n=== Profit by Gender ===");        print(d1["gender"].to_string(index=False))
    print("\n=== Avg Spend by Age Group ===");  print(d1["age_group"].to_string(index=False))
    print("\n=== Store Revenue vs Target ===");  print(d2["store_bvr"].to_string(index=False))
    print("\n=== Quarterly Revenue ===");        print(d3["quarterly"].to_string(index=False))
    print("\n=== Weekday vs Weekend ===");       print(d3["weekday_weekend"].to_string(index=False))

    return df, kpis, d1, d2, d3


if __name__ == "__main__":
    folder = sys.argv[1] if len(sys.argv) > 1 else "."
    main(folder)
