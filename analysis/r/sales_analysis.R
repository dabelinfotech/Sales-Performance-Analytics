# =====================================================================
# Sales Performance Analysis  —  R
# ---------------------------------------------------------------------
# Reproduces the enriched fact table and every KPI in the three
# dashboards using the tidyverse.
#
# Assumptions:
#   * Revenue is on NET units (sold - returned).
#   * Each Sales Person ID is treated as its Store ID (1:1 here);
#     store revenue is attributed via the sales person's store.
#   * Customer age is computed as of 2023-12-31.
#
# Usage:  Rscript sales_analysis.R /path/to/csv/folder
# =====================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
  library(tidyr)
})

args   <- commandArgs(trailingOnly = TRUE)
folder <- if (length(args) >= 1) args[1] else "."
fp     <- function(name) file.path(folder, name)

# ---------------------------------------------------------------------
# 1. LOAD
# ---------------------------------------------------------------------
fact <- read_csv(fp("fact_table.csv"),           show_col_types = FALSE)
cust <- read_csv(fp("customers_table.csv"),      show_col_types = FALSE)
prod <- read_csv(fp("products_table.csv"),       show_col_types = FALSE)
sp   <- read_csv(fp("sales_persons_table.csv"),  show_col_types = FALSE)
tgt  <- read_csv(fp("monthly_store_targets.csv"),show_col_types = FALSE)

fact <- fact %>% mutate(`Order Date` = mdy(`Order Date`))
cust <- cust %>% mutate(`Date of Birth` = mdy(`Date of Birth`)) %>%
  rename(`Cust DOB` = `Date of Birth`)
sp   <- sp %>% select(-`Date of Birth`)
tgt  <- tgt %>% mutate(Month = mdy(Month))

# ---------------------------------------------------------------------
# 2. ENRICHED FACT TABLE
# ---------------------------------------------------------------------
ref_date <- as.Date("2023-12-31")

df <- fact %>%
  left_join(prod, by = "Product ID") %>%
  left_join(cust, by = "Customer ID") %>%
  left_join(sp,   by = "Sales Person ID") %>%
  mutate(
    `Net Quantity` = `Quantity Sold` - `Quantity Returned`,
    Revenue        = `Net Quantity` * `Sales Price`,
    COGS           = `Net Quantity` * `Cost Price`,
    Profit         = Revenue - COGS,
    Age            = as.integer(floor(as.numeric(ref_date - `Cust DOB`) / 365.25)),
    `Age Group`    = cut(Age,
                         breaks = c(0, 25, 35, 45, 55, 65, Inf),
                         labels = c("Under 25","25-34","35-44","45-54","55-64","65+"),
                         right  = FALSE),
    MonthStart = floor_date(`Order Date`, "month"),
    MonthName  = month(`Order Date`, label = TRUE, abbr = TRUE),
    MonthNum   = month(`Order Date`),
    Weekday    = wday(`Order Date`, label = TRUE, abbr = FALSE, week_start = 1),
    Quarter    = paste0("Q", quarter(`Order Date`)),
    IsWeekend  = wday(`Order Date`, week_start = 1) >= 6,
    `Store Name` = coalesce(`Store Name`, "Unknown")
  )

# ---------------------------------------------------------------------
# 3. HEADLINE KPIs
# ---------------------------------------------------------------------
kpis <- df %>% summarise(
  `Total Revenue`      = sum(Revenue),
  `Total Profit`       = sum(Profit),
  `Profit Margin`      = sum(Profit) / sum(Revenue),
  `Total Units Sold`   = sum(`Quantity Sold`),
  `Total Returned`     = sum(`Quantity Returned`),
  `Overall Return Rate`= sum(`Quantity Returned`) / sum(`Quantity Sold`)
)

# ---------------------------------------------------------------------
# 4. DASHBOARD 1 — CUSTOMER & PRODUCT
# ---------------------------------------------------------------------
d1_gender <- df %>%
  group_by(Gender) %>%
  summarise(Profit = sum(Profit), Revenue = sum(Revenue), .groups = "drop")

d1_age <- df %>%
  group_by(`Age Group`) %>%
  summarise(Profit = sum(Profit), Revenue = sum(Revenue),
            Orders = n(), .groups = "drop") %>%
  mutate(`Avg Spend` = Revenue / Orders)

d1_time <- df %>%
  group_by(MonthStart) %>%
  summarise(Profit = sum(Profit), Revenue = sum(Revenue), .groups = "drop") %>%
  arrange(MonthStart) %>%
  mutate(`MoM Growth` = (Profit - lag(Profit)) / lag(Profit),
         `MoM Growth` = replace_na(`MoM Growth`, 0))

d1_weekday <- df %>%
  group_by(Weekday) %>%
  summarise(Profit = sum(Profit), .groups = "drop") %>%
  arrange(Weekday)

product_tbl <- df %>%
  group_by(`Product Name`) %>%
  summarise(Profit      = sum(Profit),
            Revenue     = sum(Revenue),
            QtySold     = sum(`Quantity Sold`),
            QtyReturned = sum(`Quantity Returned`), .groups = "drop") %>%
  mutate(`Return Rate` = QtyReturned / QtySold)

d1_top_profit  <- product_tbl %>% arrange(desc(Profit))        %>% slice_head(n = 10)
d1_top_selling <- product_tbl %>% arrange(desc(QtySold))       %>% slice_head(n = 10)
d1_top_returns <- product_tbl %>% arrange(desc(`Return Rate`)) %>% slice_head(n = 10)

# ---------------------------------------------------------------------
# 5. DASHBOARD 2 — STORE BUDGET VS REVENUE
# ---------------------------------------------------------------------
sp2 <- sp %>% mutate(`Store ID` = `Sales Person ID`)

store_rev <- df %>%
  group_by(`Store Name`) %>%
  summarise(Revenue = sum(Revenue), .groups = "drop")

store_tgt <- tgt %>%
  group_by(`Store ID`) %>%
  summarise(Target = sum(`Monthly Target`), .groups = "drop") %>%
  left_join(sp2 %>% select(`Store ID`, `Store Name`), by = "Store ID")

d2_store_bvr <- store_rev %>%
  left_join(store_tgt %>% select(`Store Name`, Target), by = "Store Name") %>%
  mutate(Variance = Revenue - Target,
         `% to Target` = Revenue / Target) %>%
  arrange(desc(Revenue))

month_rev <- df  %>% group_by(MonthStart) %>%
  summarise(Revenue = sum(Revenue), .groups = "drop")
month_tgt <- tgt %>% mutate(MonthStart = floor_date(Month, "month")) %>%
  group_by(MonthStart) %>%
  summarise(Target = sum(`Monthly Target`), .groups = "drop")

d2_month <- full_join(month_rev, month_tgt, by = "MonthStart") %>%
  arrange(MonthStart) %>%
  mutate(across(c(Revenue, Target), ~replace_na(., 0)),
         Variance = Revenue - Target)

# ---------------------------------------------------------------------
# 6. DASHBOARD 3 — REVENUE ANALYSIS
# ---------------------------------------------------------------------
d3_quarter <- df %>%
  group_by(Quarter) %>%
  summarise(Revenue = sum(Revenue), .groups = "drop") %>%
  mutate(`Avg Revenue` = mean(Revenue),
         `Variance vs Avg` = Revenue - mean(Revenue))

d3_weekend <- df %>%
  mutate(Type = if_else(IsWeekend, "Weekend", "Weekday")) %>%
  group_by(Type) %>%
  summarise(Revenue = sum(Revenue), .groups = "drop")

# d3 monthly revenue vs target == d2_month (reused)

# ---------------------------------------------------------------------
# 7. OUTPUT
# ---------------------------------------------------------------------
cat("=== HEADLINE KPIs ===\n");           print(as.data.frame(kpis))
cat("\n=== Profit by Gender ===\n");       print(as.data.frame(d1_gender))
cat("\n=== Avg Spend by Age Group ===\n"); print(as.data.frame(d1_age))
cat("\n=== Store Revenue vs Target ===\n");print(as.data.frame(d2_store_bvr))
cat("\n=== Quarterly Revenue ===\n");      print(as.data.frame(d3_quarter))
cat("\n=== Weekday vs Weekend ===\n");     print(as.data.frame(d3_weekend))

# Optional: write each table to CSV
# write_csv(d2_store_bvr, "out_store_bvr.csv")  # etc.
