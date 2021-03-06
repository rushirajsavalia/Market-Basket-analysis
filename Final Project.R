library(data.table)
library(dplyr)
library(tidyr)
library(Ckmeans.1d.dp)
library(ggplot2)
library(knitr)
library(stringr)

setwd("C:/Users/Rushiraj/Desktop/NU/Data mining/Project files")

aisles <- read.csv("aisles.csv", na.strings = "", stringsAsFactors=FALSE)
departments <- read.csv("departments.csv", na.strings = "", stringsAsFactors=FALSE)
orderp <- read.csv("order_products__prior.csv", na.strings = "", stringsAsFactors=FALSE)
ordert <- read.csv("order_products__train.csv", na.strings = "", stringsAsFactors=FALSE)
orders <- read.csv("orders.csv", na.strings = "", stringsAsFactors=FALSE)
products <- read.csv("products.csv", na.strings = "", stringsAsFactors=FALSE)

glimpse(aisles)
glimpse(departments)
glimpse(orderp)
glimpse(orders)
glimpse(ordert)
glimpse(products)

head(aisles,10)
head(departments,10)
head(orderp,10)
head(orders,10) 
head(ordert,10)
head(products,10)

#When people buy groceries online.

orders %>% 
  ggplot(aes(x=order_hour_of_day)) + 
  geom_histogram(stat="count",fill="blue")

#Hour of Day
#There is a clear effect of hour of day on order volume. Most orders are between 8.00-18.00

orders %>% 
  ggplot(aes(x=order_dow)) + 
  geom_histogram(stat="count",fill="blue")
#Most orders are on days 0 and 1 which is Sunday and Monday. 

#When do they order again?

orders %>% 
  ggplot(aes(x=days_since_prior_order)) + 
  geom_histogram(stat="count",fill="blue")

#People seem to order more often after exactly 1 week.

#Convert all categorial variable to factor as we can use them to make better model 
aisles$aisle <- as.factor(aisles$aisle)
departments$department <- as.factor(departments$department)
orders$eval_set <- as.factor(orders$eval_set)
products$product_name <- as.factor(products$product_name)

#In the products table, replace aisle_id and department_id with aisle name and department name
products <- products %>% 
  inner_join(aisles) %>% 
  inner_join(departments) %>% 
  select(-aisle_id, -department_id)

#Now we don't need ailes and departments so we will remove it. 
rm(aisles, departments)

#New products table
head(products,10)

#Add the column user_id to model
ordert$user_id <- orders$user_id[match(ordert$order_id, orders$order_id)]

#Check model
head(ordert,10)

#Create a new table orders_products which contains the tables "orders" and orderp to make model
orders_products <- orders %>% inner_join(orderp, by = "order_id")

#remove orderp
rm(orderp)
#clear memory for smooth process
gc()

#Make new orders_products table
head(orders_products,10)

# We create the prd and we start with the data inside the orders_products table
#Create temporary prd to create model which contains data from order_products 
prd <- orders_products %>%
  arrange(user_id, order_number, product_id) %>%
  group_by(user_id, product_id) %>% 
  mutate(product_time = row_number()) %>%        #Create the new variable product time through row_number()
  ungroup()                                      #Identified how many times a user bought a product

#See the temporary prd table
head(prd,10)

prd <- prd %>%
  group_by(product_id) %>%                        #Group by product_id
  summarise(
    prod_orders = n(),                          #Total number of orders per product    
    prod_reorders = sum(reordered),             #Total number of reorders per product    
    prod_first_orders = sum(product_time == 1),
    prod_second_orders = sum(product_time == 2))

#See the temporary prd table
head(prd,10)

#Calculate prod_reorder_probability variable
prd$prod_reorder_probability <- prd$prod_second_orders / prd$prod_first_orders
#Caclculate the prod_reorder_times variable
prd$prod_reorder_times <- 1 + prd$prod_reorders / prd$prod_first_orders
#Caclculate the prod_reorder_ratio variable
prd$prod_reorder_ratio <- prd$prod_reorders / prd$prod_orders

#Remove the prod_reorders, prod_first_orders, and prod_second_orders variables
prd <- prd %>% select(-prod_reorders, -prod_first_orders, -prod_second_orders)

#Remove products table
rm(products)
#clear memory for smooth process
gc()

#See the final prd table
head(prd,20)

users <- orders %>%
  filter(eval_set == "prior") %>%                       #Keep only prior order
  group_by(user_id) %>%                                 #Group orders by user_id
  summarise(                                            #Total number of orders per user
    user_orders = max(order_number),                    #Omit the missing values and calculate the sum and mean
    user_period = sum(days_since_prior_order, na.rm = T),
    user_mean_days_since_prior = mean(days_since_prior_order, na.rm = T))

#See the temporary users table
head(users,10)

us <- orders_products %>%
  group_by(user_id) %>%
  summarise(
    user_total_products = n(),
    user_reorder_ratio = sum(reordered == 1) / sum(order_number > 1),
    user_distinct_products = n_distinct(product_id) #Counts the number of unique values in model
  )

#See the us table
head(us,10)

#Combine users and us tables and store the results into users table
users <- users %>% inner_join(us)

#Calculate the user_average_basket variable
users$user_average_basket <- users$user_total_products / users$user_orders

#See the users table
head(users,10)

us <- orders %>%
  filter(eval_set != "prior") %>%        #Exclude prior orders and keep only train and test order
  select(user_id, order_id, eval_set,time_since_last_order = days_since_prior_order)

#Combine users and us tables and store the results into the users table
users <- users %>% inner_join(us)

#Remove the us table
rm(us)
#Garbage collection. clear memory for smooth process
gc()

#See the final users table
head(users,10)

data <- orders_products %>%
  group_by(user_id, product_id) %>% 
  summarise(
    up_orders = n(),
    up_first_order = min(order_number),
    up_last_order = max(order_number),
    up_average_cart_position = mean(add_to_cart_order))

#Remove the tables orders_products and orders
rm(orders_products, orders)

#See the temporary data table
head(data, 10)

#use inner_join to combine the table data with the tables prd and users
data <- data %>%                      
  inner_join(prd, by = "product_id") %>%
  inner_join(users, by = "user_id")

#Calculate up_order_rate, up_orders_since_last_order, up_order_rate_since_first_order
data$up_order_rate <- data$up_orders / data$user_orders
data$up_orders_since_last_order <- data$user_orders - data$up_last_order
data$up_order_rate_since_first_order <- data$up_orders / (data$user_orders - data$up_first_order + 1)

#See the temporary data table
head(data, 10)

data <- data %>% 
  left_join(ordert %>% select(user_id, product_id, reordered), 
            by = c("user_id", "product_id"))

#Remove the tables ordert, prd, users
rm(ordert, prd, users)
#Garbage collection. clear memory for smooth process
gc()

#See the final data table. Final model 
head(data, 10)

#Training Model
train <- as.data.frame(data[data$eval_set == "train",])
train$eval_set <- NULL
train$user_id <- NULL
#Transform missing values of reordered variable to 0
train$reordered[is.na(train$reordered)] <- 0

#See train table
head(train,10)

#Testing Model
test <- as.data.frame(data[data$eval_set == "test",])
test$eval_set <- NULL
test$user_id <- NULL
test$reordered <- NULL

#See test table
head(test,10)

library(xgboost)

params <- list(
  "objective"           = "reg:logistic",
  "eval_metric"         = "logloss", 
  "eta"                 = 0.1, 
  "max_depth"           = 6, 
  "min_child_weight"    = 10,  
  "gamma"               = 0.70,  
  "subsample"           = 0.76,
  "colsample_bytree"    = 0.95,  
  "alpha"               = 2e-05,  
  "lambda"              = 10 
)

#Sampling technique. 10% of the train table
subtrain <- train %>% sample_frac(0.1)
#Create an xgb.DMatrix that is named X with predictors from subtrain table and response the reordered variable
X <- xgb.DMatrix(as.matrix(subtrain %>% select(-reordered, -order_id, -product_id)), label = subtrain$reordered)
#Create the actual model
model <- xgboost(data = X, params = params, nrounds = 80)

#Estimate the importance of the predictors
importance <- xgb.importance(colnames(X), model = model)
#Plot the importance of the predictors
xgb.ggplot.importance(importance)

rm(X, importance, subtrain)
gc()

#Use the xgb.DMatrix to group our test data into a matrix
X <- xgb.DMatrix(as.matrix(test %>% select(-order_id, -product_id)))
#Apply the model and we predict the reordered variable for the test set.
test$reordered <- predict(model, X)
#The model estimates a probability. 
#Apply a threshold so every prediction above 0.21 will be considered as a reorder (reordered=1)
test$reordered <- (test$reordered > 0.21) * 1

#Create the final table with reordered products per order
submission <- test %>%
  filter(reordered == 1) %>%
  group_by(order_id) %>%
  summarise(products = paste(product_id, collapse = " "))
#submission table
head(submission,10)

#Create the table missing where we have the orders in which none product will be ordered according to our prediction
missing <- data.frame(
  order_id = unique(test$order_id[!test$order_id %in% submission$order_id]),
  products = "None"
)

submission <- submission %>% bind_rows(missing) %>% arrange(order_id)
#See the submission table
head(submission,10)

#Use the xgb.DMatrix to group our train data into a matrix
X <- xgb.DMatrix(as.matrix(train %>% select(-order_id, -product_id, -reordered)))
#Apply the model and we predict the reordered variable for the train set.
train$reordered_pred <- predict(model, X)
#The model estimates a probability. 
#Apply a threshold so every prediction above 0.21 will be considered as a reorder (reordered=1)
train$reordered_pred <- (train$reordered_pred > 0.21) * 1

#Create the final table with reordered products per order
submission_train <- train %>%
  filter(reordered_pred == 1) %>%
  group_by(order_id) %>%
  summarise(products = paste(product_id, collapse = " "))

real_reorders <- train %>%
  filter(reordered == 1) %>%
  group_by(order_id) %>%
  summarise(
    real_products = paste(product_id, collapse = " "))

submission_train <- real_reorders %>% 
  inner_join(submission_train, by = "order_id") 

#See the submission table
head(submission_train,10)

