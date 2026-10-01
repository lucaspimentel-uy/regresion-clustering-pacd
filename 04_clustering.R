# 04_clustering.R -- Paso 2: perfiles de siniestralidad de los 62 barrios (k-means)
source("00_setup.R")

col_cl <- c("#0072B2", "#E69F00", "#009E73", "#CC79A7", "#D55E00", "#56B4E9")  # Okabe-Ito
# Guarda un grafico en outputs/figuras con tamaño y resolucion fijos
guardar <- function(p, nombre, w = 7.5, h = 4.5) {
  ggsave(file.path(dir_fig, nombre), p, width = w, height = h, dpi = 150, bg = "white")
}

# ---- 1. Perfil de cada barrio -------------------------------------------------
# Siniestros individuales con su barrio (salida de 02_siniestros_barrio.R)
sin <- readRDS(file.path(dir_proc, "siniestros_barrio.rds"))

# Categorias de Tipo de Siniestro con menos de 3 % del total -> OTROS (frecuencias
# vistas en 02_siniestros_barrio.R). Los tipos faltantes (10 casos) tambien van a OTROS.
sh   <- prop.table(table(sin$tipo))     # proporcion de cada tipo
keep <- names(sh)[sh >= 0.03]           # tipos que se conservan
stopifnot(setequal(keep, c("COLISIÓN ENTRE VEHÍCULOS", "DESPISTE", "ATROPELLO DE PEATÓN", "CAÍDA")))
sin$tipo_ag <- ifelse(is.na(sin$tipo) | !(sin$tipo %in% keep), "OTROS", sin$tipo)
cat("Tipo agrupado:\n"); print(table(sin$tipo_ag))

# Variables del clustering: proporciones sobre TODOS los siniestros del barrio.
# "OTROS" queda afuera para que las 4 proporciones de tipo no sumen exactamente 1.
vars <- c("p_colision", "p_despiste", "p_atropello_peaton", "p_caida",
          "p_grave_fatal", "p_nocturno", "p_finde")
# Nombres legibles para graficos y tablas
etiq <- c(p_colision = "Colisión entre vehículos", p_despiste = "Despiste",
          p_atropello_peaton = "Atropello de peatón", p_caida = "Caída",
          p_grave_fatal = "Grave o fatal", p_nocturno = "Nocturno (22–5 h)",
          p_finde = "Fin de semana")
# Una fila por barrio. mean() de una condicion logica = proporcion de siniestros que la cumplen.
perfil <- sin |>
  group_by(barrio) |>
  summarise(n = n(),
            p_colision = mean(tipo_ag == "COLISIÓN ENTRE VEHÍCULOS"),
            p_despiste = mean(tipo_ag == "DESPISTE"),
            p_atropello_peaton = mean(tipo_ag == "ATROPELLO DE PEATÓN"),
            p_caida = mean(tipo_ag == "CAÍDA"),
            p_grave_fatal = mean(gravedad %in% c("GRAVE", "FATAL")),
            n_grave_fatal = sum(gravedad %in% c("GRAVE", "FATAL")),
            p_nocturno = mean(nocturno),
            p_finde = mean(finde),
            # externas (NO entran al clustering)
            # municipio mas frecuente del barrio y que fraccion de sus siniestros cae en el
            municipio_dom = names(which.max(table(municipio))),
            pct_mun_dom = max(table(municipio)) / n(),
            # descriptor extra: peso de avenidas/boulevares/rambla segun el nombre de calle
            p_avenida = mean(grepl("^(AVENIDA|BOULEVARD|BULEVAR|RAMBLA)", calle[!is.na(calle)])),
            .groups = "drop")
stopifnot(nrow(perfil) == 62)

# Densidad = siniestros por km2 (area de los poligonos en UTM 21S)
barrios <- st_read(f_barrios, quiet = TRUE) |> st_make_valid() |> st_transform(4326)
stopifnot(setequal(barrios$barrio, perfil$barrio))   # mismos 62 barrios en ambas fuentes
# El area se calcula en UTM (metros) y se pasa de m2 a km2
barrios$area_km2 <- as.numeric(st_area(st_transform(barrios, 32721))) / 1e6
perfil <- perfil |>
  left_join(st_drop_geometry(barrios)[, c("barrio", "area_km2")], by = "barrio") |>
  mutate(densidad = n / area_km2)

# ---- 2. Revision de faltantes, distribuciones y extremos -----------------------
cat("\nFaltantes en las variables del perfil:", sum(is.na(perfil[vars])), "\n")
# Minimo, cuartiles, media, maximo y desvio de cada variable
cat("\nResumen de las variables del perfil (proporciones):\n")
print(round(t(sapply(perfil[vars], function(v)
  c(min = min(v), q1 = unname(quantile(v, .25)), mediana = median(v), media = mean(v),
    q3 = unname(quantile(v, .75)), max = max(v), sd = sd(v)))), 3))
# Variables muy correlacionadas aportarian informacion repetida a la distancia
cat("\nCorrelaciones entre variables:\n"); print(round(cor(perfil[vars]), 2))
# Con pocos graves/fatales por barrio, p_grave_fatal es una proporcion inestable
cat("\nSiniestros graves/fatales por barrio: min =", min(perfil$n_grave_fatal),
    "| mediana =", median(perfil$n_grave_fatal), "| max =", max(perfil$n_grave_fatal), "\n")

# Formato largo (una fila por barrio x variable) para graficar todo con facet_wrap
larga <- perfil |> select(barrio, all_of(vars)) |>
  pivot_longer(-barrio, names_to = "variable", values_to = "valor") |>
  mutate(variable = factor(etiq[variable], levels = etiq))
p_h <- ggplot(larga, aes(valor)) +
  geom_histogram(bins = 14, fill = "#2C6E91", colour = "white") +
  scale_x_continuous(labels = label_percent(accuracy = 1)) +
  facet_wrap(~variable, scales = "free", ncol = 4) +
  labs(x = "Proporción de los siniestros del barrio", y = "Barrios")
guardar(p_h, "clu_01_histogramas.png", 10, 5)

# Barrios extremos: puntaje z (cuantos desvios se alejan de la media) mayor a 2,5 en valor absoluto
zl <- larga |> group_by(variable) |> mutate(z = (valor - mean(valor)) / sd(valor)) |> ungroup()
cat("\nExtremos (|z| > 2,5):\n")
print(as.data.frame(zl |> filter(abs(z) > 2.5) |> arrange(variable, desc(abs(z))) |>
                      mutate(valor = round(valor, 3), z = round(z, 2))), row.names = FALSE)

# ---- 3. Estandarizacion z-score ------------------------------------------------
# Aunque todas son proporciones, sus desvios son muy distintos (ver abajo): sin
# estandarizar, la distancia euclidea quedaria dominada por p_colision (sd ~ 0,07)
# y casi ignoraria p_nocturno (sd ~ 0,02). Con z-score cada variable pesa igual.
cat("\nDesvios antes de estandarizar:\n"); print(round(sapply(perfil[vars], sd), 4))
Z <- scale(as.matrix(perfil[vars])); rownames(Z) <- perfil$barrio   # media 0 y sd 1 por columna
d <- dist(Z)    # matriz de distancias euclideas entre barrios (se usa en la silueta)

# ---- 4. k-means, k = 2..10; codo y silueta -------------------------------------
# Para cada k: kmeans con 25 inicios aleatorios (se queda con el mejor), su WSS
# (suma de cuadrados intra-grupo) y su silueta promedio
ks <- 2:10
barrido <- lapply(ks, function(k) {
  set.seed(2024)
  km <- kmeans(Z, centers = k, nstart = 25, iter.max = 100)
  list(km = km, wss = km$tot.withinss, sil = mean(silhouette(km$cluster, d)[, 3]))
})
# Resumen por k, con los tamaños de los grupos de mayor a menor
tab_k <- data.frame(k = ks, WSS = sapply(barrido, `[[`, "wss"),
                    silueta = sapply(barrido, `[[`, "sil"),
                    tamanos = sapply(barrido, function(b)
                      paste(sort(b$km$size, decreasing = TRUE), collapse = "/")))
cat("\n== Barrido de k ==\n"); print(transform(tab_k, WSS = round(WSS, 1), silueta = round(silueta, 3)),
                                    row.names = FALSE)
write.csv(tab_k, file.path(dir_tab, "clu_barrido_k.csv"), row.names = FALSE)

# WSS(k = 1) es la suma de cuadrados total: (n - 1) * p, porque cada variable tiene
# varianza 1. Se incluye como punto de referencia del codo.
wss1 <- sum(scale(Z, scale = FALSE)^2)
wss_plot <- rbind(data.frame(k = 1, WSS = wss1), tab_k[, c("k", "WSS")])
cat("WSS(k=1) =", round(wss1, 1), "| caidas sucesivas:",
    paste(round(-diff(wss_plot$WSS), 1), collapse = " "), "\n")

# k elegido (se resalta en rojo en ambos graficos)
k_elegido <- 2
p_codo <- ggplot(wss_plot, aes(k, WSS)) +
  geom_line(colour = "grey50") + geom_point(size = 2, colour = "#2C6E91") +
  geom_point(data = subset(wss_plot, k == k_elegido), size = 4, shape = 21,
             colour = "#C0392B", stroke = 1.2) +
  scale_x_continuous(breaks = 1:10) +
  labs(x = "Número de grupos (k)", y = "Suma de cuadrados intra-grupo (WSS)", title = "Método del codo")
p_sil <- ggplot(tab_k, aes(k, silueta)) +
  geom_hline(yintercept = 0.25, linetype = "dashed", colour = "grey60") +
  geom_line(colour = "grey50") + geom_point(size = 2, colour = "#2C6E91") +
  geom_point(data = subset(tab_k, k == k_elegido), size = 4, shape = 21,
             colour = "#C0392B", stroke = 1.2) +
  scale_x_continuous(breaks = ks) +
  labs(x = "Número de grupos (k)", y = "Silueta promedio", title = "Silueta promedio",
       subtitle = "Línea punteada: 0,25 (por debajo, sin estructura sustancial)")
guardar(p_codo + p_sil, "clu_02_codo_silueta.png", 10, 4.2)

# Estabilidad del k elegido frente a la semilla: 30 semillas, nstart = 25
km_ref <- barrido[[which(ks == k_elegido)]]$km     # particion de referencia
# Indice de Rand ajustado entre dos particiones: 1 = identicas, ~0 = como al azar.
# Se cuentan pares de barrios: s = juntos en ambas; sa, sb = juntos en cada una; e = esperado por azar
rand_aj <- function(a, b) {
  t <- table(a, b); n <- sum(t); c2 <- function(x) x * (x - 1) / 2
  s <- sum(c2(t)); sa <- sum(c2(rowSums(t))); sb <- sum(c2(colSums(t)))
  e <- sa * sb / c2(n); (s - e) / ((sa + sb) / 2 - e)
}
# Repite el k-means con 30 semillas: si WSS casi no varia y el indice es ~1, la solucion es estable
est <- sapply(1:30, function(s) {
  set.seed(s); km <- kmeans(Z, k_elegido, nstart = 25, iter.max = 100)
  c(wss = km$tot.withinss, ari = rand_aj(km_ref$cluster, km$cluster))
})
cat("\nEstabilidad k =", k_elegido, "(30 semillas): WSS min/max =",
    paste(round(range(est["wss", ]), 2), collapse = " / "),
    "| Rand ajustado vs particion de referencia, min =", round(min(est["ari", ]), 3), "\n")

# Silueta por barrio del k elegido (negativa = el barrio queda mas cerca del otro grupo)
sil <- silhouette(km_ref$cluster, d)
cat("Barrios con silueta negativa:", sum(sil[, 3] < 0), "de", nrow(Z), "\n")

# ---- 5. Caracterizacion --------------------------------------------------------
# Grupos numerados por tamano decreciente (las etiquetas de kmeans son arbitrarias)
orden <- order(km_ref$size, decreasing = TRUE)
perfil$grupo <- factor(match(km_ref$cluster, orden))
perfil$sil <- sil[, 3]
cat("\nTamano de cada grupo:\n"); print(table(perfil$grupo))

# Media de cada variable por grupo, en la escala original (proporciones) para poder interpretarlas
medias <- perfil |> group_by(grupo) |>
  summarise(barrios = n(), across(all_of(vars), mean), .groups = "drop")
cat("\n== Medias por grupo (escala original, proporciones) ==\n")
print(medias |> mutate(across(all_of(vars), ~ round(.x, 3))), width = 200)
cat("Media general:\n"); print(round(colMeans(perfil[vars]), 3))
write.csv(medias, file.path(dir_tab, "clu_medias_por_grupo.csv"), row.names = FALSE)

# Lista de barrios de cada grupo, y tabla completa barrio por barrio
cat("\n== Barrios por grupo ==\n")
for (g in levels(perfil$grupo)) {
  cat("\nGrupo", g, "(", sum(perfil$grupo == g), "barrios ):\n")
  cat(paste(sort(perfil$barrio[perfil$grupo == g]), collapse = ", "), "\n")
}
write.csv(perfil |> arrange(grupo, barrio) |>
            select(grupo, barrio, n, all_of(vars), n_grave_fatal, municipio_dom, pct_mun_dom,
                   p_avenida, area_km2, densidad, sil),
          file.path(dir_tab, "clu_barrios_por_grupo.csv"), row.names = FALSE)

# ---- 6. Interpretacion cruzada -------------------------------------------------
# ¿Los grupos coinciden con los municipios? Tabla cruzada y test exacto de Fisher
# (p-valor simulado porque la tabla es grande para el calculo exacto)
cat("\n== Grupo x municipio dominante ==\n")
tab_mun <- table(Grupo = perfil$grupo, Municipio = sub("MUNICIPIO ", "", perfil$municipio_dom))
print(tab_mun)
set.seed(2024)
cat("Fisher (p simulado):", signif(fisher.test(tab_mun, simulate.p.value = TRUE, B = 20000)$p.value, 3), "\n")
# Pureza: si es alta, cada barrio pertenece casi por completo a un solo municipio
cat("Pureza del municipio dominante (mediana de % de siniestros del barrio en su municipio):",
    round(100 * median(perfil$pct_mun_dom), 1), "%\n")
write.csv(as.data.frame.matrix(tab_mun), file.path(dir_tab, "clu_grupo_x_municipio.csv"))

# Variables externas (no usadas para agrupar) resumidas por grupo: volumen, densidad y avenidas
ext <- perfil |> group_by(grupo) |>
  summarise(barrios = n(),
            total_mediana = median(n), total_media = mean(n),
            densidad_mediana = median(densidad), densidad_q1 = quantile(densidad, .25),
            densidad_q3 = quantile(densidad, .75), area_mediana_km2 = median(area_km2),
            p_avenida_media = mean(p_avenida), .groups = "drop")
cat("\n== Volumen, densidad y avenidas por grupo ==\n"); print(as.data.frame(ext |> mutate(across(-grupo, ~ round(.x, 2)))))
write.csv(ext, file.path(dir_tab, "clu_externas_por_grupo.csv"), row.names = FALSE)
# Kruskal-Wallis: ¿difieren las variables externas entre grupos? (no parametrico)
cat("\nKruskal-Wallis por grupo -> total:", signif(kruskal.test(n ~ grupo, perfil)$p.value, 3),
    "| densidad:", signif(kruskal.test(densidad ~ grupo, perfil)$p.value, 3),
    "| p_avenida:", signif(kruskal.test(p_avenida ~ grupo, perfil)$p.value, 3), "\n")
cat("Correlacion de Spearman (62 barrios): densidad vs p_avenida =",
    round(cor(perfil$densidad, perfil$p_avenida, method = "spearman"), 2),
    "| total vs densidad =", round(cor(perfil$n, perfil$densidad, method = "spearman"), 2), "\n")

# Sensibilidad: que pasa con k = 3 y 4 respecto de k = 2 (solo cruce de particiones)
for (k in 3:4) {
  cat("\nk =", k, "vs k =", k_elegido, "(filas: grupo elegido; columnas: grupos de k =", k, "):\n")
  print(table(elegido = perfil$grupo, alternativo = barrido[[which(ks == k)]]$km$cluster))
}

# ---- 7. Visualizaciones --------------------------------------------------------
# 7a. PCA a 2 componentes
# Z ya esta centrada y escalada, por eso no se vuelve a centrar ni escalar.
# ve = % de varianza explicada por cada componente.
pca <- prcomp(Z, center = FALSE, scale. = FALSE)
ve <- 100 * pca$sdev^2 / sum(pca$sdev^2)
cat("\nVarianza explicada por PC1, PC2:", round(ve[1:2], 1), "(acum.", round(sum(ve[1:2]), 1), "%)\n")
cat("Cargas (PC1, PC2):\n"); print(round(pca$rotation[, 1:2], 2))
# Coordenadas de cada barrio en PC1-PC2 y su distancia al origen (para rotular los extremos)
sc <- data.frame(barrio = perfil$barrio, grupo = perfil$grupo, PC1 = pca$x[, 1], PC2 = pca$x[, 2])
sc$dist_origen <- sqrt(sc$PC1^2 + sc$PC2^2)
etiquetar <- sc$barrio %in% sc$barrio[order(-sc$dist_origen)][1:10]   # los 10 mas extremos
# Flechas de las variables: se escalan (esc) para que entren en la nube de barrios
carg <- data.frame(var = etiq[vars], pca$rotation[, 1:2])
esc <- 0.8 * min(max(abs(sc$PC1)) / max(abs(carg$PC1)), max(abs(sc$PC2)) / max(abs(carg$PC2)))
p_pca <- ggplot(sc, aes(PC1, PC2, colour = grupo)) +
  geom_hline(yintercept = 0, colour = "grey85") + geom_vline(xintercept = 0, colour = "grey85") +
  geom_segment(data = carg, aes(x = 0, y = 0, xend = PC1 * esc, yend = PC2 * esc),
               inherit.aes = FALSE, colour = "grey60", arrow = arrow(length = unit(0.12, "cm"))) +
  geom_text_repel(data = carg, aes(PC1 * esc, PC2 * esc, label = var),
                  inherit.aes = FALSE, colour = "grey35", size = 3, fontface = "italic",
                  box.padding = 0.5, point.padding = 0.3, min.segment.length = Inf,
                  max.overlaps = Inf, seed = 2024) +
  geom_point(size = 2.4) +
  geom_text_repel(data = sc[etiquetar, ], aes(label = barrio), size = 3, show.legend = FALSE,
                  max.overlaps = Inf, min.segment.length = 0.2,
                  nudge_x = ifelse(sc$barrio[etiquetar] == "CENTRO", 0.9, 0)) +
  scale_colour_manual(values = col_cl, name = "Grupo") +
  labs(x = sprintf("PC1 (%.1f %% de la varianza)", ve[1]),
       y = sprintf("PC2 (%.1f %% de la varianza)", ve[2]),
       subtitle = "Flechas: peso de cada variable. Se rotulan los 10 barrios más alejados del centro")
guardar(p_pca, "clu_03_pca.png", 9, 6.5)

# 7b. Boxplots de cada variable por grupo (escala original)
lg <- perfil |> select(barrio, grupo, all_of(vars)) |>
  pivot_longer(all_of(vars), names_to = "variable", values_to = "valor") |>
  mutate(variable = factor(etiq[variable], levels = etiq))
p_box <- ggplot(lg, aes(grupo, valor, fill = grupo)) +
  geom_boxplot(outlier.size = 1, alpha = 0.85, colour = "grey30") +
  scale_fill_manual(values = col_cl, guide = "none") +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  facet_wrap(~variable, scales = "free_y", ncol = 4) +
  labs(x = "Grupo", y = "Proporción de los siniestros del barrio")
guardar(p_box, "clu_04_boxplots.png", 10, 5.5)

# 7c. Mapa coropletico de los 62 barrios
# Une los poligonos con el grupo de cada barrio y los colorea por grupo
mapa <- barrios |> left_join(perfil[, c("barrio", "grupo")], by = "barrio")
p_map <- ggplot(mapa) +
  geom_sf(aes(fill = grupo), colour = "white", linewidth = 0.25) +
  scale_fill_manual(values = col_cl, name = "Grupo") +
  theme_void() + theme(legend.position = "right")
guardar(p_map, "clu_05_mapa.png", 8, 6.5)

# Guarda el perfil con el grupo asignado (lo usan los scripts siguientes)
saveRDS(perfil, file.path(dir_proc, "perfil_barrios_grupos.rds"))
cat("\nListo.\n")
