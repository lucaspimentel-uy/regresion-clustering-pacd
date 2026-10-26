-- consultas.sql -- consultas de analisis sobre data/processed/siniestros_mvd.sqlite
-- Tablas: siniestros (1 fila por siniestro), barrios (1 por barrio),
--         clima_diario (1 por dia: tipo de dia y clima).
-- Fechas como texto 'YYYY-MM-DD'; nocturno y finde como 0/1.
-- Cada consulta se guarda en outputs/tablas/sql_<nombre>.csv (scripts/02_base_relacional.R).

-- name: perfil_barrios
-- Perfil de siniestralidad de cada barrio: insumo del clustering (scripts/05).
-- Las proporciones son sobre TODOS los siniestros del barrio. Volumen, densidad,
-- municipio dominante y peso de avenidas son descriptores externos (no se agrupa por ellos).
WITH mun AS (
  SELECT barrio_id, municipio, COUNT(*) AS n_mun,
         ROW_NUMBER() OVER (PARTITION BY barrio_id ORDER BY COUNT(*) DESC) AS orden
  FROM siniestros
  GROUP BY barrio_id, municipio
)
SELECT b.barrio_id,
       b.barrio,
       COUNT(*)                                                            AS n,
       AVG(CASE WHEN s.tipo_ag = 'COLISIÓN ENTRE VEHÍCULOS' THEN 1.0 ELSE 0 END) AS p_colision,
       AVG(CASE WHEN s.tipo_ag = 'DESPISTE'                 THEN 1.0 ELSE 0 END) AS p_despiste,
       AVG(CASE WHEN s.tipo_ag = 'ATROPELLO DE PEATÓN'      THEN 1.0 ELSE 0 END) AS p_atropello,
       AVG(CASE WHEN s.tipo_ag = 'CAÍDA'                    THEN 1.0 ELSE 0 END) AS p_caida,
       AVG(CASE WHEN s.gravedad IN ('GRAVE', 'FATAL')       THEN 1.0 ELSE 0 END) AS p_grave_fatal,
       AVG(s.nocturno * 1.0)                                               AS p_nocturno,
       AVG(s.finde * 1.0)                                                  AS p_finde,
       b.area_km2,
       COUNT(*) / b.area_km2                                               AS densidad,
       m.municipio                                                         AS municipio_dom,
       1.0 * m.n_mun / COUNT(*)                                            AS pct_municipio_dom,
       AVG(CASE WHEN s.calle IS NULL THEN NULL
                WHEN s.calle LIKE 'AVENIDA%' OR s.calle LIKE 'BOULEVARD%'
                  OR s.calle LIKE 'BULEVAR%' OR s.calle LIKE 'RAMBLA%' THEN 1.0
                ELSE 0 END)                                                AS p_avenida
FROM siniestros AS s
JOIN barrios AS b ON s.barrio_id = b.barrio_id
JOIN mun     AS m ON m.barrio_id = b.barrio_id AND m.orden = 1
GROUP BY b.barrio_id, b.barrio, b.area_km2, m.municipio, m.n_mun
ORDER BY b.barrio;

-- name: resumen_anual_municipio
-- Siniestros por municipio y año, por dia de la ventana (2021 solo tiene julio-diciembre)
-- y porcentaje grave o fatal.
WITH dias AS (
  SELECT strftime('%Y', fecha) AS anio, COUNT(*) AS dias
  FROM clima_diario
  GROUP BY anio
)
SELECT s.municipio,
       strftime('%Y', s.fecha)                                             AS anio,
       d.dias,
       COUNT(*)                                                            AS siniestros,
       ROUND(1.0 * COUNT(*) / d.dias, 2)                                   AS por_dia,
       ROUND(100.0 * AVG(CASE WHEN s.gravedad IN ('GRAVE', 'FATAL') THEN 1.0 ELSE 0 END), 1)
                                                                           AS pct_grave_fatal
FROM siniestros AS s
JOIN dias AS d ON strftime('%Y', s.fecha) = d.anio
GROUP BY s.municipio, anio, d.dias
ORDER BY s.municipio, anio;

-- name: siniestros_por_tipo_dia_clima
-- Media de siniestros por dia segun tipo de dia y estado del clima (todo Montevideo).
-- LEFT JOIN desde clima_diario: un dia sin siniestros contaria como 0.
WITH diario AS (
  SELECT fecha, COUNT(*) AS n
  FROM siniestros
  GROUP BY fecha
)
SELECT c.tipo_dia,
       c.estado_clima,
       COUNT(*)                         AS dias,
       ROUND(AVG(COALESCE(d.n, 0)), 2)  AS media_por_dia
FROM clima_diario AS c
LEFT JOIN diario AS d ON c.fecha = d.fecha
GROUP BY c.tipo_dia, c.estado_clima
ORDER BY c.tipo_dia, c.estado_clima;

-- name: gravedad_por_tipo
-- Gravedad segun el tipo de siniestro: que tipos concentran los casos graves o fatales.
SELECT tipo_ag                                                             AS tipo,
       COUNT(*)                                                            AS siniestros,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM siniestros), 1)      AS pct_del_total,
       ROUND(100.0 * AVG(CASE WHEN gravedad IN ('GRAVE', 'FATAL') THEN 1.0 ELSE 0 END), 1)
                                                                           AS pct_grave_fatal,
       ROUND(100.0 * AVG(CASE WHEN gravedad = 'FATAL' THEN 1.0 ELSE 0 END), 2)
                                                                           AS pct_fatal
FROM siniestros
GROUP BY tipo_ag
ORDER BY siniestros DESC;
