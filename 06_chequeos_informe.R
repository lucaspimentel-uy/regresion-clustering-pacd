# 06_chequeos_informe.R -- cifras del informe que no salen de los scripts 01-04
#   (a) validacion de la limpieza contra siniestros_montevideo.csv
#   (b) registros por dia y por año (contexto de la deriva al alza)
#   (c) Punta Carretas: perfil, rambla y distancia a los centros de grupo
# Diagnostico: NO modifica el clustering ni ningun archivo de resultados.
source("00_setup.R")

sin <- readRDS(file.path(dir_proc, "siniestros_barrio.rds"))
pf  <- readRDS(file.path(dir_proc, "perfil_barrios_grupos.rds"))

# ---- (a) El .rds coincide con la fuente independiente ----------------------------
ref <- read.csv(f_sin_mvd, colClasses = "character")
k_u <- sort(paste(format(sin$fecha), format(sin$x, scientific = FALSE),
                  format(sin$y, scientific = FALSE), sep = "|"))
k_r <- sort(paste(ref$fecha, ref$coord_x, ref$coord_y, sep = "|"))
cat("(a) filas:", length(k_u), "vs", length(k_r), "| multiconjuntos fecha|x|y identicos:",
    identical(k_u, k_r), "\n")

# ---- (b) Registros por año, con y sin duplicados exactos ---------------------------
raw <- read.csv(f_unificado, colClasses = "character", strip.white = TRUE,
                quote = "", comment.char = "")
raw$fecha <- as.Date(raw$Fecha, format = "%m/%d/%Y")
mv <- raw[raw$Departamento == "MONTEVIDEO", ]
cols_orig <- c("Fecha", "Calle", "Tipo.de.Siniestro", "Gravedad", "Dia.Semana",
               "Hora", "Departamento", "Localidad", "fixed", "X", "Y")
mv$dup <- duplicated(mv[, cols_orig])
anio <- as.integer(format(mv$fecha, "%Y"))
dias <- c(`2018` = 365, `2019` = 365, `2020` = 366, `2021` = 365,
          `2022` = 365, `2023` = 365, `2024` = 366, `2025` = 365)
cat("\n(b) Registros por año:\n")
print(rbind(con_duplicados = table(anio), sin_duplicados = table(anio[!mv$dup]),
            duplicados = table(anio[mv$dup])))
cat("Registros por dia (tabla del informe, con duplicados):\n")
print(round(table(anio) / dias, 1))

# ---- (c) Punta Carretas ----------------------------------------------------------
keep <- c("COLISIÓN ENTRE VEHÍCULOS", "DESPISTE", "ATROPELLO DE PEATÓN", "CAÍDA")
sin$t <- factor(ifelse(is.na(sin$tipo) | !(sin$tipo %in% keep), "OTROS", sin$tipo),
                levels = c(keep, "OTROS"))
sin$rambla <- grepl("^RAMBLA", sin$calle)          # calle que empieza con RAMBLA
pc <- sin[sin$barrio == "PUNTA CARRETAS", ]
pct   <- function(d) round(100 * prop.table(table(d$t)), 1)
resum <- function(d) c(pct(d), n = nrow(d), nocturno = round(100 * mean(d$nocturno), 1),
                       grave_fatal = round(100 * mean(d$gravedad %in% c("GRAVE", "FATAL")), 1),
                       finde = round(100 * mean(d$finde), 1))
cat("\n(c) Rambla vs fuera de ella, toda Montevideo:\n")
print(rbind(rambla = resum(sin[sin$rambla, ]), fuera = resum(sin[!sin$rambla, ])))
cat("\nPunta Carretas: total, sobre la rambla y fuera de ella:\n")
print(rbind(total = resum(pc), rambla = resum(pc[pc$rambla, ]), resto = resum(pc[!pc$rambla, ])))
cat("Despistes y caidas sobre la rambla en PC:",
    sum(pc$t[pc$rambla] == "DESPISTE"), sum(pc$t[pc$rambla] == "CAÍDA"), "\n")

cat("\nBarrios con >= 60 siniestros sobre la rambla (despiste/caida sobre rambla vs resto del barrio):\n")
print(as.data.frame(sin |> group_by(barrio) |> filter(sum(rambla) >= 60) |>
  summarise(n_rambla = sum(rambla), pct_barrio_en_rambla = round(100 * mean(rambla), 1),
            despiste_rambla = round(100 * mean(t[rambla] == "DESPISTE"), 1),
            despiste_resto = round(100 * mean(t[!rambla] == "DESPISTE"), 1),
            caida_rambla = round(100 * mean(t[rambla] == "CAÍDA"), 1),
            caida_resto = round(100 * mean(t[!rambla] == "CAÍDA"), 1),
            grupo = first(pf$grupo[match(barrio, pf$barrio)]), .groups = "drop")))

v <- c("p_colision", "p_despiste", "p_atropello_peaton", "p_caida", "p_grave_fatal",
       "p_nocturno", "p_finde")
i <- pf$barrio == "PUNTA CARRETAS"
cat("\nPerfil (%) de PC y medias de grupo:\n")
print(round(100 * rbind(PC = unlist(pf[i, v]), G1 = colMeans(pf[pf$grupo == 1, v]),
                        G2 = colMeans(pf[pf$grupo == 2, v])), 1))
cat("Rango en el grupo 1 (%): despiste", round(100 * range(pf$p_despiste[pf$grupo == 1]), 1),
    "| caida", round(100 * range(pf$p_caida[pf$grupo == 1]), 1), "\n")
cat("Puesto de PC entre los 62 (1 = valor mas alto, salvo donde se indica): despiste",
    rank(-pf$p_despiste)[i], "| caida", rank(-pf$p_caida)[i], "| atropello", rank(-pf$p_atropello_peaton)[i],
    "| nocturno", rank(-pf$p_nocturno)[i], "| colision (1 = mas bajo)", rank(pf$p_colision)[i],
    "| grave/fatal (1 = mas bajo)", rank(pf$p_grave_fatal)[i], "\n")

# Distancia euclidea (variables estandarizadas con la media y el desvio de los 62 barrios,
# igual que en 04_clustering.R) a los centros de los dos grupos
Z  <- scale(as.matrix(pf[v]))
c1 <- colMeans(Z[pf$grupo == 1, ]); c2 <- colMeans(Z[pf$grupo == 2, ])
mu <- colMeans(pf[v]); sdv <- sapply(pf[v], sd)
perf <- function(d) c(p_colision = mean(d$t == "COLISIÓN ENTRE VEHÍCULOS"),
                      p_despiste = mean(d$t == "DESPISTE"),
                      p_atropello_peaton = mean(d$t == "ATROPELLO DE PEATÓN"),
                      p_caida = mean(d$t == "CAÍDA"),
                      p_grave_fatal = mean(d$gravedad %in% c("GRAVE", "FATAL")),
                      p_nocturno = mean(d$nocturno), p_finde = mean(d$finde))
cat("\nDistancia de Punta Carretas a los centros de grupo (z):\n")
for (nm in c("con todos sus siniestros", "sin los de rambla (solo diagnostico)")) {
  d <- if (nm == "con todos sus siniestros") pc else pc[!pc$rambla, ]
  z <- (perf(d) - mu) / sdv
  cat(sprintf("  %-38s n = %3d  grupo 1: %.2f | grupo 2: %.2f\n", nm, nrow(d),
              sqrt(sum((z - c1)^2)), sqrt(sum((z - c2)^2))))
}
