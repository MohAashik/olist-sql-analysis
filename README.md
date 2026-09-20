# Olist E-Commerce SQL Analysis

An end-to-end SQL project on Microsoft SQL Server: I take the **Brazilian
E-Commerce Public Dataset by Olist** (~100,000 real orders), build a
**staging → clean star-schema pipeline**, and answer the business questions a
marketplace actually cares about — from revenue trends to customer retention and
delivery performance.

> **Goal:** turn raw, messy order data into clean, trustworthy insight that a
> business can act on.

---

## 📌 Overview

| | |
|---|---|
| **Dataset** | [Brazilian E-Commerce Public Dataset by Olist (Kaggle)](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — ~100k orders, 2016–2018 |
| **Tools** | Microsoft SQL Server (T-SQL), SSMS |
| **Skills** | Data modelling · Star schema · ETL · Data cleaning · Joins · CTEs · Window functions · RFM · Cohort & Pareto analysis |
| **Deliverable** | 5 SQL scripts: create → load → clean → analyse |

---

## 🗂 Repository structure

```
olist-sql-analysis/
├── README.md
└── sql/
    ├── 01_create_tables.sql        # database + staging & clean star-schema tables
    ├── 02_load_data_SQL2014.sql    # load the CSVs into staging (BULK INSERT)
    ├── 03_data_cleaning.sql        # clean staging -> clean star schema
    ├── 04_business_analysis.sql    # core business questions (Q1-Q9)
    └── 05_advanced_analysis.sql    # advanced analytics (A1-A7)
```

---

## 🏗 The approach (ETL pipeline)

```
Raw CSVs  ->  Staging tables (raw, all text)  ->  Clean star schema  ->  Analysis
              (loading dock)                      (dimensions + facts)
```

The clean model is a **star schema** — three dimensions (`dim_customers`,
`dim_products`, `dim_sellers`) around fact tables (`fact_orders`,
`fact_order_items`, `fact_payments`) — built for fast, simple analytical queries.

---

## 🧹 Data cleaning — key decisions

Raw data is never analysis-ready. Each fix is a deliberate, documented decision:

- **Customer identity:** Olist issues a **new `customer_id` for every order**, so
  I used `customer_unique_id` to count *real people* — otherwise every buyer looks
  brand-new.
- **Category translation:** product categories were in **Portuguese** → translated
  to English via a lookup table; missing ones default to `'unknown'`.
- **Type conversion:** text timestamps and prices converted to proper `datetime` /
  `decimal` types (blank/invalid values become `NULL`, not errors).
- **De-duplication & integrity:** removed duplicates with `ROW_NUMBER()` and kept
  only records whose parent (order / product / seller) exists — no orphan rows.
- **Data prep note:** the source CSVs are UTF-8 with quoted fields; to load them
  reliably on SQL Server 2014, I converted them to clean, tab-separated ASCII.

---

## 📊 Business questions & key findings

*(All revenue figures are on **delivered** orders. Reproduce by running the scripts.)*

| Question | Key finding |
|---|---|
| Overall KPIs | **~R$13.2M** revenue across **~96k delivered orders**, AOV **≈ R$137** |
| Revenue by category | **Health & Beauty** leads; the top ~5 categories carry most revenue |
| Revenue by region | **São Paulo ≈ 38% of revenue** — highly concentrated |
| Payment behaviour | **Credit card ≈ 74%** of payments (avg **~3.5 installments**) |
| Customer loyalty | **Only ~3% of customers ever order again** |
| Seller concentration | **Top 20% of sellers ≈ 82% of revenue** (Pareto / 80-20) |
| Delivery performance | Average **~12.5 days**, **~8%** delivered later than promised |

---

## 💡 Recommendations

- **Invest in retention.** With only ~3% of customers repeating, getting existing
  customers to buy again is the biggest, cheapest growth lever.
- **Watch concentration risk.** Revenue leans heavily on São Paulo and a small core
  of sellers — worth diversifying.
- **Improve delivery in weaker regions.** Delivery is slower/later in northern
  states — an operational focus area.

---

## ▶️ How to run

1. Get the data from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
   and place the CSVs in a folder SQL Server can read.
2. In **SSMS**, run the scripts **in order**, each with **F5**:
   `01` → `02` (edit the file path first) → `03` → `04` → `05`.
3. Target engine: **SQL Server 2014+**. All scripts are re-runnable.

---

🎥 Project walkthrough

Video walkthrough — https://drive.google.com/file/d/1k-dfu2Azop6I9m8a2b9n640hq93Ye1PC/view?usp=sharing

---

## 👤 Author

**Mohammed Aashik** — aspiring Data Analyst (SQL · Power BI · Python · Excel)

- 📧 aashikdot006@gmail.com
- 💼 [LinkedIn](https://www.linkedin.com/in/mohamedaashik10/)
- 📍 Gampola / Kandy, Sri Lanka

---

*Dataset © Olist, licensed CC BY-NC-SA 4.0. This project is for educational /
portfolio purposes.*
