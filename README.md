# Siniestralidad vial en Montevideo: un pipeline reproducible

Proyecto final de **Programación Avanzada para Ciencia de Datos**. A partir de la base de siniestros de tránsito de Uruguay, construye un flujo reproducible que va del archivo original a un informe Quarto, para responder dos preguntas sobre Montevideo (julio 2021 – diciembre 2025):

1. **Cuándo.** ¿Cómo evoluciona la siniestralidad y qué explica cuántos siniestros hay por día: el calendario o el clima? ¿Pasa lo mismo en los 8 municipios? *(análisis temporal + regresión lineal)*
2. **Dónde.** ¿Hay perfiles de siniestralidad diferenciados entre los 62 barrios? *(clustering k-means)*

## Datos

Todos los originales están en `data/raw/` y **ningún script los modifica**.

| Archivo | Contenido |
|---|---|
| `uru_siniestros_unificado.zip` | Siniestros de todo el país 2018–2025 (224.694 filas): fecha, hora, calle, tipo, gravedad, coordenadas UTM. Se lee directo desde el zip. |
| `barrios_montevideo.geojson` | Polígonos de los 62 barrios de Montevideo. |
| `panel_diario_montevideo.csv` | Municipio × día con tipo de día (incluye feriados) y clima. |
| `siniestros_montevideo.csv` | Siniestros de Montevideo con lat/lon y municipio (referencia para validar y asignar municipio). |

## Estructura

```
.
├── run_all.R                 # ejecuta todo: datos -> resultados -> informe
├── R/                        # funciones propias
│   ├── datos.R               #   lectura, limpieza, asignacion espacial, SQL
│   ├── analisis.R            #   temporal, metricas y modelos, clustering
│   └── utilidades.R          #   validaciones, guardado de tablas y figuras
├── scripts/                  # etapas del pipeline, en orden
│   ├── 00_setup.R            #   paquetes, rutas (here), parametros, semilla
│   ├── 01_preparar_datos.R   #   raw -> data/processed (+ 15 validaciones)
│   ├── 02_base_relacional.R  #   base SQLite + consultas SQL
│   ├── 03_analisis_temporal.R
│   ├── 04_regresion.R        #   modelos anidados + automatizacion por municipio
│   └── 05_clustering.R
├── sql/
│   ├── chequeos.sql          # integridad referencial
│   └── consultas.sql         # perfil por barrio, resumenes, gravedad por tipo
├── data/
│   ├── raw/                  # datos originales (solo lectura)
│   └── processed/            # generados por 01 y 02
├── outputs/
│   ├── tablas/               # CSV de resultados y de validaciones
│   └── figuras/              # PNG
├── report/
│   ├── informe.qmd           # informe Quarto (fuente)
│   ├── informe.html          # informe generado (autocontenido)
│   └── informe.pdf
└── docs/                     # material del curso y guion de la presentacion
```

## Requisitos

- **R ≥ 4.2** (en Windows, R 4.2 o posterior trabaja en UTF-8; los datos tienen tildes).
- Paquetes: `dplyr`, `tidyr`, `purrr` (≥ 1.0), `readr`, `ggplot2`, `lubridate`, `slider`, `broom`, `sf`, `DBI`, `RSQLite`, `cluster`, `scales`, `patchwork`, `here`, `knitr`, `rmarkdown` y, opcional, `quarto`.

  ```r
  install.packages(c("dplyr", "tidyr", "purrr", "readr", "ggplot2", "lubridate", "slider",
                     "broom", "sf", "DBI", "RSQLite", "cluster", "scales", "patchwork",
                     "here", "knitr", "rmarkdown", "quarto"))
  ```
  `scripts/00_setup.R` corta con un mensaje claro si falta alguno.
- **Quarto** (https://quarto.org/docs/get-started/) para generar el informe. El PDF se genera con Typst, que viene incluido en Quarto (no hace falta LaTeX).

## Ejecución

Desde la raíz del proyecto:

```r
# En R (RGui, RStudio, etc.)
setwd("ruta/al/proyecto")
source("run_all.R")
```

o desde una terminal:

```bash
Rscript run_all.R
```

`run_all.R` **borra `data/processed/` y `outputs/`**, ejecuta `scripts/01` a `05` en orden y genera `report/informe.html` y `report/informe.pdf`. Es la prueba de reproducibilidad: el proyecto se reconstruye partiendo solo de `data/raw/` y del código. Tarda menos de un minuto. Para no borrar nada, poner `limpiar <- FALSE` al principio del archivo.

También se puede correr cada etapa por separado (`source("scripts/03_analisis_temporal.R")`) una vez que existen las salidas de las anteriores, o solo el informe con `quarto render report/informe.qmd` (o `quarto::quarto_render("report/informe.qmd")`).

Los caminos se arman con `here`, a partir del archivo `.here` de la raíz: no hay caminos absolutos ni hace falta cambiar nada al mover el proyecto.

## Qué genera cada etapa

| Script | Salidas principales |
|---|---|
| `01_preparar_datos.R` | `data/processed/siniestros_mvd.csv` (36.612 siniestros con barrio y municipio), `barrios.csv`, `clima_diario.csv`, `panel_diario.csv`; tablas de frecuencias, flujo de registros y problemas de calidad |
| `02_base_relacional.R` | `data/processed/siniestros_mvd.sqlite` (tablas `siniestros`, `barrios`, `clima_diario`), `perfil_barrios.csv`, `outputs/tablas/sql_*.csv` |
| `03_analisis_temporal.R` | `tmp_*`: resumen anual, perfil mensual, tendencia e índice base 100 por municipio |
| `04_regresion.R` | `reg_*`: comparación de modelos, test F, coeficientes, diagnóstico, métricas por municipio |
| `05_clustering.R` | `clu_*`: barrido de k, estabilidad, medias por grupo, barrios por grupo, mapa |

Cada etapa escribe además `outputs/tablas/validaciones_<etapa>.csv` (29 validaciones en total). Si una falla, el pipeline se detiene con un mensaje que dice cuál.

## Principales resultados

- **Calidad de datos.** La lectura con el manejo de comillas por defecto descartaba bloques enteros del archivo (49.544 de 224.694 filas) por 107 calles con comillas. Tras quitar 90 duplicados exactos y 11 puntos fuera de los barrios, la base limpia coincide fila a fila con una fuente independiente.
- **Tiempo.** ~22 siniestros por día, con enero siempre como mes más bajo y una tendencia al alza de ~4 % anual (más fuerte en el municipio A, no significativa en el CH).
- **Regresión.** El calendario (tipo de día y mes) explica casi todo lo explicable (R² ≈ 0,28); el clima no mejora la predicción ni para Montevideo ni en ningún municipio.
- **Clustering.** Dos perfiles de barrio (k = 2, silueta 0,33): ciudad compacta (choques entre vehículos, atropellos) y periferia (más despistes, caídas y casos graves). Se diferencian por tipo de siniestro, no por cantidad.

## Limitaciones

Siniestros registrados (posible subregistro) y sin datos de exposición (tránsito); modelo lineal sobre conteos; split aleatorio sobre una serie temporal; estructura de clusters débil. Detalle en la sección 8 del informe.
