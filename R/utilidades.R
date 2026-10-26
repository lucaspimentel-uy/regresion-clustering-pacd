# utilidades.R -- validaciones, guardado de tablas/figuras y formato de numeros.

# ---- Validaciones -------------------------------------------------------------
# Registro de las validaciones de la sesion. Cada script lo vuelca a una tabla con
# guardar_validaciones(), y el informe las muestra.
.validaciones <- new.env()
.validaciones$filas <- list()

# Evalua una condicion; la registra y, si es falsa, corta el pipeline con un mensaje claro.
validar <- function(condicion, nombre, detalle = "") {
  ok <- isTRUE(condicion)
  .validaciones$filas[[length(.validaciones$filas) + 1]] <-
    tibble(validacion = nombre, resultado = if (ok) "OK" else "FALLA", detalle = detalle)
  if (!ok) {
    stop("Validacion fallida: ", nombre, if (nzchar(detalle)) paste0(" (", detalle, ")"),
         call. = FALSE)
  }
  invisible(TRUE)
}

# Corta si faltan columnas necesarias (se registra como validacion).
validar_columnas <- function(datos, columnas, nombre_tabla) {
  faltantes <- setdiff(columnas, names(datos))
  validar(length(faltantes) == 0,
          paste("Columnas necesarias en", nombre_tabla),
          if (length(faltantes) == 0) paste(length(columnas), "columnas presentes")
          else paste("faltan:", paste(faltantes, collapse = ", ")))
}

guardar_validaciones <- function(etapa) {
  tabla <- bind_rows(.validaciones$filas) |> mutate(etapa = etapa, .before = 1)
  write_csv(tabla, file.path(dir_tab, paste0("validaciones_", etapa, ".csv")))
  .validaciones$filas <- list()
  message(nrow(tabla), " validaciones OK (", etapa, ")")
  invisible(tabla)
}

# ---- Salidas ------------------------------------------------------------------
guardar_tabla <- function(tabla, nombre) {
  write_csv(tabla, file.path(dir_tab, paste0(nombre, ".csv")))
  invisible(tabla)
}

guardar_figura <- function(grafico, nombre, ancho = 8, alto = 4.5) {
  ggsave(file.path(dir_fig, paste0(nombre, ".png")), grafico,
         width = ancho, height = alto, dpi = 150, bg = "white")
  invisible(grafico)
}

# Numeros con formato rioplatense (coma decimal, punto de miles), para el informe.
fmt <- function(x, decimales = 0) {
  formatC(x, format = "f", digits = decimales, big.mark = ".", decimal.mark = ",")
}
fmt_pct <- function(x, decimales = 1) paste0(fmt(100 * x, decimales), " %")

# Paleta Okabe-Ito (apta para daltonismo)
paleta <- c("#0072B2", "#E69F00", "#009E73", "#CC79A7", "#D55E00", "#56B4E9",
            "#F0E442", "#000000")
col_punto <- "#2C6E91"
col_linea <- "#C0392B"
