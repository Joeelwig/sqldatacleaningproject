-- Cafe Sales Data Cleaning Project

-- Step 1. Undestanding the schema of the starting data:
			SELECT 
			    column_name, 
			    data_type
			FROM 
			    information_schema.columns
			WHERE 
			    table_name = 'cafe_sales';
			-- Query shows that all columns are of the 'text' data type
			-- quantity, price_per_unit and total_spent will need to be changed to NUMERIC with 1 decimal place after values within each field have been cleaned
			-- transaction_date will need to be converted to a date

-- Step 2. Check for duplicates:
			SELECT transaction_id, COUNT(*)
			FROM cafe_sales
			GROUP BY transaction_id
			HAVING COUNT(*) > 1;
			-- No duplicates on transaction_id
		
			-- Duplicate test using ROW_NUMBER window function across the whole dataset
			WITH duplicates AS (
			SELECT 
			    *,
			    ROW_NUMBER() OVER (PARTITION BY transaction_id, item, quantity, price_per_unit, total_spent, payment_method, 'location', transaction_date ORDER BY transaction_id, item, quantity, price_per_unit, total_spent, payment_method, 'location', transaction_date) AS row_number
			FROM 
			    cafe_sales)
			
			SELECT * FROM duplicates
			WHERE row_number > 1
			-- Returns no results so there are no duplicates across the dataset

-- Step 3. Handle missing values:

	-- 3a Identify missing Data: using queries to find NULL values.
		
		-- Identifying missing or incorrect transaction_id data
			SELECT transaction_id
			FROM cafe_sales
			WHERE transaction_id IS NULL;
			
			SELECT transaction_id
			FROM cafe_sales
			WHERE transaction_id NOT LIKE 'TXN_%';
			-- Both queries returned zero results
			
			SELECT DISTINCT LENGTH(transaction_id)
			FROM cafe_sales;
			-- All ids have the same length so I am confident that all transaction codes are in the correct format

		--Remaining fields
			SELECT DISTINCT item FROM cafe_sales;
			-- Using the above example statement across each field returned the same three missing values: null, UNKNOWN & ERROR
			-- My approach:
			-- Numeric fields (quantity, price_per_unit, total_spent) - I will first convert all missing values to null. I will then convert the data type to numeric. Then I will calculate the missing values where the other two values are known.
			-- Categorical fields: I will convert missing values to null
		

	-- 3b Cleaning the numerical columns (quantity, price_per_unit, total_spent)
		--Create first staging table
			CREATE TABLE cafe_sales_staging1 AS
			SELECT *
			FROM cafe_sales;

		--Replace ERROR and UNKNOWN with null (quantity, price_per_unit, total_spent)
			UPDATE cafe_sales_staging1
			SET quantity = NULL
			WHERE quantity = 'ERROR' OR quantity = 'UNKNOWN';
			
			UPDATE cafe_sales_staging1
			SET price_per_unit = NULL
			WHERE price_per_unit = 'ERROR' OR price_per_unit = 'UNKNOWN';
			
			UPDATE cafe_sales_staging1
			SET total_spent = NULL
			WHERE total_spent = 'ERROR' OR total_spent = 'UNKNOWN';
			
		--Change to numeric data type
			ALTER TABLE cafe_sales_staging1
			ALTER COLUMN quantity TYPE NUMERIC(5,1)
			USING quantity::NUMERIC(5,1);
			
			ALTER TABLE cafe_sales_staging1
			ALTER COLUMN price_per_unit TYPE NUMERIC(5,1)
			USING price_per_unit::NUMERIC(5,1);
			
			ALTER TABLE cafe_sales_staging1
			ALTER COLUMN total_spent TYPE NUMERIC(5,1)
			USING total_spent::NUMERIC(5,1);
			
		--Calculate missing numeric values - update each field when the other two fields are not null
			UPDATE cafe_sales_staging1
			SET 
			    quantity = CASE 
			                 WHEN quantity IS NULL AND price_per_unit IS NOT NULL AND total_spent IS NOT NULL 
			                 THEN total_spent / price_per_unit 
			                 ELSE quantity 
			               END,
			    price_per_unit = CASE 
			                      WHEN price_per_unit IS NULL AND quantity IS NOT NULL AND total_spent IS NOT NULL 
			                      THEN total_spent / quantity 
			                      ELSE price_per_unit 
			                    END,
			    total_spent = CASE 
			                    WHEN total_spent IS NULL AND quantity IS NOT NULL AND price_per_unit IS NOT NULL 
			                    THEN quantity * price_per_unit 
			                    ELSE total_spent 
			                  END;

	-- 3c Cleaning the categorical variables and transaction_date

		-- Create 2nd staging table
			CREATE TABLE cafe_sales_staging2 AS
			SELECT *
			FROM cafe_sales_staging1;
			
		-- Update missing vales in categorical fields and transaction_date to null
			UPDATE cafe_sales_staging2
			SET item = NULL
			WHERE item = 'ERROR' OR item = 'UNKNOWN';
			
			UPDATE cafe_sales_staging2
			SET payment_method = NULL
			WHERE payment_method = 'ERROR' OR payment_method = 'UNKNOWN';
			
			UPDATE cafe_sales_staging2
			SET location = NULL
			WHERE location = 'ERROR' OR location = 'UNKNOWN';
			
			UPDATE cafe_sales_staging2
			SET transaction_date = NULL
			WHERE transaction_date = 'ERROR' OR transaction_date = 'UNKNOWN';
			
		-- Change transaction_date from Text to Date type
			UPDATE cafe_sales_staging2
			SET transaction_date = TO_DATE(transaction_date, 'YYYY-MM-DD');
			
			ALTER TABLE cafe_sales_staging2
			ALTER COLUMN transaction_date TYPE DATE
			USING transaction_date::DATE;

	-- 3d Updating null price per unit for items, updating null items where they have a price per unit match
		-- Where item is known and price_per_unit is null, update price per unit to the item price
			UPDATE cafe_sales_staging2
			SET price_per_unit = (
			  CASE
			    WHEN price_per_unit IS NULL AND item IS NOT NULL
			    THEN (
			      SELECT MAX(price_per_unit) 
			      FROM cafe_sales_staging2 AS t2
			      WHERE t2.item = cafe_sales_staging2.item
			        AND t2.price_per_unit IS NOT NULL
			    )
			    ELSE price_per_unit
			  END
			);
	
		-- Identify null items which have prices 
			SELECT item, price_per_unit
			FROM cafe_sales_staging2
			GROUP BY item, price_per_unit
			ORDER BY price_per_unit, item
			-- Can see that cake and juice have same price (3) as well as sandwich and smoothie (4)
			
		-- Update price_per_unit on remaining items which have unique prices and these to "Cake or Juice" and "Sandwich or Smoothie"
			UPDATE cafe_sales_staging2
			SET item = (
				CASE
			    WHEN item IS NULL AND price_per_unit = 1.0 THEN 'Cookie'
				WHEN item IS NULL AND price_per_unit = 1.5 THEN 'Tea'
				WHEN item IS NULL AND price_per_unit = 2.0 THEN 'Coffee'
				WHEN item IS NULL AND price_per_unit = 3.0 THEN 'Cake or Juice'
				WHEN item IS NULL AND price_per_unit = 4.0 THEN 'Sandwich or Smoothie'
				WHEN item IS NULL AND price_per_unit = 5.0 THEN 'Salad'
			    ELSE item
			  	END
			);
		--Calculate missing numeric values - update each field when the other two fields are not null
			UPDATE cafe_sales_staging2
			SET 
			    quantity = CASE 
			                 WHEN quantity IS NULL AND price_per_unit IS NOT NULL AND total_spent IS NOT NULL 
			                 THEN total_spent / price_per_unit 
			                 ELSE quantity 
			               END,
			    price_per_unit = CASE 
			                      WHEN price_per_unit IS NULL AND quantity IS NOT NULL AND total_spent IS NOT NULL 
			                      THEN total_spent / quantity 
			                      ELSE price_per_unit 
			                    END,
			    total_spent = CASE 
			                    WHEN total_spent IS NULL AND quantity IS NOT NULL AND price_per_unit IS NOT NULL 
			                    THEN quantity * price_per_unit 
			                    ELSE total_spent 
			                  END;
			
		--Checking for remaining missing values
			SELECT * FROM cafe_sales_staging2
			WHERE (quantity IS NULL OR price_per_unit IS NULL OR total_spent IS NULL)
			-- Dataset now only has 26 rows with missing quantity, price_per_unit or payment_method information vs 1456 rows originally
			-- I will remove these records as they don't provide enough information for meaningful analysis
			
			DELETE FROM cafe_sales_staging2
			WHERE (quantity IS NULL OR price_per_unit IS NULL OR total_spent IS NULL);
			
			
		-- Finally I would like to introduce a new field category (food, drink, null)
			ALTER TABLE cafe_sales_staging2
			ADD COLUMN category TEXT;
			
			UPDATE cafe_sales_staging2
			SET category = CASE 
			    WHEN item IN('Cake', 'Cookie', 'Salad', 'Sandwich') THEN 'Food'
			    WHEN item IN('Coffee', 'Juice', 'Smoothie', 'Tea') THEN 'Drink'
			    ELSE NULL
			END;
		
--Step 4. Create final table cafe_sales_clean
			CREATE TABLE cafe_sales_clean AS
			SELECT transaction_id, category, item, quantity, price_per_unit, total_spent, payment_method, location, transaction_date      
			FROM cafe_sales_staging2
			LIMIT 0;
			
			INSERT INTO cafe_sales_clean (transaction_id, category, item, quantity, price_per_unit, total_spent, payment_method, location, transaction_date)
			SELECT transaction_id, category, item, quantity, price_per_unit, total_spent, payment_method, location, transaction_date
			FROM cafe_sales_staging2;
			
			SELECT *
			FROM cafe_sales_clean



