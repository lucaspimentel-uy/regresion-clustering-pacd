# analisis.R -- funciones de analisis temporal, regresion y clustering.

# ---- Temporal ----------------------------------------------------------------
# Total de siniestros por periodo (dia, mes o año) con la cantidad de dias que
# participan y la tasa por dia (permite comparar meses o años incompletos).
agregar_periodo <- function(diario, unidad, ...) {
  diario |>
    mutate(periodo = floor_date(fecha, unidad)) |>
    group_by(..., periodo) |>
    summarise(siniestros = sum(n_siniestros), dias = n(), .groups = "drop") |>
    mutate(por_dia = siniestros / dias)
}

# Tendencia lineal controlando la estacionalidad: por_dia ~ tiempo (años) + mes.
# Devuelve la pendiente (siniestros por dia, por año) con su intervalo del 95 %.
estimar_tendencia <- function(mensual) {
  datos <- mutate(mensual, t = time_length(periodo - min(periodo), "year"),
                  mes = factor(month(periodo)))
  lm(por_dia ~ t + mes, data = datos) |>
    tidy(conf.int = TRUE) |>
    filter(term == "t") |>
    transmute(pendiente = estimate, ic_inf = conf.low, ic_sup = conf.high, p_valor = p.value,
              media_por_dia = mean(datos$por_dia), pct_anual = 100 * pendiente / media_por_dia)
}

# ---- Regresion ---------------------------------------------------------------
calcular_mae  <- function(observado, predicho) mean(abs(observado - predicho), na.rm = TRUE)
calcular_rmse <- function(observado, predicho) sqrt(mean((observado - predicho)^2, na.rm = TRUE))

# Split aleatorio por fecha: devuelve las fechas de entrenamiento. Se hace sobre las
# fechas (no sobre filas) para que todos los municipios usen los mismos dias.
dividir_fechas <- function(fechas, prop_train, semilla) {
  fechas <- sort(unique(fechas))
  set.seed(semilla)
  fechas[sample(length(fechas), size = round(prop_train * length(fechas)))]
}

# Ajuste, error en train y en test, y R2 de un modelo lineal (una fila).
evaluar_modelo <- function(modelo, train, test, respuesta) {
  resumen <- glance(modelo)
  tibble(parametros = length(coef(modelo)),
         R2 = resumen$r.squared, R2_aj = resumen$adj.r.squared, AIC = resumen$AIC,
         MAE_train  = calcular_mae(train[[respuesta]],  predict(modelo, train)),
         RMSE_train = calcular_rmse(train[[respuesta]], predict(modelo, train)),
         MAE_test   = calcular_mae(test[[respuesta]],   predict(modelo, test)),
         RMSE_test  = calcular_rmse(test[[respuesta]],  predict(modelo, test)))
}

# Referencia minima: predecir siempre la media de entrenamiento.
evaluar_baseline <- function(train, test, respuesta) {
  media <- mean(train[[respuesta]])
  tibble(parametros = 1L,
         MAE_train  = calcular_mae(train[[respuesta]], media),
         RMSE_train = calcular_rmse(train[[respuesta]], media),
         MAE_test   = calcular_mae(test[[respuesta]], media),
         RMSE_test  = calcular_rmse(test[[respuesta]], media))
}

# Problemas de un panel diario antes de modelar ("" si no hay ninguno).
diagnosticar_panel <- function(datos, n_dias, factores, min_dias = 5) {
  problemas <- c(
    if (nrow(datos) != n_dias) paste(nrow(datos), "filas (esperado", n_dias, ")"),
    if (anyNA(datos)) paste(sum(is.na(datos)), "NA"),
    if (anyDuplicated(datos$fecha)) "fechas repetidas",
    map_chr(factores, function(f) {
      conteo <- table(datos[[f]])
      raros <- names(conteo)[conteo < min_dias]
      if (length(raros)) paste0(f, " con menos de ", min_dias, " dias: ",
                                paste(raros, collapse = ", ")) else NA_character_
    }) |> purrr::discard(is.na)
  )
  paste(problemas, collapse = " | ")
}

# ---- Clustering --------------------------------------------------------------
# k-means con varios inicios y semilla fija; devuelve WSS, silueta promedio y tamaños.
resumir_kmeans <- function(Z, k, semilla, distancias = dist(Z)) {
  set.seed(semilla)
  km <- kmeans(Z, centers = k, nstart = 25, iter.max = 100)
  tibble(k = k, WSS = km$tot.withinss,
         silueta = mean(silhouette(km$cluster, distancias)[, "sil_width"]),
         tamanos = paste(sort(km$size, decreasing = TRUE), collapse = "/"),
         modelo = list(km))
}

# Indice de Rand ajustado entre dos particiones (1 = identicas, ~0 = como al azar).
rand_ajustado <- function(a, b) {
  tabla <- table(a, b)
  pares <- function(x) x * (x - 1) / 2
  s  <- sum(pares(tabla))
  sa <- sum(pares(rowSums(tabla)))
  sb <- sum(pares(colSums(tabla)))
  esperado <- sa * sb / pares(sum(tabla))
  (s - esperado) / ((sa + sb) / 2 - esperado)
}
