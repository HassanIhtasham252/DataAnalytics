select * from customer_nodes;
select * from customer_transactions;
select * from regions;

-- Customer Nodes Exploration

-- 1. How many unique nodes are there on the Data Bank system?
 
select Distinct node_id
from customer_nodes;

-- Answer: There are 5 unique nodes on the Data Bank System.

-- 2. What is the number of nodes per region?

select region_id,count(node_id)
from customer_nodes
group by region_id
order by region_id asc;

/* Answer: The number of nodes per region are as follows:

1: 770 Australia
2: 735 America
3: 714 Africa
4. 665 Asia
5. 616 Europe */

-- 3. How many customers are allocated to each region?

select region_id,count(distinct customer_id)
from customer_nodes
group by region_id;


/* Answer: The number of customers per region are as follows:

1: 110 Australia
2: 105 America
3: 102 Africa
4. 95 Asia
5. 88 Europe */

-- 4. How many days on average are customers reallocated to a different node?

select avg(datediff(end_date, start_date)) as AverageNo_ofDays
from customer_nodes
where end_date IS NOT NULL AND YEAR(end_date) <> 9999;

/* Answer: The average no. of days after which customers are reallocated
to a different node is 14.6 days ~ 15 days */

/*5. What is the median, 80th and 95th percentile for this same reallocation
days metric for each region? */

select region_id,(max(datediff(end_date, start_date)) - min(datediff(end_date, start_date)))/2 as median, 
0.85*count(dense_rank(select * from customer_nodes))
from customer_nodes
where datediff(end_date, start_date)<100
group by region_id
order by region_id Asc;

select count(*), region_id
from customer_nodes
group by region_id;

SELECT 
  r.region_id,
  AVG(CASE WHEN rn = FLOOR(0.5 * cnt + 0.5) THEN ReallocationDays END) AS 'Median',
  AVG(CASE WHEN rn = FLOOR(0.8 * cnt + 0.5) THEN ReallocationDays END) AS 'P80',
  AVG(CASE WHEN rn = FLOOR(0.95 * cnt + 0.5) THEN ReallocationDays END) AS 'P95'
FROM (
  SELECT 
    cn.region_id,
    DATEDIFF(cn.end_date, cn.start_date) AS ReallocationDays,
    @rn := IF(@prev_region = cn.region_id, @rn + 1, 1) AS rn,
    @cnt := IF(@prev_region = cn.region_id, @cnt, (SELECT COUNT(*) FROM customer_nodes WHERE region_id = cn.region_id)) AS cnt,
    @prev_region := cn.region_id
  FROM 
    customer_nodes cn,
    (SELECT @rn := 0, @cnt := 0, @prev_region := NULL) r
  ORDER BY 
    cn.region_id, DATEDIFF(cn.end_date, cn.start_date)
) AS ranked
JOIN regions r ON ranked.region_id = r.region_id
GROUP BY region_id;

-- Customer Transactions

-- 1. What is the unique count and total amount for each transaction type?

select count(txn_type),sum(txn_amount), txn_type
from customer_transactions
group by txn_type;

/* 
2671	deposit
1580	withdrawal
1617	purchase

1359168	deposit
793003	withdrawal
806537	purchase */

-- 2. What is the average total historical deposit counts and amounts for all customers?

select avg(no_of_deposits), avg(total_txn_amount)
from ( 
select count(txn_type) as no_of_deposits, sum(txn_amount) as total_txn_amount, customer_id
from customer_transactions
where txn_type = 'deposit'
group by customer_id) as deposit_summary;

-- Answer: 5.3420 avg number of deposits while 2718.3360 is the avg deposit amount for all customers.

/* 3. For each month - how many Data Bank customers make more than 1
deposit and either 1 purchase or 1 withdrawal in a single month? */

Select count(distinct customer_id) as No_of_customers,extract(month from txn_date) as txn_month
from customer_transactions
where 
customer_id in (
select customer_id
from customer_transactions
where txn_type = 'deposit'
group by customer_id, extract(month from txn_date)
having count(*) >1)
and
customer_id In(
select customer_id
from customer_transactions
where txn_type in ('purchase','withdrawal')
group by extract(month from txn_date), customer_id
having count(distinct txn_type) >=1)
group by txn_month;

/* No_of_customers txn_month
381	1
368	2
370	3
251	4
*/
-- 4. What is the closing balance for each customer at the end of the month?


select customer_id, 
	   extract(month from txn_date) as month, 
       sum(case when txn_type='deposit' then txn_amount else 0 end) - 
       sum(case when txn_type in ('purchase','withdrawal') then txn_amount else 0 end)
       as closing_balance
from customer_transactions
group by customer_id,extract(month from txn_date)
order by customer_id,extract(month from txn_date);

-- 5. What is the percentage of customers who increase their closing balance by more than 5%?

Set sql_mode = '';

WITH ClosingBalances AS (
    SELECT 
        customer_id, 
        EXTRACT(MONTH FROM txn_date) AS month_number,
        monthname(txn_date) as month_name,
        SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END)
        AS closing_balance
    FROM 
        customer_transactions
    GROUP BY 
        customer_id, EXTRACT(MONTH FROM txn_date)
),

PercInc AS (
    SELECT 
        cb.customer_id, 
        cb.month_number, 
        cb.closing_balance,
        LAG(cb.closing_balance,1) OVER (PARTITION BY cb.customer_id ORDER BY cb.month_number) AS prev_month_closing_balance,
        (cb.closing_balance - LAG(cb.closing_balance,1) OVER (PARTITION BY cb.customer_id ORDER BY cb.month_number)) / LAG(cb.closing_balance) OVER (PARTITION BY cb.customer_id ORDER BY cb.month_number) * 100 AS perc_inc
    FROM 
        ClosingBalances cb
)

SELECT 
    COUNT(DISTINCT CASE WHEN perc_inc > 5 THEN customer_id END) AS customers_with_perc_inc_gt_5,
    COUNT(DISTINCT customer_id) AS total_customers,
    (COUNT(DISTINCT CASE WHEN perc_inc > 5 THEN customer_id END) * 100.0) / NULLIF(COUNT(DISTINCT customer_id), 0) AS percentage_of_customers_with_perc_inc_gt_5
FROM 
    PercInc;
    
-- C. DATA ALLOCATION CHALLENGE

-- Option 1: Data is allocated based off the amount of money at the end of the previous month?

SET SQL_mode = '';

WITH adjusted_amount AS (
SELECT customer_id, txn_type, 
EXTRACT(MONTH FROM (txn_date)) AS month_number, 
MONTHNAME(txn_date) AS month,
CASE 
WHEN  txn_type = 'deposit' THEN txn_amount
ELSE -txn_amount
END AS amount
FROM customer_transactions
),
balance AS (
SELECT customer_id, month_number, month,
SUM(amount) OVER(PARTITION BY customer_id, month_number ORDER BY month_number ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) 
AS running_balance
FROM adjusted_amount
),
allocation AS (
SELECT customer_id, month_number,month,
LAG(running_balance,1) OVER(PARTITION BY customer_id, month_number ORDER BY month_number) AS monthly_allocation
FROM balance
)
SELECT month_number,month,
SUM(CASE WHEN monthly_allocation < 0 THEN 0 ELSE monthly_allocation END) AS total_allocation
FROM allocation
GROUP BY 1,2
ORDER BY 1,2; 

/*month_number : month: total_allocation
1	January	480325
2	February	312219
3	March	396069
4	April	133485 */


 
-- Option 2: Data is allocated on the average amount of money kept in the
-- account in the previous 30 days

WITH updated_transactions AS (
SELECT customer_id, txn_type, 
EXTRACT(MONTH FROM(txn_date)) AS Month_number,
MONTHNAME(txn_date) AS month,
CASE
WHEN txn_type = 'deposit' THEN txn_amount
ELSE -txn_amount
END AS amount
FROM customer_transactions
),
balance AS (
SELECT customer_id, month, month_number,
SUM(amount) OVER(PARTITION BY customer_id, month_number ORDER BY customer_id, month_number 
ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_balance
FROM updated_transactions
),

avg_running AS(
SELECT customer_id, month,month_number,
AVG(running_balance) AS avg_balance
FROM balance
GROUP BY 1,2,3
ORDER BY 1

)
SELECT month_number,month, 
SUM(CASE WHEN avg_balance < 0 THEN 0 ELSE avg_balance END) AS allocation_balance
FROM avg_running
GROUP BY 1,2
ORDER by 1,2;

/*month_number : month: total_allocation
1	January	217827.2799
2	February	97159.8692
3	March	101812.0747
4	April	68871.4419 */

-- Option 3: Data is updated real-time
WITH updated_transactions AS (
SELECT customer_id, txn_type,
EXTRACT(MONTH FROM(txn_date)) AS month_number,
MONTHNAME(txn_date) AS month,
CASE
WHEN txn_type = 'deposit' THEN txn_amount
ELSE -txn_amount
END AS amount
FROM customer_transactions
),
balance AS (
SELECT customer_id, month_number, month, 
SUM(amount) OVER(PARTITION BY customer_id, month_number ORDER BY customer_id, month_number ASC 
ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_balance
FROM updated_transactions
)
SELECT month_number, month,
SUM(CASE WHEN running_balance < 0 THEN 0 ELSE running_balance END) AS total_allocation
FROM balance
GROUP BY 1,2
ORDER BY 1;

/*month_number : month: total_allocation
1	January	697003
2	February	443208
3	March	528041
4	April	216160 */
    
