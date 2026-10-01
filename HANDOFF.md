# HANDOFF — regresión + clustering de siniestros (Montevideo)

Scripts en la raíz, se ejecutan desde la raíz del proyecto (`Rscript 01_fechas.R`).
R 4.6.1; paquetes en la biblioteca de usuario (`R_LIBS_USER`). `00_setup.R` falla con mensaje claro si falta alguno.

## Estado

| Paso | Estado | Archivo |
|---|---|---|
| 0.a Setup | cerrado | `00_setup.R` |
| 0.b Fechas | cerrado (usuario aprobó) | `01_fechas.R` |
| 0.c Siniestros individuales + barrio | cerrado | `02_siniestros_barrio.R` → `data/processed/siniestros_barrio.rds` |
| 1 Regresión | cerrado | `03_regresion.R` → `outputs/figuras/reg_*.png`, `outputs/tablas/reg_*.csv` |
| 2 Clustering | pendiente | `04_clustering.R` |
| Extensión día × franja | no empezar hasta cerrar 1 y 2 | — |

## Paso 0.b — hallazgo

La hipótesis del enunciado (formatos de fecha mezclados / separador tab) **no era la causa**.

- Separador: `", "` (coma + espacio); encabezado con espacio final. 11 campos en las 224.695 líneas (`count.fields(quote="")`).
- Formato de `Fecha`: único, `m/d/yyyy`. Los largos 8/9/10 son solo meses/días de 1 o 2 dígitos.
  `as.Date(format="%m/%d/%Y")` → **0 NA** de 224.694. Weekday(Fecha) coincide 100 % con `Dia Semana`.
- **Causa real**: 107 líneas con comillas dobles dentro de `Calle` (`CAMINO VECINAL "RUTA JONES"`).
  `read.csv()` / `readr` con `quote` por defecto abren una comilla y se tragan líneas: `read.csv` devolvía 49.544 filas.
  **Siempre leer con `quote = ""`, `strip.white = TRUE`, `comment.char = ""`.**
- Montevideo por año (sin filtrar): 2018 8.109 · 2019 8.109 · 2020 6.533 · 2021 6.921 · 2022 7.683 · 2023 7.902 · 2024 8.422 · 2025 8.748 (total 62.427). Sin meses vacíos.
- Montevideo en 2021-07-01/2025-12-31: **36.713** (esperado ~36.612; diferencia 101 = 0,28 %). Explicado en 0.c.

## Paso 0.c — resultados

- 36.713 (ventana) − 90 duplicados exactos (11 campos originales idénticos) = 36.623 − 11 sin barrio = **36.612**. Coincide con `siniestros_montevideo.csv`.
- Los 11 sin barrio: coordenadas (558945, 6150640) ×10 y (558985, 6150535) ×1, Ruta 1 km 22, `Localidad = SIN DATOS`. Quedan fuera de los 62 polígonos → excluidos del `.rds`.
- **EPSG**: 32721 y 31981 dan error mediano 4 cm / máx 7 cm vs lat/lon conocida; indistinguibles (misma proyección, datum casi igual). Control UTM 20S: 547 km. Se usó 32721. El test descarta la zona equivocada, no separa los dos candidatos.
- QA: 0 % sin barrio, 62 barrios, min 206 (LA BLANQUEADA), max 1.804 (UNION), mediana 531 — idéntico a la referencia.
- 6 geometrías de barrio inválidas → `st_make_valid()` (el QA da igual a la referencia).
- `Tipo`: 1 registro con variante sin tilde `COLISIÓN CON OBSTACULO EN CALZADA` (cae en OTROS igual). 10 tipos `NA`. Gravedad sin `NA`. FATAL sola = 1,2 % (443): `p_grave_fatal` la combina con GRAVE (11,9 %), como pide el enunciado.
- El `.rds` NO agrupa categorías: el corte 3 % → "OTROS" se aplica en `04_clustering.R`. Trae también `municipio` (por coordenada, desde `siniestros_montevideo.csv`; función exacta de x,y), `lon`/`lat`, `nocturno`, `finde`.
- `data/raw/` ahora tiene el panel y `siniestros_montevideo.csv`. `.gitignore` excluye el unificado (26 MB) y `data/processed/`.

## Paso 1 — resultados

- Panel: 13.160 filas = 8 municipios × 1.645 días, sin NA ni fechas faltantes; suma 36.612 (= `.rds` del 0.c). Clima y `tipo_dia` idénticos entre municipios por fecha.
- Chequeo contra valores de referencia, **ajuste sobre los 1.645 días sin split**: R² 0,223 / 0,294 / 0,297; RMSE 5,67 / 5,41 / 5,39; baseline 6,44. **Coincide exacto** → sin bug.
- Con split 70/30 (semilla 2024, 1.152/493), ajuste sobre train: R² 0,203 / 0,284 / 0,291; R² aj. 0,202 / 0,276 / 0,280; AIC 7300,0 / 7198,1 / 7197,3. RMSE test: baseline 6,47, M0 5,53, **M1 5,39**, M2 5,42. MAE test: 5,31 / 4,51 / 4,33 / 4,34.
- Mejor = M1 (menor RMSE test; M2 gana por 0,8 de AIC = empate; F M2 vs M1 p = 0,057). El clima no aporta.
- Residuos M1: Shapiro p ≈ 4e-6 (cola derecha), Breusch-Pagan p = 0,11 (**sin heterocedasticidad detectable**, contrario a lo esperado; ajustados en rango estrecho 10–26), var. residual/media = 1,32, autocorrelación lag-1 = 0,11.
- **Discrepancia con el enunciado**: "el mismo modelo da R² 0,13 por municipio × día" NO se reproduce. M2 sobre las 13.160 filas da R² = **0,055**; con `zona_id` como factor da 0,134. La media 2,78 sí coincide. El informe cita 0,055 (0,134 con municipio).
- Serie diaria: caídas cada enero y deriva al alza (~20 → ~25 por día, 2021→2025) que el modelo no recoge. No se agregó tendencia (regla: no tocar el diseño para subir R²); queda como limitación.
- `lluvia_mm` y `estado_clima` casi redundantes (todo día "lluvia" tiene mm > 0; todo otro día tiene 0).
- Split aleatorio sobre serie diaria → error de test algo optimista.
