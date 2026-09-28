use data_analysis_project

--analyze sales performance over time

select
year(order_date) as order_year,
format(order_date,'yyyy-MMM') as order_month, /* or if want the date in month use datetrunc */
sum(sales_amount) as total_sales,
count(distinct customer_key) as total_customers,
sum(quantity) as total_quantity
from gold.fact_sales
where order_date is not null
group by year(order_date),format(order_date,'yyyy-MMM')
order by year(order_date),format(order_date,'yyyy-MMM')

/* cumulative analysis
meaning :- aggregate the data progressively over time
helps to understand weather our business is growing or declining
formula:- cumulative / date dimension 
we can calculate like sales by year
moving average by year

using window fun

task :- calculate the total sales per month and the running total of sales over thime
and the running average

*/
select 
order_date,
total_sales,
sum(total_sales) over( order by order_date) runing_total,
avg(avg_price) over( order by order_date) moving_average

from(

	select 
	datetrunc(YEAR,order_date) as order_date,
	sum(sales_amount) as total_sales,
	avg(price) as avg_price
	from gold.fact_sales
	where order_date is not null
	group by datetrunc(YEAR,order_date)
	) t


/* performance analysis
meaning :- comparing the current value to a target value.
helps measure success and compare performance.
so using this we can measure 

current sales -target sales to know how well a product or a business is performing
current sales - average sales
current year sales - previous year sales (year over year) sales
current sales - lowest sales 

using window functions

task :- analyze the yearly performance of products by comparing their sales to both the average sales
performance of the product and the previous year sales

*/
with yearly_product_sales as (

	select 
	year(f.order_date) as order_year,
	p.product_name	,
	sum(f.sales_amount) as current_sales
	from gold.fact_sales f
	left join gold.dim_products p
	on p.product_key = f.product_key
	where order_date is not null
	group by year(order_date),p.product_name	
)

select 
order_year,
product_name,
current_sales,
avg(current_sales) over(partition by product_name) as avg_sales,
current_sales-avg(current_sales) over(partition by product_name) as diff_avg,
case when current_sales-avg(current_sales) over(partition by product_name) > 0 then 'above average'
	 when current_sales-avg(current_sales) over(partition by product_name) < 0 then 'below average'
	 else 'avg'
end avg_change,
--year over year analysis
lag(current_sales) over(partition by product_name order by order_year) py_sales,
current_sales-lag(current_sales) over(partition by product_name order by order_year) diff_py,
case when current_sales-lag(current_sales) over(partition by product_name order by order_year) > 0 then 'increased'
	 when current_sales-lag(current_sales) over(partition by product_name order by order_year) < 0 then 'decreased'
	 else 'no change'
end py_change
from  yearly_product_sales
order by product_name,order_year


/* part-to-whole-analysis
meaning : - analyze how an individual part is performing compared to the overall,
allowing us to understand which category has the greatest impact on the business

formula :- (measure / total measure) *100 
(sales / total sales) *100 by category
(quantity / total quantity)*100 by coumtry

task : - which categories contribute the most to overall sales

*/
with total_sales as 
(
select 
p.category,
sum(f.sales_amount) as over_all_sales
from gold.dim_products p
left join gold.fact_sales f
on f.product_key = p.product_key
  where p.category is not null
group by p.category
having sum(f.sales_amount) is not null
)
select 
category,
over_all_sales,
sum(over_all_sales) over() total_sales,
concat(round((cast(over_all_sales as float)/sum(over_all_sales) over()) * 100 ,2),'%')as [contribution to total]
from total_sales
order by over_all_sales desc


/*
data segmentation 
meaning : - group the data based on a specific range.
helps understand the correlation between two measures

formula : - measure / measure 
total products by sales range 
total customers by age 


task : - segment products into cost ranges and count how many products fall in each segment
*/
with product_segment as 
(
select 
product_key,
product_name,
cost,
case when cost < 100 then 'below 100'
	 when cost between 100 and 500 then ' 100-500'
	 when cost between 500 and 1000   then '500-1000'
	 else 'above 1000'
end cost_range
from gold.dim_products
)

select 
cost_range,
count(product_key) as total_products
from product_segment
group by cost_range
order by total_products desc

/*
task 2 :- group customers into three segments based on their spending behaviour :
-- vip at least 12 months of history and spending more than 5000
and regular atleast 12 months of history but spending 5000 or less 
and new lifespan less than 12 months 
and find the total number of customers by each group
*/
with customer_spendings as
(
select 
c.customer_key,
sum(f.sales_amount) as total_spending,
min(order_date) as first_order,
max(order_date) as last_order,
datediff(month,min(order_date),max(order_date)) as lifespam 
from gold.fact_sales f
left join gold.dim_customers c
on f.customer_key = c.customer_key
group by c.customer_key
) 
select customer_segment,
count(customer_key) as total_customers
from(
select 
customer_key,
case when lifespam >= 12 and total_spending > 5000 then 'vip'
	 when lifespam >= 12 and total_spending <= 5000 then 'regular'
	 else 'new customer'
end customer_segment 
from customer_spendings
) t
group by customer_segment
order by total_customers desc

/*
build customer report

purpose :-
	this report consolidates key customer metrics and behaviours
highlights :
	1.gathers essential fields such as names,ages, and transcation details.
	2.segments customers into categories (vip,regular,new) and group by ages
	3. aggergates customer-level metrics :
		- total orders
		- total sales
		- total quantity purchased
		- total products
		- lifespan (in months)
	4. calculates valuable kpi's:
		- recency (months since last order)
		- average order value
		- average monthly spend

*/
create view gold.report_customers as 
 with base_query as
(
	select 
	f.order_number,
	f.product_key,
	f.order_date,
	f.sales_amount,
	f.quantity,
	c.customer_key,
	c.customer_number,
	concat(c.first_name,' ' ,c.last_name) as customer_name,
	datediff(year,c.birthdate,getdate()) age
	from gold.fact_sales f
	left join gold.dim_customers c
	on c.customer_key = f.customer_key
	where order_date is not null
)
,
-- customer aggregations: summarizes key metrics at the customer level
customer_aggregation  as (

select 
		customer_key,
		customer_number,
		customer_name,
		age,
		count(distinct order_date) as total_orders,
		sum(sales_amount) as total_sales,
		sum(quantity) as total_quantity,
		max(order_Date) as last_order_date,
		DATEDIFF(month,min(order_date),max(order_date)) as lifespan
from base_query
group by 
		customer_key,
		customer_number,
		customer_name,
		age
) 

select 
	    customer_key,
		customer_number,
		customer_name,
		age,
		lifespan,
		case when age < 20  then 'under 20'
			 when age between 20 and 29 then '20-29'
			 when age between 30 and 39 then '30-39'
			 when age between 40 and 49 then '40-49'
			 else '50 and aboove'
		end as age_group ,
		case when lifespan >= 12 and total_sales > 5000 then 'vip'
	         when lifespan >= 12 and total_sales <= 5000 then 'regular'
	         else 'new customer'
		end as customer_segment,
		datediff(month,last_order_date,getdate()) as recency,
		total_orders,
		total_sales,
		total_quantity,
		last_order_date,
		--compute average order value
		case when total_sales = 0 then 0
			else total_sales/total_orders
		end as avg_order_value,
		-- avg monthly spend
		case when lifespan = 0 then total_sales
			else total_sales/lifespan
		end as avg_monthly_spend

from customer_aggregation

select * from gold.report_customers

/*
Product Report

	Purpose:
		This report consolidates key product metrics and behaviors.
		Highlights:
				1. Gathers essential fields such as product name, category, subcategory, and cost.
				2. Segments products by revenue to identify High-Performers, Mid-Range, or Low-Performers.
				3. Aggregates product-level metrics:
				   - total orders
				   - total sales
                   - total quantity sold
                   - total customers (unique)
                   - lifespan (in months)
                4. Calculates valuable KPIs:
                   - recency (months since last sale)
                   - average order revenue (AOR)
                   - average monthly revenue
 */
create view gold.report_products as 
with base_query as
(
	select 
		f.order_number,
		f.customer_key,
		f.order_date,
		f.sales_amount,
		f.quantity,
		p.product_key,
		p.product_name,
		p.category,
		p.subcategory,
		p.cost
		from gold.fact_sales f
		left join gold.dim_products p
		on p.product_key = f.product_key
) ,
--aggregations 
aggregations as
(

	select 
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	count(distinct order_number) as total_orders,
	count(distinct customer_key) as total_customers,
	sum(sales_amount) as total_sales,
	sum(quantity) as total_quantity,
	max(order_date) as last_order_date,
    datediff(month,min(order_date),max(order_Date)) as life_spam,
	round(avg(cast(sales_amount as float)/nullif(quantity,0)),1) as avg_selling_price
	from base_query
	group by 
	product_key,
	product_NAME,
	category,
	subcategory,
	cost
	
)
--final query

select
		product_key,
		product_name,
		category,
		subcategory,
		cost,
		last_order_date,
		datediff(month,last_order_date,getdate()) as recency_in_months,
		case when total_sales > 50000 then 'high performer'
			 when total_sales >= 10000 then 'mid range'
			 else ' low performer'
		end as product_segment,
		life_spam,
		total_orders,
		total_customers,
		total_sales,
		total_quantity,
		avg_selling_price,
	-- average order revenue(AOR)
		case when total_orders = 0  then 0
			 else total_sales/total_orders
			end as avg_order_revenue,
	-- average monthly revenue
		case when life_spam=0 then total_sales
			 else total_sales/life_spam
		end as avg_monthly_revenue
	from aggregations


	select * from gold.report_products


