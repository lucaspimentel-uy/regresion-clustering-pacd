# 00_setup.R -- paquetes, rutas, parametros y funciones propias.
# Todos los scripts del pipeline empiezan con:
#   source(here::here("scripts", "00_setup.R"))
# `here` ubica la raiz del proyecto (archivo .here), asi que los scripts funcionan
# sin importar el directorio de trabajo y sin caminos absolutos.

# ---- Paquetes -----------------------------------------------------------------
paquetes <- c("dplyr", "tidyr", "purrr", "readr", "ggplot2", "lubridate", "slider",
              "broom", "sf", "DBI", "RSQLite", "cluster", "scales", "patchwork", "here")
faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) {
  stop("Faltan paquetes: ", paste(faltan, collapse = ", "),
       "\nInstalar con install.packages(c(",
       paste0("\"", faltan, "\"", collapse = ", "), "))")
}
suppressPackageStartupMessages(
  for (p in paquetes) library(p, character.only = TRUE)
)
# Los datos y los scripts estan en UTF-8 (tildes en categorias como "CAÍDA").
if (!l10n_info()[["UTF-8"]]) {
  warning("La sesion de R no usa UTF-8 (locale ", Sys.getlocale("LC_CTYPE"), "). ",
          "Usar R >= 4.2 en Windows o un locale UTF-8 (p. ej. LANG=C.UTF-8).")
}

# ---- Rutas (relativas a la raiz del proyecto) ---------------------------------
dir_raw  <- here("data", "raw")         # datos originales: solo lectura
dir_proc <- here("data", "processed")   # datos generados por el pipeline
dir_fig  <- here("outputs", "figuras")
dir_tab  <- here("outputs", "tablas")
dir_sql  <- here("sql")
for (d in c(dir_proc, dir_fig, dir_tab)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

# Datos originales
f_zip_unificado <- file.path(dir_raw, "uru_siniestros_unificado.zip")    # siniestros de todo el pais
f_csv_unificado <- "uru_siniestros_unificado.csv"                         # nombre dentro del zip
f_barrios       <- file.path(dir_raw, "barrios_montevideo.geojson")       # 62 poligonos de barrio
f_panel_raw     <- file.path(dir_raw, "panel_diario_montevideo.csv")      # municipio x dia, con clima
f_sin_mvd_ref   <- file.path(dir_raw, "siniestros_montevideo.csv")        # referencia: lat/lon y municipio

# Datos procesados (salidas de 01 y 02)
f_siniestros <- file.path(dir_proc, "siniestros_mvd.csv")
f_barrios_tab <- file.path(dir_proc, "barrios.csv")
f_clima      <- file.path(dir_proc, "clima_diario.csv")
f_panel      <- file.path(dir_proc, "panel_diario.csv")
f_db         <- file.path(dir_proc, "siniestros_mvd.sqlite")
f_perfil     <- file.path(dir_proc, "perfil_barrios.csv")

# ---- Parametros del analisis --------------------------------------------------
semilla   <- 2024                          # split train/test y k-means
fecha_ini <- as.Date("2021-07-01")         # ventana: la misma del panel diario
fecha_fin <- as.Date("2025-12-31")
umbral_otros <- 0.03                       # tipos de siniestro con < 3 % del total -> "OTROS"
epsg_utm  <- 32721                         # WGS84 / UTM 21S (se valida en 01)
set.seed(semilla)

# ---- Funciones propias --------------------------------------------------------
walk(list.files(here("R"), pattern = "\\.R$", full.names = TRUE), source)

theme_set(theme_minimal(base_size = 11))
