# 02_siniestros_barrio.R -- Paso 0.c: siniestros individuales de Montevideo + barrio
# Salida: data/processed/siniestros_barrio.rds
source("00_setup.R")

# ---- 1. Lectura (quote = "": ver 01_fechas.R) ---------------------------------
raw <- read.csv(f_unificado, colClasses = "character", strip.white = TRUE,
                quote = "", comment.char = "")
cat("Filas leidas:", nrow(raw), "\n")
raw$fecha <- as.Date(raw$Fecha, format = "%m/%d/%Y")
stopifnot(!anyNA(raw$fecha))   # todas las fechas deben parsear

# ---- 2. Montevideo y ventana --------------------------------------------------
# Se queda con Montevideo y con la ventana de analisis definida en 00_setup.R
m <- raw |>
  filter(Departamento == "MONTEVIDEO", fecha >= fecha_ini, fecha <= fecha_fin)
cat("Montevideo", format(fecha_ini), "/", format(fecha_fin), ":", nrow(m), "filas\n")

# ---- 3. Duplicados exactos ----------------------------------------------------
# 90 filas repiten los 11 campos originales (fecha, calle, tipo, gravedad, hora,
# coordenadas, etc.). Se conserva una. Con esto el total baja de 36.713 a 36.623;
# las 11 restantes hasta 36.612 son las que quedan sin barrio en el join (seccion 7).
cols_orig <- c("Fecha", "Calle", "Tipo.de.Siniestro", "Gravedad", "Dia.Semana",
               "Hora", "Departamento", "Localidad", "fixed", "X", "Y")
n_dup <- sum(duplicated(m[, cols_orig]))      # cuenta las repeticiones (sin contar la 1ra aparicion)
m <- m[!duplicated(m[, cols_orig]), ]         # conserva la primera de cada grupo
cat("Duplicados exactos eliminados:", n_dup, "-> quedan", nrow(m), "\n")

# ---- 4. Faltantes escritos como texto -> NA -----------------------------------
# Antes de recodificar, verificar que no queden variantes sin cubrir.
faltantes_txt <- c("NO SE INGRESO", "SIN DATOS")
chr_cols <- c("Calle", "Tipo.de.Siniestro", "Gravedad", "Dia.Semana", "Localidad")
cat("\nValores tipo 'faltante' por columna (antes de recodificar):\n")
for (cl in chr_cols) {
  v <- m[[cl]]
  # Busca cualquier texto que parezca un faltante (vacio, SIN DATO, N/A, NULL, etc.)
  hit <- v[grepl("SIN DATO|NO SE ING|^$|DESCONOC|^S/D|^N/A$|^NULL$", v, ignore.case = TRUE)]
  cat(sprintf("  %-18s %s\n", cl,
              if (length(hit)) paste(names(table(hit)), table(hit), sep = "=", collapse = " | ")
              else "(ninguno)"))
}
# Recodifica los dos textos de faltante como NA verdadero
m[chr_cols] <- lapply(m[chr_cols], function(v) { v[v %in% faltantes_txt] <- NA; v })

# ---- 5. Hora valida (0-23) y derivadas ----------------------------------------
m$hora <- suppressWarnings(as.integer(m$Hora))     # texto no numerico -> NA (sin warning)
n_hora_mal <- sum(is.na(m$hora) | m$hora < 0 | m$hora > 23)
m$hora[!is.na(m$hora) & (m$hora < 0 | m$hora > 23)] <- NA   # horas imposibles -> NA
cat("\nHora fuera de 0-23 o no numerica:", n_hora_mal, "\n")

# nocturno: entre las 22 y las 5 h (NA si no hay hora). finde: sabado o domingo.
m$nocturno <- !is.na(m$hora) & (m$hora >= 22 | m$hora <= 5)
m$nocturno[is.na(m$hora)] <- NA
m$finde <- as.integer(format(m$fecha, "%u")) >= 6          # sabado y domingo
m$x <- as.numeric(m$X); m$y <- as.numeric(m$Y)             # coordenadas a numerico

# ---- 6. Frecuencias de categorias (ANTES de agrupar nada) ---------------------
# Tabla ordenada de mayor a menor con cantidad y porcentaje (incluye los NA)
frec <- function(v) {
  t <- sort(table(v, useNA = "ifany"), decreasing = TRUE)
  data.frame(categoria = ifelse(is.na(names(t)), "<NA>", names(t)),
             n = as.integer(t), pct = round(100 * as.numeric(t) / length(v), 2))
}
f_tipo <- frec(m$Tipo.de.Siniestro)
f_grav <- frec(m$Gravedad)
cat("\n== Tipo de Siniestro (n =", nrow(m), ") ==\n"); print(f_tipo, row.names = FALSE)
cat("\n== Gravedad ==\n"); print(f_grav, row.names = FALSE)
write.csv(f_tipo, file.path(dir_tab, "frecuencias_tipo_siniestro.csv"), row.names = FALSE)
write.csv(f_grav, file.path(dir_tab, "frecuencias_gravedad.csv"), row.names = FALSE)

# ---- 7. EPSG: determinacion empirica ------------------------------------------
# `siniestros_montevideo.csv` trae coord_x/coord_y (UTM 21S) y latitud/longitud del
# MISMO punto. Se transforma coord_x/coord_y bajo cada candidato a lon/lat y se mide
# la distancia (m) contra la lat/lon conocida. Se incluye 32720 (UTM 20S) como
# control negativo para mostrar que la prueba discrimina.
ref <- read.csv(f_sin_mvd)
ref_ll <- st_as_sf(ref, coords = c("longitud", "latitud"), crs = 4326)   # puntos de referencia en lon/lat
# Error de un EPSG candidato: pasa coord_x/coord_y a lon/lat y mide la distancia (m) al punto de referencia
err_epsg <- function(epsg) {
  p <- st_as_sf(ref, coords = c("coord_x", "coord_y"), crs = epsg) |> st_transform(4326)
  d <- as.numeric(st_distance(st_geometry(p), st_geometry(ref_ll), by_element = TRUE))
  c(mediana_m = median(d), p99_m = unname(quantile(d, 0.99)), max_m = max(d))
}
cand <- c("32721 WGS84/UTM21S" = 32721, "31981 SIRGAS2000/UTM21S" = 31981,
          "32720 UTM20S (control)" = 32720)
tab_epsg <- t(sapply(cand, err_epsg))
cat("\nError (metros) de coord_x/coord_y -> lat/lon vs lat/lon conocida, n =", nrow(ref), "\n")
print(signif(tab_epsg, 3))
# Resultado (ver informe): 32721 y 31981 reproducen la lat/lon con error < 1 m (el
# redondeo a 6 decimales de la lat/lon equivale a ~0,1 m); ambos CRS comparten
# proyeccion UTM 21S y difieren solo en el datum (WGS84 vs SIRGAS 2000, practicamente
# coincidentes), asi que el test NO puede separarlos. El control 32720 da errores de
# cientos de km. Se adopta 32721 (WGS84): es el mismo datum de la lat/lon de la referencia.
epsg_utm <- 32721

# ---- 8. Asignar barrio --------------------------------------------------------
# Lee los poligonos y los deja en lon/lat (4326) con geometrias validas
barrios <- st_read(f_barrios, quiet = TRUE)
cat("\nBarrios:", nrow(barrios), "| CRS:", st_crs(barrios)$input,
    "| geometrias invalidas:", sum(!st_is_valid(barrios)), "\n")
if (is.na(st_crs(barrios))) st_crs(barrios) <- 4326     # si no trae CRS, se asume lon/lat
barrios <- st_transform(barrios, 4326)
if (any(!st_is_valid(barrios))) barrios <- st_make_valid(barrios)

# Convierte cada siniestro en un punto (coordenadas UTM) y lo pasa a lon/lat;
# st_join le asigna el barrio cuyo poligono lo contiene
m$id <- seq_len(nrow(m))
pts <- st_as_sf(m, coords = c("x", "y"), crs = epsg_utm, remove = FALSE) |>
  st_transform(4326)
j <- st_join(pts, barrios[, c("nrobarrio", "barrio", "codba")], join = st_intersects)
# Un punto sobre un limite compartido puede quedar en 2 barrios: se conserva el primero
n_multi <- sum(duplicated(j$id))
j <- j[!duplicated(j$id), ]
stopifnot(nrow(j) == nrow(m))   # una fila por siniestro
cat("Puntos en el limite de 2 barrios (duplicados por el join):", n_multi, "\n")

# Puntos que no cayeron en ningun poligono
sin_barrio <- is.na(j$barrio)
cat("\nSin barrio asignado:", sum(sin_barrio), sprintf("(%.2f %%)", 100 * mean(sin_barrio)), "\n")
if (any(sin_barrio)) {
  cat("Coordenadas de los puntos sin barrio:\n")
  print(table(paste(j$x[sin_barrio], j$y[sin_barrio])))
}

# ---- 9. Municipio (para caracterizar clusters en el Paso 2) -------------------
# El unificado no trae municipio; `siniestros_montevideo.csv` si (zona_id), por
# coordenada. Se valida que zona_id sea funcion de (coord_x, coord_y).
ref$xy <- paste(ref$coord_x, ref$coord_y)    # clave de coordenada (x y como texto)
chk <- tapply(ref$zona_id, ref$xy, function(z) length(unique(z)))
cat("\nCoordenadas con mas de un municipio en la referencia:", sum(chk > 1), "\n")
mun <- ref[!duplicated(ref$xy), c("xy", "zona_id")]            # una fila por coordenada
j$municipio <- mun$zona_id[match(paste(j$x, j$y), mun$xy)]     # cruce por coordenada
cat("Siniestros sin municipio por coordenada:", sum(is.na(j$municipio)), "\n")

# ---- 10. Control de calidad ---------------------------------------------------
# Referencia del curso (36.612 siniestros): 0 % sin barrio, 62 barrios, min 206
# (La Blanqueada), max 1.804 (Union), mediana 531.
ok <- j[!sin_barrio, ]
por_barrio <- ok |> st_drop_geometry() |> count(barrio, name = "n") |> arrange(n)
cat("\n== Control de calidad (siniestros con barrio:", nrow(ok), ") ==\n")
cat("Barrios con datos:", nrow(por_barrio), "\n")
cat("Minimo:", por_barrio$n[1], "(", por_barrio$barrio[1], ")\n")
cat("Maximo:", por_barrio$n[nrow(por_barrio)], "(", por_barrio$barrio[nrow(por_barrio)], ")\n")
cat("Mediana:", median(por_barrio$n), "\n")
write.csv(por_barrio, file.path(dir_tab, "siniestros_por_barrio.csv"), row.names = FALSE)

# ---- 11. Guardar --------------------------------------------------------------
# Se excluyen los puntos sin barrio (caen fuera de los 62 barrios; no pueden entrar
# al perfil de ninguno). Las categorias NO se agrupan aqui: el corte del 3 % a
# "OTROS" se aplica en 04_clustering.R despues de ver las frecuencias.
ll <- st_coordinates(ok)    # lon/lat de cada punto, para guardarlas como columnas
out <- ok |>
  st_drop_geometry() |>
  transmute(fecha, hora, dia_semana = Dia.Semana, calle = Calle,
            tipo = Tipo.de.Siniestro, gravedad = Gravedad, localidad = Localidad,
            nocturno, finde, x, y, lon = ll[, 1], lat = ll[, 2],
            nrobarrio, barrio, codba, municipio)
saveRDS(out, file.path(dir_proc, "siniestros_barrio.rds"))
cat("\nGuardado:", file.path(dir_proc, "siniestros_barrio.rds"), "-", nrow(out), "filas\n")
