
-- ============================================================
-- PROJECT: Data Quality & Evaluation Performance Analytics
-- FILE: data_quality_checks.sql
-- PURPOSE: Initial data integrity validation
-- DATABASE: evaluation_analytics.db
-- ============================================================


-- ============================================================
-- CHECK 01: Dataset row counts
-- Expected: 400 requests, 800 evaluations
-- ============================================================

SELECT
    'requests' AS table_name,
    COUNT(*) AS total_rows
FROM requests

UNION ALL

SELECT
    'evaluations' AS table_name,
    COUNT(*) AS total_rows
FROM evaluations;


-- ============================================================
-- CHECK 02: Duplicate primary key values (V05)
-- Expected: 0 rows for each query
-- ============================================================

-- V05a: Duplicate Request_ID
SELECT
    Request_ID,
    COUNT(*) AS occurrences
FROM requests
GROUP BY Request_ID
HAVING COUNT(*) > 1;

-- V05b: Duplicate Evaluation_ID
SELECT
    Evaluation_ID,
    COUNT(*) AS occurrences
FROM evaluations
GROUP BY Evaluation_ID
HAVING COUNT(*) > 1;


-- ============================================================
-- CHECK 03: Invalid foreign key references (V15)
-- Expected: 0 rows
-- ============================================================

SELECT
    e.Evaluation_ID,
    e.Request_ID
FROM evaluations AS e
LEFT JOIN requests AS r
    ON e.Request_ID = r.Request_ID
WHERE r.Request_ID IS NULL;


-- ============================================================
-- CHECK 04: Exactly two evaluations per request (V16)
-- Expected: 0 rows
-- ============================================================

SELECT
    r.Request_ID,
    COUNT(e.Evaluation_ID) AS evaluation_count
FROM requests AS r
LEFT JOIN evaluations AS e
    ON r.Request_ID = e.Request_ID
GROUP BY r.Request_ID
HAVING COUNT(e.Evaluation_ID) <> 2;


-- ============================================================
-- CHECK 05: Two distinct reviewers per request (V17)
-- Expected: 0 rows
-- ============================================================

SELECT
    Request_ID,
    COUNT(*) AS total_evaluations,
    COUNT(DISTINCT Reviewer_ID) AS unique_reviewers
FROM evaluations
GROUP BY Request_ID
HAVING COUNT(*) <> 2
    OR COUNT(DISTINCT Reviewer_ID) <> 2;
	
	


-- ============================================================
-- CHECK 06: Missing required values (V03)
-- Expected: 0 rows
-- ============================================================

SELECT 'requests' AS source_table, Request_ID AS record_id
FROM requests
WHERE Request_ID IS NULL OR TRIM(Request_ID) = ''
   OR Created_At IS NULL OR TRIM(Created_At) = ''
   OR Completed_At IS NULL OR TRIM(Completed_At) = ''
   OR Category IS NULL OR TRIM(Category) = ''
   OR Language IS NULL OR TRIM(Language) = ''
   OR Complexity IS NULL OR TRIM(Complexity) = ''
   OR Processing_Time_Min IS NULL
   OR Processing_Status IS NULL OR TRIM(Processing_Status) = ''

UNION ALL

SELECT 'evaluations', Evaluation_ID
FROM evaluations
WHERE Evaluation_ID IS NULL OR TRIM(Evaluation_ID) = ''
   OR Request_ID IS NULL OR TRIM(Request_ID) = ''
   OR Reviewer_ID IS NULL OR TRIM(Reviewer_ID) = ''
   OR Evaluated_At IS NULL OR TRIM(Evaluated_At) = ''
   OR Accuracy_Score IS NULL
   OR Completeness_Score IS NULL
   OR Guideline_Score IS NULL
   OR Error_Type IS NULL OR TRIM(Error_Type) = '';


   
   

-- ============================================================
-- CHECK 07: Invalid categorical values (V06-V09, V11)
-- Expected: 0 rows
-- ============================================================

SELECT 'V06 - Category' AS rule, Request_ID AS record_id
FROM requests
WHERE Category IS NULL OR Category NOT IN (
    'Extraction',
    'Classification',
    'Summarization',
    'Guideline Review',
    'Data Validation'
)

UNION ALL

SELECT 'V07 - Language', Request_ID
FROM requests
WHERE Language IS NULL OR Language NOT IN ('vi', 'en')

UNION ALL

SELECT 'V08 - Complexity', Request_ID
FROM requests
WHERE Complexity IS NULL
   OR Complexity NOT IN ('Low', 'Medium', 'High')

UNION ALL

SELECT 'V09 - Reviewer', Evaluation_ID
FROM evaluations
WHERE Reviewer_ID IS NULL
   OR Reviewer_ID NOT IN ('R01', 'R02', 'R03', 'R04')

UNION ALL

SELECT 'V11 - Error Type', Evaluation_ID
FROM evaluations
WHERE Error_Type IS NULL OR Error_Type NOT IN (
    'None',
    'Incorrect Information',
    'Missing Information',
    'Format Violation',
    'Guideline Violation',
    'Other'
);




-- ============================================================
-- CHECK 08: Invalid score values (V10)
-- Expected: 0 rows
-- ============================================================

SELECT
    Evaluation_ID,
    Accuracy_Score,
    Completeness_Score,
    Guideline_Score
FROM evaluations
WHERE Accuracy_Score IS NULL
   OR Completeness_Score IS NULL
   OR Guideline_Score IS NULL
   OR typeof(Accuracy_Score) <> 'integer'
   OR typeof(Completeness_Score) <> 'integer'
   OR typeof(Guideline_Score) <> 'integer'
   OR Accuracy_Score NOT BETWEEN 1 AND 5
   OR Completeness_Score NOT BETWEEN 1 AND 5
   OR Guideline_Score NOT BETWEEN 1 AND 5;

   
   
   


-- ============================================================
-- CHECK 09: Processing time consistency (V12, V13)
-- Normalize single-digit hours before comparison
-- Expected: 0 rows
-- ============================================================

WITH normalized AS (
    SELECT
        Request_ID,
        Created_At,
        Completed_At,
        Processing_Time_Min,

        CASE
            WHEN substr(Created_At, 12, 2) LIKE '%:'
            THEN substr(Created_At, 1, 11) || '0'
                 || substr(Created_At, 12)
            ELSE Created_At
        END AS created_fixed,

        CASE
            WHEN substr(Completed_At, 12, 2) LIKE '%:'
            THEN substr(Completed_At, 1, 11) || '0'
                 || substr(Completed_At, 12)
            ELSE Completed_At
        END AS completed_fixed

    FROM requests
)
SELECT
    Request_ID,
    Created_At,
    Completed_At,
    Processing_Time_Min,
    ROUND(
        (julianday(completed_fixed) - julianday(created_fixed))
        * 1440,
        2
    ) AS calculated_minutes
FROM normalized
WHERE julianday(created_fixed) IS NULL
   OR julianday(completed_fixed) IS NULL
   OR julianday(completed_fixed) < julianday(created_fixed)
   OR Processing_Time_Min < 0
   OR ABS(
       (julianday(completed_fixed) - julianday(created_fixed))
       * 1440 - Processing_Time_Min
   ) > 0.01;

   
   

-- ============================================================
-- CHECK 10: Evaluation timestamp consistency (V14)
-- Normalize single-digit hours before comparison
-- Expected: 0 rows
-- ============================================================

WITH normalized AS (
    SELECT
        e.Evaluation_ID,
        e.Request_ID,
        r.Completed_At,
        e.Evaluated_At,

        CASE
            WHEN substr(r.Completed_At, 12, 2) LIKE '%:'
            THEN substr(r.Completed_At, 1, 11) || '0'
                 || substr(r.Completed_At, 12)
            ELSE r.Completed_At
        END AS completed_fixed,

        CASE
            WHEN substr(e.Evaluated_At, 12, 2) LIKE '%:'
            THEN substr(e.Evaluated_At, 1, 11) || '0'
                 || substr(e.Evaluated_At, 12)
            ELSE e.Evaluated_At
        END AS evaluated_fixed

    FROM evaluations AS e
    JOIN requests AS r
        ON e.Request_ID = r.Request_ID
)
SELECT
    Evaluation_ID,
    Request_ID,
    Completed_At,
    Evaluated_At
FROM normalized
WHERE julianday(completed_fixed) IS NULL
   OR julianday(evaluated_fixed) IS NULL
   OR julianday(evaluated_fixed) < julianday(completed_fixed);

   
   

-- ============================================================
-- CHECK 11: Derive evaluation pass/fail status
-- Expected: 800 evaluations, each classified
-- ============================================================

SELECT
    Evaluation_ID,
    Accuracy_Score,
    Completeness_Score,
    Guideline_Score,
    CASE
        WHEN Accuracy_Score >= 4
         AND Completeness_Score >= 4
         AND Guideline_Score >= 4
        THEN 'PASS'
        ELSE 'FAIL'
    END AS evaluation_result
FROM evaluations
ORDER BY Evaluation_ID;





-- Validation finding:
-- EV00015 has scores (3, 4, 3) but Error_Type = 'None'.
-- Expected: FAIL with a non-'None' error type.
-- Status: 1 unresolved data quality issue.
-- Action: Flag for review; do not modify source data.

-- ============================================================
-- CHECK 12: Error type vs evaluation result
-- Expected: 0 rows
-- ============================================================

SELECT
    Evaluation_ID,
    Accuracy_Score,
    Completeness_Score,
    Guideline_Score,
    Error_Type
FROM evaluations
WHERE
    (
        Accuracy_Score >= 4
        AND Completeness_Score >= 4
        AND Guideline_Score >= 4
        AND Error_Type <> 'None'
    )
    OR
    (
        (
            Accuracy_Score < 4
            OR Completeness_Score < 4
            OR Guideline_Score < 4
        )
        AND Error_Type = 'None'
    );
