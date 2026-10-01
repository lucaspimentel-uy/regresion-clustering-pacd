# HANDOFF — regresión + clustering de siniestros (Montevideo)

Scripts en la raíz, se ejecutan desde la raíz del proyecto (`Rscript 01_fechas.R`).
R 4.6.1; paquetes en la biblioteca de usuario (`R_LIBS_USER`). `00_setup.R` falla con mensaje claro si falta alguno.

## Estado

| Paso | Estado | Archivo |
|---|---|---|
| 0.a Setup | cerrado | `00_setup.R` |
| 0.b Fechas | cerrado, **números mostrados al usuario, esperando OK** | `01_fechas.R` |
| 0.c Siniestros individuales + barrio | pendiente | `02_siniestros_barrio.R` |
| 1 Regresión | pendiente | `03_regresion.R` |
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
- Montevideo en 2021-07-01/2025-12-31: **36.713** (esperado ~36.612; diferencia 101 = 0,28 %). Ver pendientes.

## Pendientes / dudas abiertas

- `data/raw/` solo tiene el unificado y el geojson. **Faltan `panel_diario_montevideo.csv` y `siniestros_montevideo.csv`.**
  El panel existe en `C:\Users\Lucas\Downloads\panel_diario_montevideo.csv` (999 KB); falta confirmar que es el correcto y copiarlo a `data/raw/`.
  `siniestros_montevideo.csv` (necesario para validar EPSG con lat/lon) **no apareció** en Downloads, Desktop, Documents ni `C:\Proyectos`.
- Diferencia 36.713 vs 36.612: investigar en 0.c (¿faltantes de X/Y? ¿duplicados? ¿columna `fixed`?). No forzar.
- `.gitignore` excluye el unificado (26 MB) y `data/processed/`.
