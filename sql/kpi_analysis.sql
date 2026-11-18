
-- ============================================================
-- PROJECT: Data Quality & Evaluation Performance Analytics
-- FILE: kpi_analysis.sql
-- SECTION 01: KPI Overview
-- ============================================================

SELECT
    (SELECT COUNT(DISTINCT Request_ID)
     FROM requests) AS total_requests,

    (SELECT COUNT(*)
     FROM evaluations) AS total_evaluations,

    (SELECT ROUND(AVG(Processing_Time_Min), 2)
     FROM requests) AS avg_processing_time_min,

    (SELECT ROUND(
        100.0 * SUM(
            CASE
                WHEN Accuracy_Score >= 4
                 AND Completeness_Score >= 4
                 AND Guideline_Score >= 4
                THEN 1 ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        2
     )
     FROM evaluations) AS evaluation_pass_rate_pct;

	 
	 
	 

-- ============================================================
-- SECTION 02: Evaluation performance by category
-- ============================================================

SELECT
    r.Category,
    COUNT(DISTINCT r.Request_ID) AS total_requests,
    COUNT(e.Evaluation_ID) AS total_evaluations,

    SUM(
        CASE
            WHEN e.Accuracy_Score >= 4
             AND e.Completeness_Score >= 4
             AND e.Guideline_Score >= 4
            THEN 1 ELSE 0
        END
    ) AS passed_evaluations,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN e.Accuracy_Score >= 4
                 AND e.Completeness_Score >= 4
                 AND e.Guideline_Score >= 4
                THEN 1 ELSE 0
            END
        ) / NULLIF(COUNT(e.Evaluation_ID), 0),
        2
    ) AS pass_rate_pct

FROM requests AS r
JOIN evaluations AS e
    ON r.Request_ID = e.Request_ID

GROUP BY r.Category
ORDER BY pass_rate_pct ASC;





-- ============================================================
-- SECTION 03: Error distribution among failed evaluations
-- ============================================================

WITH evaluation_results AS (
    SELECT
        Evaluation_ID,
        Error_Type,
        CASE
            WHEN Accuracy_Score >= 4
             AND Completeness_Score >= 4
             AND Guideline_Score >= 4
            THEN 'PASS'
            ELSE 'FAIL'
        END AS evaluation_result
    FROM evaluations
)

SELECT
    Error_Type,
    COUNT(*) AS total_failures,

    ROUND(
        100.0 * COUNT(*) /
        NULLIF(
            (SELECT COUNT(*)
             FROM evaluation_results
             WHERE evaluation_result = 'FAIL'),
            0
        ),
        2
    ) AS pct_of_all_failures

FROM evaluation_results
WHERE evaluation_result = 'FAIL'
GROUP BY Error_Type
ORDER BY total_failures DESC;





-- ============================================================
-- SECTION 04: Reviewer agreement
-- ============================================================

WITH evaluation_results AS (
    SELECT
        Request_ID,
        Reviewer_ID,
        CASE
            WHEN Accuracy_Score >= 4
             AND Completeness_Score >= 4
             AND Guideline_Score >= 4
            THEN 1 ELSE 0
        END AS is_pass
    FROM evaluations
),
request_agreement AS (
    SELECT
        Request_ID,
        COUNT(*) AS evaluation_count,
        COUNT(DISTINCT Reviewer_ID) AS reviewer_count,
        MIN(is_pass) AS min_result,
        MAX(is_pass) AS max_result
    FROM evaluation_results
    GROUP BY Request_ID
)
SELECT
    COUNT(*) AS total_requests,
    SUM(
        CASE WHEN min_result = max_result
             THEN 1 ELSE 0 END
    ) AS agreed_requests,
    SUM(
        CASE WHEN min_result <> max_result
             THEN 1 ELSE 0 END
    ) AS disagreed_requests,
    ROUND(
        100.0 * SUM(
            CASE WHEN min_result = max_result
                 THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS reviewer_agreement_pct
FROM request_agreement
WHERE evaluation_count = 2
  AND reviewer_count = 2;

  
  
  

-- ============================================================
-- SECTION 05: Monthly evaluation performance
-- Group by request creation month
-- ============================================================

SELECT
    substr(r.Created_At, 1, 7) AS month,
    COUNT(DISTINCT r.Request_ID) AS total_requests,
    COUNT(e.Evaluation_ID) AS total_evaluations,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN e.Accuracy_Score >= 4
                 AND e.Completeness_Score >= 4
                 AND e.Guideline_Score >= 4
                THEN 1 ELSE 0
            END
        ) / NULLIF(COUNT(e.Evaluation_ID), 0),
        2
    ) AS pass_rate_pct

FROM requests AS r
JOIN evaluations AS e
    ON r.Request_ID = e.Request_ID

GROUP BY substr(r.Created_At, 1, 7)
ORDER BY month;





-- ============================================================
-- SECTION 06: Reviewer score difference
-- Average absolute difference between two reviewers
-- ============================================================

WITH reviewer_pairs AS (
    SELECT
        e1.Request_ID,

        ABS(e1.Accuracy_Score - e2.Accuracy_Score)
            AS accuracy_diff,

        ABS(e1.Completeness_Score - e2.Completeness_Score)
            AS completeness_diff,

        ABS(e1.Guideline_Score - e2.Guideline_Score)
            AS guideline_diff

    FROM evaluations AS e1
    JOIN evaluations AS e2
        ON e1.Request_ID = e2.Request_ID
       AND e1.Evaluation_ID < e2.Evaluation_ID
       AND e1.Reviewer_ID <> e2.Reviewer_ID
)

SELECT
    COUNT(*) AS total_reviewer_pairs,

    ROUND(AVG(accuracy_diff), 2)
        AS avg_accuracy_diff,

    ROUND(AVG(completeness_diff), 2)
        AS avg_completeness_diff,

    ROUND(AVG(guideline_diff), 2)
        AS avg_guideline_diff,

    ROUND(
        AVG(
            (accuracy_diff + completeness_diff + guideline_diff)
            / 3.0
        ),
        2
    ) AS avg_overall_score_diff

FROM reviewer_pairs;
