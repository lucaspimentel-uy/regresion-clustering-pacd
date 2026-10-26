# 02_base_relacional.R -- base relacional SQLite y consultas SQL.
# Entrada : data/processed/{siniestros_mvd, barrios, clima_diario}.csv  (salida de 01)
# Salida  : data/processed/siniestros_mvd.sqlite   tres tablas relacionadas por barrio_id y fecha
#           data/processed/perfil_barrios.csv      perfil por barrio (insumo de 05)
#           outputs/tablas/sql_*.csv, validaciones_02_sql.csv
source(here::here("scripts", "00_setup.R"))

# ---- 1. Tablas ---------------------------------------------------------------
# SQLite no tiene tipo fecha ni logico: fechas como texto ISO y logicos como 0/1.
siniestros <- read_csv(f_siniestros, show_col_types = FALSE) |>
  mutate(fecha = format(fecha), across(c(nocturno, finde), as.integer))
barrios <- read_csv(f_barrios_tab, show_col_types = FALSE)
clima   <- read_csv(f_clima, show_col_types = FALSE) |> mutate(fecha = format(fecha))

# ---- 2. Base SQLite (se reconstruye desde cero en cada corrida) ---------------
unlink(f_db)
con <- dbConnect(SQLite(), f_db)
tablas <- list(siniestros = siniestros, barrios = barrios, clima_diario = clima)
iwalk(tablas, ~ dbWriteTable(con, .y, .x))
invisible(dbExecute(con, "CREATE INDEX idx_sin_barrio ON siniestros (barrio_id)"))
invisible(dbExecute(con, "CREATE INDEX idx_sin_fecha  ON siniestros (fecha)"))

filas_db <- map_int(names(tablas), ~ dbGetQuery(con, paste("SELECT COUNT(*) AS n FROM", .x))$n)
validar(identical(filas_db, unname(map_int(tablas, nrow))),
        "Tablas cargadas completas en SQLite",
        paste(names(tablas), fmt(filas_db), sep = ": ", collapse = "; "))

# ---- 3. Integridad referencial (sql/chequeos.sql) -----------------------------
chequeos <- leer_consultas(file.path(dir_sql, "chequeos.sql"))
iwalk(chequeos, function(sql, nombre) {
  n <- dbGetQuery(con, sql)$n
  validar(n == 0, paste("SQL:", nombre), paste(n, "filas problemáticas"))
})

# ---- 4. Consultas de analisis (sql/consultas.sql) -----------------------------
# Se ejecutan todas con map() y cada resultado se guarda como sql_<nombre>.csv.
consultas  <- leer_consultas(file.path(dir_sql, "consultas.sql"))
resultados <- map(consultas, ~ as_tibble(dbGetQuery(con, .x)))
iwalk(resultados, ~ guardar_tabla(.x, paste0("sql_", .y)))

# El perfil de barrios es insumo del clustering: va tambien a data/processed.
perfil <- resultados$perfil_barrios
validar(nrow(perfil) == nrow(barrios) && sum(perfil$n) == nrow(siniestros) &&
          !anyNA(perfil),
        "Perfil por barrio: 62 barrios, suma de siniestros igual al total, sin NA",
        paste(nrow(perfil), "barrios;", fmt(sum(perfil$n)), "siniestros"))
write_csv(perfil, f_perfil)

dbDisconnect(con)
guardar_validaciones("02_sql")
