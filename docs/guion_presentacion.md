# Guion de la presentación (≈ 10 minutos)

Sigue los puntos que pide la consigna. Cada bloque indica qué mostrar.

## 1. Pregunta (1 min)
- Siniestros de tránsito en Montevideo, julio 2021 – diciembre 2025 (36.612 siniestros).
- **Cuándo:** ¿qué explica cuántos siniestros hay por día, el calendario o el clima? ¿Cómo evoluciona?
- **Dónde:** ¿hay perfiles de siniestralidad distintos entre los 62 barrios?

## 2. Estructura del pipeline (1,5 min)
- Mostrar el árbol del `README.md` y el diagrama de la sección 3 del informe.
- `data/raw` (solo lectura) → `01` preparar → `data/processed` → `02` SQLite + SQL → `03` temporal, `04` regresión, `05` clustering → `outputs/` → informe Quarto.
- `run_all.R` borra todo lo generado y lo reconstruye desde cero.

## 3. Decisiones sobre los datos (1,5 min)
- Lectura directa desde el zip con `quote = ""` (ver punto 7).
- 90 duplicados exactos eliminados; 11 puntos fuera de los barrios excluidos.
- EPSG 32721 validado contra lat/lon conocida (error de centímetros).
- Tipos con menos de 3 % agrupados en "OTROS"; proporciones (no conteos) para el clustering.
- Mostrar la Tabla 1 (flujo de registros) y la Tabla 2 (validaciones).

## 4. Función o automatización relevante (1,5 min)
Elegir una:
- **`validar()`** (`R/utilidades.R`): registra cada control y corta el pipeline si falla. La validación estrella: la base limpia coincide fila a fila con la fuente independiente.
- **Regresión por municipio** (`scripts/04_regresion.R`): `nest()` + `map2()` + `possibly()` corren los 3 modelos en los 8 municipios, con validación previa de cada panel.
- **`leer_consultas()`** (`R/datos.R`): lee `sql/consultas.sql`, ejecuta cada consulta con `map()` y guarda cada resultado como CSV.

## 5. Resultados y visualizaciones (2,5 min)
- Figura 1 (serie diaria) y Figura 3 (índice por municipio): enero bajo y tendencia al alza de ~4 % anual.
- Tabla 6 y Figura 4: el calendario explica; el clima no aporta (ni en Montevideo ni en ningún municipio).
- Figura 8 y Figura 9 (mapa): ciudad compacta vs. periferia; la diferencia es de tipo, no de cantidad.

## 6. Dificultad o descubrimiento (1 min)
- Parecía un problema de fechas y era de lectura: 107 calles con comillas hacían que `read.csv()` descartara bloques del archivo (49.544 de 224.694 filas leídas). Se detecta comparando filas leídas con líneas del archivo.
- Resultado negativo pero valioso: el clima no mejora la predicción.

## 7. Limitaciones (0,5 min)
- Sin datos de exposición (tránsito): no se separa más riesgo de más circulación.
- Modelo lineal sobre conteos; split aleatorio en una serie temporal; clusters débiles (silueta 0,33).

## 8. Qué mejoraríamos (0,5 min)
- Modelo de Poisson o binomial negativa con tendencia y validación temporal (entrenar con el pasado, evaluar con el futuro).
- Incorporar datos de tránsito o exposición.
- Ver si los perfiles de barrio cambian año a año.
