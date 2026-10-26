# 05_clustering.R -- ¿hay perfiles de siniestralidad diferenciados entre barrios?
# k-means sobre el perfil de los 62 barrios (proporciones calculadas en SQL, script 02).
# Entrada : data/processed/perfil_barrios.csv, data/raw/barrios_montevideo.geojson (mapa)
# Salida  : outputs/tablas/clu_*.csv, outputs/figuras/clu_*.png
source(here::here("scripts", "00_setup.R"))

perfil <- read_csv(f_perfil, show_col_types = FALSE)
vars <- c("p_colision", "p_despiste", "p_atropello", "p_caida", "p_grave_fatal",
          "p_nocturno", "p_finde")
etiquetas <- c(p_colision = "Colisión entre vehículos", p_despiste = "Despiste",
               p_atropello = "Atropello de peatón", p_caida = "Caída",
               p_grave_fatal = "Grave o fatal", p_nocturno = "Nocturno (22–5 h)",
               p_finde = "Fin de semana")

validar(nrow(perfil) == 62 && !anyNA(perfil[vars]), "Perfil: 62 barrios sin faltantes")
validar(all(perfil[vars] >= 0 & perfil[vars] <= 1), "Perfil: proporciones entre 0 y 1")

# ---- 1. Estandarizacion -------------------------------------------------------
# Todas son proporciones, pero sus desvios son muy distintos: sin estandarizar, la
# distancia euclidea quedaria dominada por p_colision y casi ignoraria p_nocturno.
desvios <- map_dbl(perfil[vars], sd)
Z <- scale(as.matrix(perfil[vars]))
rownames(Z) <- perfil$barrio
distancias <- dist(Z)

# ---- 2. Eleccion de k: codo y silueta (automatizado con map) -------------------
barrido <- map(2:8, ~ resumir_kmeans(Z, .x, semilla, distancias)) |> list_rbind()
guardar_tabla(select(barrido, -modelo), "clu_barrido_k")
k_elegido <- barrido$k[which.max(barrido$silueta)]   # maxima silueta promedio

# WSS de k = 1 (variacion total) como referencia para el codo
wss <- bind_rows(tibble(k = 1, WSS = sum(scale(Z, scale = FALSE)^2)), select(barrido, k, WSS))
p_codo <- ggplot(wss, aes(k, WSS)) +
  geom_line(colour = "grey55") + geom_point(size = 2, colour = col_punto) +
  geom_point(data = filter(wss, k == k_elegido), size = 4, shape = 21, colour = col_linea,
             stroke = 1.2) +
  scale_x_continuous(breaks = 1:8) +
  labs(x = "Número de grupos (k)", y = "WSS", title = "Método del codo")
p_sil <- ggplot(barrido, aes(k, silueta)) +
  geom_hline(yintercept = 0.25, colour = "grey60", linetype = "dashed") +
  geom_line(colour = "grey55") + geom_point(size = 2, colour = col_punto) +
  geom_point(data = filter(barrido, k == k_elegido), size = 4, shape = 21, colour = col_linea,
             stroke = 1.2) +
  scale_x_continuous(breaks = 2:8) +
  labs(x = "Número de grupos (k)", y = "Silueta promedio", title = "Silueta",
       subtitle = "Punteada: 0,25 (por debajo, estructura débil)")
guardar_figura(p_codo + p_sil, "clu_01_eleccion_k", 9.5, 3.8)

# ---- 3. Modelo final y estabilidad -------------------------------------------
km <- barrido$modelo[[which(barrido$k == k_elegido)]]
# Estabilidad frente a la semilla: 30 corridas, Rand ajustado contra la particion elegida
estabilidad <- map_dbl(1:30, function(s) {
  set.seed(s)
  rand_ajustado(km$cluster, kmeans(Z, k_elegido, nstart = 25, iter.max = 100)$cluster)
})
silueta_barrio <- silhouette(km$cluster, distancias)[, "sil_width"]

# Grupos numerados por tamaño decreciente (las etiquetas de kmeans son arbitrarias)
orden <- order(km$size, decreasing = TRUE)
perfil <- perfil |>
  mutate(grupo = factor(match(km$cluster, orden)), silueta = silueta_barrio)
guardar_tabla(tibble(k = k_elegido, semillas = length(estabilidad),
                     rand_ajustado_min = min(estabilidad),
                     silueta_media = mean(silueta_barrio),
                     barrios_silueta_negativa = sum(silueta_barrio < 0)),
              "clu_estabilidad")

# ---- 4. Caracterizacion -------------------------------------------------------
medias <- perfil |>
  group_by(grupo) |>
  summarise(barrios = n(), across(all_of(vars), mean), .groups = "drop")
guardar_tabla(medias, "clu_medias_por_grupo")

# Descriptores que NO entraron al agrupamiento: volumen, densidad, avenidas, municipio
externas <- perfil |>
  group_by(grupo) |>
  summarise(barrios = n(), siniestros_mediana = median(n), densidad_mediana = median(densidad),
            area_mediana_km2 = median(area_km2), p_avenida_media = mean(p_avenida),
            .groups = "drop")
pruebas <- map(c(siniestros = "n", densidad = "densidad", avenida = "p_avenida"),
               ~ kruskal.test(perfil[[.x]], perfil$grupo)$p.value)
set.seed(semilla)
tabla_mun <- table(perfil$grupo, sub("MUNICIPIO ", "", perfil$municipio_dom))
pruebas$municipio <- fisher.test(tabla_mun, simulate.p.value = TRUE, B = 20000)$p.value
guardar_tabla(externas, "clu_externas_por_grupo")
guardar_tabla(tibble(variable = names(pruebas), p_valor = unlist(pruebas)), "clu_pruebas_externas")
guardar_tabla(as_tibble(as.data.frame.matrix(tabla_mun), rownames = "grupo"), "clu_grupo_x_municipio")
guardar_tabla(perfil |> arrange(grupo, barrio) |>
                select(grupo, barrio, n, all_of(vars), densidad, municipio_dom, p_avenida, silueta),
              "clu_barrios_por_grupo")

# ---- 5. Visualizaciones -------------------------------------------------------
# Centroides en escala estandarizada: cuantos desvios se aleja cada grupo de la media
centroides <- as_tibble(Z) |>
  mutate(grupo = perfil$grupo) |>
  group_by(grupo) |>
  summarise(across(all_of(vars), mean), barrios = n(), .groups = "drop") |>
  pivot_longer(all_of(vars), names_to = "variable", values_to = "z") |>
  mutate(variable = factor(etiquetas[variable], levels = rev(etiquetas)),
         grupo = paste0("Grupo ", grupo, " (", barrios, " barrios)"))
p_centr <- ggplot(centroides, aes(z, variable, fill = z > 0)) +
  geom_col(width = 0.65) +
  geom_vline(xintercept = 0, colour = "grey40") +
  facet_wrap(~grupo) +
  scale_fill_manual(values = c(`TRUE` = paleta[2], `FALSE` = paleta[1]), guide = "none") +
  labs(x = "Media del grupo (desvíos respecto de la media de los 62 barrios)", y = NULL)
guardar_figura(p_centr, "clu_02_perfil_grupos", 9, 4)

mapa <- leer_barrios(f_barrios, epsg_utm) |>
  left_join(select(perfil, barrio, grupo), by = "barrio")
p_mapa <- ggplot(mapa) +
  geom_sf(aes(fill = grupo), colour = "white", linewidth = 0.25) +
  scale_fill_manual(values = paleta, name = "Grupo") +
  theme_void()
guardar_figura(p_mapa, "clu_03_mapa", 7.5, 5.5)

guardar_validaciones("05_clustering")
