# 01_fechas.R -- Paso 0.b: diagnostico y arreglo de fechas del archivo unificado
# Solo R base. No se descarta ninguna fila por fecha en este script.
#
# Hallazgo: el problema NO era el formato de Fecha (hay un unico
# formato, m/d/yyyy) sino la lectura: 107 lineas traen comillas dobles dentro de
# `Calle` (p. ej. CAMINO VECINAL "RUTA JONES") y read.csv()/readr, con el manejo
# de comillas por defecto, abren una comilla y se tragan lineas hasta la siguiente.
# Con quote = "" se leen las 224.694 filas.

f <- "data/raw/uru_siniestros_unificado.csv"

x <- read.csv(f, colClasses = "character", strip.white = TRUE,
              quote = "", comment.char = "")
cat("Filas leidas:", nrow(x), " (readLines - 1 =", length(readLines(f)) - 1, ")\n")

# --- Formato de Fecha: m/d/yyyy. Se confirma de dos formas ---------------------
partes <- strsplit(x$Fecha, "/", fixed = TRUE)
p1 <- as.integer(vapply(partes, `[`, "", 1))   # candidato a mes
p2 <- as.integer(vapply(partes, `[`, "", 2))   # candidato a dia
cat("\nRango 1er componente:", range(p1, na.rm = TRUE),
    "| 2do componente:", range(p2, na.rm = TRUE), "\n")

fecha <- as.Date(x$Fecha, format = "%m/%d/%Y")
cat("\nNA tras parsear como m/d/yyyy:", sum(is.na(fecha)), "de", length(fecha), "\n")

# Contraste con la columna `Dia Semana` (independiente de la fecha): si el formato
# fuera d/m, los dias de la semana no coincidirian.
dias <- c("LUNES", "MARTES", "MIÉRCOLES", "JUEVES", "VIERNES", "SÁBADO", "DOMINGO")
dow  <- dias[as.integer(format(fecha, "%u"))]
cat("Coincidencia weekday(Fecha) vs `Dia Semana`:",
    round(mean(dow == x$Dia.Semana, na.rm = TRUE) * 100, 2), "%\n")
print(table(coincide = dow == x$Dia.Semana, useNA = "ifany"))

# --- Filas por año, todo el archivo y Montevideo -------------------------------
anio <- as.integer(format(fecha, "%Y"))
cat("\nFilas por año (todo el pais):\n"); print(table(anio, useNA = "ifany"))

mvd <- x$Departamento == "MONTEVIDEO"
cat("\nFilas por año (Departamento == MONTEVIDEO):\n")
print(table(anio[mvd], useNA = "ifany"))
cat("Total Montevideo:", sum(mvd), "\n")

# Filas por año-mes de Montevideo, para ver que no haya huecos
ym <- format(fecha[mvd], "%Y-%m")
cat("\nMeses con 0 filas en Montevideo (2018-01 a 2025-12):\n")
todos <- format(seq(as.Date("2018-01-01"), as.Date("2025-12-01"), by = "month"), "%Y-%m")
print(setdiff(todos, unique(ym)))
cat("Rango de fechas Montevideo:", format(range(fecha[mvd], na.rm = TRUE)), "\n")

# --- Ventana del analisis (solo conteo; no se filtra nada aqui) ----------------
vent <- fecha >= as.Date("2021-07-01") & fecha <= as.Date("2025-12-31")
cat("\nMontevideo en 2021-07-01 / 2025-12-31:", sum(mvd & vent, na.rm = TRUE),
    "(esperado ~36.612)\n")
cat("\nMontevideo en la ventana, por año:\n")
print(table(anio[mvd & vent]))
