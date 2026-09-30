/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Consultas - Accesos y Asistencias
Archivo: sql/02_consultas/04_accesos_asistencias.sql
Consultas: 61 a 80

Criterios generales:
- "Asistencia" = registro en registros_acceso con estado_validacion = 'Exitoso'.
- Para aprovechar idx_accesos_usuario se filtran rangos sobre fecha_hora_entrada
  (>= / <) en lugar de envolver la columna en DATE() cuando es posible.
- Semana: WEEKDAY() devuelve 0 = lunes ... 6 = domingo (fin de semana = 5 y 6).
*/

USE coworking_db;

-- =========================================================
-- 61. Listar todos los accesos registrados hoy.
-- =========================================================
SELECT
    ra.id_acceso,
    u.identificacion,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    ra.fecha_hora_entrada,
    ra.fecha_hora_salida,
    ra.metodo_acceso,
    ra.estado_validacion,
    ra.motivo_rechazo
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.fecha_hora_entrada >= CURDATE()
  AND ra.fecha_hora_entrada <  CURDATE() + INTERVAL 1 DAY
ORDER BY ra.fecha_hora_entrada;

-- =========================================================
-- 62. Mostrar usuarios con más de 20 asistencias en el mes.
--     (Mes en curso; se cuentan días distintos con acceso exitoso.)
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    COUNT(DISTINCT DATE(ra.fecha_hora_entrada)) AS dias_asistidos
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.estado_validacion = 'Exitoso'
  AND ra.fecha_hora_entrada >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
  AND ra.fecha_hora_entrada <  DATE_FORMAT(CURDATE(), '%Y-%m-01') + INTERVAL 1 MONTH
GROUP BY u.id_usuario, u.nombre, u.apellidos
HAVING COUNT(DISTINCT DATE(ra.fecha_hora_entrada)) > 20
ORDER BY dias_asistidos DESC;

-- =========================================================
-- 63. Mostrar usuarios que no asistieron en la última semana.
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    (SELECT MAX(ra2.fecha_hora_entrada)
       FROM registros_acceso ra2
      WHERE ra2.id_usuario = u.id_usuario
        AND ra2.estado_validacion = 'Exitoso') AS ultima_asistencia
FROM usuarios u
WHERE NOT EXISTS (
    SELECT 1
    FROM registros_acceso ra
    WHERE ra.id_usuario = u.id_usuario
      AND ra.estado_validacion = 'Exitoso'
      AND ra.fecha_hora_entrada >= NOW() - INTERVAL 7 DAY
)
ORDER BY ultima_asistencia;

-- =========================================================
-- 64. Calcular la asistencia promedio por día de la semana.
--     (Primero se cuentan accesos por fecha; luego se promedia por día de semana.)
-- =========================================================
SELECT
    t.num_dia,
    ELT(t.num_dia + 1, 'Lunes', 'Martes', 'Miércoles', 'Jueves',
                       'Viernes', 'Sábado', 'Domingo') AS dia_semana,
    COUNT(*)                   AS fechas_con_actividad,
    ROUND(AVG(t.asistencias), 2) AS promedio_asistencias
FROM (
    SELECT
        DATE(fecha_hora_entrada)    AS fecha,
        WEEKDAY(fecha_hora_entrada) AS num_dia,
        COUNT(*)                    AS asistencias
    FROM registros_acceso
    WHERE estado_validacion = 'Exitoso'
    GROUP BY DATE(fecha_hora_entrada), WEEKDAY(fecha_hora_entrada)
) t
GROUP BY t.num_dia
ORDER BY t.num_dia;

-- =========================================================
-- 65. Mostrar los 10 usuarios más constantes (más asistencias registradas).
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    COUNT(*)                                    AS total_asistencias,
    COUNT(DISTINCT DATE(ra.fecha_hora_entrada)) AS dias_distintos
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.estado_validacion = 'Exitoso'
GROUP BY u.id_usuario, u.nombre, u.apellidos
ORDER BY total_asistencias DESC, dias_distintos DESC
LIMIT 10;

-- =========================================================
-- 66. Mostrar accesos fuera del horario permitido.
--     Límites del coworking = apertura más temprana y cierre más tardío
--     entre los espacios que no están inactivos.
-- =========================================================
SELECT
    ra.id_acceso,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    ra.fecha_hora_entrada,
    ra.fecha_hora_salida,
    ra.metodo_acceso,
    ra.estado_validacion,
    h.apertura_coworking,
    h.cierre_coworking
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
CROSS JOIN (
    SELECT MIN(hora_apertura) AS apertura_coworking,
           MAX(hora_cierre)   AS cierre_coworking
    FROM espacios
    WHERE estado <> 'Inactivo'
) h
WHERE TIME(ra.fecha_hora_entrada) < h.apertura_coworking
   OR TIME(ra.fecha_hora_entrada) > h.cierre_coworking
ORDER BY ra.fecha_hora_entrada DESC;

-- =========================================================
-- 67. Mostrar usuarios que accedieron sin membresía activa.
--     Incluye accesos rechazados y accesos cuya fecha no estaba cubierta
--     por ninguna membresía vigente.
-- =========================================================
SELECT
    ra.id_acceso,
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    ra.fecha_hora_entrada,
    ra.metodo_acceso,
    ra.estado_validacion,
    ra.motivo_rechazo,
    CASE
        WHEN ra.estado_validacion = 'Rechazado' THEN 'Rechazado en validación'
        ELSE 'Acceso exitoso sin membresía vigente'
    END AS situacion
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.estado_validacion = 'Rechazado'
   OR NOT EXISTS (
        SELECT 1
        FROM membresias m
        WHERE m.id_usuario = ra.id_usuario
          AND m.estado = 'Activa'
          AND ra.fecha_hora_entrada BETWEEN m.fecha_inicio AND m.fecha_vencimiento
   )
ORDER BY ra.fecha_hora_entrada DESC;

-- =========================================================
-- 68. Listar usuarios que solo acceden los fines de semana.
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    COUNT(*) AS total_accesos,
    MIN(ra.fecha_hora_entrada) AS primer_acceso,
    MAX(ra.fecha_hora_entrada) AS ultimo_acceso
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.estado_validacion = 'Exitoso'
GROUP BY u.id_usuario, u.nombre, u.apellidos
HAVING SUM(WEEKDAY(ra.fecha_hora_entrada) < 5) = 0
ORDER BY total_accesos DESC;

-- =========================================================
-- 69. Mostrar usuarios que accedieron más de 2 veces en el mismo día.
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    DATE(ra.fecha_hora_entrada) AS fecha,
    COUNT(*) AS accesos_del_dia
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.estado_validacion = 'Exitoso'
GROUP BY u.id_usuario, u.nombre, u.apellidos, DATE(ra.fecha_hora_entrada)
HAVING COUNT(*) > 2
ORDER BY accesos_del_dia DESC, fecha DESC;

-- =========================================================
-- 70. Mostrar el total de accesos diarios en el último mes.
-- =========================================================
SELECT
    DATE(fecha_hora_entrada) AS fecha,
    COUNT(*)                                  AS total_accesos,
    SUM(estado_validacion = 'Exitoso')        AS exitosos,
    SUM(estado_validacion = 'Rechazado')      AS rechazados
FROM registros_acceso
WHERE fecha_hora_entrada >= CURDATE() - INTERVAL 1 MONTH
GROUP BY DATE(fecha_hora_entrada)
ORDER BY fecha;

-- =========================================================
-- 71. Mostrar usuarios que han accedido pero no tienen reservas.
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    COUNT(ra.id_acceso) AS total_accesos
FROM usuarios u
INNER JOIN registros_acceso ra ON ra.id_usuario = u.id_usuario
WHERE ra.estado_validacion = 'Exitoso'
  AND NOT EXISTS (
        SELECT 1 FROM reservas r WHERE r.id_usuario = u.id_usuario
  )
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email
ORDER BY total_accesos DESC;

-- =========================================================
-- 72. Mostrar los días con más concurrencia en el coworking.
-- =========================================================
SELECT
    DATE(fecha_hora_entrada)          AS fecha,
    ELT(WEEKDAY(fecha_hora_entrada) + 1, 'Lunes', 'Martes', 'Miércoles',
        'Jueves', 'Viernes', 'Sábado', 'Domingo') AS dia_semana,
    COUNT(DISTINCT id_usuario)        AS usuarios_distintos,
    COUNT(*)                          AS total_accesos
FROM registros_acceso
WHERE estado_validacion = 'Exitoso'
GROUP BY DATE(fecha_hora_entrada), WEEKDAY(fecha_hora_entrada)
ORDER BY usuarios_distintos DESC, total_accesos DESC
LIMIT 10;

-- =========================================================
-- 73. Mostrar usuarios que entraron pero no registraron salida.
-- =========================================================
SELECT
    ra.id_acceso,
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    ra.fecha_hora_entrada,
    ra.metodo_acceso,
    TIMESTAMPDIFF(HOUR, ra.fecha_hora_entrada, NOW()) AS horas_desde_entrada
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.estado_validacion = 'Exitoso'
  AND ra.fecha_hora_salida IS NULL
ORDER BY ra.fecha_hora_entrada;

-- =========================================================
-- 74. Mostrar accesos de usuarios con membresía vencida.
--     (Acceso sin membresía vigente en esa fecha, y con alguna membresía
--      ya vencida antes del acceso.)
-- =========================================================
SELECT
    ra.id_acceso,
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    ra.fecha_hora_entrada,
    ra.estado_validacion,
    (SELECT MAX(m.fecha_vencimiento)
       FROM membresias m
      WHERE m.id_usuario = u.id_usuario
        AND m.fecha_vencimiento < ra.fecha_hora_entrada) AS vencimiento_membresia
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE EXISTS (
        SELECT 1 FROM membresias m
        WHERE m.id_usuario = ra.id_usuario
          AND m.fecha_vencimiento < ra.fecha_hora_entrada
    )
  AND NOT EXISTS (
        SELECT 1 FROM membresias m2
        WHERE m2.id_usuario = ra.id_usuario
          AND ra.fecha_hora_entrada BETWEEN m2.fecha_inicio AND m2.fecha_vencimiento
    )
ORDER BY ra.fecha_hora_entrada DESC;

-- =========================================================
-- 75. Mostrar accesos de usuarios corporativos por empresa.
-- =========================================================
SELECT
    e.id_empresa,
    e.nombre AS empresa,
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    COUNT(ra.id_acceso)                AS total_accesos,
    MAX(ra.fecha_hora_entrada)         AS ultimo_acceso
FROM empresas e
INNER JOIN usuarios u ON u.id_empresa = e.id_empresa
LEFT JOIN registros_acceso ra
       ON ra.id_usuario = u.id_usuario
      AND ra.estado_validacion = 'Exitoso'
GROUP BY e.id_empresa, e.nombre, u.id_usuario, u.nombre, u.apellidos
ORDER BY e.nombre, total_accesos DESC;

-- =========================================================
-- 76. Mostrar clientes que nunca han usado el coworking a pesar de pagar
--     membresía (0 accesos registrados).
-- =========================================================
SELECT DISTINCT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    m.id_membresia,
    tm.nombre AS tipo_membresia,
    m.fecha_inicio,
    m.fecha_vencimiento
FROM usuarios u
INNER JOIN membresias m        ON m.id_usuario = u.id_usuario
INNER JOIN tipos_membresia tm  ON tm.id_tipo_membresia = m.id_tipo_membresia
INNER JOIN facturas f          ON f.id_membresia = m.id_membresia
                              AND f.estado = 'Pagada'
WHERE NOT EXISTS (
    SELECT 1 FROM registros_acceso ra WHERE ra.id_usuario = u.id_usuario
)
ORDER BY u.id_usuario;

-- =========================================================
-- 77. Mostrar accesos rechazados por intentos con QR inválido.
-- =========================================================
SELECT
    ra.id_acceso,
    ra.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    ra.fecha_hora_entrada AS fecha_intento,
    ra.metodo_acceso,
    ra.motivo_rechazo
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.estado_validacion = 'Rechazado'
  AND ra.metodo_acceso = 'QR'
  AND (ra.motivo_rechazo LIKE '%QR%' OR ra.motivo_rechazo LIKE '%inv_lido%')
ORDER BY ra.fecha_hora_entrada DESC;

-- =========================================================
-- 78. Mostrar accesos promedio por usuario.
-- =========================================================
SELECT
    ROUND(AVG(t.accesos), 2) AS promedio_usuarios_con_acceso,
    ROUND(SUM(t.accesos) / (SELECT COUNT(*) FROM usuarios), 2) AS promedio_todos_los_usuarios,
    SUM(t.accesos)           AS total_accesos,
    COUNT(*)                 AS usuarios_con_acceso
FROM (
    SELECT id_usuario, COUNT(*) AS accesos
    FROM registros_acceso
    WHERE estado_validacion = 'Exitoso'
    GROUP BY id_usuario
) t;

-- =========================================================
-- 79. Identificar usuarios que asisten más en la mañana (antes de las 12:00:00).
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    SUM(TIME(ra.fecha_hora_entrada) < '12:00:00')  AS accesos_manana,
    SUM(TIME(ra.fecha_hora_entrada) >= '12:00:00') AS accesos_resto_dia,
    COUNT(*)                                        AS total_accesos
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.estado_validacion = 'Exitoso'
GROUP BY u.id_usuario, u.nombre, u.apellidos
HAVING SUM(TIME(ra.fecha_hora_entrada) < '12:00:00')
     > SUM(TIME(ra.fecha_hora_entrada) >= '12:00:00')
ORDER BY accesos_manana DESC;

-- =========================================================
-- 80. Identificar usuarios que asisten más en la noche (después de las 18:00:00).
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    SUM(TIME(ra.fecha_hora_entrada) > '18:00:00')  AS accesos_noche,
    SUM(TIME(ra.fecha_hora_entrada) <= '18:00:00') AS accesos_resto_dia,
    COUNT(*)                                        AS total_accesos
FROM registros_acceso ra
INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
WHERE ra.estado_validacion = 'Exitoso'
GROUP BY u.id_usuario, u.nombre, u.apellidos
HAVING SUM(TIME(ra.fecha_hora_entrada) > '18:00:00')
     > SUM(TIME(ra.fecha_hora_entrada) <= '18:00:00')
ORDER BY accesos_noche DESC;