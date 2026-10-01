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

## 3. Regresión: siniestros por día

**Unidad y respuesta.** El día, para todo Montevideo: 1.645 observaciones obtenidas sumando `n_siniestros` del panel por fecha (el clima y `tipo_dia` son idénticos entre municipios en cada fecha). La respuesta tiene media 22,26, desvío 6,44 y rango 4–44. Se agrega porque, por municipio × día, la media es 2,78 siniestros y la variación entre municipios en un día dado es casi toda ruido que las variables disponibles no explican: el mismo calendario y clima dan R² = 0,055 por municipio × día (0,134 si se incluye el municipio como factor) contra 0,297 por día agregado. Agregar pierde ruido, no información.

**Exploración** (`../outputs/figuras/reg_01` a `reg_04`). Los fines de semana y feriados tienen menos siniestros que los días de semana, y enero es el mes más bajo. Los suavizados contra temperatura y lluvia son casi planos. La serie diaria muestra caídas cada enero y una deriva al alza (de unos 20 a unos 25 por día entre 2021 y 2025).

**Modelos anidados.** M0: `tipo_dia`; M1: + `mes`; M2: + `temp_media`, `lluvia_mm`, `viento_max_kmh`, `estado_clima`. Split aleatorio 70/30 (1.152 días de entrenamiento, 493 de prueba; semilla 2024). Baseline: predecir la media de entrenamiento.

| Modelo | R² | R² aj. | AIC | MAE train | MAE test | RMSE train | RMSE test |
|---|---|---|---|---|---|---|---|
| Baseline (media) | – | – | – | 5,15 | 5,31 | 6,42 | 6,47 |
| M0 `tipo_dia` | 0,203 | 0,202 | 7.300,0 | 4,53 | 4,51 | 5,73 | 5,53 |
| M1 + `mes` | 0,284 | 0,276 | 7.198,1 | 4,31 | 4,33 | 5,43 | 5,39 |
| M2 + clima | 0,291 | 0,280 | 7.197,3 | 4,29 | 4,34 | 5,41 | 5,42 |

Ajustados sobre los 1.645 días, sin split, los R² son 0,223 / 0,294 / 0,297 y el RMSE 5,67 / 5,41 / 5,39, contra un baseline de 6,44.

El calendario explica casi todo lo que el modelo logra explicar. Un fin de semana tiene 5,8 siniestros menos que un día de semana y un feriado 8,2 menos (M1). Respecto de enero, los demás meses suman entre 3,6 (febrero) y 7,2 (diciembre). Agregar `mes` mejora el ajuste de forma clara (F = 11,8; p < 0,001). Agregar el clima aporta menos de un punto de R², empeora levemente el RMSE de prueba (5,42 frente a 5,39) y no resulta significativo al 5 % (F = 2,15; p = 0,057); el AIC de M2 es solo 0,8 menor, un empate. Se toma **M1** como mejor modelo: menor RMSE de prueba y más simple. Reduce el RMSE de prueba un 17 % respecto de predecir la media (6,47 a 5,39); el 70 % restante de la varianza queda sin explicar.

**Residuos de M1** (`reg_05`). No hay patrón contra los valores ajustados y los residuos por mes y por tipo de día están centrados en cero. La cola derecha es más pesada que la normal (QQ-plot; Shapiro-Wilk p ≈ 4·10⁻⁶): los días con muchos siniestros se subestiman. En conteos se espera que la varianza crezca con la media, pero aquí no se detecta heterocedasticidad (Breusch-Pagan p = 0,11; desvío residual por tercil de ajustado 5,3 / 5,7 / 5,4), probablemente porque los valores ajustados ocupan un rango estrecho (10 a 26, casi todos entre 18 y 26). La varianza residual es 1,3 veces la media, una sobredispersión leve respecto de Poisson. La autocorrelación de lag 1 de los residuos es 0,11, en línea con la deriva al alza que el modelo no recoge. En observados vs. predichos (`reg_06`) las predicciones quedan en franjas verticales, porque el modelo solo tiene variables categóricas, y los días extremos (menos de 12 o más de 35) no se anticipan.

## 4. Clustering: perfiles de siniestralidad por barrio

**Unidad.** El barrio: 62 observaciones, cada una con el perfil de sus siniestros en todo el período. No se agrupan municipios porque con 8 observaciones el método del codo no es informativo, la silueta es inestable y la partición depende de la semilla; con 62 barrios el análisis es defendible.

**Variables.** Siete proporciones dentro del barrio (no conteos, para que el agrupamiento capture perfil y no volumen): colisión entre vehículos, despiste, atropello de peatón, caída, grave o fatal, nocturno y fin de semana. "OTROS" (obstáculo en calzada, atropello de animales y tipo sin dato; 3,4 % del total) queda afuera para evitar una suma exacta de 1 entre las proporciones de tipo. Solo para caracterizar, fuera del agrupamiento: total de siniestros, municipio dominante del barrio, densidad (siniestros por km²) y, como descriptor adicional, la proporción de siniestros cuya calle comienza con Avenida, Boulevard o Rambla.

**Revisión previa** (`../outputs/figuras/clu_01_histogramas.png`). Sin faltantes. `p_despiste` tiene cola derecha; las demás son aproximadamente simétricas. Los extremos con |z| > 2,5 son nueve valores en nueve barrios distintos (despiste en Lezica Melilla, 16,9 %; atropello de peatón en Tres Cruces y Centro, 24 %; caída en Manga, 21 %) y ninguno parece un error, por lo que no se excluyó ni se modificó nada. Las proporciones están correlacionadas entre sí: colisión con caída −0,78 y con despiste −0,71.

**Estandarización.** Se usó z-score aunque todas sean proporciones: los desvíos entre barrios van de 0,020 (nocturno) a 0,069 (colisión), una razón de 3,4 (11 en varianza). Sin estandarizar, la distancia euclídea quedaría dominada por la colisión.

**Elección de k.** k-means con `nstart = 25` y semilla fija, k = 2 a 10 (`clu_02_codo_silueta.png`).

| k | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|
| WSS | 297 | 242 | 209 | 185 | 167 | 151 | 136 | 124 | 114 |
| Silueta | **0,334** | 0,207 | 0,202 | 0,213 | 0,207 | 0,222 | 0,218 | 0,225 | 0,215 |

La silueta tiene un máximo claro en k = 2 y de k = 3 en adelante queda plana en torno a 0,2, por debajo de 0,25 (sin estructura sustancial). El codo **no es nítido**: entre k = 2 y 10 la curva de WSS baja de forma suave. Si se toma como referencia k = 1 (WSS = 427, la variación total), la mayor caída es la de 1 a 2 (130, contra 55 de 2 a 3 y 33 de 3 a 4), de modo que el único codo plausible coincide con la silueta, pero la evidencia del codo por sí sola no alcanzaría para elegir. Se adopta **k = 2**. La partición es idéntica en 30 semillas distintas (Rand ajustado = 1). Con k = 3 el grupo menor se conserva (12 de sus 14 barrios quedan juntos) y el grupo grande se parte en 27 y 21 barrios sin que la silueta mejore.

**Grupos.** Medias por grupo en escala original (proporción de los siniestros del barrio):

| Grupo | Barrios | Colisión | Despiste | Atrop. peatón | Caída | Grave/fatal | Nocturno | Fin de semana |
|---|---|---|---|---|---|---|---|---|
| 1 | 48 | 74,4 % | 3,6 % | 11,4 % | 7,5 % | 12,5 % | 13,2 % | 22,6 % |
| 2 | 14 | 63,1 % | 10,4 % | 8,2 % | 12,9 % | 15,7 % | 14,1 % | 26,0 % |

Grupo 2: Bañados de Carrasco, Capurro Bella Vista, Casabó Pajas Blancas, Colón Centro y Noroeste, Colón Sureste Abayuba, Conciliación, La Paloma Tomkinson, Lezica Melilla, Manga, Manga Toledo Chico, Paso de la Arena, Punta Carretas, Tres Ombúes Pueblo Victoria y Villa García Manga Rural. El grupo 1 reúne los otros 48 (lista completa en `../outputs/tablas/clu_barrios_por_grupo.csv`).

**Lectura cruzada** (`clu_05_mapa.png`). El mapa muestra que el grupo 2 ocupa casi toda la franja rural y periurbana del norte y el oeste; el grupo 1 es la ciudad compacta. La densidad lo confirma: mediana de 44 siniestros/km² en el grupo 2 (rango intercuartil 11–104) contra 237 en el grupo 1 (144–307) (Kruskal-Wallis p < 0,001); el área mediana es 21 contra 2,5 km². Las avenidas pesan más en el grupo 1 (46 % de los siniestros contra 28 %; p = 0,009). El **volumen total no distingue** a los grupos (mediana 592 contra 521; p = 0,59): no es una división de barrios "con muchos" y "con pocos" siniestros. Por municipio, el grupo 2 reúne 4 de los 8 barrios del A, 4 de 7 del G, 2 de 9 del D, 2 de 7 del F, 1 de 13 del C y 1 de 5 del CH, ninguno del B ni del E (Fisher simulado p = 0,044): se asocia con la periferia, pero no coincide con un municipio. La separación tampoco es limpia: varios barrios del grupo 1 (Nuevo París, Punta Rieles, Carrasco Norte, Peñarol, Las Canteras) tienen densidades de 70 a 84 siniestros/km², y dos barrios del grupo 2 (Capurro Bella Vista y Punta Carretas) son urbanos y tienen silueta negativa: no encajan bien en ninguno de los dos grupos. La silueta promedio es 0,36 en el grupo 1 y 0,24 en el grupo 2.

**Interpretación en lenguaje llano.**
- **Grupo 1, ciudad compacta (48 barrios).** Tres de cada cuatro siniestros son choques entre vehículos y uno de cada nueve es un atropello a un peatón; los despistes son raros (3,6 %). Es el perfil de la trama urbana densa, con mucha interacción entre vehículos y peatones.
- **Grupo 2, periferia y zona rural (14 barrios, 12 de ellos de baja densidad).** Menos choques entre vehículos y más siniestros de un solo vehículo: el despiste casi se triplica (de 3,6 % a 10,4 %) y las caídas suben de 7,5 % a 12,9 %. También hay algo más de casos graves o fatales (15,7 % contra 12,5 %) y de fin de semana (26 % contra 23 %). Es coherente con vías más abiertas y menos transitadas, pero con estos datos no se puede probar la causa (no hay velocidad, tipo de vía ni vehículo).
- La proporción nocturna casi no distingue a los grupos (14,1 % contra 13,2 %).
- Dentro del grupo 1 no aparecen subgrupos: con k ≥ 3 la silueta cae a 0,2. Los 48 barrios forman un continuo, no tipos claros.

## 5. Limitaciones y hallazgos

**Regresión.**
- Se asume normalidad sobre una respuesta de conteo; una Poisson o binomial negativa (la sobredispersión de 1,3 apunta a esta última) sería lo adecuado. Las predicciones no son enteras.
- No hay variables de exposición (tránsito, obras, eventos, parque automotor); la deriva al alza de la serie no tiene variable que la explique.
- Los datos son siniestros registrados: puede haber subregistro, y no necesariamente constante en el tiempo.
- El split es aleatorio sobre una serie diaria con autocorrelación residual leve: los días de prueba están intercalados con los de entrenamiento y el error de prueba es algo optimista.
- Dentro de M2, `lluvia_mm` y `estado_clima` son casi redundantes: todos los días clasificados como lluvia tienen mm > 0 y todos los demás tienen 0.
- Agregar a todo Montevideo impide decir algo sobre diferencias territoriales; eso lo responde el clustering.

**Clustering.**
- k-means supone distancia euclídea y grupos aproximadamente esféricos. Las proporciones están ligadas entre sí (colisión, caída y despiste se reparten el mismo total): el primer eje del PCA (43 % de la varianza) es básicamente "colisión contra siniestros de un solo vehículo".
- `p_grave_fatal` se apoya en pocos casos en los barrios chicos: el barrio con menos siniestros tiene 206 y el que menos graves o fatales tiene 20. A 206 siniestros, el error estándar de una proporción de 13 % es de 2,3 puntos, cerca del desvío entre barrios (3,6 puntos): esta variable es en buena parte ruido.
- Los límites de barrio son administrativos y cortan avenidas por el medio: una misma avenida queda repartida entre varios barrios. Los barrios rurales, grandes, agregan tramos de rutas enteras, y los barrios chicos del centro, una trama urbana: las unidades no son comparables en superficie (mediana de 21 contra 2,5 km² entre grupos).
- El descriptor de avenidas se calcula por el nombre de la calle (que empiece con Avenida, Boulevard o Rambla) y 835 siniestros no tienen calle; es una aproximación.
- El perfil agrega 4,5 años: no distingue cambios en el tiempo, y no se corrige por exposición (tránsito, parque automotor).
- Una silueta de 0,33 indica estructura débil; los grupos describen una tendencia, no tipos bien separados.

**Hallazgos.**
1. El calendario (tipo de día y mes) explica cerca del 30 % de la variación diaria de siniestros; el clima no aporta señal detectable. El 70 % restante no se explica con las variables disponibles.
2. Entre los 62 barrios hay una sola separación con respaldo: un grupo de 14 barrios, mayoritariamente periurbanos y rurales y de baja densidad, con más despistes, caídas y casos graves, frente a una ciudad compacta de 48 barrios dominada por colisiones y atropellos. Es estable (idéntica en 30 semillas) pero débil (silueta 0,33), y dos de los 14 barrios no encajan bien.
3. Dentro de la ciudad compacta no hay subgrupos distinguibles, y el volumen de siniestros no separa a los grupos.
