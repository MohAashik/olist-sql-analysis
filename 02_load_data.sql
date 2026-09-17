/**********************************************************************
 02_load_data_SQL2014.sql   (v2 - TAB-delimited clean files)
 CSV loader for SQL Server 2014. Run AFTER 01_create_tables.sql,
 then continue with 03_data_cleaning.sql.

 >>> USE THE PREPARED FILES <<<
 These BULK INSERTs expect the CLEANED data files (the "olist-data-CLEAN"
 set): plain ASCII, TAB-separated, no quotes. Those were pre-processed so
 that SQL Server 2014 can read them with zero errors (the original CSVs
 had commas inside quoted city names and UTF-8 accents, which 2014's
 BULK INSERT cannot handle).

 SETUP
 1. Put the 7 cleaned files in:  C:\olist-sql-project\data
    (replace the old ones). If you use a different folder, Ctrl+H to
    replace the path below.
 2. Run this whole script (F5).

 The files are TAB-separated, so FIELDTERMINATOR is a tab. Row terminator
 is 0x0a (UNIX line ending). FIRSTROW=2 skips the header row.
**********************************************************************/
USE OlistDW;
GO

TRUNCATE TABLE dbo.stg_customers;
TRUNCATE TABLE dbo.stg_orders;
TRUNCATE TABLE dbo.stg_order_items;
TRUNCATE TABLE dbo.stg_order_payments;
TRUNCATE TABLE dbo.stg_products;
TRUNCATE TABLE dbo.stg_sellers;
TRUNCATE TABLE dbo.stg_category;
GO

BULK INSERT dbo.stg_customers
FROM 'C:\olist-sql-project\data\olist_customers_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT dbo.stg_orders
FROM 'C:\olist-sql-project\data\olist_orders_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT dbo.stg_order_items
FROM 'C:\olist-sql-project\data\olist_order_items_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT dbo.stg_order_payments
FROM 'C:\olist-sql-project\data\olist_order_payments_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT dbo.stg_products
FROM 'C:\olist-sql-project\data\olist_products_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT dbo.stg_sellers
FROM 'C:\olist-sql-project\data\olist_sellers_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT dbo.stg_category
FROM 'C:\olist-sql-project\data\product_category_name_translation.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/*====================================================================
  Verify. Expected (roughly):
    customers 99441 | orders 99441 | order_items 112650 | payments 103886
    products 32951  | sellers 3095 | category 71
====================================================================*/
SELECT 'stg_customers'      AS staging_table, COUNT(*) AS rows_loaded FROM dbo.stg_customers

UNION ALL SELECT 'stg_orders',        COUNT(*) FROM dbo.stg_orders
UNION ALL SELECT 'stg_order_items',   COUNT(*) FROM dbo.stg_order_items
UNION ALL SELECT 'stg_order_payments',COUNT(*) FROM dbo.stg_order_payments
UNION ALL SELECT 'stg_products',      COUNT(*) FROM dbo.stg_products
UNION ALL SELECT 'stg_sellers',       COUNT(*) FROM dbo.stg_sellers
UNION ALL SELECT 'stg_category',      COUNT(*) FROM dbo.stg_category;
GO

SELECT TOP 5 * FROM dbo.stg_customers;
GO

PRINT 'Load complete (SQL 2014, tab-delimited). Continue with 03_data_cleaning.sql';
GO