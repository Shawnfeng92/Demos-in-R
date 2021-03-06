#
# Author: Xiaokang Feng
# GitHub: https://github.com/Shawnfeng92
#
# In this script, I will show you how to use linear programming problem solver ("Rglpk")
# to finish portfolio opimization with MAD related utility function.
#
# The MAD means mean absolute deviation It describes the degree of volatility of your
# portfolio. Also, people tend to use the true volatility or Sharpe Ratio as a risk
# measure to do portfolio optimization. They each have their own strengthes and 
# weaknesses.
#
# The Sharpe Ratio is well adopted in financial industry. But Sharpe Ratio optimization
# requires quadratic programming which is more complex to handle. Besides, Sharpe Ratio
# asks for a stable covariance matrix to predict future portfolio performance, while 
# the prediciton of covariance matrix is almost impossible.
#
# The MAD measures the distance of each possible return to mean return of portfolio. It 
# can describe the degree of volatility of the return distribution. Since we can use lp
# solve to solve MAD problems, it is a robust optimization, and we can customize the 
# objective function. 
#
# As a benefit of linear programming, we can add position limitation to this type
# optimization. However, the strick position limitation will increase the processing time
# at a time complex as O(e^n). So, I suggest use soft position limiation and will 
# introduce a tolerance parameter in the final version.
#

library(xts)
library(zoo)
library(Rglpk)

# Load price data as time series type
prices <- xts(read.csv.zoo(
  file = "~/GitHub/Demos/1. Data/DataStorage/AMEX.csv",
  FUN = as.Date
))

# Daily log return data
raw.returns <- diff(log(prices))

# Process optimization on stocks with full 2019 performance
raw.returns <- raw.returns["2019"]
raw.returns <- raw.returns[rowSums(is.na(raw.returns)) < ncol(raw.returns) - 5, ]
raw.returns <- raw.returns[, colSums(is.na(raw.returns)) == 0]

returns <- raw.returns[, 1:31]

# Create a min MAD optimization with simple leverage and box constraints ----
mMAD <- list()
mMAD$risk <- "MAD"

# Summary parameter
mMAD$scenarios <- nrow(returns)
mMAD$tickers <- ncol(returns)
mMAD$mu <- colMeans(returns)

# Constraints
mMAD$leverage <- 1.5
mMAD$uL <- 1 # Upper limitation for box constrain
mMAD$lL <- -1 # Lower limitation

# Objective function, weight + absolute distance
mMAD$obj <- c(
  rep(0, mMAD$tickers),
  rep(1, mMAD$scenarios)
)

# Constraint Matrix
mMAD$cM <- rbind(
  c(rep(1, mMAD$tickers), rep(0, mMAD$scenarios)),
  cbind(
    matrix(
      returns - matrix(rep(mMAD$mu, mMAD$scenarios), mMAD$scenarios),
      mMAD$scenarios
    ), diag(1, mMAD$scenarios)
  ),
  cbind(
    matrix(
      -returns + matrix(rep(mMAD$mu, mMAD$scenarios), mMAD$scenarios),
      mMAD$scenarios
    ), diag(1, mMAD$scenarios)
  )
)

# Optimization result
mMAD$time <- system.time(
  mMAD$result <- Rglpk_solve_LP(
    obj = mMAD$obj, mat = mMAD$cM,
    dir = c("==", rep(">=", 2 * mMAD$scenarios)),
    bounds = list(
      lower = list(
        ind = 1:mMAD$tickers,
        val = rep(mMAD$lL, mMAD$tickers)
      ),
      upper = list(
        ind = 1:mMAD$tickers,
        val = rep(mMAD$uL, mMAD$tickers)
      )
    ),
    rhs = c(mMAD$leverage, rep(0, 2 * mMAD$scenarios)),
    max = FALSE
  )
)

# Outputs
mMAD$weight <- mMAD$result$solution[1:mMAD$tickers]
mMAD$MAD <- mMAD$result$optimum
names(mMAD$weight) <- colnames(returns)

# Create a min MAD optimization with position constraints ----
mMAD.p <- mMAD

# Add position limitation
mMAD.p$pL <- 15

# Objective function, weight + absolute distance + position index
mMAD.p$obj <- c(
  rep(0, mMAD.p$tickers),
  rep(1, mMAD.p$scenarios),
  rep(0, mMAD.p$tickers)
)

# Constraint Matrix
mMAD.p$cM <- rbind(
  c(rep(1, mMAD.p$tickers), rep(0, mMAD.p$scenarios), rep(0, mMAD.p$tickers)),
  c(rep(0, mMAD.p$tickers), rep(0, mMAD.p$scenarios), rep(1, mMAD.p$tickers)),
  cbind(
    matrix(
      returns - matrix(rep(mMAD.p$mu, mMAD.p$scenarios), mMAD.p$scenarios),
      mMAD.p$scenarios
    ),
    diag(1, mMAD.p$scenarios),
    matrix(0, mMAD.p$scenarios, mMAD.p$tickers)
  ),
  cbind(
    matrix(
      -returns + matrix(rep(mMAD.p$mu, mMAD.p$scenarios), mMAD.p$scenarios),
      mMAD.p$scenarios
    ),
    diag(1, mMAD.p$scenarios),
    matrix(0, mMAD.p$scenarios, mMAD.p$tickers)
  ),
  cbind(
    diag(1, mMAD.p$tickers), matrix(0, mMAD.p$tickers, mMAD.p$scenarios),
    diag(-mMAD.p$lL, mMAD.p$tickers)
  ),
  cbind(
    diag(-1, mMAD.p$tickers), matrix(0, mMAD.p$tickers, mMAD.p$scenarios),
    diag(mMAD.p$uL, mMAD.p$tickers)
  )
)

# Optimization result
mMAD.p$time <- system.time(
  mMAD.p$result <- Rglpk_solve_LP(
    obj = mMAD.p$obj, mat = mMAD.p$cM,
    dir = c("==", "<=", rep(">=", 2 * mMAD.p$scenarios + 2 * mMAD.p$tickers)),
    bounds = list(
      lower = list(
        ind = 1:mMAD.p$tickers,
        val = rep(mMAD.p$lL, mMAD.p$tickers)
      ),
      upper = list(
        ind = 1:mMAD.p$tickers,
        val = rep(mMAD.p$uL, mMAD.p$tickers)
      )
    ),
    rhs = c(
      mMAD.p$leverage, mMAD.p$pL, rep(0, 2 * mMAD.p$scenarios),
      rep(-0.005, 2 * mMAD.p$tickers)
    ),
    types = c(
      rep("C", mMAD.p$tickers + mMAD.p$scenarios),
      rep("B", mMAD.p$tickers)
    ),
    max = FALSE
  )
)

# Outputs
mMAD.p$weight <- mMAD.p$result$solution[1:mMAD.p$tickers]
mMAD.p$MAD <- mMAD.p$result$optimum
names(mMAD.p$weight) <- colnames(returns)

# Create a max ratio of return over MAD optimization ----
mMAD.r <- mMAD


# Objective function, weight + absolute distance + shrinkage
mMAD.r$obj <- c(
  rep(0, mMAD.r$tickers),
  rep(1, mMAD.r$scenarios),
  0
)

# Constraint Matrix
mMAD.r$cM <- rbind(
  c(rep(1, mMAD.r$tickers), rep(0, mMAD.r$scenarios), -mMAD.r$leverage),
  c(mMAD.r$mu, rep(0, mMAD.r$scenarios), 0),
  cbind(
    matrix(
      returns - matrix(rep(mMAD.r$mu, mMAD.r$scenarios), mMAD.r$scenarios),
      mMAD.r$scenarios
    ), diag(1, mMAD.r$scenarios), rep(0, mMAD.r$scenarios)
  ),
  cbind(
    matrix(
      -returns + matrix(rep(mMAD.r$mu, mMAD.r$scenarios), mMAD.r$scenarios),
      mMAD.r$scenarios
    ), diag(1, mMAD.r$scenarios), rep(0, mMAD.r$scenarios)
  ),
  cbind(
    diag(-1, mMAD.r$tickers),
    matrix(0, mMAD.r$tickers, mMAD.r$scenarios),
    rep(mMAD.r$uL, mMAD.r$tickers)
  ),
  cbind(
    diag(1, mMAD.r$tickers),
    matrix(0, mMAD.r$tickers, mMAD.r$scenarios),
    rep(-mMAD.r$lL, mMAD.r$tickers)
  )
)

# Optimization result
mMAD.r$time <- system.time(
  mMAD.r$result <- Rglpk_solve_LP(
    obj = mMAD.r$obj, mat = mMAD.r$cM,
    dir = c("==", "==", rep(">=", 2 * mMAD.r$scenarios + 2 * mMAD.r$tickers)),
    bounds = list(
      lower = list(
        ind = 1:mMAD.r$tickers,
        val = rep(-Inf, mMAD.r$tickers)
      ),
      upper = list(
        ind = 1:mMAD.r$tickers,
        val = rep(Inf, mMAD.r$tickers)
      )
    ),
    rhs = c(0, 1, rep(0, 2 * mMAD.r$scenarios + 2 * mMAD.r$tickers)),
    max = FALSE
  )
)

# Outputs
mMAD.r$shrinkage <- mMAD.r$result$solution[length(mMAD.r$obj)]
mMAD.r$weight <- mMAD.r$result$solution[1:mMAD.r$tickers] / mMAD.r$shrinkage
mMAD.r$MAD <- mMAD.r$result$optimum / mMAD.r$shrinkage
names(mMAD.r$weight) <- colnames(returns)
