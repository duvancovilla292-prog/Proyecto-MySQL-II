/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Consultas - Espacios y Reservas
Archivo: sql/02_consultas/02_espacios_reservas.sql
Autor: [Nombre del autor]
Grupo: [Nombre del grupo]

Descripción:
Consultas 21 a 40 sobre espacios, reservas, ocupación, servicios adicionales
y asistencia.

Requisitos:
Ejecutar previamente 00_ddl/01_estructura.sql y 01_dml/01_datos_iniciales.sql.

Criterio de "reserva activa":
Reserva en estado 'Pendiente de Confirmación' o 'Confirmada'.
*/

USE coworking_db;

-- Parámetro: ventana (en días) para las consultas de ocupación (30 y 36).
SET @dias_periodo = 30;


-- =====================================================================
-- CONSULTA 21: Listar todos los espacios disponibles con su capacidad.
-- =====================================================================
SELECT
    e.id_espacio,
    e.nombre AS espacio,
    te.nombre AS tipo_espacio,
    e.capacidad_maxima,
    e.hora_apertura,
    e.hora_cierre,
    e.estado
FROM espacios e
INNER JOIN tipos_espacio te ON te.id_tipo_espacio = e.id_tipo_espacio
WHERE e.estado = 'Disponible'
ORDER BY te.nombre, e.nombre;


-- =====================================================================
-- CONSULTA 22: Listar reservas activas en el día actual (CURDATE()).
-- =====================================================================
SELECT
    r.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    e.nombre AS espacio,
    r.fecha_inicio,
    r.fecha_fin,
    r.estado
FROM reservas r
INNER JOIN usuarios u ON u.id_usuario = r.id_usuario
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE r.estado IN ('Pendiente de Confirmación', 'Confirmada')
  AND r.fecha_inicio <  DATE_ADD(CURDATE(), INTERVAL 1 DAY)
  AND r.fecha_fin    >= CURDATE()
ORDER BY r.fecha_inicio;


-- =====================================================================
-- CONSULTA 23: Mostrar reservas canceladas en el último mes.
-- (el esquema no guarda la fecha de cancelación; se usa la fecha de la
--  reserva como referencia)
-- =====================================================================
SELECT
    r.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    e.nombre AS espacio,
    r.fecha_inicio,
    r.fecha_fin,
    r.fecha_creacion,
    r.estado
FROM reservas r
INNER JOIN usuarios u ON u.id_usuario = r.id_usuario
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE r.estado = 'Cancelada'
  AND r.fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
ORDER BY r.fecha_inicio DESC;


-- =====================================================================
-- CONSULTA 24: Listar reservas de salas de reuniones en horario pico
-- (09:00:00 - 11:00:00).
-- (reservas que se cruzan con la franja pico dentro de un mismo día)
-- =====================================================================
SELECT
    r.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    e.nombre AS sala,
    r.fecha_inicio,
    r.fecha_fin,
    r.estado
FROM reservas r
INNER JOIN usuarios u ON u.id_usuario = r.id_usuario
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
INNER JOIN tipos_espacio te ON te.id_tipo_espacio = e.id_tipo_espacio
WHERE te.nombre = 'Salas de reuniones'
  AND DATE(r.fecha_inicio) = DATE(r.fecha_fin)
  AND TIME(r.fecha_inicio) < '11:00:00'
  AND TIME(r.fecha_fin)    > '09:00:00'
ORDER BY r.fecha_inicio;


-- =====================================================================
-- CONSULTA 25: Contar cuántas reservas se hacen por cada tipo de espacio.
-- =====================================================================
SELECT
    te.id_tipo_espacio,
    te.nombre AS tipo_espacio,
    COUNT(r.id_reserva) AS total_reservas
FROM tipos_espacio te
LEFT JOIN espacios e ON e.id_tipo_espacio = te.id_tipo_espacio
LEFT JOIN reservas r ON r.id_espacio = e.id_espacio
GROUP BY te.id_tipo_espacio, te.nombre
ORDER BY total_reservas DESC;


-- =====================================================================
-- CONSULTA 26: Mostrar el espacio más reservado del último mes.
-- (se excluyen reservas canceladas; en caso de empate se muestran todos)
-- =====================================================================
WITH conteo_espacios AS (
    SELECT
        e.id_espacio,
        e.nombre AS espacio,
        COUNT(r.id_reserva) AS total_reservas
    FROM espacios e
    INNER JOIN reservas r ON r.id_espacio = e.id_espacio
    WHERE r.estado <> 'Cancelada'
      AND r.fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
      AND r.fecha_inicio <  DATE_ADD(CURDATE(), INTERVAL 1 DAY)
    GROUP BY e.id_espacio, e.nombre
)
SELECT
    ce.id_espacio,
    ce.espacio,
    ce.total_reservas
FROM conteo_espacios ce
WHERE ce.total_reservas = (SELECT MAX(total_reservas) FROM conteo_espacios);


-- =====================================================================
-- CONSULTA 27: Listar usuarios que más han reservado salas privadas.
-- (salas privadas = tipo de espacio 'Oficinas privadas'; top 10)
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    COUNT(r.id_reserva) AS reservas_oficinas_privadas
FROM usuarios u
INNER JOIN reservas r ON r.id_usuario = u.id_usuario
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
INNER JOIN tipos_espacio te ON te.id_tipo_espacio = e.id_tipo_espacio
WHERE te.nombre = 'Oficinas privadas'
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email
ORDER BY reservas_oficinas_privadas DESC, u.id_usuario
LIMIT 10;


-- =====================================================================
-- CONSULTA 28: Mostrar reservas que exceden la capacidad máxima del espacio.
-- (el esquema no registra número de asistentes; se cuentan las reservas
--  activas simultáneas en el mismo espacio y se comparan con capacidad_maxima)
-- =====================================================================
SELECT
    r1.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    e.nombre AS espacio,
    e.capacidad_maxima,
    r1.fecha_inicio,
    r1.fecha_fin,
    COUNT(r2.id_reserva) AS reservas_simultaneas,
    COUNT(r2.id_reserva) - e.capacidad_maxima AS exceso
FROM reservas r1
INNER JOIN usuarios u ON u.id_usuario = r1.id_usuario
INNER JOIN espacios e ON e.id_espacio = r1.id_espacio
INNER JOIN reservas r2
        ON r2.id_espacio = r1.id_espacio
       AND r2.estado IN ('Pendiente de Confirmación', 'Confirmada')
       AND r2.fecha_inicio < r1.fecha_fin
       AND r2.fecha_fin    > r1.fecha_inicio
WHERE r1.estado IN ('Pendiente de Confirmación', 'Confirmada')
GROUP BY r1.id_reserva, u.nombre, u.apellidos, e.nombre, e.capacidad_maxima,
         r1.fecha_inicio, r1.fecha_fin
HAVING COUNT(r2.id_reserva) > e.capacidad_maxima
ORDER BY r1.fecha_inicio, r1.id_reserva;


-- =====================================================================
-- CONSULTA 29: Listar espacios que no se han reservado en la última semana.
-- (se ignoran reservas canceladas)
-- =====================================================================
SELECT
    e.id_espacio,
    e.nombre AS espacio,
    te.nombre AS tipo_espacio,
    e.estado
FROM espacios e
INNER JOIN tipos_espacio te ON te.id_tipo_espacio = e.id_tipo_espacio
WHERE NOT EXISTS (
    SELECT 1
    FROM reservas r
    WHERE r.id_espacio = e.id_espacio
      AND r.estado <> 'Cancelada'
      AND r.fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      AND r.fecha_inicio <  DATE_ADD(CURDATE(), INTERVAL 1 DAY)
)
ORDER BY te.nombre, e.nombre;


-- =====================================================================
-- CONSULTA 30: Calcular la tasa de ocupación promedio de cada espacio.
-- (horas de reservas 'Confirmada' de los últimos @dias_periodo días sobre
--  las horas operativas del espacio en el mismo periodo)
-- =====================================================================
SELECT
    e.id_espacio,
    e.nombre AS espacio,
    ROUND(COALESCE(SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60, 0), 2) AS horas_reservadas,
    ROUND(TIME_TO_SEC(TIMEDIFF(e.hora_cierre, e.hora_apertura)) / 3600 * @dias_periodo, 2) AS horas_disponibles,
    ROUND(
        COALESCE(SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60, 0)
        / (TIME_TO_SEC(TIMEDIFF(e.hora_cierre, e.hora_apertura)) / 3600 * @dias_periodo) * 100,
        2
    ) AS tasa_ocupacion_pct
FROM espacios e
LEFT JOIN reservas r
       ON r.id_espacio = e.id_espacio
      AND r.estado = 'Confirmada'
      AND r.fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL @dias_periodo DAY)
      AND r.fecha_inicio <  DATE_ADD(CURDATE(), INTERVAL 1 DAY)
GROUP BY e.id_espacio, e.nombre, e.hora_apertura, e.hora_cierre
ORDER BY tasa_ocupacion_pct DESC;


-- =====================================================================
-- CONSULTA 31: Mostrar reservas de más de 8 horas de duración.
-- =====================================================================
SELECT
    r.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    e.nombre AS espacio,
    r.fecha_inicio,
    r.fecha_fin,
    ROUND(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin) / 60, 2) AS duracion_horas,
    r.estado
FROM reservas r
INNER JOIN usuarios u ON u.id_usuario = r.id_usuario
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin) > 8 * 60
ORDER BY duracion_horas DESC;


-- =====================================================================
-- CONSULTA 32: Identificar usuarios con más de 20 reservas en total.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    COUNT(r.id_reserva) AS total_reservas
FROM usuarios u
INNER JOIN reservas r ON r.id_usuario = u.id_usuario
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email
HAVING COUNT(r.id_reserva) > 20
ORDER BY total_reservas DESC;


-- =====================================================================
-- CONSULTA 33: Mostrar reservas realizadas por empresas con más de 10
-- empleados.
-- =====================================================================
SELECT
    emp.nombre AS empresa,
    r.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    e.nombre AS espacio,
    r.fecha_inicio,
    r.fecha_fin,
    r.estado
FROM reservas r
INNER JOIN usuarios u ON u.id_usuario = r.id_usuario
INNER JOIN empresas emp ON emp.id_empresa = u.id_empresa
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE emp.id_empresa IN (
    SELECT u2.id_empresa
    FROM usuarios u2
    WHERE u2.id_empresa IS NOT NULL
    GROUP BY u2.id_empresa
    HAVING COUNT(u2.id_usuario) > 10
)
ORDER BY emp.nombre, r.fecha_inicio;


-- =====================================================================
-- CONSULTA 34: Listar reservas que se solapan en horario.
-- (pares de reservas activas del mismo espacio cuyos horarios se cruzan)
-- =====================================================================
SELECT
    e.nombre AS espacio,
    r1.id_reserva AS reserva_a,
    r1.fecha_inicio AS inicio_a,
    r1.fecha_fin AS fin_a,
    r2.id_reserva AS reserva_b,
    r2.fecha_inicio AS inicio_b,
    r2.fecha_fin AS fin_b
FROM reservas r1
INNER JOIN reservas r2
        ON r2.id_espacio = r1.id_espacio
       AND r2.id_reserva > r1.id_reserva
       AND r2.fecha_inicio < r1.fecha_fin
       AND r2.fecha_fin    > r1.fecha_inicio
INNER JOIN espacios e ON e.id_espacio = r1.id_espacio
WHERE r1.estado IN ('Pendiente de Confirmación', 'Confirmada')
  AND r2.estado IN ('Pendiente de Confirmación', 'Confirmada')
ORDER BY e.nombre, r1.fecha_inicio, r1.id_reserva, r2.id_reserva;


-- =====================================================================
-- CONSULTA 35: Listar reservas de fin de semana (DAYOFWEEK).
-- (DAYOFWEEK: 1 = domingo, 7 = sábado)
-- =====================================================================
SELECT
    r.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    e.nombre AS espacio,
    r.fecha_inicio,
    r.fecha_fin,
    DAYNAME(r.fecha_inicio) AS dia_semana,
    r.estado
FROM reservas r
INNER JOIN usuarios u ON u.id_usuario = r.id_usuario
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE DAYOFWEEK(r.fecha_inicio) IN (1, 7)
ORDER BY r.fecha_inicio;


-- =====================================================================
-- CONSULTA 36: Mostrar el porcentaje de ocupación por cada tipo de espacio.
-- (horas de reservas 'Confirmada' de los últimos @dias_periodo días sobre
--  las horas operativas de todos los espacios del tipo)
-- =====================================================================
WITH horas_por_espacio AS (
    SELECT
        e.id_espacio,
        e.id_tipo_espacio,
        TIME_TO_SEC(TIMEDIFF(e.hora_cierre, e.hora_apertura)) / 3600 * @dias_periodo AS horas_disponibles,
        COALESCE(SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60, 0) AS horas_reservadas
    FROM espacios e
    LEFT JOIN reservas r
           ON r.id_espacio = e.id_espacio
          AND r.estado = 'Confirmada'
          AND r.fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL @dias_periodo DAY)
          AND r.fecha_inicio <  DATE_ADD(CURDATE(), INTERVAL 1 DAY)
    GROUP BY e.id_espacio, e.id_tipo_espacio, e.hora_apertura, e.hora_cierre
)
SELECT
    te.id_tipo_espacio,
    te.nombre AS tipo_espacio,
    COUNT(h.id_espacio) AS total_espacios,
    ROUND(COALESCE(SUM(h.horas_reservadas), 0), 2) AS horas_reservadas,
    ROUND(COALESCE(SUM(h.horas_disponibles), 0), 2) AS horas_disponibles,
    ROUND(COALESCE(SUM(h.horas_reservadas) / NULLIF(SUM(h.horas_disponibles), 0) * 100, 0), 2) AS porcentaje_ocupacion
FROM tipos_espacio te
LEFT JOIN horas_por_espacio h ON h.id_tipo_espacio = te.id_tipo_espacio
GROUP BY te.id_tipo_espacio, te.nombre
ORDER BY porcentaje_ocupacion DESC;


-- =====================================================================
-- CONSULTA 37: Mostrar la duración promedio de reservas por tipo de espacio.
-- (se excluyen reservas canceladas)
-- =====================================================================
SELECT
    te.id_tipo_espacio,
    te.nombre AS tipo_espacio,
    COUNT(r.id_reserva) AS total_reservas,
    ROUND(AVG(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60, 2) AS duracion_promedio_horas
FROM tipos_espacio te
LEFT JOIN espacios e ON e.id_tipo_espacio = te.id_tipo_espacio
LEFT JOIN reservas r
       ON r.id_espacio = e.id_espacio
      AND r.estado <> 'Cancelada'
GROUP BY te.id_tipo_espacio, te.nombre
ORDER BY duracion_promedio_horas DESC;


-- =====================================================================
-- CONSULTA 38: Mostrar reservas con servicios adicionales incluidos.
-- =====================================================================
SELECT
    r.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    e.nombre AS espacio,
    r.fecha_inicio,
    r.estado,
    GROUP_CONCAT(CONCAT(s.nombre, ' x', rs.cantidad) ORDER BY s.nombre SEPARATOR ', ') AS servicios_incluidos,
    SUM(rs.cantidad * s.costo) AS costo_servicios
FROM reservas r
INNER JOIN reserva_servicios rs ON rs.id_reserva = r.id_reserva
INNER JOIN servicios_adicionales s ON s.id_servicio = rs.id_servicio
INNER JOIN usuarios u ON u.id_usuario = r.id_usuario
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
GROUP BY r.id_reserva, u.nombre, u.apellidos, e.nombre, r.fecha_inicio, r.estado
ORDER BY r.fecha_inicio DESC;


-- =====================================================================
-- CONSULTA 39: Listar usuarios que reservaron sala de eventos en los
-- últimos 6 meses.
-- (se excluyen reservas canceladas y reservas futuras)
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    COUNT(r.id_reserva) AS reservas_eventos,
    MAX(r.fecha_inicio) AS ultima_reserva_evento
FROM usuarios u
INNER JOIN reservas r ON r.id_usuario = u.id_usuario
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
INNER JOIN tipos_espacio te ON te.id_tipo_espacio = e.id_tipo_espacio
WHERE te.nombre = 'Salas de eventos'
  AND r.estado <> 'Cancelada'
  AND r.fecha_inicio BETWEEN DATE_SUB(CURDATE(), INTERVAL 6 MONTH) AND NOW()
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email
ORDER BY ultima_reserva_evento DESC;


-- =====================================================================
-- CONSULTA 40: Identificar reservas realizadas y nunca asistidas.
-- (reservas ya finalizadas, 'Confirmada' o 'No Show', con asistio = FALSE
--  y sin un acceso exitoso del usuario ese mismo día)
-- =====================================================================
SELECT
    r.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    e.nombre AS espacio,
    r.fecha_inicio,
    r.fecha_fin,
    r.estado,
    r.asistio
FROM reservas r
INNER JOIN usuarios u ON u.id_usuario = r.id_usuario
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE r.estado IN ('Confirmada', 'No Show')
  AND r.asistio = FALSE
  AND r.fecha_fin < NOW()
  AND NOT EXISTS (
      SELECT 1
      FROM registros_acceso ra
      WHERE ra.id_usuario = r.id_usuario
        AND ra.estado_validacion = 'Exitoso'
        AND ra.fecha_hora_entrada >= DATE(r.fecha_inicio)
        AND ra.fecha_hora_entrada <  DATE_ADD(DATE(r.fecha_inicio), INTERVAL 1 DAY)
  )
ORDER BY r.fecha_inicio DESC;