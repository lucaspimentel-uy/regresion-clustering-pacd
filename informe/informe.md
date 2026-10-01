# Siniestralidad vial en Montevideo: calendario, clima y perfiles barriales

## 1. Pregunta

1. ¿Cuántos siniestros ocurren por día en Montevideo y qué los explica mejor: el calendario o el clima?
2. ¿Existen perfiles de siniestralidad diferenciados entre los barrios?

## 2. Datos y preparación

Fuente principal: archivo unificado de siniestros de Uruguay (2018–2025, 224.694 registros; 62.427 en Montevideo). La ventana de análisis es 2021-07-01 a 2025-12-31, la misma del panel diario.

**Lectura del archivo.** El separador es coma seguida de espacio. Las fechas tienen un único formato (`m/d/yyyy`): 0 valores no parseables, y el día de la semana derivado coincide en el 100 % de los casos con la columna `Dia Semana`. El problema detectado fue otro: 107 registros traen comillas dobles dentro del nombre de la calle (por ejemplo `CAMINO VECINAL "RUTA JONES"`), y la lectura con el manejo de comillas por defecto descartaba grandes bloques del archivo (49.544 de 224.694 filas, con años enteros faltantes). Se lee con `quote = ""`.

Filas de Montevideo por año, antes de filtrar por ventana:

| Año | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 |
|---|---|---|---|---|---|---|---|---|
| Siniestros | 8.109 | 8.109 | 6.533 | 6.921 | 7.683 | 7.902 | 8.422 | 8.748 |

*(El resto de las secciones se completa al cerrar cada paso.)*
