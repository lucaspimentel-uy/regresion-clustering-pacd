# 04_regresion.R -- ¿que explica cuantos siniestros hay por dia: el calendario o el clima?
# Modelos lineales anidados sobre el total diario de Montevideo y, automatizado con
# purrr, el mismo procedimiento para cada uno de los 8 municipios.
# Entrada : data/processed/panel_diario.csv
# Salida  : outputs/tablas/reg_*.csv, outputs/figuras/reg_*.png
source(here::here("scripts", "00_setup.R"))

meses <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")
# Factores con la categoria de referencia primero (entre semana, despejado, enero)
preparar_factores <- function(datos) {
  datos |>
    mutate(tipo_dia     = factor(tipo_dia, levels = c("entre_semana", "fin_semana", "feriado")),
           estado_clima = factor(estado_clima, levels = c("despejado", "nublado", "lluvia")),
           mes          = factor(month(fecha), levels = 1:12, labels = meses))
}

panel <- read_csv(f_panel, show_col_types = FALSE) |> preparar_factores()
vars_dia <- c("tipo_dia", "mes", "temp_media", "lluvia_mm", "viento_max_kmh", "estado_clima")
dia <- panel |>
  group_by(fecha, across(all_of(vars_dia))) |>
  summarise(n_siniestros = sum(n_siniestros), .groups = "drop")
validar(nrow(dia) == n_distinct(panel$fecha), "Total diario: una fila por fecha",
        paste(fmt(nrow(dia)), "días"))

# ---- 1. Modelos y split ------------------------------------------------------
# M0: calendario (tipo de dia). M1: + mes. M2: + clima. Cada uno contiene al anterior.
formulas <- list(
  M0 = n_siniestros ~ tipo_dia,
  M1 = n_siniestros ~ tipo_dia + mes,
  M2 = n_siniestros ~ tipo_dia + mes + temp_media + lluvia_mm + viento_max_kmh + estado_clima
)
fechas_train <- dividir_fechas(dia$fecha, prop_train = 0.7, semilla = semilla)
train <- filter(dia, fecha %in% fechas_train)
test  <- filter(dia, !fecha %in% fechas_train)
validar(all(map_lgl(c("tipo_dia", "mes", "estado_clima"),
                    ~ all(levels(dia[[.x]]) %in% train[[.x]]))),
        "Todos los niveles de los factores presentes en train",
        paste(nrow(train), "días de train /", nrow(test), "de test"))

# ---- 2. Ajuste y comparacion -------------------------------------------------
modelos <- map(formulas, ~ lm(.x, data = train))
comparacion <- bind_rows(
  evaluar_baseline(train, test, "n_siniestros") |> mutate(modelo = "Baseline (media)"),
  map(modelos, evaluar_modelo, train = train, test = test, respuesta = "n_siniestros") |>
    list_rbind(names_to = "modelo")
) |> relocate(modelo)
guardar_tabla(comparacion, "reg_comparacion_modelos")

# Test F de modelos anidados: ¿cada bloque agregado mejora el ajuste?
guardar_tabla(tidy(anova(modelos$M0, modelos$M1, modelos$M2)) |>
                mutate(modelo = names(modelos), .before = 1),
              "reg_test_f")

# Mejor modelo: menor RMSE en test
mejor <- comparacion |> filter(modelo %in% names(modelos)) |>
  slice_min(RMSE_test) |> pull(modelo)
modelo_final <- modelos[[mejor]]
coeficientes <- tidy(modelo_final, conf.int = TRUE) |> mutate(modelo = mejor, .before = 1)
guardar_tabla(coeficientes, "reg_coeficientes")

# ---- 3. Diagnostico de residuos del mejor modelo ------------------------------
residuos <- augment(modelo_final, data = train)
# Autocorrelacion de lag 1: se usa la serie completa en orden cronologico
modelo_serie <- lm(formulas[[mejor]], data = dia)
diagnostico <- tibble(
  modelo = mejor,
  shapiro_p = shapiro.test(residuos$.resid)$p.value,
  # Breusch-Pagan (Koenker): n * R2 de resid^2 ~ ajustado, chi2 con 1 gl
  breusch_pagan_p = pchisq(nrow(residuos) * summary(lm(.resid^2 ~ .fitted, residuos))$r.squared,
                           df = 1, lower.tail = FALSE),
  var_resid_sobre_media = var(residuos$.resid) / mean(train$n_siniestros),
  acf_lag1 = acf(residuals(modelo_serie), lag.max = 1, plot = FALSE)$acf[2]
)
guardar_tabla(diagnostico, "reg_diagnostico")

# Efectos del mejor modelo, con intervalo del 95 %
efectos <- coeficientes |>
  filter(term != "(Intercept)") |>
  mutate(bloque = if_else(grepl("^mes", term), "Mes", "Tipo\nde día"),
         term = gsub("_", " ", sub("^mes|^tipo_dia", "", term)),
         term = factor(term, levels = rev(unique(term))))
p_coef <- ggplot(efectos, aes(estimate, term)) +
  geom_vline(xintercept = 0, colour = "grey60", linetype = "dashed") +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high), height = 0.2, colour = col_punto) +
  geom_point(size = 2, colour = col_punto) +
  facet_grid(bloque ~ ., scales = "free_y", space = "free_y") +
  theme(strip.text.y = element_text(angle = 0)) +
  labs(x = "Siniestros por día respecto de la referencia", y = NULL,
       subtitle = paste("Modelo", mejor, "- estimación e IC 95 %.",
                        "Referencias: enero y día entre semana"))
guardar_figura(p_coef, "reg_01_coeficientes", 8, 5.5)

obs_pred <- bind_rows(mutate(train, conjunto = "Train"), mutate(test, conjunto = "Test")) |>
  mutate(predicho = predict(modelo_final, pick(everything())),
         conjunto = factor(conjunto, levels = c("Train", "Test")))
p_res <- ggplot(residuos, aes(.fitted, .resid)) +
  geom_hline(yintercept = 0, colour = col_linea, linetype = "dashed") +
  geom_jitter(width = 0.15, alpha = 0.35, size = 0.9, colour = col_punto) +
  labs(x = "Valor ajustado", y = "Residuo", title = "Residuos vs. ajustados")
p_qq <- ggplot(residuos, aes(sample = .resid)) +
  stat_qq(alpha = 0.35, size = 0.9, colour = col_punto) + stat_qq_line(colour = col_linea) +
  labs(x = "Cuantil teórico", y = "Cuantil de los residuos", title = "QQ-plot")
p_op <- ggplot(filter(obs_pred, conjunto == "Test"), aes(predicho, n_siniestros)) +
  geom_abline(colour = col_linea) +
  geom_jitter(width = 0.15, alpha = 0.4, size = 0.9, colour = col_punto) +
  coord_equal(xlim = range(dia$n_siniestros), ylim = range(dia$n_siniestros)) +
  labs(x = "Predicho", y = "Observado", title = "Test: observado vs. predicho")
guardar_figura(p_res + p_qq + p_op, "reg_02_diagnostico", 11, 3.9)

# ---- 4. Automatizacion: el mismo procedimiento por municipio -------------------
# Cada municipio se valida antes de modelar; possibly() evita que un error en un
# municipio detenga a los demas (queda registrado como NA).
por_municipio <- panel |>
  nest(datos = -municipio) |>
  mutate(problemas = map_chr(datos, diagnosticar_panel, n_dias = nrow(dia),
                             factores = c("tipo_dia", "mes", "estado_clima")))
validar(all(por_municipio$problemas == ""), "Panel de cada municipio completo y sin NA",
        paste(sum(por_municipio$problemas == ""), "de", nrow(por_municipio), "municipios OK"))

ajustar_evaluar <- function(datos, formula) {
  tr <- filter(datos, fecha %in% fechas_train)
  te <- filter(datos, !fecha %in% fechas_train)
  evaluar_modelo(lm(formula, data = tr), tr, te, "n_siniestros")
}
ajustar_evaluar_seguro <- possibly(ajustar_evaluar, otherwise = NULL)

metricas_mun <- por_municipio |>
  expand_grid(modelo = names(formulas)) |>
  mutate(metricas = map2(datos, modelo, ~ ajustar_evaluar_seguro(.x, formulas[[.y]])),
         baseline = map(datos, ~ evaluar_baseline(filter(.x, fecha %in% fechas_train),
                                                  filter(.x, !fecha %in% fechas_train),
                                                  "n_siniestros")$RMSE_test),
         media_diaria = map_dbl(datos, ~ mean(.x$n_siniestros))) |>
  select(municipio, modelo, media_diaria, metricas, baseline) |>
  unnest(c(metricas, baseline)) |>
  rename(RMSE_test_baseline = baseline) |>
  mutate(mejora_pct = 100 * (1 - RMSE_test / RMSE_test_baseline))
validar(nrow(metricas_mun) == nrow(por_municipio) * length(formulas) && !anyNA(metricas_mun),
        "Métricas completas para todos los municipios y modelos",
        paste(nrow(metricas_mun), "combinaciones municipio x modelo"))
guardar_tabla(metricas_mun, "reg_metricas_municipio")

p_mun <- metricas_mun |>
  mutate(municipio = sub("MUNICIPIO ", "", municipio),
         municipio = reorder(municipio, mejora_pct, max)) |>
  ggplot(aes(mejora_pct, municipio, colour = modelo, shape = modelo)) +
  geom_vline(xintercept = 0, colour = "grey60", linetype = "dashed") +
  geom_point(size = 2.6) +
  scale_colour_manual(values = paleta[1:3], name = "Modelo") +
  scale_shape_manual(values = c(16, 17, 15), name = "Modelo") +
  labs(x = "Reducción del RMSE de test respecto de predecir la media (%)", y = "Municipio",
       subtitle = "Mismo split de días para los 8 municipios")
guardar_figura(p_mun, "reg_03_municipios", 8, 4.2)

guardar_validaciones("04_regresion")
