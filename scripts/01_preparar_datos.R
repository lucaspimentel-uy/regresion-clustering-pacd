# 01_preparar_datos.R -- de los datos originales a la base procesada.
# Entrada : data/raw/ (zip del unificado, poligonos de barrio, panel diario, referencia)
# Salida  : data/processed/siniestros_mvd.csv   un siniestro por fila, con barrio y municipio
#           data/processed/barrios.csv          un barrio por fila, con area
#           data/processed/clima_diario.csv     un dia por fila: tipo de dia y clima
#           data/processed/panel_diario.csv     municipio x dia: conteo + clima
#           outputs/tablas/frecuencias_*.csv, validaciones_01_preparacion.csv
source(here::here("scripts", "00_setup.R"))

# ---- 1. Existencia de los archivos originales --------------------------------
originales <- c(f_zip_unificado, f_barrios, f_panel_raw, f_sin_mvd_ref)
validar(all(file.exists(originales)), "Archivos originales presentes",
        paste(basename(originales), collapse = ", "))

# ---- 2. Lectura del unificado ------------------------------------------------
raw <- leer_unificado(f_zip_unificado, f_csv_unificado)
n_lineas <- contar_lineas(f_zip_unificado, f_csv_unificado)
# Con el manejo de comillas por defecto se leian 49.544 filas: este control lo detecta.
validar(nrow(raw) == n_lineas, "Lectura completa del unificado",
        paste(fmt(nrow(raw)), "filas leídas =", fmt(n_lineas), "líneas de datos"))
# Para documentar el problema: cuantas filas devuelve la lectura con comillas por defecto
n_lectura_defecto <- nrow(read.csv(unz(f_zip_unificado, f_csv_unificado), strip.white = TRUE))
n_calle_con_comillas <- sum(grepl("\"", raw$Calle))
validar_columnas(raw, c("Fecha", "Calle", "Tipo.de.Siniestro", "Gravedad", "Dia.Semana",
                        "Hora", "Departamento", "Localidad", "fixed", "X", "Y"),
                 "el unificado")

# ---- 3. Fechas ----------------------------------------------------------------
# Formato unico m/d/yyyy. Se confirma con la columna `Dia Semana`, que es independiente:
# si el formato fuera d/m, el dia de la semana derivado no coincidiria.
raw$fecha <- as.Date(raw$Fecha, format = "%m/%d/%Y")
validar(!anyNA(raw$fecha), "Fechas válidas (m/d/yyyy)",
        paste(sum(is.na(raw$fecha)), "fechas sin parsear"))
coincide_dia <- mean(dia_semana_es(raw$fecha) == raw$Dia.Semana)
validar(coincide_dia == 1, "Día de la semana coincide con la fecha",
        paste0(fmt(100 * coincide_dia, 1), " % de coincidencia"))

# ---- 4. Montevideo, ventana y duplicados exactos -----------------------------
columnas_orig <- c("Fecha", "Calle", "Tipo.de.Siniestro", "Gravedad", "Dia.Semana",
                   "Hora", "Departamento", "Localidad", "fixed", "X", "Y")
mvd <- raw |> filter(Departamento == "MONTEVIDEO", between(fecha, fecha_ini, fecha_fin))
n_ventana <- nrow(mvd)
# Filas que repiten los 11 campos originales: se conserva la primera.
mvd <- mvd[!duplicated(mvd[, columnas_orig]), ]
n_duplicados <- n_ventana - nrow(mvd)

# Contexto fuera de la ventana: registros de Montevideo por año en todo el archivo
# (con duplicados), para ver la caida de 2020 y la recuperacion posterior.
raw |>
  filter(Departamento == "MONTEVIDEO") |>
  count(anio = year(fecha), name = "registros") |>
  mutate(por_dia = registros / if_else(leap_year(anio), 366, 365)) |>
  guardar_tabla("registros_mvd_por_anio")
rm(raw)

# ---- 5. Faltantes, variables derivadas y categorias ---------------------------
mvd <- mvd |>
  recodificar_faltantes(c("Calle", "Tipo.de.Siniestro", "Gravedad", "Dia.Semana", "Localidad")) |>
  derivar_variables()
validar(!anyNA(mvd$x) && !anyNA(mvd$y), "Coordenadas completas",
        paste(sum(is.na(mvd$x) | is.na(mvd$y)), "siniestros sin coordenadas"))

# Una misma categoria aparece una vez sin tilde: se unifica antes de contar
mvd$Tipo.de.Siniestro <- recode(mvd$Tipo.de.Siniestro,
  "COLISIÓN CON OBSTACULO EN CALZADA" = "COLISIÓN CON OBSTÁCULO EN CALZADA")

# Frecuencias ANTES de agrupar (justifican el umbral del 3 %)
frecuencias <- list(tipo_siniestro = mvd$Tipo.de.Siniestro, gravedad = mvd$Gravedad) |>
  map(tabla_frecuencias)
iwalk(frecuencias, ~ guardar_tabla(.x, paste0("frecuencias_", .y)))
mvd$tipo_ag <- agrupar_categorias(mvd$Tipo.de.Siniestro, umbral_otros)

# ---- 6. Barrio ----------------------------------------------------------------
# Las coordenadas X/Y estan en UTM 21S. Se valida el EPSG contra la lat/lon conocida de
# la referencia (mismo punto): el error debe ser de centimetros. UTM 20S es un control
# negativo, para mostrar que la prueba discrimina.
referencia <- read_csv(f_sin_mvd_ref, show_col_types = FALSE)
err <- map(c(utm21s = epsg_utm, control_utm20s = 32720), ~ error_epsg(referencia, .x))
validar(err$utm21s["max_m"] < 1 && err$control_utm20s["mediana_m"] > 1e5,
        paste0("EPSG ", epsg_utm, " reproduce la lat/lon de referencia"),
        paste0("error max ", fmt(100 * err$utm21s["max_m"], 1), " cm; control UTM 20S: ",
               fmt(err$control_utm20s["mediana_m"] / 1000), " km"))

barrios <- leer_barrios(f_barrios, epsg_utm)
mvd <- asignar_barrio(mvd, barrios, epsg_utm)
n_sin_barrio <- sum(is.na(mvd$barrio))
mvd <- filter(mvd, !is.na(barrio))   # fuera de los 62 poligonos (Ruta 1 km 22)

# ---- 7. Municipio -------------------------------------------------------------
# El unificado no trae municipio; la referencia si (zona_id), por coordenada.
# Primero se valida que zona_id sea funcion de la coordenada.
mun_por_xy <- referencia |> distinct(coord_x, coord_y, zona_id)
validar(!any(duplicated(mun_por_xy[, c("coord_x", "coord_y")])),
        "Municipio único por coordenada en la referencia")
mvd <- mvd |>
  left_join(mun_por_xy, by = c("x" = "coord_x", "y" = "coord_y")) |>
  rename(municipio = zona_id)
validar(!anyNA(mvd$municipio), "Todos los siniestros con municipio",
        paste(sum(is.na(mvd$municipio)), "sin municipio"))

# ---- 8. Validacion contra la fuente independiente ----------------------------
# La referencia (36.612 filas) se construyo por separado. Si la limpieza es correcta,
# los dos conjuntos tienen exactamente los mismos pares fecha + coordenadas.
validar(identical(clave_fecha_xy(mvd$fecha, mvd$x, mvd$y),
                  clave_fecha_xy(referencia$fecha, referencia$coord_x, referencia$coord_y)),
        "Base limpia = referencia (fecha y coordenadas, fila a fila)",
        paste0(fmt(n_ventana), " en la ventana - ", n_duplicados, " duplicados - ",
               n_sin_barrio, " sin barrio = ", fmt(nrow(mvd))))

# ---- 9. Tablas procesadas -----------------------------------------------------
siniestros <- mvd |>
  arrange(fecha, hora) |>
  transmute(id = row_number(), fecha, hora, dia_semana = Dia.Semana, calle = Calle,
            tipo = Tipo.de.Siniestro, tipo_ag, gravedad = Gravedad, nocturno, finde,
            x, y, lon = round(lon, 6), lat = round(lat, 6), barrio_id = nrobarrio, barrio, municipio)
write_csv(siniestros, f_siniestros)

tabla_barrios <- barrios |>
  st_drop_geometry() |>
  transmute(barrio_id = nrobarrio, barrio, area_km2) |>
  arrange(barrio_id)
validar(n_distinct(tabla_barrios$barrio_id) == nrow(tabla_barrios) &&
          all(siniestros$barrio_id %in% tabla_barrios$barrio_id),
        "Barrios: identificador único y todos los siniestros con barrio conocido",
        paste(nrow(tabla_barrios), "barrios;", n_distinct(siniestros$barrio_id), "con siniestros"))
write_csv(tabla_barrios, f_barrios_tab)

# Clima y tipo de dia: el panel original los repite en cada municipio. Se valida que
# sean identicos entre municipios para cada fecha y se guarda una fila por dia.
panel_raw <- read_csv(f_panel_raw, show_col_types = FALSE)
vars_dia <- c("tipo_dia", "temp_media", "temp_max", "temp_min", "lluvia_mm",
              "viento_max_kmh", "estado_clima")
validar_columnas(panel_raw, c("fecha", "zona_id", "n_siniestros", vars_dia), "el panel diario")
distintos <- panel_raw |> group_by(fecha) |> summarise(across(all_of(vars_dia), n_distinct))
validar(all(distintos[vars_dia] == 1), "Clima idéntico entre municipios en cada fecha")
clima <- panel_raw |> distinct(fecha, across(all_of(vars_dia))) |> arrange(fecha)
fechas <- seq(fecha_ini, fecha_fin, by = "day")
validar(identical(clima$fecha, fechas), "Clima: un registro por cada día de la ventana",
        paste(fmt(nrow(clima)), "días"))
write_csv(clima, f_clima)

# Panel municipio x dia generado desde los siniestros limpios. Debe coincidir con el
# n_siniestros del panel original en las 13.160 filas.
panel <- contar_por_dia(siniestros, fechas, sort(unique(panel_raw$zona_id))) |>
  left_join(clima, by = "fecha")
cotejo <- panel |>
  inner_join(select(panel_raw, fecha, municipio = zona_id, n_original = n_siniestros),
             by = c("fecha", "municipio"))
validar(nrow(cotejo) == nrow(panel_raw) && all(cotejo$n_siniestros == cotejo$n_original),
        "Panel generado = panel original (conteo municipio x día)",
        paste(fmt(nrow(panel)), "filas;", sum(cotejo$n_siniestros != cotejo$n_original),
              "diferencias"))
write_csv(panel, f_panel)

# Resumen del flujo de registros (lo usa el informe)
guardar_tabla(tibble(paso = c("Filas del unificado", "Montevideo en la ventana",
                              "Duplicados exactos", "Fuera de los 62 barrios",
                              "Siniestros en la base procesada"),
                     registros = c(n_lineas, n_ventana, -n_duplicados, -n_sin_barrio,
                                   nrow(siniestros))),
              "flujo_registros")

# Problemas de calidad detectados (lo usa el informe)
guardar_tabla(tibble(
  problema = c("Calles con comillas dobles (rompen la lectura por defecto)",
               "Filas leidas con el manejo de comillas por defecto",
               "Filas leidas con quote = \"\"",
               "Duplicados exactos en la ventana",
               "Siniestros fuera de los 62 barrios",
               "Siniestros sin calle", "Siniestros sin tipo", "Siniestros sin hora valida"),
  n = c(n_calle_con_comillas, n_lectura_defecto, n_lineas, n_duplicados, n_sin_barrio,
        sum(is.na(siniestros$calle)), sum(is.na(siniestros$tipo)), sum(is.na(siniestros$hora)))),
  "problemas_calidad")
guardar_validaciones("01_preparacion")
