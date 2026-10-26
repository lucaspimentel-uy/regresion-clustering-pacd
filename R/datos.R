# datos.R -- funciones de lectura, limpieza y construccion de la base procesada.

# ---- Lectura ------------------------------------------------------------------
# Lee el CSV unificado directamente desde el zip (data/raw no se modifica).
# quote = "": 107 lineas traen comillas dobles dentro de `Calle`
# (p. ej. CAMINO VECINAL "RUTA JONES"); con el manejo de comillas por defecto,
# read.csv()/read_csv() abren una comilla y se "tragan" bloques enteros del archivo.
# El separador real es ", " (coma + espacio): strip.white = TRUE quita el espacio.
leer_unificado <- function(ruta_zip, archivo) {
  read.csv(unz(ruta_zip, archivo), colClasses = "character", strip.white = TRUE,
           quote = "", comment.char = "", encoding = "UTF-8")
}

# Cantidad de lineas de datos del archivo (sin encabezado): control de la lectura.
contar_lineas <- function(ruta_zip, archivo) {
  length(readLines(unz(ruta_zip, archivo), encoding = "UTF-8")) - 1
}

# Dia de la semana en mayusculas y en espanol, como la columna `Dia Semana`.
dia_semana_es <- function(fecha) {
  dias <- c("LUNES", "MARTES", "MIÉRCOLES", "JUEVES", "VIERNES", "SÁBADO", "DOMINGO")
  dias[as.integer(format(fecha, "%u"))]          # %u: 1 = lunes ... 7 = domingo
}

# ---- Limpieza -----------------------------------------------------------------
# Textos que en el archivo representan un dato faltante -> NA.
recodificar_faltantes <- function(datos, columnas, textos = c("NO SE INGRESO", "SIN DATOS")) {
  mutate(datos, across(all_of(columnas), ~ if_else(.x %in% textos, NA_character_, .x)))
}

# Tabla de frecuencias ordenada (incluye NA) para revisar categorias antes de agrupar.
tabla_frecuencias <- function(x) {
  tibble(categoria = x) |>
    count(categoria, sort = TRUE) |>
    mutate(categoria = coalesce(categoria, "<NA>"), pct = round(100 * n / sum(n), 2))
}

# Agrupa en "OTROS" las categorias con menos de `umbral` del total (y los NA).
agrupar_categorias <- function(x, umbral) {
  prop <- prop.table(table(x))
  conservar <- names(prop)[prop >= umbral]
  if_else(is.na(x) | !(x %in% conservar), "OTROS", x)
}

# Hora (0-23), indicadores nocturno (22 a 5 h) y fin de semana, coordenadas numericas.
derivar_variables <- function(datos) {
  datos |>
    mutate(hora     = suppressWarnings(as.integer(Hora)),
           hora     = if_else(hora %in% 0:23, hora, NA_integer_),
           nocturno = hora >= 22 | hora <= 5,
           finde    = as.integer(format(fecha, "%u")) >= 6,
           x        = as.numeric(X),
           y        = as.numeric(Y))
}

# ---- Espacial -----------------------------------------------------------------
# Poligonos de barrio en lon/lat, con geometrias reparadas y area en km2 (calculada en UTM).
leer_barrios <- function(ruta, epsg_metros) {
  barrios <- st_read(ruta, quiet = TRUE)
  if (is.na(st_crs(barrios))) st_crs(barrios) <- 4326
  barrios <- st_make_valid(st_transform(barrios, 4326))
  barrios$area_km2 <- as.numeric(st_area(st_transform(barrios, epsg_metros))) / 1e6
  barrios
}

# Error (m) al pasar coord_x/coord_y de la referencia a lon/lat bajo un EPSG candidato,
# comparado contra la lat/lon que trae la misma referencia. Sirve para validar el EPSG.
error_epsg <- function(referencia, epsg) {
  conocido <- st_as_sf(referencia, coords = c("longitud", "latitud"), crs = 4326)
  candidato <- st_as_sf(referencia, coords = c("coord_x", "coord_y"), crs = epsg) |>
    st_transform(4326)
  d <- as.numeric(st_distance(candidato, conocido, by_element = TRUE))
  c(mediana_m = median(d), max_m = max(d))
}

# Asigna a cada siniestro el barrio cuyo poligono lo contiene (NA si cae fuera de todos).
# Un punto sobre un limite compartido puede caer en 2 barrios: se conserva el primero.
asignar_barrio <- function(datos, barrios, epsg) {
  puntos <- datos |>
    mutate(id = row_number()) |>
    st_as_sf(coords = c("x", "y"), crs = epsg, remove = FALSE) |>
    st_transform(4326)
  unido <- st_join(puntos, barrios[, c("nrobarrio", "barrio")], join = st_intersects)
  unido <- unido[!duplicated(unido$id), ]
  lonlat <- st_coordinates(unido)
  unido |>
    st_drop_geometry() |>
    mutate(lon = lonlat[, 1], lat = lonlat[, 2]) |>
    select(-id)
}

# Clave de comparacion fecha|x|y, para cotejar contra la referencia fila a fila.
clave_fecha_xy <- function(fecha, x, y) {
  sort(paste(format(fecha), format(x, scientific = FALSE, trim = TRUE),
             format(y, scientific = FALSE, trim = TRUE), sep = "|"))
}

# ---- Panel diario -------------------------------------------------------------
# Conteo de siniestros por municipio y dia, con 0 en los dias sin siniestros.
contar_por_dia <- function(siniestros, fechas, municipios) {
  siniestros |>
    count(municipio, fecha, name = "n_siniestros") |>
    complete(municipio = municipios, fecha = fechas, fill = list(n_siniestros = 0L)) |>
    arrange(fecha, municipio)
}

# ---- SQL ----------------------------------------------------------------------
# Lee un archivo .sql con varias consultas separadas por lineas "-- name: <nombre>".
# Devuelve una lista nombrada de textos SQL.
leer_consultas <- function(ruta) {
  lineas <- readLines(ruta, encoding = "UTF-8")
  inicio <- grep("^-- name:", lineas)
  validar(length(inicio) > 0, paste("Consultas con nombre en", basename(ruta)))
  fin <- c(inicio[-1] - 1, length(lineas))
  consultas <- map2(inicio, fin, ~ paste(lineas[(.x + 1):.y], collapse = "\n"))
  set_names(consultas, trimws(sub("^-- name:", "", lineas[inicio])))
}
