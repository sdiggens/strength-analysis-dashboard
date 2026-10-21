# Strength Analysis Dashboard
# Tracks estimated one-rep max (1RM) for four lifts using each session's best set,
# and projects to 15 July 2026 only where the data shows a clear upward trend.
#
# How to run: open this file in RStudio, then Session > Set Working Directory >
# To Source File Location, then click "Source". Needs the tidyverse package.

library(tidyverse)

# 1. Load and clean ------------------------------------------------------------
lifts <- read_csv("lifts.csv", show_col_types = FALSE) %>%
  mutate(Date = dmy(Date)) %>%
  filter(!is.na(Date), !is.na(Est_1RM))

focus       <- c("Bench Press", "Deadlift", "French Press", "Preacher Curl")
target_date <- as.Date("2026-07-15")

# 2. Keep each session's best set ------------------------------------------------
# Later sets in a session are weaker because of fatigue, and sets from the same
# session are not independent measurements, so each session contributes one value:
# its best estimated 1RM.
peaks <- lifts %>%
  filter(Exercise %in% focus) %>%
  group_by(Exercise, Date) %>%
  summarise(Est_1RM = max(Est_1RM), .groups = "drop")

# 3. Fit a linear trend for each lift and test whether it is reliable -------------
trends <- peaks %>%
  group_by(Exercise) %>%
  group_modify(~ {
    fit  <- lm(Est_1RM ~ Date, data = .x)
    coef <- summary(fit)$coefficients
    last <- max(.x$Date)
    pred <- predict(fit, newdata = tibble(Date = target_date),
                    interval = "prediction", level = 0.80)
    tibble(
      sessions    = nrow(.x),
      kg_per_week = coef[2, 1] * 7,
      p_value     = coef[2, 4],
      r_squared   = summary(fit)$r.squared,
      last_date   = last,
      fit_last    = unname(predict(fit, newdata = tibble(Date = last))),
      proj        = pred[1, "fit"],
      proj_low    = pred[1, "lwr"],
      proj_high   = pred[1, "upr"]
    )
  }) %>%
  ungroup() %>%
  # Only treat a trend as real if it is upward and statistically significant
  mutate(clear_trend = p_value < 0.05 & kg_per_week > 0)

print(trends %>% mutate(across(where(is.numeric), ~ round(.x, 3))), width = Inf)
write_csv(trends, "trend_summary.csv")

# 4. Population benchmarks (85 kg male, compound lifts only) ---------------------
benchmarks <- tribble(
  ~Exercise,     ~Value, ~Label,
  "Bench Press",  62,    "Beginner (62 kg)",
  "Bench Press",  83,    "Novice (83 kg)",
  "Bench Press", 107,    "Intermediate (107 kg)",
  "Deadlift",    104,    "Beginner (104 kg)",
  "Deadlift",    134,    "Novice (134 kg)",
  "Deadlift",    169,    "Intermediate (169 kg)"
)

proj_points <- trends %>% filter(clear_trend)
# Panel titles: lifts without a clear trend say so, instead of showing a projection
panel_titles <- trends %>%
  mutate(title = if_else(clear_trend,
                         sprintf("%s\nTrend: %+.1f kg/week (R² = %.2f)", Exercise, kg_per_week, r_squared),
                         sprintf("%s\nNo clear trend: %+.1f kg/week (R² = %.2f), not projected",
                                 Exercise, kg_per_week, r_squared)))
panel_titles <- setNames(panel_titles$title, panel_titles$Exercise)

# 5. Draw the dashboard -------------------------------------------------------------
p <- ggplot(peaks, aes(x = Date, y = Est_1RM)) +
  geom_hline(data = benchmarks, aes(yintercept = Value),
             colour = "#7f8c8d", linetype = "dashed", alpha = 0.5) +
  geom_text(data = benchmarks, aes(y = Value, label = Label),
            x = min(peaks$Date), hjust = 0, vjust = -0.5,
            colour = "#7f8c8d", size = 2.6, fontface = "italic") +
  geom_point(colour = "#2c3e50", size = 2.2, alpha = 0.85) +
  geom_smooth(method = "lm", formula = y ~ x, colour = "#e74c3c",
              fill = "#e74c3c", alpha = 0.12, linewidth = 1) +
  # Projection only where the trend is clear: dashed extension plus 80% range
  geom_segment(data = proj_points,
               aes(x = last_date, y = fit_last, xend = target_date, yend = proj),
               colour = "#e74c3c", linetype = "dashed", linewidth = 0.9) +
  geom_errorbar(data = proj_points,
                aes(x = target_date, ymin = proj_low, ymax = proj_high),
                inherit.aes = FALSE, width = 4, colour = "#d35400") +
  geom_point(data = proj_points, aes(x = target_date, y = proj),
             colour = "#f1c40f", size = 4, shape = 18) +
  geom_text(data = proj_points,
            aes(x = target_date, y = proj, label = paste0(round(proj, 1), " kg")),
            hjust = 1.2, vjust = -0.6, colour = "#d35400", size = 3, fontface = "bold") +
  facet_wrap(~ Exercise, scales = "free_y", nrow = 2,
             labeller = as_labeller(panel_titles)) +
  coord_cartesian(xlim = c(min(peaks$Date), as.Date("2026-07-28")), clip = "off") +
  labs(
    title    = "Strength Progress and Projections to 15 July 2026",
    subtitle = str_wrap("Best set per session (estimated 1RM). Red line: linear trend with 95% band. Projections only where the trend is significant (p < 0.05), with 80% range.", width = 100),
    x        = "Date (2026)",
    y        = "Estimated 1-rep max (kg)",
    caption  = "Dashed grey lines: population strength standards for an 85 kg male"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title       = element_text(face = "bold", size = 14, colour = "#1a252f"),
    plot.subtitle    = element_text(size = 9, colour = "#7f8c8d", margin = margin(b = 12)),
    strip.text       = element_text(face = "bold", size = 10.5, colour = "#2c3e50", lineheight = 1.1),
    panel.spacing    = unit(2, "lines"),
    panel.grid.minor = element_blank()
  )

print(p)
ggsave("strength_dashboard.png", p, width = 9, height = 7, dpi = 150, bg = "white")
message("Saved strength_dashboard.png and trend_summary.csv")
