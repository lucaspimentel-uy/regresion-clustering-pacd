# 03_regresion.R -- Paso 1: siniestros por dia en Montevideo, calendario vs clima
# Corre solo sobre el panel (no usa el archivo unificado).
source("00_setup.R")

# ---- 1. Datos: panel municipio x dia -> dia (todo Montevideo) -----------------
panel <- read.csv(f_panel, stringsAsFactors = FALSE)
panel$fecha <- as.Date(panel$fecha)

# Clima y tipo_dia son identicos entre municipios en una misma fecha (verificado);
# se comprueba aqui y se toma el primer valor.
vars_dia <- c("tipo_dia", "temp_media", "lluvia_mm", "viento_max_kmh", "estado_clima")
chk <- panel |> group_by(fecha) |> summarise(across(all_of(vars_dia), n_distinct))
stopifnot(all(chk[vars_dia] == 1))

meses <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")
dia <- panel |>
  group_by(fecha) |>
  summarise(total_siniestros = sum(n_siniestros),
            across(all_of(vars_dia), first), .groups = "drop") |>
  mutate(tipo_dia     = factor(tipo_dia, levels = c("entre_semana", "fin_semana", "feriado")),
         estado_clima = factor(estado_clima, levels = c("despejado", "nublado", "lluvia")),
         mes          = factor(as.integer(format(fecha, "%m")), levels = 1:12, labels = meses))
stopifnot(nrow(dia) == 1645)
y <- dia$total_siniestros
cat("Dias:", nrow(dia), "| total:", sum(y), "| media:", round(mean(y), 2),
    "| sd:", round(sd(y), 2), "| rango:", paste(range(y), collapse = "-"), "\n")
cat("\nlluvia_mm medio por estado_clima (posible solapamiento entre ambas variables):\n")
print(dia |> group_by(estado_clima) |>
        summarise(dias = n(), lluvia_mm_media = round(mean(lluvia_mm), 2),
                  pct_dias_con_lluvia_mm_0 = round(100 * mean(lluvia_mm == 0), 1)))

# ---- 2. Exploracion grafica ---------------------------------------------------
col_pt <- "#2C6E91"; col_ln <- "#C0392B"; col_gr <- "grey55"
guardar <- function(p, nombre, w = 7.5, h = 4.5) {
  ggsave(file.path(dir_fig, nombre), p, width = w, height = h, dpi = 150, bg = "white")
}

p_tipo <- ggplot(dia, aes(tipo_dia, total_siniestros)) +
  geom_boxplot(fill = "grey90", colour = "grey30", outlier.size = 0.8) +
  labs(x = NULL, y = "Siniestros por día", title = "Por tipo de día")
p_mes <- ggplot(dia, aes(mes, total_siniestros)) +
  geom_boxplot(fill = "grey90", colour = "grey30", outlier.size = 0.8) +
  labs(x = NULL, y = NULL, title = "Por mes")
guardar(p_tipo + p_mes + plot_layout(widths = c(1, 2.2)), "reg_01_boxplots.png", 9, 4)

p_temp <- ggplot(dia, aes(temp_media, total_siniestros)) +
  geom_point(alpha = 0.35, size = 1, colour = col_pt) +
  geom_smooth(method = "loess", formula = y ~ x, colour = col_ln, fill = col_ln, alpha = 0.15) +
  labs(x = "Temperatura media (°C)", y = "Siniestros por día")
p_llu <- ggplot(dia, aes(lluvia_mm, total_siniestros)) +
  geom_point(alpha = 0.35, size = 1, colour = col_pt) +
  geom_smooth(method = "loess", formula = y ~ x, colour = col_ln, fill = col_ln, alpha = 0.15) +
  labs(x = "Lluvia (mm)", y = NULL)
guardar(p_temp + p_llu, "reg_02_scatter_clima.png", 9, 4)

dia$media_movil <- as.numeric(stats::filter(dia$total_siniestros, rep(1 / 28, 28), sides = 2))
p_serie <- ggplot(dia, aes(fecha, total_siniestros)) +
  geom_line(colour = col_gr, linewidth = 0.25) +
  geom_line(aes(y = media_movil), colour = col_ln, linewidth = 0.8, na.rm = TRUE) +
  labs(x = NULL, y = "Siniestros por día", subtitle = "Gris: dato diario. Rojo: media móvil de 28 días")
guardar(p_serie, "reg_03_serie_temporal.png", 9, 3.8)
dia$media_movil <- NULL

p_hist <- ggplot(dia, aes(total_siniestros)) +
  geom_histogram(binwidth = 2, fill = col_pt, colour = "white", boundary = 0) +
  geom_vline(xintercept = mean(y), colour = col_ln, linetype = "dashed") +
  labs(x = "Siniestros por día", y = "Días", subtitle = "Línea punteada: media")
guardar(p_hist, "reg_04_histograma.png", 6.5, 4)

# ---- 3. Split 70/30 con semilla fija -------------------------------------------
set.seed(2024)
idx   <- sample(nrow(dia), size = round(0.7 * nrow(dia)))
train <- dia[idx, ]
test  <- dia[-idx, ]
cat("\nTrain:", nrow(train), "| Test:", nrow(test), "\n")
stopifnot(all(sapply(c("tipo_dia", "mes", "estado_clima"),
                     function(v) all(levels(dia[[v]]) %in% train[[v]]))))

# ---- 4. Modelos anidados --------------------------------------------------------
f0 <- total_siniestros ~ tipo_dia
f1 <- update(f0, . ~ . + mes)
f2 <- update(f1, . ~ . + temp_media + lluvia_mm + viento_max_kmh + estado_clima)
mods <- list(M0 = lm(f0, train), M1 = lm(f1, train), M2 = lm(f2, train))

tab_mod <- do.call(rbind, lapply(names(mods), function(n) {
  s <- summary(mods[[n]])
  data.frame(modelo = n, parametros = length(coef(mods[[n]])),
             R2 = s$r.squared, R2_aj = s$adj.r.squared, AIC = AIC(mods[[n]]))
}))
cat("\n== Modelos anidados (ajuste sobre train) ==\n")
print(transform(tab_mod, R2 = round(R2, 3), R2_aj = round(R2_aj, 3), AIC = round(AIC, 1)),
      row.names = FALSE)
cat("\nTest F de modelos anidados (M0 -> M1 -> M2):\n")
print(anova(mods$M0, mods$M1, mods$M2))

# ---- 5. MAE y RMSE, train y test, mas baseline de la media ---------------------
mae  <- function(o, p) mean(abs(o - p))
rmse <- function(o, p) sqrt(mean((o - p)^2))
metricas <- function(mod) {
  c(MAE_train  = mae(train$total_siniestros, predict(mod, train)),
    RMSE_train = rmse(train$total_siniestros, predict(mod, train)),
    MAE_test   = mae(test$total_siniestros,  predict(mod, test)),
    RMSE_test  = rmse(test$total_siniestros, predict(mod, test)))
}
mu <- mean(train$total_siniestros)   # baseline: predecir siempre la media de train
base <- c(MAE_train  = mae(train$total_siniestros, mu), RMSE_train = rmse(train$total_siniestros, mu),
          MAE_test   = mae(test$total_siniestros, mu),  RMSE_test  = rmse(test$total_siniestros, mu))
tab_err <- data.frame(modelo = c("Baseline (media)", names(mods)),
                      rbind(base, t(sapply(mods, metricas))), row.names = NULL)
cat("\n== MAE y RMSE ==\n"); print(transform(tab_err, MAE_train = round(MAE_train, 2),
  RMSE_train = round(RMSE_train, 2), MAE_test = round(MAE_test, 2),
  RMSE_test = round(RMSE_test, 2)), row.names = FALSE)

write.csv(merge(tab_mod, tab_err, by = "modelo", all = TRUE) |> arrange(modelo),
          file.path(dir_tab, "reg_comparacion_modelos.csv"), row.names = FALSE)

# Chequeo contra los valores de referencia del enunciado (R2 0,223/0,294/0,297;
# RMSE 5,67/5,41/5,39; baseline 6,44). Ajuste sobre los 1.645 dias, sin split.
full <- lapply(list(M0 = f0, M1 = f1, M2 = f2), lm, data = dia)
cat("\n== Chequeo: ajuste sobre los 1.645 dias (sin split) ==\n")
print(data.frame(modelo = names(full),
                 R2 = round(sapply(full, function(m) summary(m)$r.squared), 3),
                 RMSE = round(sapply(full, function(m) sqrt(mean(residuals(m)^2))), 2)),
      row.names = FALSE)
cat("Baseline (sd poblacional):", round(sqrt(mean((y - mean(y))^2)), 2), "\n")

# ---- 6. Residuos del mejor modelo ----------------------------------------------
# Criterio: menor RMSE en test. Se informa tambien que dice el AIC.
mejor <- tab_err$modelo[-1][which.min(tab_err$RMSE_test[-1])]
cat("\nMejor por RMSE test:", mejor, "| mejor por AIC:",
    tab_mod$modelo[which.min(tab_mod$AIC)], "\n")
mm <- mods[[mejor]]
rd <- data.frame(ajustado = fitted(mm), resid = residuals(mm),
                 mes = train$mes, tipo_dia = train$tipo_dia)

p_rf <- ggplot(rd, aes(ajustado, resid)) +
  geom_point(alpha = 0.4, size = 1, colour = col_pt) +
  geom_hline(yintercept = 0, colour = col_ln, linetype = "dashed") +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, colour = "grey30", linewidth = 0.6) +
  labs(x = "Valores ajustados", y = "Residuos", title = "Residuos vs. ajustados")
p_qq <- ggplot(rd, aes(sample = resid)) +
  stat_qq(alpha = 0.4, size = 1, colour = col_pt) + stat_qq_line(colour = col_ln) +
  labs(x = "Cuantiles teóricos", y = "Cuantiles de los residuos", title = "QQ-plot")
p_rm <- ggplot(rd, aes(mes, resid)) +
  geom_hline(yintercept = 0, colour = col_ln, linetype = "dashed") +
  geom_boxplot(fill = "grey90", colour = "grey30", outlier.size = 0.8) +
  labs(x = NULL, y = "Residuos", title = "Residuos por mes")
p_rt <- ggplot(rd, aes(tipo_dia, resid)) +
  geom_hline(yintercept = 0, colour = col_ln, linetype = "dashed") +
  geom_boxplot(fill = "grey90", colour = "grey30", outlier.size = 0.8) +
  labs(x = NULL, y = "Residuos", title = "Residuos por tipo de día")
guardar((p_rf + p_qq) / (p_rm + p_rt), "reg_05_residuos.png", 10, 8)

# Diagnosticos numericos (sin paquetes extra)
cat("\n== Diagnosticos de residuos (", mejor, ", train) ==\n", sep = "")
cat("Shapiro-Wilk p =", signif(shapiro.test(rd$resid)$p.value, 3), "\n")
# Breusch-Pagan (version Koenker): n * R2 de resid^2 ~ ajustado, ~ chi2(1)
aux <- summary(lm(rd$resid^2 ~ rd$ajustado))
bp  <- nrow(rd) * aux$r.squared
cat("Breusch-Pagan: estadistico =", round(bp, 2), " p =", signif(pchisq(bp, 1, lower.tail = FALSE), 3), "\n")
cat("sd de residuos por tercil de valor ajustado:\n")
print(round(tapply(rd$resid, cut(rd$ajustado, quantile(rd$ajustado, 0:3 / 3), include.lowest = TRUE), sd), 2))
cat("Varianza residual / media de la respuesta (Poisson ~ 1):",
    round(var(rd$resid) / mean(train$total_siniestros), 2), "\n")
# Autocorrelacion de lag 1 de los residuos del modelo ajustado a la serie completa
res_full <- residuals(full[[mejor]])
cat("Autocorrelacion lag-1 de residuos (serie completa, orden cronologico):",
    round(acf(res_full, lag.max = 1, plot = FALSE)$acf[2], 3), "\n")

cat("\n== Coeficientes del mejor modelo ==\n")
cf <- as.data.frame(summary(mm)$coefficients)
names(cf) <- c("estimado", "error_est", "t", "p")
print(round(cf, 3))
write.csv(cbind(termino = rownames(cf), round(cf, 4)),
          file.path(dir_tab, paste0("reg_coeficientes_", mejor, ".csv")), row.names = FALSE)

# ---- 7. Observados vs. predichos -----------------------------------------------
op <- bind_rows(
  data.frame(conjunto = "Train", obs = train$total_siniestros, pred = predict(mm, train)),
  data.frame(conjunto = "Test",  obs = test$total_siniestros,  pred = predict(mm, test)))
op$conjunto <- factor(op$conjunto, levels = c("Train", "Test"))
p_op <- ggplot(op, aes(pred, obs)) +
  geom_point(alpha = 0.4, size = 1, colour = col_pt) +
  geom_abline(slope = 1, intercept = 0, colour = col_ln) +
  coord_equal(xlim = range(op$obs), ylim = range(op$obs)) +
  facet_wrap(~conjunto) +
  labs(x = "Predicho", y = "Observado",
       subtitle = paste0("Modelo ", mejor, ". Recta roja: identidad (predicción perfecta)"))
guardar(p_op, "reg_06_obs_vs_pred.png", 9, 4.8)

cat("\nListo. Figuras en", dir_fig, "\n")
