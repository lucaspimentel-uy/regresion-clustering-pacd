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

**Siniestros individuales.** Se filtró Departamento = MONTEVIDEO y 2021-07-01 / 2025-12-31 (36.713 registros). Se eliminaron 90 duplicados exactos (los 11 campos originales idénticos), lo que deja 36.623. Los faltantes escritos como texto (`SIN DATOS`, `NO SE INGRESO`) se recodificaron a `NA`; la hora está siempre en 0–23. Se derivó `nocturno` (22 a 5 h; 13,5 % de los casos) y `finde` (sábado y domingo; 23,3 %).

**Asignación de barrio.** Las coordenadas del archivo están en UTM 21S. Se contrastaron contra la latitud/longitud conocida de `siniestros_montevideo.csv` (36.612 puntos): bajo EPSG:32721 (WGS84) y EPSG:31981 (SIRGAS 2000) el error mediano es 4 cm y el máximo 7 cm, es decir, el redondeo de la lat/lon; un control con UTM 20S da 547 km de error. Los dos candidatos son indistinguibles con esta prueba (misma proyección, datums casi coincidentes); se usó 32721. Luego se transformó a EPSG:4326 y se unió con los 62 polígonos de barrio (6 geometrías inválidas reparadas con `st_make_valid`).

Once puntos (Ruta 1 km 22, `Localidad = SIN DATOS`, coordenadas repetidas de relleno) caen fuera de los 62 barrios y se excluyen: quedan **36.612 siniestros, 100 % con barrio**, 62 barrios con datos, mínimo 206 (La Blanqueada), máximo 1.804 (Unión), mediana 531.

**Categorías de `Tipo de Siniestro`** (antes de agrupar): colisión entre vehículos 71,6 %, atropello de peatón 11,1 %, caída 8,8 %, despiste 5,0 %, colisión con obstáculo en calzada 2,3 %, atropello de animales 1,1 %, sin dato 0,03 %. Por debajo del 3 %: obstáculo, animales y sin dato → "OTROS". **Gravedad:** leve 71,3 %, sin lesionados 15,6 %, grave 11,9 %, fatal 1,2 %.

*(El resto de las secciones se completa al cerrar cada paso.)*
