# Utility functions that act as wrappers around
# the utilities from other utils files
source("import_utils.R")
source("dose_utils.R")
source("optim_utils.R")
source("final_size_utils.R")
source("NGM_utils.R")
calc_targets <- function(params,
                         targets = c("Infections", "Hospitalizations", "Deaths"),
                         strategies = c("Uniform", "Vulnerable", "Transmitters"),
                         target_coverages = seq(0, 1.0, 0.2),
                         vacc_program = list(
                           "vacc_types" = c("Pfizer", "Sinovac"),
                           "vacc_percs" = c(20, 80)
                         ),
                         eligibility_cutoff = 15,
                         # include_children = FALSE,
                         uptake = 1.0,
                         cutoff = 60) {
  out <- expand.grid(
    Strategy = strategies,
    Vaccine = list("any vacc" = c("any vacc")),
    Coverage = target_coverages
  )

  out$Infections <- rep(NA, nrow(out))
  out$Hospitalizations <- rep(NA, nrow(out))
  out$Deaths <- rep(NA, nrow(out))

  out_lower <- out
  out_upper <- out

  params_central <- params
  params_lower <- params
  params_upper <- params

  for (i in 1:nrow(out)) {
    # Calculate age-specific vaccination coverage
    if (eligibility_cutoff == 15) {
      vacc_prop <- calc_age_specific_coverage_over_15(
        target_coverage = out$Coverage[i],
        params = params,
        strategy = out$Strategy[i],
        uptake = uptake
      )
    } else if (eligibility_cutoff == 10) {
      vacc_prop <- calc_age_specific_coverage_over_10(
        target_coverage = out$Coverage[i],
        params = params,
        strategy = out$Strategy[i],
        uptake = uptake
      )
    } else if (eligibility_cutoff == 5) {
      vacc_prop <- calc_age_specific_coverage_over_5(
        target_coverage = out$Coverage[i],
        params = params,
        strategy = out$Strategy[i],
        uptake = uptake
      )
    }
    # if (include_children) {
    #   vacc_prop = calc_age_specific_coverage_children_included(
    #     target_coverage = out$Coverage[i],
    #     params = params,
    #     strategy = out$Strategy[i],
    #     uptake = uptake
    #   )
    # } else{
    #   vacc_prop = calc_age_specific_coverage(
    #     target_coverage = out$Coverage[i],
    #     params = params,
    #     strategy = out$Strategy[i],
    #     uptake = uptake
    #   )
    # }

    # Update the vaccine efficacy given the current vaccine combination
    params_central$efficacy <- import_mixed_efficacy_data(
      params$strain,
      vacc_program
    )

    # if(vacc_comb[1] %in% c("Pfizer", "AstraZeneca") & vacc_comb[2] %in% c("Pfizer", "AstraZeneca")){
    #   params_lower$efficacy = import_efficacy_data(
    #     params$strain,
    #     vaccine_1 = paste(vacc_comb[1], "(lower)", sep =
    #                         " "),
    #     vaccine_2 = paste(vacc_comb[2], "(lower)", sep =
    #                         " ")
    #   )
    #
    #   params_upper$efficacy = import_efficacy_data(
    #     params$strain,
    #     vaccine_1 = paste(vacc_comb[1], "(upper)", sep =
    #                         " "),
    #     vaccine_2 = paste(vacc_comb[2], "(upper)", sep =
    #                         " ")
    #   )
    # } else {
    #   params_lower$efficacy = import_efficacy_data(params$strain,
    #                                                vaccine_1 = vacc_comb[1],
    #                                                vaccine_2 = vacc_comb[2])
    #   params_upper$efficacy = import_efficacy_data(params$strain,
    #                                                vaccine_1 = vacc_comb[1],
    #                                                vaccine_2 = vacc_comb[2])
    # }

    params_lower <- get_params(params$country,
      R0 = params$R0 - 1,
      vacc_program = vacc_program,
      seropositivity = params$seropositivity,
      strain = params$strain
    )

    params_upper <- get_params(params$country,
      R0 = params$R0 + 1,
      vacc_program = vacc_program,
      seropositivity = params$seropositivity,
      strain = params$strain
    )

    params_lower$efficacy <- params_central$efficacy
    params_upper$efficacy <- params_central$efficacy

    # Calculate the age-specific infections / hospitalizations / deaths
    final_burden <- calc_final_burden(params_central, vacc_prop)

    out$Infections[i] <- sum(final_burden$infections) * 1e5 / sum(params$population_size)
    out$Hospitalizations[i] <- sum(final_burden$hospitalizations) * 1e5 / sum(params$population_size)
    out$Deaths[i] <- sum(final_burden$deaths) * 1e5 / sum(params$population_size)


    final_burden_lower <- calc_final_burden(params_lower, vacc_prop)

    out_lower$Infections[i] <- sum(final_burden_lower$infections) * 1e5 / sum(params$population_size)
    out_lower$Hospitalizations[i] <- sum(final_burden_lower$hospitalizations) * 1e5 / sum(params$population_size)
    out_lower$Deaths[i] <- sum(final_burden_lower$deaths) * 1e5 / sum(params$population_size)


    final_burden_upper <- calc_final_burden(params_upper, vacc_prop)

    out_upper$Infections[i] <- sum(final_burden_upper$infections) * 1e5 / sum(params$population_size)
    out_upper$Hospitalizations[i] <- sum(final_burden_upper$hospitalizations) * 1e5 / sum(params$population_size)
    out_upper$Deaths[i] <- sum(final_burden_upper$deaths) * 1e5 / sum(params$population_size)
  }

  # Melt, and then stitch together lower, central and upper estimates
  out <- out %>%
    dplyr::select(-Hospitalizations) %>%
    reshape2::melt(
      id.vars = c("Strategy", "Vaccine", "Coverage"),
      variable.name = "Target"
    )
  out_lower <- out_lower %>%
    dplyr::select(-Hospitalizations) %>%
    reshape2::melt(
      id.vars = c("Strategy", "Vaccine", "Coverage"),
      variable.name = "Target"
    )
  out_upper <- out_upper %>%
    dplyr::select(-Hospitalizations) %>%
    reshape2::melt(
      id.vars = c("Strategy", "Vaccine", "Coverage"),
      variable.name = "Target"
    )

  out$lower <- out_lower$value
  out$upper <- out_upper$value

  return(out)
}


calc_target_breakdown <- function(params,
                                  target = "Deaths",
                                  strategies = c("Uniform", "Vulnerable", "Transmitters"),
                                  target_coverages = seq(0, 1.0, 0.2),
                                  vaccine_combination = c("BNT162b2", "ChAdOx1"),
                                  eligibility_cutoff = 15,
                                  # include_children = FALSE,
                                  uptake = 1.0,
                                  cutoff = 60) {
  out <- expand.grid(
    Strategy = strategies,
    Coverage = target_coverages
  )

  out$Unvaccinated <- rep(NA, nrow(out))
  out$Vaccinated <- rep(NA, nrow(out))

  for (i in 1:nrow(out)) {
    # Calculate age-specific vaccination coverage

    if (eligibility_cutoff == 15) {
      vacc_prop <- calc_age_specific_coverage_over_15(
        target_coverage = out$Coverage[i],
        params = params,
        strategy = out$Strategy[i],
        uptake = uptake
      )
    } else if (eligibility_cutoff == 10) {
      vacc_prop <- calc_age_specific_coverage_over_10(
        target_coverage = out$Coverage[i],
        params = params,
        strategy = out$Strategy[i],
        uptake = uptake
      )
    } else if (eligibility_cutoff == 5) {
      vacc_prop <- calc_age_specific_coverage_over_5(
        target_coverage = out$Coverage[i],
        params = params,
        strategy = out$Strategy[i],
        uptake = uptake
      )
    }
    # if (include_children) {
    #   vacc_prop = calc_age_specific_coverage_children_included(
    #     target_coverage = out$Coverage[i],
    #     params = params,
    #     strategy = out$Strategy[i],
    #     uptake = uptake
    #   )
    # } else{
    #   vacc_prop = calc_age_specific_coverage(
    #     target_coverage = out$Coverage[i],
    #     params = params,
    #     strategy = out$Strategy[i],
    #     uptake = uptake
    #   )
    # }

    # Update the vaccine efficacy given the current vaccine combination
    params$efficacy <- import_efficacy_data(params$strain,
      vaccine_1 = vaccine_combination[1],
      vaccine_2 = vaccine_combination[2],
      cutoff = cutoff
    )



    # Calculate the age-specific infections / hospitalizations / deaths
    final_burden <- calc_final_burden(params, vacc_prop)

    out$Unvaccinated[i] <- sum(final_burden$deaths[1:16])
    out$Vaccinated[i] <- sum(final_burden$deaths[17:32])
  }



  # Melt, and then stitch together lower, central and upper estimates
  out <- out %>%
    reshape2::melt(
      id.vars = c("Strategy", "Coverage"),
      variable.name = "Group"
    )

  return(out)
}



plot_targets <- function(out, l1 = NA, l2 = NA) {
  plt <- out %>%
    mutate(
      value = if_else(value < 0, 0, value),
      lower = if_else(lower < 0, 0, lower),
      upper = if_else(upper < 0, 0, upper)
    ) %>%
    ggplot2::ggplot(aes(
      x = Coverage,
      y = value,
      col = Strategy,
      fill = Strategy
    )) +
    geom_line(lwd = 1) +
    geom_ribbon(aes(ymin = lower, ymax = upper),
      alpha = 0.1,
      colour = NA
    ) +
    # facet_grid(Target ~ Vaccine, scales = "free") +
    facet_grid(Target ~ ., scales = "free") +
    ylab("Cases per 100,000 population") +
    xlab("Target Coverage") +
    scale_x_continuous(
      label = scales::percent,
      breaks = seq(0, 1, by = 0.2),
      limits = c(0, 1)
    ) +
    theme_bw(base_size = 18) +
    theme(axis.text.x = element_text(angle = -90, vjust = 0.5)) +
    geom_vline(col = "red", xintercept = l1, lty = "dashed") +
    geom_vline(col = "red", xintercept = l2, lty = "dashed") +
    expand_limits(y = c(0, 100))

  print(plt)
}


plot_breakdown <- function(out, target = "Deaths") {
  out$Coverage <- factor(paste(as.integer(out$Coverage * 100), "%", sep = ""),
    levels = c("0%", "20%", "40%", "60%", "80%", "100%")
  )
  plt <- ggplot2::ggplot(out, aes(x = Coverage, y = value, fill = Group)) +
    geom_col() +
    ylab(paste("Total", target)) +
    xlab("Target Coverage") +
    facet_grid(. ~ Strategy) +
    scale_fill_manual(values = c("darkred", "red")) +
    # scale_x_continuous(
    #   label = scales::percent,
    #   breaks = seq(0, 1, by = 0.2),
    #   limits = c(0, 1)
    # ) +
    theme(
      panel.background = element_rect(fill = "white", colour = "white"),
      panel.grid.major = element_line(colour = "grey90"),
      panel.grid.minor = element_line(colour = "grey90"),
      panel.grid.major.x = element_blank(),
      axis.line = element_line(size = 0.4, colour = "grey10"),
      text = element_text(size = 12, family = "serif"),
      legend.key = element_rect(fill = "white", colour = "white"),
      strip.background = element_rect(fill = "white"),
      strip.text = element_text(size = 12, colour = "black"),
      panel.spacing = unit(1, "lines")
    )
  print(plt)
}



calc_targets_ages <- function(params,
                              targets = c("Infections", "Hospitalizations", "Deaths"),
                              strategies = c("Uniform", "Vulnerable", "Transmitters"),
                              target_coverages = seq(0, 1.0, 0.2),
                              vacc_program = list(
                                "vacc_types" = c("Pfizer", "Sinovac"),
                                "vacc_percs" = c(20, 80)
                              ),
                              eligibility_cutoff = 15,
                              # include_children = FALSE,
                              uptake = 1.0,
                              cutoff = 60) {
  out <- expand.grid(
    Strategy = strategies,
    Vaccine = list("any vacc" = c("any vacc")),
    Coverage = target_coverages
  )

  out$Infections <- rep(NA, nrow(out))
  out$Hospitalizations <- rep(NA, nrow(out))
  out$Deaths <- rep(NA, nrow(out))

  out_lower <- out
  out_upper <- out

  params_central <- params
  params_lower <- params
  params_upper <- params

  everything <- map(
    1:nrow(out),
    function(x) {
      # for (i in 1:nrow(out)) {
      # Calculate age-specific vaccination coverage
      if (eligibility_cutoff == 15) {
        vacc_prop <- calc_age_specific_coverage_over_15(
          target_coverage = out$Coverage[x],
          params = params,
          strategy = out$Strategy[x],
          uptake = uptake
        )
      } else if (eligibility_cutoff == 10) {
        vacc_prop <- calc_age_specific_coverage_over_10(
          target_coverage = out$Coverage[x],
          params = params,
          strategy = out$Strategy[x],
          uptake = uptake
        )
      } else if (eligibility_cutoff == 5) {
        vacc_prop <- calc_age_specific_coverage_over_5(
          target_coverage = out$Coverage[x],
          params = params,
          strategy = out$Strategy[x],
          uptake = uptake
        )
      }



      #     if (include_children) {
      #   vacc_prop = calc_age_specific_coverage_children_included(
      #     target_coverage = out$Coverage[x],
      #     params = params,
      #     strategy = out$Strategy[x],
      #     uptake = uptake
      #   )
      # } else{
      #   vacc_prop = calc_age_specific_coverage(
      #     target_coverage = out$Coverage[x],
      #     params = params,
      #     strategy = out$Strategy[x],
      #     uptake = uptake
      #   )
      # }

      # Update the vaccine efficacy given the current vaccine combination
      params_central$efficacy <- import_mixed_efficacy_data(params$strain,
        vacc_program = vacc_program
      )


      # if(vacc_comb[1] %in% c("Pfizer", "AstraZeneca") & vacc_comb[2] %in% c("Pfizer", "AstraZeneca")){
      # params_lower$efficacy = import_efficacy_data(
      #   params$strain,
      #   vaccine_1 = paste(vacc_comb[1], "(lower)", sep =
      #                       " "),
      #   vaccine_2 = paste(vacc_comb[2], "(lower)", sep =
      #                       " ")
      # )
      #
      # params_upper$efficacy = import_efficacy_data(
      #   params$strain,
      #   vaccine_1 = paste(vacc_comb[1], "(upper)", sep =
      #                       " "),
      #   vaccine_2 = paste(vacc_comb[2], "(upper)", sep =
      #                       " ")
      # )
      # } else {
      #   params_lower$efficacy = import_efficacy_data(params$strain,
      #                                                  vaccine_1 = vacc_comb[1],
      #                                                  vaccine_2 = vacc_comb[2])
      #   params_upper$efficacy = import_efficacy_data(params$strain,
      #                                                vaccine_1 = vacc_comb[1],
      #                                                vaccine_2 = vacc_comb[2])
      # }

      # params_central = get_params(params$country,R0 = params$R0,
      #                           vaccine_1 = vacc_comb[1],
      #                           vaccine_2 = vacc_comb[2],
      #                           seropositivity = params$seropositivity,
      #                           strain = params$strain)
      #

      params_lower <- get_params(params$country,
        R0 = params$R0 - 1,
        vacc_program = vacc_program,
        seropositivity = params$seropositivity,
        strain = params$strain
      )

      params_upper <- get_params(params$country,
        R0 = params$R0 + 1,
        vacc_program = vacc_program,
        seropositivity = params$seropositivity,
        strain = params$strain
      )

      params_lower$efficacy <- params_central$efficacy
      params_upper$efficacy <- params_central$efficacy

      # Calculate the age-specific infections / hospitalizations / deaths
      final_burden <- calc_final_burden_tibble(params_central, vacc_prop)
      #
      # out$Infections[i] = sum(final_burden$infections) * 1e5 / sum(params$population_size)
      # out$Hospitalizations[i] = sum(final_burden$hospitalizations) * 1e5 / sum(params$population_size)
      # out$Deaths[i] = sum(final_burden$deaths) * 1e5 / sum(params$population_size)
      #

      final_burden_lower <- calc_final_burden_tibble(params_lower, vacc_prop)
      #
      # out_lower$Infections[i] = sum(final_burden_lower$infections) * 1e5 / sum(params$population_size)
      # out_lower$Hospitalizations[i] = sum(final_burden_lower$hospitalizations) * 1e5 / sum(params$population_size)
      # out_lower$Deaths[i] = sum(final_burden_lower$deaths) * 1e5 / sum(params$population_size)
      #

      final_burden_upper <- calc_final_burden_tibble(params_upper, vacc_prop)
      #
      # out_upper$Infections[i] = sum(final_burden_upper$infections) * 1e5 / sum(params$population_size)
      # out_upper$Hospitalizations[i] = sum(final_burden_upper$hospitalizations) * 1e5 / sum(params$population_size)
      # out_upper$Deaths[i] = sum(final_burden_upper$deaths) * 1e5 / sum(params$population_size)
      #
      final_burden$interval <- "mean"
      final_burden_lower$interval <- "lower"
      final_burden_upper$interval <- "upper"
      fb_comb <- bind_rows(
        final_burden,
        final_burden_lower,
        final_burden_upper
      )
      fb_comb$coverage <- out$Coverage[x]
      fb_comb$strategy <- out$Strategy[x]
      fb_comb$vaccine <- out$Vaccine[x]
      return(fb_comb)
    }
  )
  #
  # # Melt, and then stitch together lower, central and upper estimates
  # out = out %>%
  #   dplyr::select(-Hospitalizations) %>%
  #   reshape2::melt(id.vars = c("Strategy", "Vaccine", "Coverage"),
  #                  variable.name = "Target")
  # out_lower = out_lower %>%
  #   dplyr::select(-Hospitalizations) %>%
  #   reshape2::melt(id.vars = c("Strategy", "Vaccine", "Coverage"),
  #                  variable.name = "Target")
  # out_upper = out_upper %>%
  #   dplyr::select(-Hospitalizations) %>%
  #   reshape2::melt(id.vars = c("Strategy", "Vaccine", "Coverage"),
  #                  variable.name = "Target")
  #
  # out$lower = out_lower$value
  # out$upper = out_upper$value
  #
  # return(out)

  return(do.call(bind_rows, everything))
}


facet_labeller <- function(variable, value) {
  if (variable == "coverage") {
    return(paste(value * 100, "% coverage", sep = ""))
  } else {
    return(as.character(value))
  }
}

get_default_vacc_perc <- function(n, i) {
  round_share <- floor(100. / n)
  if (i > 1) {
    return(round_share)
  } else {
    return(100 - round_share * (n - 1))
  }
}


make_info_button <- function(name) {
  text_path <- paste0("./info_buttons/", name, ".Rmd")

  dropdownButton(
    includeMarkdown(text_path),
    # tags$h3("Text here"),
    size = "xs",
    circle = TRUE, status = "primary",
    icon = icon("info"),
    width = "25vw"
  )
}