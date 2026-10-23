# 07_automatizacion.R -- Paso 3: automatizar la regresion de 03 por municipio
#
# PROCEDIMIENTO QUE SE AUTOMATIZA
# En 03_regresion.R se ajustaron tres modelos anidados una sola vez, para el total diario
# de Montevideo: M0 (n ~ tipo_dia), M1 (+ mes) y M2 (+ temp_media + lluvia_mm +
# viento_max_kmh + estado_clima). Cada uno con split 70/30 aleatorio (semilla 2024) y las
# metricas R2, R2 ajustado, AIC, RMSE/MAE de test y el baseline de la media de train.
# Aqui se repite exactamente ese procedimiento para cada municipio (zona_id) del panel,
# con respuesta n_siniestros: 8 municipios x 3 modelos = 24 ajustes con un solo flujo
# (preparar -> validar -> ajustar -> graficar -> comparar), con validaciones y chequeos.
#
# Uso: desde la raiz del proyecto, `Rscript 07_automatizacion.R`. Solo usa el panel.
source("00_setup.R")

# purrr no esta en 00_setup.R: se carga aqui, con el mismo chequeo de instalacion
if (!requireNamespace("purrr", quietly = TRUE)) {
  stop("Falta el paquete: purrr\nInstalar con install.packages(\"purrr\")")
}
suppressPackageStartupMessages(library(purrr))

# ---- 1. Datos y constantes compartidas -----------------------------------------
panel <- read.csv(f_panel, stringsAsFactors = FALSE)
panel$fecha <- as.Date(panel$fecha)
municipios <- sort(unique(panel$zona_id))
cat("Panel:", nrow(panel), "filas |", length(municipios), "municipios |",
    n_distinct(panel$fecha), "dias | total:", sum(panel$n_siniestros), "\n")

# Mismos niveles y orden de referencia que 03 (el 1er nivel es la referencia de lm():
# entre_semana, despejado, ene). Se usan tanto en el caso manual como en las funciones.
meses        <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")
niv_tipo_dia <- c("entre_semana", "fin_semana", "feriado")
niv_clima    <- c("despejado", "nublado", "lluvia")

# Mismas formulas que 03: cada modelo contiene al anterior
f0 <- n_siniestros ~ tipo_dia
f1 <- update(f0, . ~ . + mes)
f2 <- update(f1, . ~ . + temp_media + lluvia_mm + viento_max_kmh + estado_clima)
formulas <- list(M0 = f0, M1 = f1, M2 = f2)

prop_train <- 0.7
semilla    <- 2024
# Columnas de metricas que devuelve ajustar_modelo() (sin el objeto lm)
cols_metricas <- c("r2", "r2_aj", "aic", "rmse_test", "mae_test", "rmse_baseline",
                   "n_train", "n_test")

col_pt <- "#2C6E91"; col_ln <- "#C0392B"; col_gr <- "grey55"   # mismos colores que 03
col_modelo <- c(M0 = "grey65", M1 = col_pt, M2 = col_ln)

# ---- 2. Caso manual: MUNICIPIO A, modelo M1, sin funciones ----------------------
# Es el procedimiento de 03 escrito paso a paso. Sirve de referencia para comprobar
# despues que la funcion automatizada da lo mismo.
A <- panel[panel$zona_id == "MUNICIPIO A", ]               # filtrar el municipio
A <- A[order(A$fecha), ]                                    # una fila por dia, en orden
A$tipo_dia     <- factor(A$tipo_dia, levels = niv_tipo_dia) # preparar factores
A$estado_clima <- factor(A$estado_clima, levels = niv_clima)
A$mes          <- factor(as.integer(format(A$fecha, "%m")), levels = 1:12, labels = meses)

set.seed(2024)                                              # split 70/30 como en 03
idx_A   <- sample(nrow(A), size = round(0.7 * nrow(A)))
train_A <- A[idx_A, ]
test_A  <- A[-idx_A, ]
# Todos los niveles de los factores deben estar en train; si no, predict() fallaria en test
stopifnot(all(levels(A$tipo_dia) %in% train_A$tipo_dia),
          all(levels(A$mes) %in% train_A$mes),
          all(levels(A$estado_clima) %in% train_A$estado_clima))

m1_A <- lm(n_siniestros ~ tipo_dia + mes, data = train_A)   # M1 ajustado sobre train
pred_A <- predict(m1_A, test_A)
manual_A <- data.frame(
  r2            = summary(m1_A)$r.squared,
  r2_aj         = summary(m1_A)$adj.r.squared,
  aic           = AIC(m1_A),
  rmse_test     = sqrt(mean((test_A$n_siniestros - pred_A)^2)),
  mae_test      = mean(abs(test_A$n_siniestros - pred_A)),
  rmse_baseline = sqrt(mean((test_A$n_siniestros - mean(train_A$n_siniestros))^2)),
  n_train       = nrow(train_A),
  n_test        = nrow(test_A))
cat("\n== Caso manual: MUNICIPIO A, M1 ==\n")
print(round(manual_A, 3), row.names = FALSE)

# ---- 3. Funciones reutilizables --------------------------------------------------

# Filtra un municipio y arma los factores (mismos niveles/orden que 03).
# Devuelve un data.frame ordenado por fecha, una fila por dia.
preparar_municipio <- function(panel, municipio) {
  d <- panel[panel$zona_id == municipio, ]
  d <- d[order(d$fecha), ]
  d$fecha        <- as.Date(d$fecha)
  d$tipo_dia     <- factor(d$tipo_dia, levels = niv_tipo_dia)
  d$estado_clima <- factor(d$estado_clima, levels = niv_clima)
  d$mes          <- factor(as.integer(format(d$fecha, "%m")), levels = 1:12, labels = meses)
  d
}

# Chequea que los datos de un municipio sirvan para ajustar. Devuelve un tibble de una
# fila: un contador por chequeo, `ok` (TRUE si no hay ningun problema) y `problema`
# (texto con lo que fallo). Con la validacion el flujo descarta el municipio con un
# mensaje en lugar de fallar adentro de lm() o predict().
validar_municipio <- function(datos, municipio, n_esperado = 1645, min_por_nivel = 5,
                              fechas_esperadas = seq(fecha_ini, fecha_fin, by = "day")) {
  vars_chk <- c("fecha", "n_siniestros", "tipo_dia", "mes", "temp_media", "lluvia_mm",
                "viento_max_kmh", "estado_clima")
  y <- datos$n_siniestros

  n_filas      <- nrow(datos)
  n_na         <- sum(is.na(datos[vars_chk]))
  n_dup        <- sum(duplicated(datos$fecha))
  n_faltantes  <- sum(!fechas_esperadas %in% datos$fecha)
  n_invalidos  <- sum(y < 0 | y != round(y), na.rm = TRUE)   # negativos o no enteros
  v            <- var(y, na.rm = TRUE)
  var_cero     <- is.na(v) || v == 0
  todo_ceros   <- any(!is.na(y)) && all(y == 0, na.rm = TRUE)

  # Dias por nivel de cada factor (table() sobre un factor incluye los niveles con 0 dias)
  vars_niv <- c("tipo_dia", "mes", "estado_clima")
  conteos  <- map(set_names(vars_niv), \(v) table(datos[[v]]))
  n_ausentes <- sum(unlist(map(conteos, \(n) n == 0)))
  n_pocos    <- sum(unlist(map(conteos, \(n) n > 0 & n < min_por_nivel)))
  niveles_malos <- unlist(imap(conteos, \(n, v) {
    n <- n[n < min_por_nivel]
    sprintf("%s:%s(%d)", v, names(n), as.integer(n))
  }))

  problemas <- c(
    if (n_filas != n_esperado) sprintf("%d filas (esperado %d)", n_filas, n_esperado),
    if (n_na > 0)        sprintf("%d NA", n_na),
    if (n_dup > 0)       sprintf("%d fechas duplicadas", n_dup),
    if (n_faltantes > 0) sprintf("%d fechas faltantes", n_faltantes),
    if (n_invalidos > 0) sprintf("%d conteos negativos o no enteros", n_invalidos),
    if (var_cero)        "varianza cero",
    if (todo_ceros)      "todo en ceros",
    if (length(niveles_malos) > 0)
      sprintf("niveles con menos de %d dias: %s", min_por_nivel,
              paste(niveles_malos, collapse = ", ")))

  tibble(municipio = municipio, n_filas = n_filas, n_na = n_na, n_fechas_dup = n_dup,
         n_fechas_faltantes = n_faltantes, n_invalidos = n_invalidos,
         varianza_cero = var_cero, todo_ceros = todo_ceros,
         niveles_ausentes = n_ausentes, niveles_pocos = n_pocos,
         ok = length(problemas) == 0,
         problema = if (length(problemas) == 0) "ninguno" else paste(problemas, collapse = " | "))
}

# Elige los dias de train. Depende solo de las fechas, la proporcion y la semilla:
# cualquier municipio con las mismas fechas recibe exactamente el mismo split.
# (Con 1.645 fechas da el mismo split que sample(nrow(dia), ...) en 03.)
dividir_fechas <- function(fechas, prop_train = 0.7, semilla = 2024) {
  fechas <- sort(unique(fechas))
  set.seed(semilla)
  sample(fechas, size = round(prop_train * length(fechas)))
}

# Split por fecha + lm + metricas. La respuesta es la 1ra variable de la formula.
# Devuelve un tibble de una fila: las metricas (R2, R2 aj. y AIC sobre train; RMSE y MAE
# sobre test; rmse_baseline = predecir siempre la media de train) y el lm en `ajuste`.
ajustar_modelo <- function(datos, formula, prop_train = 0.7, semilla = 2024) {
  resp     <- all.vars(formula)[1]
  es_train <- datos$fecha %in% dividir_fechas(datos$fecha, prop_train, semilla)
  train    <- datos[es_train, ]
  test     <- datos[!es_train, ]

  # Todos los niveles de los factores de la formula deben estar en train (como en 03)
  vars_fac <- intersect(all.vars(formula), names(datos)[map_lgl(datos, is.factor)])
  sin_dias <- unlist(map(vars_fac, \(v) {
    falta <- setdiff(levels(datos[[v]]), as.character(train[[v]]))
    if (length(falta) > 0) paste0(v, "=", falta)
  }))
  if (length(sin_dias) > 0) {
    stop("Niveles sin ningun dia en train: ", paste(sin_dias, collapse = ", "))
  }

  mod  <- lm(formula, data = train)
  s    <- summary(mod)
  pred <- predict(mod, test)
  tibble(r2            = s$r.squared,
         r2_aj         = s$adj.r.squared,
         aic           = AIC(mod),
         rmse_test     = sqrt(mean((test[[resp]] - pred)^2)),
         mae_test      = mean(abs(test[[resp]] - pred)),
         rmse_baseline = sqrt(mean((test[[resp]] - mean(train[[resp]]))^2)),
         n_train       = nrow(train),
         n_test        = nrow(test),
         ajuste        = list(mod))
}

# Serie diaria con el ajuste (izquierda) y observados vs predichos (derecha), con el lm
# ya ajustado. Guarda un PNG en `dir` y devuelve invisible la ruta.
graficar_municipio <- function(datos, modelo, municipio, dir = dir_fig,
                               archivo = paste0("auto_", gsub(" ", "_", tolower(municipio)), ".png")) {
  datos$pred <- predict(modelo, datos)
  p_serie <- ggplot(datos, aes(fecha)) +
    geom_line(aes(y = n_siniestros), colour = col_gr, linewidth = 0.25) +
    geom_line(aes(y = pred), colour = col_ln, linewidth = 0.4) +
    labs(x = NULL, y = "Siniestros por día", title = "Serie diaria",
         subtitle = "Gris: observado. Rojo: ajuste del modelo")
  p_op <- ggplot(datos, aes(pred, n_siniestros)) +
    geom_point(alpha = 0.3, size = 0.8, colour = col_pt) +
    geom_abline(slope = 1, intercept = 0, colour = col_ln) +
    labs(x = "Predicho", y = "Observado", title = "Observados vs. predichos",
         subtitle = "Recta roja: identidad")
  p <- p_serie + p_op + plot_layout(widths = c(2, 1)) +
    plot_annotation(title = municipio, subtitle = deparse1(formula(modelo)))
  ruta <- file.path(dir, archivo)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  ggsave(ruta, p, width = 10, height = 4, dpi = 150, bg = "white")
  invisible(ruta)
}

# Flujo completo sobre un panel: preparar (map) -> validar (map_dfr) -> descartar los que
# fallan -> ajustar todas las combinaciones municipio x modelo (pmap). El ajuste va dentro
# de safely(): si una combinacion falla, se registra el error y el resto sigue.
correr_flujo <- function(panel, municipios, formulas, prop_train = 0.7, semilla = 2024) {
  datos      <- map(set_names(municipios), \(m) preparar_municipio(panel, m))
  validacion <- map_dfr(municipios, \(m) validar_municipio(datos[[m]], m))

  descartados <- validacion$municipio[!validacion$ok]
  for (m in descartados) {
    message("Municipio descartado: ", m, " -> ", validacion$problema[validacion$municipio == m])
  }
  datos_ok <- datos[validacion$municipio[validacion$ok]]

  ajustar_seguro <- safely(ajustar_modelo)
  grilla  <- expand_grid(municipio = names(datos_ok), modelo = names(formulas))
  salidas <- pmap(grilla, \(municipio, modelo)
                  ajustar_seguro(datos_ok[[municipio]], formulas[[modelo]], prop_train, semilla))

  fallo <- map_lgl(salidas, \(s) !is.null(s$error))
  for (i in which(fallo)) {
    message("Ajuste fallido: ", grilla$municipio[i], " ", grilla$modelo[i], " -> ",
            conditionMessage(salidas[[i]]$error))
  }
  resultados <- bind_cols(grilla[!fallo, ], map_dfr(salidas[!fallo], "result"))
  list(datos = datos_ok, validacion = validacion, resultados = resultados,
       fallos = grilla[fallo, ])
}

# ---- 4. Corrida automatizada: 8 municipios x 3 modelos ----------------------------
flujo      <- correr_flujo(panel, municipios, formulas, prop_train, semilla)
datos_ok   <- flujo$datos
validacion <- flujo$validacion
res        <- flujo$resultados

cat("\n== Validacion (", nrow(validacion), " municipios, ", sum(validacion$ok),
    " ok) ==\n", sep = "")
print(validacion, n = Inf, width = Inf)
cat("Ajustes fallidos:", nrow(flujo$fallos), "\n")

# Indicadores escalares por municipio (map_dbl: un numero por elemento de la lista)
media_dia <- map_dbl(datos_ok, \(d) mean(d$n_siniestros))
total_mun <- map_dbl(datos_ok, \(d) sum(d$n_siniestros))
cat("\nMedia diaria por municipio:", paste(names(media_dia), round(media_dia, 2), sep = "=", collapse = " | "), "\n")

# El split es el mismo para todos: mismas fechas en train
fechas_train <- map(datos_ok, \(d) dividir_fechas(d$fecha, prop_train, semilla))
stopifnot(n_distinct(fechas_train) == 1)

# Tabla de resultados (sin la list-column del lm) y su guardado
tab_res <- res |> select(municipio, modelo, all_of(cols_metricas))
cat("\n== Metricas por municipio y modelo ==\n")
print(tab_res |> mutate(across(c(r2, r2_aj, rmse_test, mae_test, rmse_baseline), \(x) round(x, 3)),
                        aic = round(aic, 1)), n = Inf, width = Inf)

f_met <- file.path(dir_tab, "auto_metricas_municipio_modelo.csv")
f_val <- file.path(dir_tab, "auto_validacion.csv")
walk2(list(tab_res |> mutate(across(where(is.double), \(x) round(x, 4))), validacion),
      c(f_met, f_val), \(t, f) write.csv(t, f, row.names = FALSE))

# ---- 5. Comparacion entre modelos y municipios ----------------------------------------
# Test F de M1 -> M2 en cada municipio (usa los lm guardados en la list-column `ajuste`)
p_F_clima <- map_dbl(names(datos_ok), \(m) {
  mod <- \(nom) res$ajuste[[which(res$municipio == m & res$modelo == nom)]]
  anova(mod("M1"), mod("M2"))[["Pr(>F)"]][2]
})
comparacion <- res |>
  group_by(municipio) |>
  summarise(rmse_baseline = first(rmse_baseline),
            rmse_M0 = rmse_test[modelo == "M0"],
            rmse_M1 = rmse_test[modelo == "M1"],
            rmse_M2 = rmse_test[modelo == "M2"],
            r2_M1   = r2[modelo == "M1"],
            ganador = modelo[which.min(rmse_test)]) |>
  mutate(media_dia        = media_dia[municipio],
         mejora_M1_pct    = 100 * (rmse_baseline - rmse_M1) / rmse_baseline,
         mejora_clima_pct = 100 * (rmse_M1 - rmse_M2) / rmse_M1,   # M2 vs M1 (>0: el clima baja el RMSE)
         p_F_clima        = p_F_clima,
         clima_aporta     = rmse_M2 < rmse_M1) |>
  # Ranking por cuanto mejora M1 al baseline: mide que tan explicable es el municipio por
  # calendario (el RMSE absoluto solo ordenaria por tamano: mas siniestros, mas error)
  arrange(desc(mejora_M1_pct)) |>
  mutate(ranking = row_number())

cat("\n== Comparacion por municipio (RMSE de test) ==\n")
print(comparacion |> mutate(across(where(is.double), \(x) round(x, 3))), n = Inf, width = Inf)
cat("\nGanador por municipio:", paste(table(comparacion$ganador), names(table(comparacion$ganador)),
                                      sep = " x ", collapse = " | "), "\n")
cat("Municipios donde el clima baja el RMSE test (M2 < M1):",
    sum(comparacion$clima_aporta), "de", nrow(comparacion),
    "| con test F significativo (p < 0.05):", sum(comparacion$p_F_clima < 0.05), "\n")

# Grafico comparativo: RMSE de test (con el baseline) y R2, por municipio y modelo
res_g <- res |> mutate(mun = sub("MUNICIPIO ", "", municipio))
p_rmse <- ggplot(res_g, aes(mun, rmse_test, fill = modelo)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_point(data = distinct(res_g, mun, rmse_baseline), aes(mun, rmse_baseline),
             inherit.aes = FALSE, shape = 18, size = 3) +
  scale_fill_manual(values = col_modelo) +
  labs(x = "Municipio", y = "RMSE test (siniestros por día)", fill = "Modelo",
       title = "Error de test", subtitle = "Rombo negro: baseline (media de train)")
p_r2 <- ggplot(res_g, aes(mun, r2, fill = modelo)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  scale_fill_manual(values = col_modelo) +
  labs(x = "Municipio", y = "R² (train)", fill = "Modelo", title = "Ajuste")
ggsave(file.path(dir_fig, "auto_comparacion.png"),
       p_rmse + p_r2 + plot_layout(guides = "collect"),
       width = 10, height = 4.2, dpi = 150, bg = "white")

# ---- 6. Graficos por municipio (M1): un PNG cada uno, prefijo auto_ --------------------
mods_M1 <- set_names(res$ajuste[res$modelo == "M1"], res$municipio[res$modelo == "M1"])
walk(names(datos_ok), \(m) graficar_municipio(datos_ok[[m]], mods_M1[[m]], m))
cat("\nFiguras por municipio: ", length(list.files(dir_fig, pattern = "^auto_municipio_")),
    " PNG en ", dir_fig, "\n", sep = "")

# ---- 7. Prueba de robustez: un MUNICIPIO X defectuoso (solo en memoria) ------------------
# Copia de A con 3 NA en n_siniestros, sin dias feriado (se pasan a entre_semana) y con
# 145 dias menos (los ultimos). No se escribe a disco.
panel_X <- panel |>
  filter(zona_id == "MUNICIPIO A", fecha <= fecha_fin - 145) |>
  mutate(zona_id      = "MUNICIPIO X",
         tipo_dia     = replace(tipo_dia, tipo_dia == "feriado", "entre_semana"),
         n_siniestros = replace(n_siniestros, c(10, 200, 450), NA))
flujo_X <- correr_flujo(bind_rows(panel, panel_X), c(municipios, "MUNICIPIO X"), formulas,
                        prop_train, semilla)

val_X <- flujo_X$validacion |> filter(municipio == "MUNICIPIO X")
cat("\n== Prueba de robustez: MUNICIPIO X ==\n")
cat("ok =", val_X$ok, "\nproblema:", val_X$problema, "\n")
cat("Municipios que siguieron en el flujo:", n_distinct(flujo_X$resultados$municipio),
    "| filas de resultados:", nrow(flujo_X$resultados), "\n")

# Si X no se hubiera validado, safely() contiene el error del ajuste en vez de cortar todo
ajuste_X <- safely(ajustar_modelo)(preparar_municipio(panel_X, "MUNICIPIO X"), f1)
cat("X sin validar -> resultado NULL:", is.null(ajuste_X$result),
    "| error capturado:", conditionMessage(ajuste_X$error), "\n")

# ---- 8. Chequeos de que la automatizacion no se equivoca ---------------------------------
# a) M1 de MUNICIPIO A: la funcion da lo mismo que el caso manual
fila_A_M1 <- res |> filter(municipio == "MUNICIPIO A", modelo == "M1") |> select(all_of(cols_metricas))
stopifnot(isTRUE(all.equal(as.data.frame(fila_A_M1), manual_A, check.attributes = FALSE)))

# b) La suma de los 8 municipios es 36.612 y coincide con el total diario del panel
total_diario <- tapply(panel$n_siniestros, panel$fecha, sum)
suma_por_dia <- tapply(bind_rows(datos_ok)$n_siniestros, bind_rows(datos_ok)$fecha, sum)
stopifnot(length(datos_ok) == 8,
          sum(total_mun) == 36612,
          sum(total_diario) == 36612,
          isTRUE(all.equal(total_diario, suma_por_dia)))

# c) Tabla final: exactamente 8 x 3 filas (una por combinacion), sin NA en las metricas
stopifnot(nrow(tab_res) == 8 * 3,
          nrow(distinct(tab_res, municipio, modelo)) == 8 * 3,
          !anyNA(tab_res[cols_metricas]))

# d) Sanity de las metricas
stopifnot(all(tab_res$r2 >= 0 & tab_res$r2 <= 1),
          all(tab_res$rmse_test > 0),
          all(tab_res$n_train + tab_res$n_test == 1645))

# e) La prueba con X: marcado como no ok, descartado, y los otros 8 dan lo mismo que antes
stopifnot(!val_X$ok,
          !"MUNICIPIO X" %in% flujo_X$resultados$municipio,
          isTRUE(all.equal(select(flujo_X$resultados, municipio, modelo, all_of(cols_metricas)),
                           tab_res)))
cat("\nTodos los stopifnot pasaron.\n")

# ---- 9. Lectura de la comparacion y respuestas a la consigna ---------------------------------
# (cifras de la corrida con panel completo, split 70/30, semilla 2024: 1.152 train / 493 test)
#
# LECTURA DE LA COMPARACION
# - R2 bajo, como se esperaba: M1 entre 0,036 (F) y 0,131 (C), media 0,070; M2 entre 0,036 y
#   0,133, media 0,075. Es coherente con el 0,055 de M2 sobre las 13.160 filas (HANDOFF): con
#   2 a 3,5 siniestros por municipio-dia casi todo es ruido de conteo. No es un bug ni se
#   cambio el diseno para subirlo.
# - Ganador por RMSE de test: M1 en 5 municipios (C, CH, E, F, G) y M0 en 3 (A, B, D); M2 en
#   ninguno. En A, B y D los 11 parametros de mes agregan ruido: M1 queda peor que M0 en test.
# - M1 sobre el baseline (RMSE test): de +7,4 % (C) a -0,9 % (A), media 3,0 %. Ranking por esa
#   mejora: C, CH, E, D, F, B, G, A. A es el unico donde M1 es peor que predecir la media.
# - Clima (M2 vs M1): no baja el RMSE de test en ninguno de los 8 (de -0,04 % a -0,80 %). El
#   test F sobre train solo es significativo en A (p = 0,003), pero esa mejora dentro de la
#   muestra (R2 0,038 -> 0,053) no se traslada a test. Misma conclusion que 03: el clima no aporta.
#
# RESPUESTAS A LAS 8 PREGUNTAS
# 1) Que se repetia: el procedimiento completo de 03 (filtrar y armar factores, split 70/30,
#    ajustar M0/M1/M2, calcular R2, R2 aj., AIC, RMSE/MAE de test y baseline, graficar) para
#    cada municipio: 8 municipios x 3 modelos = 24 ajustes, mas 8 graficos y 8 validaciones.
# 2) Pasaron a argumentos: el municipio (municipio), la formula (formula), la proporcion de
#    train (prop_train = 0,7), la semilla (semilla = 2024), el tamano esperado
#    (n_esperado = 1645), el minimo de dias por nivel (min_por_nivel = 5), la carpeta de
#    salida (dir = dir_fig) y el nombre del archivo. Los niveles de los factores y las
#    formulas M0/M1/M2 quedan como constantes compartidas arriba, iguales a 03.
# 3) Que devuelve cada funcion:
#    - preparar_municipio(): data.frame de 1.645 filas del municipio, ordenado por fecha, con
#      tipo_dia, estado_clima y mes como factor (referencia entre_semana, despejado, ene).
#    - validar_municipio(): tibble de 1 fila con 12 columnas: un contador por chequeo, `ok`
#      (logico) y `problema` (texto; "ninguno" si ok).
#    - dividir_fechas(): vector de 1.152 fechas de train (auxiliar, comun a todos).
#    - ajustar_modelo(): tibble de 1 fila con r2, r2_aj, aic, rmse_test, mae_test,
#      rmse_baseline, n_train (1.152), n_test (493) y el lm en la list-column `ajuste`
#      (se uso para el test F M1 vs M2 y para graficar).
#    - graficar_municipio(): invisible la ruta del PNG (outputs/figuras/auto_municipio_x.png).
#    - correr_flujo(): lista con datos validos, validacion, resultados (24 filas) y fallos.
# 4) Por que cada herramienta de purrr:
#    - map(): una lista con nombre de 8 data.frames, uno por municipio (cada elemento es un
#      data.frame distinto); tambien para contar dias por nivel dentro de la validacion.
#    - map_dbl(): un numero por municipio: media diaria (de 2,05 en CH a 3,52 en C; la media
#      de las 8 da 2,78, la de HANDOFF), total (suma 36.612) y p del test F del clima.
#    - map_dfr(): junta tibbles de una fila en una tabla: la validacion (8 x 12) y los
#      resultados de los ajustes (24 filas).
#    - pmap(): recorre las 24 filas de expand_grid(municipio, modelo) pasando dos argumentos
#      por fila; no hay una sola lista que recorrer sino un par (municipio, modelo).
#    - walk() / walk2(): efectos laterales sin resultado que usar: walk() guarda los 8 PNG,
#      walk2() escribe los 2 CSV (tabla, ruta). No hizo falta map2(): walk2() es su version
#      para efectos laterales y no hay otro lugar con dos listas en paralelo que devuelvan algo.
#    - safely(): envuelve ajustar_modelo() para que un error quede en $error y no corte pmap().
# 5) Problema a mano: 24 bloques copiados y pegados (cada uno con su filtro, split, lm y
#    metricas) en que un descuido silencioso rompe la comparacion: olvidar set.seed() o
#    cambiarlo en un solo bloque deja a un municipio con otros dias de train (todos los
#    resultados dejan de ser comparables sin que nada falle), un nombre de municipio mal
#    copiado da un data.frame de 0 filas o mezcla un modelo con los datos de otro municipio,
#    y cualquier cambio (otra formula, otra proporcion) hay que repetirlo 24 veces. Aca el
#    split sale de una sola funcion que depende solo de las fechas (stopifnot: las 8 listas
#    de fechas de train son identicas) y cada formula esta definida una vez.
# 6) Validaciones incorporadas en validar_municipio(): n de filas (= 1.645), NA, fechas
#    duplicadas, fechas faltantes respecto de 2021-07-01/2025-12-31, conteos negativos o no
#    enteros, varianza cero, todo en ceros, y niveles de tipo_dia/mes/estado_clima ausentes o
#    con menos de 5 dias. Ademas ajustar_modelo() exige que todos los niveles esten en train
#    (como 03). Los 8 municipios reales pasaron todo (el calendario es el mismo en todos: 77
#    dias feriado, 46 de ellos en train; entre 113 y 155 dias por mes).
# 7) Datos inesperados: MUNICIPIO X (copia de A con 3 NA, sin feriados y con 145 dias menos)
#    dio ok = FALSE con problema: "1500 filas (esperado 1645) | 3 NA | 145 fechas faltantes |
#    niveles con menos de 5 dias: tipo_dia:feriado(0)". Se descarto con un mensaje y el flujo
#    siguio con los 8 restantes: 24 filas de resultados, identicas a las de la corrida sin X.
#    Si X no se hubiera validado, safely() habria capturado el error del ajuste ("Niveles sin
#    ningun dia en train: tipo_dia=feriado") sin cortar el resto, en vez de un error de predict().
# 8) Como verificar que no hay resultados incorrectos (stopifnot de la seccion 8):
#    a) M1 de MUNICIPIO A: la funcion da lo mismo que el caso manual (all.equal);
#    b) la suma de n_siniestros de los 8 municipios es 36.612 y coincide, dia por dia, con el
#       total diario del panel;
#    c) la tabla final tiene exactamente 8 x 3 = 24 filas, sin repetir combinaciones y sin NA;
#    d) sanity: R2 entre 0 y 1, RMSE > 0 y n_train + n_test = 1.645 en las 24 filas;
#    e) MUNICIPIO X queda marcado y fuera de los resultados, y los otros 8 no cambian.
