-- chequeos.sql -- integridad referencial de la base relacional.
-- Cada consulta debe devolver 0 filas problematicas (columna n = 0).
-- Las ejecuta scripts/02_base_relacional.R; si alguna da > 0, el pipeline se detiene.

-- name: siniestros_sin_barrio
-- Siniestros cuyo barrio_id no existe en la tabla barrios
SELECT COUNT(*) AS n
FROM siniestros AS s
LEFT JOIN barrios AS b ON s.barrio_id = b.barrio_id
WHERE b.barrio_id IS NULL;

-- name: siniestros_sin_dia
-- Siniestros cuya fecha no esta en la tabla de dias (clima y tipo de dia)
SELECT COUNT(*) AS n
FROM siniestros AS s
LEFT JOIN clima_diario AS c ON s.fecha = c.fecha
WHERE c.fecha IS NULL;

-- name: ids_repetidos
-- Identificadores de siniestro repetidos
SELECT COUNT(*) AS n
FROM (SELECT id FROM siniestros GROUP BY id HAVING COUNT(*) > 1);
