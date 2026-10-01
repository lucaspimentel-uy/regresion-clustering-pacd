# 00_setup.R -- paquetes, semilla y rutas (relativas a la raiz del proyecto)
# Uso: desde la raiz del proyecto, `source("00_setup.R")` al inicio de cada script.
# Si falta algun paquete: install.packages(c("dplyr", "tidyr", "ggplot2", "sf",
#                                            "ggrepel", "patchwork", "scales"))

# Paquetes: dplyr/tidyr (manejo de datos), ggplot2/ggrepel/patchwork/scales (graficos),
# sf (datos espaciales), cluster (silueta)
paquetes <- c("dplyr", "tidyr", "ggplot2", "sf", "ggrepel", "patchwork",
              "scales", "cluster")
# Detecta los que no estan instalados y, si falta alguno, corta indicando como instalarlo
faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) {
  stop("Faltan paquetes: ", paste(faltan, collapse = ", "),
       "\nInstalar con install.packages(c(",
       paste0("\"", faltan, "\"", collapse = ", "), "))")
}
# Carga de paquetes sin mensajes de arranque
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(sf)
  library(ggrepel)
  library(patchwork)
  library(scales)
  library(cluster)
})

# Semilla global: hace reproducibles el split train/test y el k-means
set.seed(2024)

# Rutas relativas a la raiz del proyecto
dir_raw  <- "data/raw"          # datos originales (no se modifican)
dir_proc <- "data/processed"    # datos intermedios (.rds)
dir_fig  <- "outputs/figuras"
dir_tab  <- "outputs/tablas"

# Si no existe data/raw, el script no se esta ejecutando desde la raiz del proyecto
if (!dir.exists(dir_raw)) {
  stop("No encuentro '", dir_raw, "'. Ejecutar desde la raiz del proyecto ",
       "(getwd() = ", getwd(), ").")
}
# Crea las carpetas de salida si todavia no existen
for (d in c(dir_proc, dir_fig, dir_tab)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# Archivos de entrada
f_unificado <- file.path(dir_raw, "uru_siniestros_unificado.csv")   # siniestros de todo el pais
f_barrios   <- file.path(dir_raw, "barrios_montevideo.geojson")     # poligonos de los 62 barrios
f_panel     <- file.path(dir_raw, "panel_diario_montevideo.csv")    # panel municipio x dia (con clima)
f_sin_mvd   <- file.path(dir_raw, "siniestros_montevideo.csv")      # Montevideo con lat/lon y municipio

# Ventana de analisis (la misma que el panel)
fecha_ini <- as.Date("2021-07-01")
fecha_fin <- as.Date("2025-12-31")

# Tema grafico comun a todas las figuras
theme_set(theme_minimal(base_size = 11))
