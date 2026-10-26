# 03_analisis_temporal.R -- evolucion de la siniestralidad: serie diaria, mensual y anual,
# estacionalidad y tendencia por municipio.
# Entrada : data/processed/panel_diario.csv
# Salida  : outputs/tablas/tmp_*.csv, outputs/figuras/tmp_*.png
source(here::here("scripts", "00_setup.R"))

panel <- read_csv(f_panel, show_col_types = FALSE)
diario <- panel |>
  group_by(fecha) |>
  summarise(n_siniestros = sum(n_siniestros), .groups = "drop")

# ---- 1. Granularidad mensual y control de periodo completo --------------------
mensual <- agregar_periodo(diario, "month")
validar(all(mensual$dias == days_in_month(mensual$periodo)), "Meses completos en la serie",
        paste(nrow(mensual), "meses; ninguno con dias faltantes"))

# ---- 2. Resumen anual y variacion respecto del año anterior --------------------
# 2021 solo tiene julio-diciembre: se compara la tasa por dia, no el total.
anual <- agregar_periodo(diario, "year") |>
  mutate(anio = year(periodo), var_pct = 100 * (por_dia / lag(por_dia) - 1)) |>
  select(anio, dias, siniestros, por_dia, var_pct)
guardar_tabla(anual, "tmp_resumen_anual")

# ---- 3. Serie diaria con media movil de 28 dias -------------------------------
diario <- diario |>
  mutate(media_movil = slide_dbl(n_siniestros, mean, .before = 13, .after = 14,
                                 .complete = TRUE))
p_serie <- ggplot(diario, aes(fecha, n_siniestros)) +
  geom_line(colour = "grey65", linewidth = 0.25) +
  geom_line(aes(y = media_movil), colour = col_linea, linewidth = 0.9, na.rm = TRUE) +
  labs(x = NULL, y = "Siniestros por día",
       subtitle = "Gris: dato diario. Rojo: media móvil centrada de 28 días")
guardar_figura(p_serie, "tmp_01_serie_diaria", 9, 3.8)

# ---- 4. Estacionalidad: perfil mensual por año --------------------------------
perfil_mensual <- mutate(mensual, anio = factor(year(periodo)))
p_mes <- ggplot(perfil_mensual, aes(month(periodo), por_dia, colour = anio)) +
  geom_line(linewidth = 0.8) + geom_point(size = 1.4) +
  scale_x_continuous(breaks = 1:12, labels = c("ene", "feb", "mar", "abr", "may", "jun",
                                               "jul", "ago", "sep", "oct", "nov", "dic")) +
  scale_colour_manual(values = paleta, name = "Año") +
  labs(x = NULL, y = "Siniestros por día (media del mes)")
guardar_figura(p_mes, "tmp_02_perfil_mensual", 8, 4.2)
guardar_tabla(perfil_mensual |>
                group_by(mes = month(periodo)) |>
                summarise(por_dia_medio = mean(por_dia), minimo = min(por_dia),
                          maximo = max(por_dia), años = n(), .groups = "drop"),
              "tmp_perfil_mensual")

# ---- 5. Tendencia por municipio (automatizacion con nest + map) ----------------
# Serie mensual de cada municipio -> modelo por_dia ~ tiempo + mes -> pendiente.
mensual_mun <- agregar_periodo(panel, "month", municipio)
tendencias <- bind_rows(mutate(mensual, municipio = "MONTEVIDEO"), mensual_mun) |>
  nest(serie = -municipio) |>
  mutate(tendencia = map(serie, estimar_tendencia)) |>
  select(-serie) |>
  unnest(tendencia)
guardar_tabla(tendencias, "tmp_tendencia_municipios")

# Indice base 100 sobre la media movil de 12 meses (quita la estacionalidad).
# Base: los 12 meses que terminan en junio de 2022 (la primera ventana completa).
indice <- bind_rows(mutate(mensual, municipio = "MONTEVIDEO"), mensual_mun) |>
  group_by(municipio) |>
  arrange(periodo, .by_group = TRUE) |>
  mutate(por_dia_12m = slide_dbl(por_dia, mean, .before = 11, .complete = TRUE)) |>
  filter(!is.na(por_dia_12m)) |>
  mutate(indice = 100 * por_dia_12m / first(por_dia_12m)) |>
  ungroup()
guardar_tabla(indice |> select(municipio, periodo, por_dia_12m, indice), "tmp_indice_12m")

# Un panel por municipio, con todo Montevideo en gris como referencia
indice_mvd <- filter(indice, municipio == "MONTEVIDEO") |> select(-municipio)
p_indice <- indice |>
  filter(municipio != "MONTEVIDEO") |>
  mutate(municipio = sub("MUNICIPIO ", "Municipio ", municipio)) |>
  ggplot(aes(periodo, indice)) +
  geom_hline(yintercept = 100, colour = "grey70", linetype = "dashed") +
  geom_line(data = indice_mvd, colour = "grey60", linewidth = 0.6) +
  geom_line(colour = col_punto, linewidth = 0.9) +
  facet_wrap(~municipio, ncol = 4) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(x = "Fin de la ventana de 12 meses", y = "Índice (jul 2021–jun 2022 = 100)",
       subtitle = "Media móvil de 12 meses de siniestros por día. Gris: todo Montevideo")
guardar_figura(p_indice, "tmp_03_indice_municipios", 9, 4.8)

guardar_validaciones("03_temporal")
