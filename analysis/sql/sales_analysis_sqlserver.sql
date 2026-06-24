/*======================================================================
  Sales Performance Analysis  —  Microsoft SQL Server (T-SQL)
  ----------------------------------------------------------------------
  Reproduces the enriched fact table and every KPI in the three
  dashboards.

  Assumptions baked into the model:
    * Revenue is on NET units (sold - returned); returns are netted out
      of revenue and profit.
    * The fact table has no store key, so each Sales Person ID is treated
      as its Store ID (a clean 1:1 in this dataset). Store revenue is
      attributed via the sales person's store.
    * Customer age is computed as of 2023-12-31.

  Sections:
    0. Schema + bulk load
    1. Enriched fact view  (vSales)
    2. Headline KPIs
    3. Dashboard 1 - Customer & Product
    4. Dashboard 2 - Store Budget vs Revenue
    5. Dashboard 3 - Revenue Analysis
======================================================================*/


/*----------------------------------------------------------------------
  0.  SCHEMA + BULK LOAD
      Adjust the file paths in the BULK INSERT statements to wherever the
      CSVs live on the SQL Server host. FORMAT='CSV' + FIRSTROW=2 skips
      the header row.
----------------------------------------------------------------------*/
IF OBJECT_ID('dbo.fact_table')           IS NOT NULL DROP TABLE dbo.fact_table;
IF OBJECT_ID('dbo.customers_table')      IS NOT NULL DROP TABLE dbo.customers_table;
IF OBJECT_ID('dbo.products_table')       IS NOT NULL DROP TABLE dbo.products_table;
IF OBJECT_ID('dbo.sales_persons_table')  IS NOT NULL DROP TABLE dbo.sales_persons_table;
IF OBJECT_ID('dbo.monthly_store_targets') IS NOT NULL DROP TABLE dbo.monthly_store_targets;
GO

CREATE TABLE dbo.products_table (
    ProductID     INT          PRIMARY KEY,
    ProductName   NVARCHAR(100),
    Category      NVARCHAR(60),
    SalesPrice    DECIMAL(10,2),
    CostPrice     DECIMAL(10,2)
);

CREATE TABLE dbo.customers_table (
    CustomerID    INT          PRIMARY KEY,
    FirstName     NVARCHAR(60),
    LastName      NVARCHAR(60),
    Gender        NVARCHAR(10),
    Location      NVARCHAR(60),
    DateOfBirth   DATE
);

CREATE TABLE dbo.sales_persons_table (
    SalesPersonID INT          PRIMARY KEY,
    FirstName     NVARCHAR(60),
    LastName      NVARCHAR(60),
    StoreName     NVARCHAR(60),
    DateOfBirth   DATE
);

CREATE TABLE dbo.fact_table (
    ProductID        INT,
    CustomerID       INT,
    SalesPersonID    INT,
    QuantitySold     INT,
    PaymentMethod    NVARCHAR(30),
    QuantityReturned INT,
    OrderDate        DATE
);

CREATE TABLE dbo.monthly_store_targets (
    StoreID       INT,
    MonthDate     DATE,
    MonthlyTarget DECIMAL(14,2)
);
GO

/*  Example bulk loads — edit paths to match your server.
BULK INSERT dbo.products_table        FROM 'C:\data\products_table.csv'        WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');
BULK INSERT dbo.customers_table       FROM 'C:\data\customers_table.csv'       WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');
BULK INSERT dbo.sales_persons_table   FROM 'C:\data\sales_persons_table.csv'   WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');
BULK INSERT dbo.fact_table            FROM 'C:\data\fact_table.csv'            WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');
BULK INSERT dbo.monthly_store_targets FROM 'C:\data\monthly_store_targets.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');
*/
GO


/*----------------------------------------------------------------------
  1.  ENRICHED FACT VIEW  (vSales)
      One row per order line with all money + date dimensions.
----------------------------------------------------------------------*/
IF OBJECT_ID('dbo.vSales') IS NOT NULL DROP VIEW dbo.vSales;
GO
CREATE VIEW dbo.vSales AS
SELECT
    f.OrderDate,
    p.ProductName,
    p.Category,
    c.Gender,
    sp.StoreName,
    f.SalesPersonID                                   AS StoreID,
    f.QuantitySold,
    f.QuantityReturned,
    (f.QuantitySold - f.QuantityReturned)             AS NetQuantity,
    p.SalesPrice,
    p.CostPrice,
    /* Money metrics on NET units */
    CAST((f.QuantitySold - f.QuantityReturned) * p.SalesPrice AS DECIMAL(14,2)) AS Revenue,
    CAST((f.QuantitySold - f.QuantityReturned) * p.CostPrice  AS DECIMAL(14,2)) AS COGS,
    CAST((f.QuantitySold - f.QuantityReturned) * (p.SalesPrice - p.CostPrice) AS DECIMAL(14,2)) AS Profit,
    /* Date dimensions */
    DATEFROMPARTS(YEAR(f.OrderDate), MONTH(f.OrderDate), 1)        AS MonthStart,
    MONTH(f.OrderDate)                                            AS MonthNum,
    DATENAME(MONTH, f.OrderDate)                                  AS MonthName,
    DATEPART(QUARTER, f.OrderDate)                                AS QuarterNum,
    'Q' + CAST(DATEPART(QUARTER, f.OrderDate) AS VARCHAR(1))      AS Quarter,
    DATENAME(WEEKDAY, f.OrderDate)                               AS Weekday,
    CASE WHEN DATENAME(WEEKDAY, f.OrderDate) IN ('Saturday','Sunday')
         THEN 1 ELSE 0 END                                       AS IsWeekend,
    /* Customer age as of 2023-12-31 (whole years) + age band */
    CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31'), c.DateOfBirth) > '2023-12-31'
         THEN DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') - 1
         ELSE DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') END    AS Age,
    CASE
        WHEN (CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31'), c.DateOfBirth) > '2023-12-31'
                   THEN DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') - 1
                   ELSE DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') END) < 25 THEN 'Under 25'
        WHEN (CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31'), c.DateOfBirth) > '2023-12-31'
                   THEN DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') - 1
                   ELSE DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') END) < 35 THEN '25-34'
        WHEN (CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31'), c.DateOfBirth) > '2023-12-31'
                   THEN DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') - 1
                   ELSE DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') END) < 45 THEN '35-44'
        WHEN (CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31'), c.DateOfBirth) > '2023-12-31'
                   THEN DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') - 1
                   ELSE DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') END) < 55 THEN '45-54'
        WHEN (CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31'), c.DateOfBirth) > '2023-12-31'
                   THEN DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') - 1
                   ELSE DATEDIFF(YEAR, c.DateOfBirth, '2023-12-31') END) < 65 THEN '55-64'
        ELSE '65+'
    END                                                          AS AgeGroup
FROM dbo.fact_table f
JOIN dbo.products_table      p  ON p.ProductID     = f.ProductID
JOIN dbo.customers_table     c  ON c.CustomerID    = f.CustomerID
JOIN dbo.sales_persons_table sp ON sp.SalesPersonID = f.SalesPersonID;
GO


/*----------------------------------------------------------------------
  2.  HEADLINE KPIs
----------------------------------------------------------------------*/
SELECT
    SUM(Revenue)                              AS TotalRevenue,
    SUM(Profit)                               AS TotalProfit,
    CAST(SUM(Profit)*1.0 / NULLIF(SUM(Revenue),0) AS DECIMAL(5,4)) AS ProfitMargin,
    SUM(QuantitySold)                         AS TotalUnitsSold,
    SUM(QuantityReturned)                     AS TotalReturned,
    CAST(SUM(QuantityReturned)*1.0 / NULLIF(SUM(QuantitySold),0) AS DECIMAL(5,4)) AS ReturnRate
FROM dbo.vSales;
GO


/*----------------------------------------------------------------------
  3.  DASHBOARD 1 — CUSTOMER & PRODUCT
----------------------------------------------------------------------*/

-- 3a. Profit & revenue by gender
SELECT Gender, SUM(Profit) AS Profit, SUM(Revenue) AS Revenue
FROM dbo.vSales
GROUP BY Gender
ORDER BY Gender;

-- 3b. Profit, revenue, orders & average spend by age group
SELECT
    AgeGroup,
    SUM(Profit)                                       AS Profit,
    SUM(Revenue)                                      AS Revenue,
    COUNT(*)                                          AS Orders,
    CAST(SUM(Revenue)*1.0 / NULLIF(COUNT(*),0) AS DECIMAL(12,2)) AS AvgSpend
FROM dbo.vSales
GROUP BY AgeGroup,
         CASE AgeGroup WHEN 'Under 25' THEN 1 WHEN '25-34' THEN 2 WHEN '35-44' THEN 3
                       WHEN '45-54' THEN 4 WHEN '55-64' THEN 5 ELSE 6 END
ORDER BY CASE AgeGroup WHEN 'Under 25' THEN 1 WHEN '25-34' THEN 2 WHEN '35-44' THEN 3
                       WHEN '45-54' THEN 4 WHEN '55-64' THEN 5 ELSE 6 END;

-- 3c. Profitability over time + month-over-month growth (window function)
WITH m AS (
    SELECT MonthStart, MIN(MonthName) AS MonthName,
           SUM(Profit) AS Profit, SUM(Revenue) AS Revenue
    FROM dbo.vSales
    GROUP BY MonthStart
)
SELECT
    MonthStart, MonthName, Profit, Revenue,
    CAST( (Profit - LAG(Profit) OVER (ORDER BY MonthStart))
          / NULLIF(LAG(Profit) OVER (ORDER BY MonthStart),0) AS DECIMAL(8,4)) AS MoMGrowth
FROM m
ORDER BY MonthStart;

-- 3d. Profit by weekday (ordered Mon -> Sun, independent of DATEFIRST)
SELECT
    DATENAME(WEEKDAY, OrderDate) AS Weekday,
    SUM(Profit)                  AS Profit
FROM dbo.vSales
GROUP BY DATENAME(WEEKDAY, OrderDate),
         (DATEPART(WEEKDAY, OrderDate) + @@DATEFIRST - 2) % 7   -- 0=Mon .. 6=Sun
ORDER BY MIN((DATEPART(WEEKDAY, OrderDate) + @@DATEFIRST - 2) % 7);

-- 3e. Top 10 products by profit
SELECT TOP (10) ProductName,
       SUM(Profit)  AS Profit,
       SUM(Revenue) AS Revenue
FROM dbo.vSales
GROUP BY ProductName
ORDER BY SUM(Profit) DESC;

-- 3f. Top 10 best-selling products (units)
SELECT TOP (10) ProductName, SUM(QuantitySold) AS UnitsSold
FROM dbo.vSales
GROUP BY ProductName
ORDER BY SUM(QuantitySold) DESC;

-- 3g. Top 10 products by return rate
SELECT TOP (10)
    ProductName,
    SUM(QuantitySold)     AS UnitsSold,
    SUM(QuantityReturned) AS UnitsReturned,
    CAST(SUM(QuantityReturned)*1.0 / NULLIF(SUM(QuantitySold),0) AS DECIMAL(6,4)) AS ReturnRate
FROM dbo.vSales
GROUP BY ProductName
ORDER BY SUM(QuantityReturned)*1.0 / NULLIF(SUM(QuantitySold),0) DESC;
GO


/*----------------------------------------------------------------------
  4.  DASHBOARD 2 — STORE BUDGET VS REVENUE
----------------------------------------------------------------------*/

-- 4a. Store revenue vs annual target (+ variance and % to target)
WITH rev AS (
    SELECT StoreName, StoreID, SUM(Revenue) AS Revenue
    FROM dbo.vSales GROUP BY StoreName, StoreID
),
tgt AS (
    SELECT t.StoreID, SUM(t.MonthlyTarget) AS Target
    FROM dbo.monthly_store_targets t GROUP BY t.StoreID
)
SELECT
    r.StoreName,
    r.Revenue,
    g.Target,
    (r.Revenue - g.Target)                                   AS Variance,
    CAST(r.Revenue*1.0 / NULLIF(g.Target,0) AS DECIMAL(6,4)) AS PctToTarget
FROM rev r
JOIN tgt g ON g.StoreID = r.StoreID
ORDER BY r.Revenue DESC;

-- 4b. Month-by-month total revenue vs target
WITH rev AS (
    SELECT MonthStart, SUM(Revenue) AS Revenue
    FROM dbo.vSales GROUP BY MonthStart
),
tgt AS (
    SELECT DATEFROMPARTS(YEAR(MonthDate), MONTH(MonthDate), 1) AS MonthStart,
           SUM(MonthlyTarget) AS Target
    FROM dbo.monthly_store_targets
    GROUP BY DATEFROMPARTS(YEAR(MonthDate), MONTH(MonthDate), 1)
)
SELECT
    COALESCE(rev.MonthStart, tgt.MonthStart) AS MonthStart,
    ISNULL(rev.Revenue, 0)                   AS Revenue,
    ISNULL(tgt.Target, 0)                    AS Target,
    ISNULL(rev.Revenue,0) - ISNULL(tgt.Target,0) AS Variance
FROM rev
FULL OUTER JOIN tgt ON tgt.MonthStart = rev.MonthStart
ORDER BY MonthStart;
GO


/*----------------------------------------------------------------------
  5.  DASHBOARD 3 — REVENUE ANALYSIS
----------------------------------------------------------------------*/

-- 5a. Quarterly revenue vs the quarterly average (window AVG over all quarters)
WITH q AS (
    SELECT Quarter, SUM(Revenue) AS Revenue
    FROM dbo.vSales GROUP BY Quarter
)
SELECT
    Quarter,
    Revenue,
    AVG(Revenue) OVER () AS AvgQuarterRevenue,
    Revenue - AVG(Revenue) OVER () AS VarianceVsAvg
FROM q
ORDER BY Quarter;

-- 5b. Weekday vs weekend revenue
SELECT
    CASE WHEN IsWeekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS DayType,
    SUM(Revenue) AS Revenue
FROM dbo.vSales
GROUP BY IsWeekend
ORDER BY DayType;

-- 5c. Monthly revenue vs target — same query as 4b (reused by Dashboard 3)
GO
