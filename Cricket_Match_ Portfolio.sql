CREATE TABLE cricket_match (
	match_id VARCHAR(50),
	match_date VARCHAR(50),
	stadium_name VARCHAR(100),
	team_1 VARCHAR(100),
	team_2 VARCHAR(100),
	toss_winner VARCHAR(100),
	toss_decision VARCHAR(50),
	match_winner VARCHAR(100),
	win_margin VARCHAR(50),
	player_of_match VARCHAR(100),
	umpire_1 VARCHAR(100),
	umpire_2 VARCHAR(100),
	first_innings_score VARCHAR(50),
	second_innings_score VARCHAR(50),
	first_innings_wickets VARCHAR(50),
	second_innings_wickets VARCHAR(50),
	attendance VARCHAR(50),
	weather_conditions VARCHAR(50),
	pitch_type VARCHAR(50),
	match_duration_mins VARCHAR(50)
);

SELECT COUNT(*) AS total_rows
FROM cricket_match;

-- An empty table structure is created.

SELECT * FROM cricket_match
LIMIT 20;


-- STEP1: Trimming extra speces from "match_id" & setting it as the PRIMARY KEY for unique Identification.

BEGIN;
UPDATE cricket_match
SET match_id = TRIM(match_id);
COMMIT;


SELECT match_id, COUNT(*)
FROM cricket_match
GROUP BY match_id
HAVING COUNT(*) > 1;

DELETE FROM cricket_match
WHERE ctid NOT IN (
	SELECT MIN(ctid)
	FROM cricket_match
	GROUP BY match_id
);

-- Let verify this

SELECT match_id, COUNT(*)
FROM cricket_match
GROUP BY match_id
HAVING COUNT(*) > 1;

-- Now Let's Add PRIMARY KEY

ALTER TABLE cricket_match
ADD PRIMARY KEY (match_id);

-- STEP2: Converting empty string & literal 'Nan' text into NULL values for data integrity.

BEGIN;
UPDATE cricket_match
SET stadium_name = NULLIF(NULLIF(TRIM(stadium_name), ''), 'Nan'),
	weather_conditions = NULLIF(NULLIF(TRIM(weather_conditions), ''), 'NaN'),
	umpire_2 = NULLIF(NULLIF(TRIM(umpire_2), ''), 'NaN'),
	attendance = NULLIF(NULLIF(TRIM(attendance), ''), 'NaN');
COMMIT;

-- STEP3: Standardizing mixed date formates (MM/DD/YYYY) and DD-MM-YYYY) using Regex and altering type to DATE.

SELECT DISTINCT match_date
FROM cricket_match;

BEGIN;
ALTER TABLE cricket_match
ALTER COLUMN match_date TYPE DATE
USING (
	CASE
		WHEN match_date LIKE '%/%'
			THEN TO_DATE(match_date, 'MM/DD/YYYY')

		WHEN match_date LIKE '%-%'
			THEN TO_DATE(match_date, 'DD-MM-YYYY')

		ELSE NULL
	END

	);

ROLLBACK;
COMMIT;

SELECT DISTINCT *
FROM cricket_match
LIMIT 100;

--STEP4: Normalizing team names and string data by removing trailing spaces and applying uppercase consistency.
BEGIN;
UPDATE cricket_match
SET team_1 = UPPER(TRIM(team_1)),
	team_2 = UPPER(TRIM(team_2)),
	toss_winner = UPPER(TRIM(toss_winner)),
	match_winner = UPPER(TRIM(match_winner));
COMMIT;
-- Normalizing toss decisions into standard 'BAT' and 'FIELD' categories.
BEGIN;
UPDATE cricket_match
SET toss_decision = CASE
	WHEN UPPER(TRIM(toss_decision)) IN ('BATTING', 'BAT') THEN 'BAT'
	WHEN UPPER(TRIM(toss_decision)) IN ('FIELDING', 'FIELD', 'BOWL') THEN 'FIELD'
	ELSE UPPER(TRIM(toss_decision))
END;
COMMIT;

SELECT *
FROM cricket_match
LIMIT 100;

-- STEP5 A: Extracting pure numeric values ('21 runs' to '21').

BEGIN;
ALTER TABLE cricket_match
ALTER COLUMN win_margin TYPE INT
USING NULLIF(REGEXP_REPLACE(win_margin, '\D', '', 'g'), '')::INT;

SELECT COUNT(*)
FROM cricket_match;
COMMIT;

-- STEP5B: Handling missing data by replacing NULL values in win_margin with the column's overall average.
BEGIN;
UPDATE cricket_match
SET win_margin = (
	SELECT ROUND(AVG(win_margin))
	FROM cricket_match
)
WHERE win_margin IS NULL;

SELECT *
FROM cricket_match
LIMIT 100;

SELECT win_margin
FROM cricket_match
WHERE match_id = 'M_4982_808';

SELECT ROUND(AVG(win_margin))
FROM cricket_match;

COMMIT;

-- STEP6: Removing decimal extensions from attendance figures and converting the column data to INT.

BEGIN;
ALTER TABLE cricket_match
ALTER COLUMN attendance TYPE INT
USING REPLACE(attendance, '.0', '')::INT;

SELECT attendance FROM cricket_match;
COMMIT;


SELECT * FROM cricket_match;

-- STEP7: Fixing negative time entry using the Absolute (ABS) mathematical function and casting to INT.

BEGIN;
ALTER TABLE cricket_match
ALTER COLUMN match_duration_mins TYPE INTEGER 
USING ABS(match_duration_mins::INTEGER);
ROLLBACK;
COMMIT;

-- STEP8: Extracting pure numeric values {(}'347 (approx)' to '347'}.

BEGIN;
ALTER TABLE cricket_match
ALTER COLUMN first_innings_score TYPE INT
USING NULLIF(REGEXP_REPLACE(first_innings_score, '\D', '', 'g'), '')::INT;
COMMIT;


SELECT * FROM cricket_match;

-- STEP8B: Casting the remaining pre-cleaned numeric columns directly from VARCHAR to INT type for analytical queries.

BEGIN;
ALTER TABLE cricket_match
ALTER COLUMN second_innings_score TYPE INT USING second_innings_score::INT,
ALTER COLUMN first_innings_wickets TYPE INT USING first_innings_wickets::INT,
ALTER COLUMN second_innings_wickets TYPE INT USING second_innings_wickets::INT;
ROLLBACK;
COMMIT;

----------------------------------------*****************************************--------------------------------------------------------
-- Creating a backup of the fully cleaned table.
----------------------------------------*****************************************--------------------------------------------------------

CREATE TABLE cricket_match_backup AS
SELECT * FROM cricket_match;

SELECT * FROM cricket_match;
----------------------------------------*****************************************--------------------------------------------------------
----------------------------------------*****************************************--------------------------------------------------------

/*--------
PHASE-2: EXPLORING DATA ANALYSIS & AGGREGATION
Objective1: Identify the stadium with the highest proportion of missing attendance records.
--------*/

SELECT
	stadium_name,
	COUNT(*) AS total_matches,
	SUM(CASE WHEN attendance IS NULL THEN 1 ELSE 0 END) AS missing_attendance,
	ROUND(
		(SUM(CASE WHEN attendance IS NULL THEN 1 ELSE 0 END) * 100.0) / COUNT(*), 2) AS missing_percentage
FROM cricket_match
GROUP BY stadium_name
ORDER BY missing_attendance DESC
LIMIT 1;

/*-----
DATAINSIGHT: This query helps identify which stadium has the most incomplete data, allowing it to be highlighted
in future reports.
-------*/

-- Objective2: Calculate the win percentage for teams that win the toss and choose to bat first versus those that choose to field first.

SELECT
	toss_decision,
	COUNT(*) AS total_toss_decision,
	SUM(CASE WHEN toss_winner = match_winner THEN 1 ELSE 0 END) AS matches_won,
	ROUND((SUM(CASE WHEN toss_winner = match_winner THEN 1 ELSE 0 END) * 100.0) / COUNT(*), 2) AS win_percentage
FROM cricket_match
WHERE toss_decision IN ('BAT', 'FIELD')
GROUP BY toss_decision;

/*----------
DATAINSIGHT: Teams choose to BAT more frequently (552 times) than to FIELD (448 times) after winning the toss.
----------*/

--Objective3: Analyse venue performance by calculating average first innings scores and attendance.

SELECT
	stadium_name,
	ROUND(AVG(first_innings_score)) AS avg_score,
	ROUND(AVG(attendance)) AS avg_attendance
FROM cricket_match
WHERE stadium_name IS NOT NULL AND first_innings_score IS NOT NULL
GROUP BY stadium_name
ORDER BY avg_score DESC;

/*--------
DATAINSIGHT: Highest Scoring Venue - 'Gabba' with the highest avg first innings score 484
			 Highest Crowd Turnout - 'SCG' records the highest avg attendance 51717
---------*/

-- Objective Identify thrilling run chases where the team batting second won despite lossing 8 or more wickets.

SELECT
	match_date,
	team_1,
	team_2,
	stadium_name,
	match_winner
FROM cricket_match
WHERE
	(match_winner = team_2 AND toss_winner = team_1 AND toss_decision = 'BAT' or
	 match_winner = team_1 AND toss_winner = team_2 AND toss_decision = 'BAT')
	 AND second_innings_wickets >=8
ORDER BY match_date DESC
LIMIT 5;

/*--------
DATAINSIGHT:
These 5 matches represent extremely tight chases where the chasing
team pulled off a victory with only 1 or 2 wickets remaining.

SCG (3 matches) and MCG (2 matches) host all five of the thrilling
finishes, indicating that Australian venues tend close, edge-of-the-seat run
cheses.

India and New Zealand appear most frequently in these high tension victories
featuring in 2 matches each.
--------*/

-- Objective: Determine the most active umpires by combining their appearances as either umpire_1 or umpire_2.

SELECT * FROM cricket_match;

WITH AllUmpires AS(
	SELECT umpire_1 AS umpire_name FROM cricket_match WHERE umpire_1 IS NOT NULL
	UNION ALL
	SELECT umpire_2 AS umpire_name FROM cricket_match WHERE umpire_2 IS NOT NULL
)
SELECT umpire_name, COUNT(*) AS matches_officiated
FROM AllUmpires
GROUP BY umpire_name
ORDER BY matches_officiated DESC
LIMIT 3;
)

/*--------
DATAINSIGHT:
"Aleem Dar " (303), "Simon Taufel" (298), "Marais Erasmus" (289) These umpires are highly experienced and reliable.
---------*/

-- Objective: Find the ideal playing conditions (pitch type and weather) that result in the highest run aggregates.

SELECT
	pitch_type,
	weather_conditions,
	ROUND(AVG(first_innings_score + second_innings_score)) AS avg_total_runs
FROM cricket_match
WHERE pitch_type IS NOT NULL AND weather_conditions IS NOT NULL
GROUP BY pitch_type, weather_conditions
ORDER BY avg_total_runs DESC
LIMIT 1;

/*--------
DATAINSIGHT:
The combination of Cloudy weather and an Unkown pitch type produced the highest
average match aggregate with 1,871 total runs.
---------*/

-- Objective: Build a comprehensive team performance view showing total matches, wins, and win ration.

WITH TeamMatches AS (
	SELECT team_1 AS team FROM cricket_match
	UNION ALL
	SELECT team_2 AS team FROM cricket_match
),
MatchesPlayed AS (
	SELECT team, COUNT(*) AS total_matches
	FROM TeamMatches
	GROUP BY team
),
MatchesWon AS (
	SELECT match_winner AS team, COUNT(*) AS total_wins
	FROM cricket_match
	WHERE match_winner NOT IN ('Draw', 'No Result') AND match_winner IS NOT NULL
	GROUP BY match_winner
)

SELECT
	p.team,
	p.total_matches,
	COALESCE(w.total_wins, 0) AS total_wins,
	ROUND((COALESCE(w.total_wins, 0) * 100.0) / p.total_matches, 2) AS win_ratio
FROM MatchesPlayed p
LEFT JOIN MatchesWon w ON p.team = w.team
ORDER BY win_ratio DESC;

/*-------
DATAINSIGHT:
Now we are abke to see the clear leader board with "team, total_matches, total_wins and win_ratio"
---------*/

-- Objective: Rank the top 10 largest victories using window functions.

SELECT
	match_winner AS winner,
	CASE WHEN match_winner = team_1 THEN team_2 ELSE team_1 END AS opponent, win_margin,
	DENSE_RANK() OVER (ORDER BY win_margin DESC) AS victory_rank
FROM cricket_match
WHERE win_margin IS NOT NULL
ORDER BY victory_rank
LIMIT 10;

/*----------
DATAINSIGHT:
By running this query we can now dive into the record books and uncover the most
brutal defeats and bigest victories, alowing us to the most dominant performance in the
tournamnet's history.
-----------*/

--Thank you!