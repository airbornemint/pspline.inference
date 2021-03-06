# Copyright 2017-2019 Ben Artin
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Sample spline parameters
#' @param model spline GAM
#' @param samples number of samples
#' @keywords internal
sample.params = function(model, samples) {
  mu = stats::coef(model)
  sig = model$Vp
  sigL = mgcv::mroot(sig)
  colL = ncol(sigL)

  t(mu + sigL %*% matrix(rnorm(colL * samples), colL, samples))
}

#' Eval model prediction with given model params at given predictors
#' @param params model params
#' @param model model to evaluate
#' @param predictors predictor values at which to evaluate
#' @param outcome outcome function
#' @return data frame of model evaluated with params at predictors
#' @keywords internal
eval.model = function(params, model, predictors, outcome) {
  # Get model predictions for given param values
  fit = predict(model, predictors, type="lpmatrix") %*% params

  model %>% outcome(
    predictors %>%
      mutate(
        pspline.out=model$family$linkinv(fit)
      ) %>%
      rename_at("pspline.out", function(x) model.var(model))
  )
}

#' @keywords internal
quantile.multi = function(data, probs, prob.names) {
  names(data) %>%
    ldply(function(name) {
      data.frame(t(quantile(data[[name]], probs=probs, names=FALSE, na.rm=TRUE))) %>%
        setNames(prob.names) %>%
        mutate(name=name)
    }) %>%
    melt(id.vars="name") %>%
    mutate(variable=sprintf(as.character(.data$variable), .data$name)) %>%
    dcast(. ~ variable) %>%
    select(-".")
}

#' Calculate quantiles of model outcome variables
#' @param data data.frame containing predictor variables and outcome variables
#' @param model associated model (its formula is used to determine which variables in \code{data} are predictors and which are outcomes)
#' @param probs probabilities at which quantiles will be calculated (same as for `quantile`)
#' @param prob.names format strings used to construct names of the new data columns. For example, if \code{probs} is 0.05 and
#' \code{prob.names} is \code{\%s.lower}, then the 5th percentile of each outcome variable \code{var} will be returned in \code{var.lower}.
#' @return data frame of predictors and associated outcome quantiles.
#' @keywords internal
quantile.outcomes = function(data, model, probs, prob.names) {
  predictors = intersect(names(data), pred.vars(model))

    confints = function(samples) {
      samples %>% 
        select(-.data$pspline.sample) %>% 
        quantile.multi(probs, prob.names)
    }

  if (length(predictors) > 0) {
    data %>%
      group_by_at(predictors) %>%
      summarize(confints(across())) %>%
      ungroup()
  } else {
    data %>% summarize(confints(across()))
  }
}

#' Return empirical CDF for model outcome variables
#' @param data data.frame containing predictor variables and outcome variables
#' @param model associated model (its formula is used to determine which variables in \code{data} are predictors and which are outcomes)
#' @return list of ECDFs
#' @keywords internal
ecdf.outcomes = function(data, model) {
  data %<>% select(-.data$pspline.sample)
  outcomes = setdiff(names(data), pred.vars(model))
  lapply(outcomes, function(outcome) {
    ecdf(data[[outcome]])
  }) %>% setNames(outcomes)
}

#' Calculate confidence intervals of model outcome variables
#' @param data data frame containing predictor and outcome variables
#' @param model associated model
#' @param level confidence level
#' @return data frame of predictors and associated lower CL, median, and upper CL
#' @keywords internal
confints.outcomes = function(data, model, level) {
  quantile.outcomes(
    data, model,
    c((1 - level) / 2, .5, (1 + level) / 2),
    c("%s.lower", "%s.median", "%s.upper")
  )
}

pred.vars = function(model) {
  all.vars(model$pred.formula)
}

pred.var = function(model) {
  vars = pred.vars(model)
  assert_that(length(vars) == 1, msg="Exactly one predictor is required for this computation")
  vars[1]
}

model.vars = function(model) {
  setdiff(all.vars(model$formula), all.vars(model$pred.formula))
}

model.var = function(model) {
  vars = model.vars(model)
  assert_that(length(vars) == 1, msg="Exactly one model variable is required for this computation")
  vars[1]
}
