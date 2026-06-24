# Excel Formula Reference — Sales Performance Dashboard

This documents every calculation in the workbook. The **Data** sheet holds the enriched
transaction table; the **Calc** sheet holds the aggregations; the three dashboards chart
the Calc tables. All metrics use live formulas, so editing the Data sheet recalculates
everything.

---

## Data sheet — derived row-level columns

Columns A–H are dimensions; I–P are values. Assuming a header in row 1 and data in rows
2..N (N = 20001 for this dataset):

| Column | Metric | Formula (row 2, fill down) |
|---|---|---|
| K | Net Quantity | `=I2-J2`  (Quantity Sold − Quantity Returned) |
| N | Revenue | `=K2*L2`  (Net Quantity × Sales Price) |
| O | COGS | `=K2*M2`  (Net Quantity × Cost Price) |
| P | Profit | `=N2-O2`  (Revenue − COGS) |

Dimension helpers (if rebuilding from the raw join):

| Metric | Formula |
|---|---|
| Weekday name | `=TEXT(A2,"dddd")` |
| Quarter | `="Q"&ROUNDUP(MONTH(A2)/3,0)` |
| Month label | `=TEXT(A2,"mmm")` |
| Customer age | `=DATEDIF(DOB,DATE(2023,12,31),"Y")` |
| Age group | `=LOOKUP(Age,{0;25;35;45;55;65},{"Under 25";"25-34";"35-44";"45-54";"55-64";"65+"})` |

---

## Headline KPIs

| KPI | Formula |
|---|---|
| Total Revenue | `=SUM(Data!N2:N20001)` |
| Total Profit | `=SUM(Data!P2:P20001)` |
| Profit Margin | `=SUM(Data!P2:P20001)/SUM(Data!N2:N20001)` |
| Total Units Sold | `=SUM(Data!I2:I20001)` |
| Overall Return Rate | `=SUM(Data!J2:J20001)/SUM(Data!I2:I20001)` |

---

## Dashboard 1 — Customer & Product

**Profit / Revenue by Gender** (one row per gender, label in A):
```
Profit   =SUMIF(Data!$D$2:$D$20001, A2, Data!$P$2:$P$20001)
Revenue  =SUMIF(Data!$D$2:$D$20001, A2, Data!$N$2:$N$20001)
```

**By Age Group** (label in A):
```
Profit     =SUMIF(Data!$E$2:$E$20001, A2, Data!$P$2:$P$20001)
Revenue    =SUMIF(Data!$E$2:$E$20001, A2, Data!$N$2:$N$20001)
Orders     =COUNTIF(Data!$E$2:$E$20001, A2)
Avg Spend  =IF(D2=0, 0, C2/D2)        ' Revenue / Orders
```

**Profit over time** (one row per month, month number implied by row order):
```
Profit      =SUMPRODUCT((MONTH(Data!$A$2:$A$20001)=1)*Data!$P$2:$P$20001)   ' change 1 -> month #
Revenue     =SUMPRODUCT((MONTH(Data!$A$2:$A$20001)=1)*Data!$N$2:$N$20001)
MoM Growth  =IF(C2=0, 0, (C3-C2)/C2)  ' current month profit vs prior month
```

**Profit by Weekday** (weekday name in A):
```
=SUMIF(Data!$G$2:$G$20001, A2, Data!$P$2:$P$20001)
```

**Top products** (product name in A):
```
Profit       =SUMIF(Data!$B$2:$B$20001, A2, Data!$P$2:$P$20001)
Units Sold   =SUMIF(Data!$B$2:$B$20001, A2, Data!$I$2:$I$20001)
Units Ret.   =SUMIF(Data!$B$2:$B$20001, A2, Data!$J$2:$J$20001)
Return Rate  =IF(B2=0, 0, C2/B2)      ' Units Returned / Units Sold
```
Ranking is done by sorting these helper tables; for a self-ranking version use
`=LARGE(range, k)` with `INDEX/MATCH` to pull the matching product name.

---

## Dashboard 2 — Store Budget vs Revenue

Store name in A; annual Target is the sum of the 12 monthly targets per store (an input).
```
Revenue      =SUMIF(Data!$F$2:$F$20001, A2, Data!$N$2:$N$20001)
Target       (input: =SUM of that store's 12 monthly targets)
Variance     =B2-C2                   ' Revenue − Target
% to Target  =IF(C2=0, 0, B2/C2)
```

Headline tiles:
```
Total Variance       =SUM(VarianceColumn)
Stores Above Target  =COUNTIF(VarianceColumn, ">0")
```

**Month-by-month total** (month number by row):
```
Revenue   =SUMPRODUCT((MONTH(Data!$A$2:$A$20001)=1)*Data!$N$2:$N$20001)
Target    (input: sum of all stores' target for that month)
Variance  =B2-C2
```

---

## Dashboard 3 — Revenue Analysis

**Quarterly revenue vs average** (quarter label "Q1".. in A):
```
Revenue       =SUMIF(Data!$H$2:$H$20001, A2, Data!$N$2:$N$20001)
Avg Revenue   =AVERAGE(QuarterRevenueRange)
```

**Weekday vs Weekend revenue:**
```
Weekend   =SUMIF(Data!$G$2:$G$20001,"Saturday",Data!$N$2:$N$20001)
         + SUMIF(Data!$G$2:$G$20001,"Sunday",  Data!$N$2:$N$20001)
Weekday   =SUM(Data!$N$2:$N$20001) - WeekendValue
```

**Monthly revenue vs target** — reuses the Dashboard-2 month-by-month table.

---

## Notes & assumptions

- **Revenue is on net units** (sold − returned), so returns are already netted out of revenue
  and profit. If you want gross revenue instead, use `Quantity Sold × Sales Price`.
- **Store mapping:** the fact table has no store key, so each Sales Person ID is treated as
  its Store ID (a clean 1:1 in this data). Store revenue is summed via the sales person's
  store name.
- **Age** is computed as of 31 Dec 2023.
- Replace `20001` with your actual last data row if the dataset size changes. Converting the
  Data range to an Excel **Table** (`Ctrl+T`) lets you use structured references like
  `Sales[Profit]` that auto-expand, removing the hardcoded row count.
```
