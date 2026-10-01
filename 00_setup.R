# 00_setup.R -- paquetes, semilla y rutas (relativas a la raiz del proyecto)
# Uso: desde la raiz del proyecto, `source("00_setup.R")` al inicio de cada script.
# Si falta algun paquete: install.packages(c("dplyr", "tidyr", "ggplot2", "sf",
#                                            "ggrepel", "patchwork", "scales"))

paquetes <- c("dplyr", "tidyr", "ggplot2", "sf", "ggrepel", "patchwork",
              "scales", "cluster")
faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) {
  stop("Faltan paquetes: ", paste(faltan, collapse = ", "),
       "\nInstalar con install.packages(c(",
       paste0("\"", faltan, "\"", collapse = ", "), "))")
}
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

set.seed(2024)

# Rutas relativas a la raiz del proyecto
dir_raw  <- "data/raw"
dir_proc <- "data/processed"
dir_fig  <- "outputs/figuras"
dir_tab  <- "outputs/tablas"

if (!dir.exists(dir_raw)) {
  stop("No encuentro '", dir_raw, "'. Ejecutar desde la raiz del proyecto ",
       "(getwd() = ", getwd(), ").")
}
for (d in c(dir_proc, dir_fig, dir_tab)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

f_unificado <- file.path(dir_raw, "uru_siniestros_unificado.csv")
f_barrios   <- file.path(dir_raw, "barrios_montevideo.geojson")
f_panel     <- file.path(dir_raw, "panel_diario_montevideo.csv")
f_sin_mvd   <- file.path(dir_raw, "siniestros_montevideo.csv")

# Ventana de analisis (la misma que el panel)
fecha_ini <- as.Date("2021-07-01")
fecha_fin <- as.Date("2025-12-31")

# Tema grafico comun
theme_set(theme_minimal(base_size = 11))
