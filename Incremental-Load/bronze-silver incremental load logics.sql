-- incremental load logic for sales table
-- Loading crm_sales_details
SET @start_time = GETDATE();

PRINT '>> Incremental Loading Table: silver.crm_sales_details';

INSERT INTO silver.crm_sales_details (
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    sls_order_dt,
    sls_ship_dt,
    sls_due_dt,
    sls_sales,
    sls_quantity,
    sls_price
)
SELECT 
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,

    CASE 
        WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
        ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
    END AS sls_order_dt,

    CASE 
        WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
        ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
    END AS sls_ship_dt,

    CASE 
        WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
        ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
    END AS sls_due_dt,

    CASE 
        WHEN sls_sales IS NULL 
          OR sls_sales <= 0 
          OR sls_sales != sls_quantity * ABS(sls_price)
        THEN sls_quantity * ABS(sls_price)
        ELSE sls_sales
    END AS sls_sales,

    sls_quantity,

    CASE 
        WHEN sls_price IS NULL OR sls_price <= 0 
        THEN sls_sales / NULLIF(sls_quantity, 0)
        ELSE sls_price
    END AS sls_price

FROM bronze.crm_sales_details

WHERE 
    CASE 
        WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
        ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
    END
    >
    (
        SELECT ISNULL(MAX(sls_order_dt), '1900-01-01')
        FROM silver.crm_sales_details
    );

SET @end_time = GETDATE();

PRINT '>> Load Duration: '
    + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR)
    + ' seconds';

PRINT '>> -------------';
-------- incremental load for product table

-- Loading silver.crm_prd_info
SET @start_time = GETDATE();

PRINT '>> Incremental Loading Table: silver.crm_prd_info';

INSERT INTO silver.crm_prd_info (
    prd_id,
    cat_id,
    prd_key,
    prd_nm,
    prd_cost,
    prd_line,
    prd_start_dt,
    prd_end_dt
)
SELECT
    prd_id,

    REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,

    SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,

    TRIM(prd_nm) AS prd_nm,

    ISNULL(prd_cost, 0) AS prd_cost,

    CASE 
        WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
        WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
        WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
        WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
        ELSE 'n/a'
    END AS prd_line,

    CAST(prd_start_dt AS DATE) AS prd_start_dt,

    CAST(
        DATEADD(
            DAY,
            -1,
            LEAD(prd_start_dt) OVER (
                PARTITION BY prd_key
                ORDER BY prd_start_dt
            )
        ) AS DATE
    ) AS prd_end_dt

FROM bronze.crm_prd_info AS b

WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.crm_prd_info AS s
    WHERE s.prd_key = SUBSTRING(b.prd_key, 7, LEN(b.prd_key))
);

SET @end_time = GETDATE();

PRINT '>> Load Duration: '
    + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR)
    + ' seconds';

PRINT '>> -------------';

--incremental load for customers table 
-- Loading silver.crm_cust_info
SET @start_time = GETDATE();

PRINT '>> Incremental Loading Table: silver.crm_cust_info';

INSERT INTO silver.crm_cust_info (
    cst_id, 
    cst_key, 
    cst_firstname, 
    cst_lastname, 
    cst_marital_status, 
    cst_gndr,
    cst_create_date
)
SELECT
    cst_id,
    cst_key,
    TRIM(cst_firstname) AS cst_firstname,
    TRIM(cst_lastname) AS cst_lastname,

    CASE 
        WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
        WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
        ELSE 'n/a'
    END AS cst_marital_status,

    CASE 
        WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
        WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
        ELSE 'n/a'
    END AS cst_gndr,

    cst_create_date

FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY cst_id 
            ORDER BY cst_create_date DESC
        ) AS flag_last
    FROM bronze.crm_cust_info
    WHERE cst_id IS NOT NULL
) t

WHERE flag_last = 1

-- Incremental condition
AND NOT EXISTS
(
    SELECT 1
    FROM silver.crm_cust_info s
    WHERE s.cst_id = t.cst_id
);

SET @end_time = GETDATE();

PRINT '>> Load Duration: '
    + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR)
    + ' seconds';

PRINT '>> -------------';
-- incremental load logic for 'bronze.erp_cust_az12'

SET @start_time = GETDATE();

PRINT '>> Incremental Load Into: silver.erp_cust_az12';

INSERT INTO silver.erp_cust_az12 (
    cid,
    bdate,
    gen
)
SELECT
    CASE
        WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
        ELSE cid
    END AS cid,

    CASE
        WHEN bdate > GETDATE() THEN NULL
        ELSE bdate
    END AS bdate,

    CASE
        WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
        WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
        ELSE 'n/a'
    END AS gen

FROM bronze.erp_cust_az12 AS b

WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.erp_cust_az12 AS s
    WHERE s.cid =
        CASE
            WHEN b.cid LIKE 'NAS%' 
                THEN SUBSTRING(b.cid, 4, LEN(b.cid))
            ELSE b.cid
        END
);

SET @end_time = GETDATE();

PRINT '>> Load Duration: '
    + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR)
    + ' seconds';

PRINT '>> -------------';
-- incremental load logic for bronze.erp_loc_a101
-- Loading erp_loc_a101
SET @start_time = GETDATE();

PRINT '>> Incremental Loading Table: silver.erp_loc_a101';

INSERT INTO silver.erp_loc_a101 (
    cid,
    cntry
)
SELECT
    REPLACE(b.cid, '-', '') AS cid,

    CASE
        WHEN TRIM(b.cntry) = 'DE' THEN 'Germany'
        WHEN TRIM(b.cntry) IN ('US', 'USA') THEN 'United States'
        WHEN TRIM(b.cntry) = '' OR b.cntry IS NULL THEN 'n/a'
        ELSE TRIM(b.cntry)
    END AS cntry

FROM bronze.erp_loc_a101 AS b

WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.erp_loc_a101 AS s
    WHERE s.cid = REPLACE(b.cid, '-', '')
);

SET @end_time = GETDATE();

PRINT '>> Load Duration: '
    + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR)
    + ' seconds';

PRINT '>> -------------';

--incremental load logic for bronze.erp_px_cat_g1v2
-- Loading erp_px_cat_g1v2
SET @start_time = GETDATE();

PRINT '>> Incremental Loading Table: silver.erp_px_cat_g1v2';

INSERT INTO silver.erp_px_cat_g1v2 (
    id,
    cat,
    subcat,
    maintenance
)
SELECT
    b.id,
    b.cat,
    b.subcat,
    b.maintenance
FROM bronze.erp_px_cat_g1v2 AS b

WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.erp_px_cat_g1v2 AS s
    WHERE s.id = b.id
);

SET @end_time = GETDATE();

PRINT '>> Load Duration: '
    + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR)
    + ' seconds';

PRINT '>> -------------';



