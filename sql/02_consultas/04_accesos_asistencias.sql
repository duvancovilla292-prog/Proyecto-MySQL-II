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
    DATE(fecha_hora_entrada) AS fecha,
    ELT(WEEKDAY(fecha_hora_entrada) + 1, 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo') AS dia_semana,
    COUNT(DISTINCT id_usuario) AS usuarios_distintos,
    COUNT(*) AS total_accesos
FROM registros_acceso
WHERE estado_validacion = 'Exitoso'
GROUP BY DATE(fecha_hora_entrada), dia_semana
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

-- =====================================================================
-- DATOS ADICIONALES PARA LA CONSULTA 61 (accesos del 2026-10-01)
-- =====================================================================
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, fecha_hora_salida, metodo_acceso, estado_validacion, motivo_rechazo) VALUES
(1,  '2026-10-01 07:58:00', NULL, 'QR',   'Exitoso',   NULL),
(2,  '2026-10-01 08:32:00', NULL, 'RFID', 'Exitoso',   NULL),
(3,  '2026-10-01 08:15:00', NULL, 'RFID', 'Exitoso',   NULL),
(4,  '2026-10-01 09:02:00', NULL, 'QR',   'Exitoso',   NULL),
(12, '2026-10-01 07:50:00', NULL, 'RFID', 'Exitoso',   NULL),
(9,  '2026-10-01 08:30:00', NULL, 'QR',   'Rechazado', 'Membresía Vencida'),
(6,  '2026-10-01 08:45:00', NULL, 'RFID', 'Rechazado', 'Membresía Vencida'),
(13, '2026-10-01 09:10:00', NULL, 'QR',   'Rechazado', 'Membresía Suspendida');


-- =====================================================================
-- DATOS ADICIONALES PARA LA CONSULTA 62 (mes en curso: octubre 2026)
-- Usuarios con más de 20 asistencias exitosas en el mes
-- =====================================================================

-- Usuario 1: 22 días hábiles de octubre (QR)
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, fecha_hora_salida, metodo_acceso, estado_validacion, motivo_rechazo)
WITH RECURSIVE dias AS (
    SELECT DATE('2026-10-01') AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM dias WHERE d < DATE('2026-10-31')
)
SELECT 1, TIMESTAMP(d, '08:00:00'),
       CASE WHEN d = DATE('2026-10-01') THEN NULL ELSE TIMESTAMP(d, '17:30:00') END,
       'QR', 'Exitoso', NULL
FROM dias
WHERE DAYOFWEEK(d) BETWEEN 2 AND 6;

-- Usuario 2: 22 días hábiles de octubre (RFID)
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, fecha_hora_salida, metodo_acceso, estado_validacion, motivo_rechazo)
WITH RECURSIVE dias AS (
    SELECT DATE('2026-10-01') AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM dias WHERE d < DATE('2026-10-31')
)
SELECT 2, TIMESTAMP(d, '08:30:00'),
       CASE WHEN d = DATE('2026-10-01') THEN NULL ELSE TIMESTAMP(d, '18:00:00') END,
       'RFID', 'Exitoso', NULL
FROM dias
WHERE DAYOFWEEK(d) BETWEEN 2 AND 6;

-- Usuario 3: exactamente 20 días hábiles (1 al 28 de octubre). NO debe aparecer.
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, fecha_hora_salida, metodo_acceso, estado_validacion, motivo_rechazo)
WITH RECURSIVE dias AS (
    SELECT DATE('2026-10-01') AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM dias WHERE d < DATE('2026-10-28')
)
SELECT 3, TIMESTAMP(d, '08:15:00'),
       CASE WHEN d = DATE('2026-10-01') THEN NULL ELSE TIMESTAMP(d, '17:15:00') END,
       'RFID', 'Exitoso', NULL
FROM dias
WHERE DAYOFWEEK(d) BETWEEN 2 AND 6;

-- Usuario 4: 22 intentos en días hábiles, todos RECHAZADOS. NO debe aparecer.
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, fecha_hora_salida, metodo_acceso, estado_validacion, motivo_rechazo)
WITH RECURSIVE dias AS (
    SELECT DATE('2026-10-01') AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM dias WHERE d < DATE('2026-10-31')
)
SELECT 4, TIMESTAMP(d, '09:00:00'), NULL, 'QR', 'Rechazado', 'QR Inválido'
FROM dias
WHERE DAYOFWEEK(d) BETWEEN 2 AND 6;


-- =====================================================================
-- DATOS ADICIONALES PARA LA CONSULTA 66
-- Accesos fuera del horario permitido (antes de 06:00 o después de 23:00)
-- =====================================================================
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, fecha_hora_salida, metodo_acceso, estado_validacion, motivo_rechazo) VALUES
-- Membresías Premium (acceso 24/7): ingresos exitosos fuera de horario
(3,  '2026-09-26 05:30:00', '2026-09-26 08:00:00', 'RFID', 'Exitoso',   NULL),
(12, '2026-09-24 05:45:00', '2026-09-24 14:00:00', 'RFID', 'Exitoso',   NULL),
(4,  '2026-09-27 23:30:00', '2026-09-28 01:15:00', 'QR',   'Exitoso',   NULL),
(17, '2026-09-29 23:45:00', NULL,                  'QR',   'Exitoso',   NULL),
-- Membresías Mensual: intentos rechazados fuera de horario
(5,  '2026-09-21 05:50:00', NULL,                  'QR',   'Rechazado', 'Fuera de Horario'),
(8,  '2026-09-19 23:20:00', NULL,                  'RFID', 'Rechazado', 'Fuera de Horario'),
-- Casos límite que NO deben aparecer (exactamente en el borde del horario)
(12, '2026-09-23 06:00:00', '2026-09-23 15:00:00', 'RFID', 'Exitoso',   NULL),
(3,  '2026-09-22 23:00:00', '2026-09-22 23:30:00', 'RFID', 'Exitoso',   NULL);


-- =====================================================================
-- DATOS ADICIONALES PARA LA CONSULTA 69
-- Usuarios con más de 2 accesos exitosos en el mismo día
-- =====================================================================
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, fecha_hora_salida, metodo_acceso, estado_validacion, motivo_rechazo) VALUES
-- Usuario 7 (Corporativa): 4 ingresos exitosos el 2026-09-23
(7,  '2026-09-23 08:00:00', '2026-09-23 10:30:00', 'QR',   'Exitoso',   NULL),
(7,  '2026-09-23 11:15:00', '2026-09-23 13:00:00', 'QR',   'Exitoso',   NULL),
(7,  '2026-09-23 14:00:00', '2026-09-23 16:30:00', 'RFID', 'Exitoso',   NULL),
(7,  '2026-09-23 17:30:00', '2026-09-23 18:45:00', 'RFID', 'Exitoso',   NULL),
-- Usuario 10 (Mensual): 3 ingresos exitosos el 2026-09-24
(10, '2026-09-24 08:50:00', '2026-09-24 10:30:00', 'RFID', 'Exitoso',   NULL),
(10, '2026-09-24 12:00:00', '2026-09-24 13:30:00', 'RFID', 'Exitoso',   NULL),
(10, '2026-09-24 15:00:00', '2026-09-24 17:00:00', 'QR',   'Exitoso',   NULL),
-- Casos que NO deben aparecer
-- Usuario 5: exactamente 2 ingresos exitosos el 2026-09-24 (no supera el umbral)
(5,  '2026-09-24 09:00:00', '2026-09-24 11:30:00', 'QR',   'Exitoso',   NULL),
(5,  '2026-09-24 14:00:00', '2026-09-24 16:00:00', 'QR',   'Exitoso',   NULL),
-- Usuario 14: 3 intentos el 2026-09-23, pero solo 2 exitosos y 1 rechazado
(14, '2026-09-23 09:00:00', '2026-09-23 12:00:00', 'QR',   'Exitoso',   NULL),
(14, '2026-09-23 13:00:00', '2026-09-23 17:00:00', 'QR',   'Exitoso',   NULL),
(14, '2026-09-23 18:30:00', NULL,                  'QR',   'Rechazado', 'QR Inválido');


-- =====================================================================
-- DATOS ADICIONALES PARA LA CONSULTA 71
-- Usuarios con accesos exitosos y sin reservas
-- =====================================================================

-- Usuarios nuevos (31 y 32 deben aparecer; 33 no)
INSERT INTO usuarios (id_usuario, id_empresa, identificacion, nombre, apellidos, fecha_nacimiento, email, telefono, fecha_registro) VALUES
(31, NULL, '1098100031', 'Mauricio', 'Londoño', '1990-06-15', 'mauricio.londono@gmail.com', '3107770031', '2026-09-14 10:00:00'),
(32, NULL, '1098100032', 'Carolina', 'Vélez',   '1994-11-03', 'carolina.velez@outlook.com', '3107770032', '2026-09-21 09:30:00'),
(33, NULL, '1098100033', 'Jorge',    'Ramírez', '1988-01-28', 'jorge.ramirez@hotmail.com', '3107770033', '2026-09-09 11:00:00');

-- Membresías
INSERT INTO membresias (id_membresia, id_usuario, id_tipo_membresia, fecha_inicio, fecha_vencimiento, estado, renovaciones) VALUES
(33, 31, 2, '2026-09-14 10:30:00', '2026-10-14 10:30:00', 'Activa',  0),
(34, 32, 4, '2026-09-21 09:45:00', '2026-10-21 09:45:00', 'Activa',  0),
(35, 33, 1, '2026-09-09 08:00:00', '2026-09-10 08:00:00', 'Vencida', 0);

-- Facturas de las membresías de los usuarios 31 y 32
INSERT INTO facturas (id_factura, id_usuario, id_membresia, id_reserva, monto_total, saldo_pendiente, estado, motivo_anulacion, fecha_emision, fecha_vencimiento) VALUES
(55, 31, 33, NULL, 350.00, 0.00, 'Pagada', NULL, '2026-09-14 10:35:00', '2026-09-29 23:59:59'),
(56, 32, 34, NULL, 650.00, 0.00, 'Pagada', NULL, '2026-09-21 09:50:00', '2026-10-06 23:59:59');

INSERT INTO detalle_facturas (id_factura, id_servicio, descripcion, cantidad, precio_unitario) VALUES
(55, NULL, 'Membresía Mensual - septiembre 2026', 1, 350.00),
(56, NULL, 'Membresía Premium - septiembre 2026', 1, 650.00);

INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion, fecha_pago) VALUES
(55, 'Tarjeta',        350.00, 'Pagado', '2026-09-14 10:40:00'),
(56, 'Transferencia',  650.00, 'Pagado', '2026-09-21 10:00:00');

-- Accesos (ninguno de estos usuarios tiene reservas)
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, fecha_hora_salida, metodo_acceso, estado_validacion, motivo_rechazo) VALUES
-- Usuario 31: 3 accesos exitosos
(31, '2026-09-15 09:00:00', '2026-09-15 17:30:00', 'QR',   'Exitoso',   NULL),
(31, '2026-09-16 09:05:00', '2026-09-16 17:00:00', 'QR',   'Exitoso',   NULL),
(31, '2026-09-17 08:55:00', '2026-09-17 16:45:00', 'QR',   'Exitoso',   NULL),
-- Usuario 32: 2 accesos exitosos y 1 rechazado (el rechazado no cuenta)
(32, '2026-09-22 08:30:00', '2026-09-22 18:00:00', 'RFID', 'Exitoso',   NULL),
(32, '2026-09-23 08:40:00', '2026-09-23 17:50:00', 'RFID', 'Exitoso',   NULL),
(32, '2026-09-24 08:35:00', NULL,                  'QR',   'Rechazado', 'QR Inválido'),
-- Usuario 33: solo un intento rechazado, no debe aparecer
(33, '2026-09-20 08:30:00', NULL,                  'RFID', 'Rechazado', 'Membresía Vencida');


-- =====================================================================
-- DATOS ADICIONALES PARA LA CONSULTA 76
-- Clientes con membresía pagada y 0 accesos registrados
-- =====================================================================

INSERT INTO usuarios (id_usuario, id_empresa, identificacion, nombre, apellidos, fecha_nacimiento, email, telefono, fecha_registro) VALUES
(34, NULL, '1098100034', 'Ana María', 'Calderón', '1991-04-09', 'anamaria.calderon@gmail.com', '3107770034', '2026-09-10 09:00:00'),
(35, NULL, '1098100035', 'Pedro',     'Villamil', '1986-08-21', 'pedro.villamil@outlook.com',  '3107770035', '2026-08-03 10:00:00');

-- Usuario 34: una membresía. Usuario 35: dos membresías (agosto vencida y septiembre activa)
INSERT INTO membresias (id_membresia, id_usuario, id_tipo_membresia, fecha_inicio, fecha_vencimiento, estado, renovaciones) VALUES
(36, 34, 2, '2026-09-10 09:30:00', '2026-10-10 09:30:00', 'Activa',  0),
(37, 35, 2, '2026-08-03 10:30:00', '2026-09-02 10:30:00', 'Vencida', 0),
(38, 35, 2, '2026-09-03 10:30:00', '2026-10-03 10:30:00', 'Activa',  1);

INSERT INTO facturas (id_factura, id_usuario, id_membresia, id_reserva, monto_total, saldo_pendiente, estado, motivo_anulacion, fecha_emision, fecha_vencimiento) VALUES
(57, 34, 36, NULL, 350.00, 0.00, 'Pagada', NULL, '2026-09-10 09:35:00', '2026-09-25 23:59:59'),
(58, 35, 37, NULL, 350.00, 0.00, 'Pagada', NULL, '2026-08-03 10:35:00', '2026-08-18 23:59:59'),
(59, 35, 38, NULL, 350.00, 0.00, 'Pagada', NULL, '2026-09-03 10:35:00', '2026-09-18 23:59:59');

INSERT INTO detalle_facturas (id_factura, id_servicio, descripcion, cantidad, precio_unitario) VALUES
(57, NULL, 'Membresía Mensual - septiembre 2026', 1, 350.00),
(58, NULL, 'Membresía Mensual - agosto 2026',     1, 350.00),
(59, NULL, 'Membresía Mensual - septiembre 2026', 1, 350.00);

-- Pagos a tiempo (antes del vencimiento de cada factura)
INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion, fecha_pago) VALUES
(57, 'Tarjeta',        350.00, 'Pagado', '2026-09-10 09:45:00'),
(58, 'Efectivo',       350.00, 'Pagado', '2026-08-03 10:45:00'),
(59, 'Transferencia',  350.00, 'Pagado', '2026-09-03 11:00:00');

-- No se insertan registros_acceso para los usuarios 34 y 35


-- =====================================================================
-- DATOS ADICIONALES PARA LA CONSULTA 80
-- Usuarios con más accesos exitosos de noche (después de las 18:00)
-- =====================================================================
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, fecha_hora_salida, metodo_acceso, estado_validacion, motivo_rechazo) VALUES
-- Usuario 20: 3 accesos nocturnos (más el diurno ya existente del 09-23) -> debe aparecer
(20, '2026-09-24 18:30:00', '2026-09-24 21:00:00', 'QR',   'Exitoso',   NULL),
(20, '2026-09-25 19:00:00', '2026-09-25 21:30:00', 'QR',   'Exitoso',   NULL),
(20, '2026-09-28 18:45:00', '2026-09-28 20:30:00', 'QR',   'Exitoso',   NULL),
-- Usuario 23: solo accesos nocturnos -> debe aparecer
(23, '2026-09-29 18:20:00', '2026-09-29 20:15:00', 'QR',   'Exitoso',   NULL),
(23, '2026-09-30 18:40:00', '2026-09-30 20:00:00', 'QR',   'Exitoso',   NULL),
-- Usuario 8: 2 nocturnos que igualan sus 2 diurnos existentes (empate) -> NO aparece
(8,  '2026-09-22 18:30:00', '2026-09-22 20:30:00', 'QR',   'Exitoso',   NULL),
(8,  '2026-09-24 19:15:00', '2026-09-24 21:00:00', 'QR',   'Exitoso',   NULL),
-- Usuario 14: 1 nocturno frente a 2 diurnos existentes -> NO aparece
(14, '2026-09-26 18:30:00', '2026-09-26 20:00:00', 'QR',   'Exitoso',   NULL),
-- Usuario 11: intento nocturno rechazado (no cuenta) frente a 1 diurno -> NO aparece
(11, '2026-09-26 19:30:00', NULL,                  'QR',   'Rechazado', 'Sin Reserva Activa');