/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Consultas - Usuarios y Membresías
Archivo: sql/02_consultas/01_usuarios_membresias.sql
Autor: [Nombre del autor]
Grupo: [Nombre del grupo]

Descripción:
Consultas 01 a 20 sobre usuarios, empresas, membresías, reservas,
facturación, servicios adicionales y registros de acceso.

Requisitos:
Ejecutar previamente 00_ddl/01_estructura.sql y 01_dml/01_datos_iniciales.sql.

Criterio de "reserva activa":
Reserva en estado 'Pendiente de Confirmación' o 'Confirmada'.
*/

USE coworking_db;



-- CONSULTA 01: Listar todos los usuarios con su información básica.

SELECT
    u.id_usuario,
    u.identificacion,
    u.nombre,
    u.apellidos,
    u.fecha_nacimiento,
    u.email,
    u.telefono,
    u.fecha_registro,
    e.nombre AS empresa
FROM usuarios u
LEFT JOIN empresas e ON e.id_empresa = u.id_empresa
ORDER BY u.id_usuario;



-- CONSULTA 02: Listar los usuarios con membresía activa.

SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    tm.nombre AS tipo_membresia,
    m.fecha_inicio,
    m.fecha_vencimiento,
    m.estado
FROM usuarios u
INNER JOIN membresias m ON m.id_usuario = u.id_usuario
INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
WHERE m.estado = 'Activa'
ORDER BY u.id_usuario;



-- CONSULTA 03: Listar los usuarios cuya membresía está vencida.

SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    tm.nombre AS tipo_membresia,
    m.fecha_inicio,
    m.fecha_vencimiento,
    m.estado
FROM usuarios u
INNER JOIN membresias m ON m.id_usuario = u.id_usuario
INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
WHERE m.estado = 'Vencida'
ORDER BY m.fecha_vencimiento DESC;



-- CONSULTA 04: Listar los usuarios con membresía suspendida.

SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    tm.nombre AS tipo_membresia,
    m.fecha_inicio,
    m.fecha_vencimiento,
    m.estado
FROM usuarios u
INNER JOIN membresias m ON m.id_usuario = u.id_usuario
INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
WHERE m.estado = 'Suspendida'
ORDER BY u.id_usuario;



-- CONSULTA 05: Contar cuántos usuarios tienen cada tipo de membresía.
-- (total histórico de usuarios y usuarios con membresía activa)

SELECT
    tm.id_tipo_membresia,
    tm.nombre AS tipo_membresia,
    COUNT(DISTINCT m.id_usuario) AS total_usuarios,
    COUNT(DISTINCT CASE WHEN m.estado = 'Activa' THEN m.id_usuario END) AS usuarios_con_membresia_activa
FROM tipos_membresia tm
LEFT JOIN membresias m ON m.id_tipo_membresia = tm.id_tipo_membresia
GROUP BY tm.id_tipo_membresia, tm.nombre
ORDER BY total_usuarios DESC;



-- CONSULTA 06: Mostrar el top 10 de usuarios con más antigüedad en el coworking.
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    u.fecha_registro,
    TIMESTAMPDIFF(MONTH, u.fecha_registro, NOW()) AS antiguedad_meses,
    TIMESTAMPDIFF(DAY, u.fecha_registro, NOW()) AS antiguedad_dias
FROM usuarios u
ORDER BY u.fecha_registro ASC
LIMIT 10;


-- =====================================================================
-- CONSULTA 07: Listar usuarios que pertenecen a una empresa específica.
-- (modificar la variable @nombre_empresa para consultar otra empresa)
-- =====================================================================
SET @nombre_empresa = 'TechNova Solutions SAS' COLLATE utf8mb4_unicode_ci;

SELECT
    e.nombre AS empresa,
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    u.telefono,
    u.fecha_registro
FROM usuarios u
INNER JOIN empresas e ON e.id_empresa = u.id_empresa
WHERE e.nombre = @nombre_empresa
ORDER BY u.apellidos, u.nombre;


-- CONSULTA 08: Contar cuántos usuarios están asociados a cada empresa.
SELECT
    e.id_empresa,
    e.nombre AS empresa,
    COUNT(u.id_usuario) AS total_usuarios
FROM empresas e
LEFT JOIN usuarios u ON u.id_empresa = e.id_empresa
GROUP BY e.id_empresa, e.nombre
ORDER BY total_usuarios DESC, e.nombre;


-- =====================================================================
-- CONSULTA 09: Mostrar usuarios que nunca han hecho una reserva.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    u.fecha_registro
FROM usuarios u
LEFT JOIN reservas r ON r.id_usuario = u.id_usuario
WHERE r.id_reserva IS NULL
ORDER BY u.id_usuario;


-- =====================================================================
-- CONSULTA 10: Mostrar usuarios con más de 5 reservas activas en el mes.
-- (reservas 'Pendiente de Confirmación' o 'Confirmada' cuya fecha de
--  inicio cae dentro del mes en curso)
-- =====================================================================
SELECT MIN(fecha_inicio), MAX(fecha_inicio) FROM reservas;

SELECT 
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    COUNT(r.id_reserva) AS reservas_activas_mes
FROM usuarios u
INNER JOIN reservas r ON r.id_usuario = u.id_usuario
WHERE r.estado IN ('Pendiente de Confirmación', 'Confirmada')
  AND r.fecha_inicio >= '2026-09-01'
  AND r.fecha_inicio < '2026-10-01'
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email
HAVING COUNT(r.id_reserva) > 5
ORDER BY reservas_activas_mes DESC;


-- =====================================================================
-- CONSULTA 11: Calcular el promedio de edad de los usuarios.
-- =====================================================================
SELECT
    COUNT(*) AS total_usuarios,
    ROUND(AVG(TIMESTAMPDIFF(YEAR, u.fecha_nacimiento, CURDATE())), 2) AS promedio_edad_anios,
    MIN(TIMESTAMPDIFF(YEAR, u.fecha_nacimiento, CURDATE())) AS edad_minima,
    MAX(TIMESTAMPDIFF(YEAR, u.fecha_nacimiento, CURDATE())) AS edad_maxima
FROM usuarios u;


-- =====================================================================
-- CONSULTA 12: Listar usuarios que han cambiado de membresía más de 2 veces.
-- (el esquema no incluye log_cambios_membresia; se usa el recuento de
--  membresías registradas por usuario como número de cambios)
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    COUNT(m.id_membresia) AS total_membresias,
    COUNT(DISTINCT m.id_tipo_membresia) AS tipos_distintos
FROM usuarios u
INNER JOIN membresias m ON m.id_usuario = u.id_usuario
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email
HAVING COUNT(m.id_membresia) > 2
ORDER BY total_membresias DESC;


-- =====================================================================
-- CONSULTA 13: Listar usuarios que han gastado más de $500 en reservas.
-- (suma de pagos en estado 'Pagado' sobre facturas ligadas a reservas,
--  excluyendo facturas anuladas)
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    SUM(p.monto) AS total_gastado_reservas
FROM usuarios u
INNER JOIN facturas f
        ON f.id_usuario = u.id_usuario
       AND f.id_reserva IS NOT NULL
       AND f.estado <> 'Anulada'
INNER JOIN pagos p
        ON p.id_factura = f.id_factura
       AND p.estado_transaccion = 'Pagado'
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email
HAVING SUM(p.monto) > 500
ORDER BY total_gastado_reservas DESC;


-- =====================================================================
-- CONSULTA 14: Mostrar usuarios que tienen tanto membresía como servicios
-- adicionales.
-- (servicios consumidos directamente o incluidos en sus reservas)
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    (SELECT COUNT(*)
       FROM membresias m
      WHERE m.id_usuario = u.id_usuario) AS total_membresias,
    (SELECT COALESCE(SUM(cs.cantidad), 0)
       FROM consumos_servicios cs
      WHERE cs.id_usuario = u.id_usuario) AS unidades_consumidas,
    (SELECT COALESCE(SUM(rs.cantidad), 0)
       FROM reserva_servicios rs
      INNER JOIN reservas r ON r.id_reserva = rs.id_reserva
      WHERE r.id_usuario = u.id_usuario) AS unidades_en_reservas
FROM usuarios u
WHERE EXISTS (SELECT 1
                FROM membresias m
               WHERE m.id_usuario = u.id_usuario)
  AND (
        EXISTS (SELECT 1
                  FROM consumos_servicios cs
                 WHERE cs.id_usuario = u.id_usuario)
        OR
        EXISTS (SELECT 1
                  FROM reserva_servicios rs
                 INNER JOIN reservas r ON r.id_reserva = rs.id_reserva
                 WHERE r.id_usuario = u.id_usuario)
      )
ORDER BY u.id_usuario;


-- =====================================================================
-- CONSULTA 15: Listar usuarios con membresía Premium y reservas activas.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    tm.nombre AS tipo_membresia,
    m.fecha_vencimiento,
    COUNT(r.id_reserva) AS reservas_activas
FROM usuarios u
INNER JOIN membresias m ON m.id_usuario = u.id_usuario
INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
INNER JOIN reservas r ON r.id_usuario = u.id_usuario
WHERE tm.nombre = 'Premium'
  AND m.estado = 'Activa'
  AND r.estado IN ('Pendiente de Confirmación', 'Confirmada')
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email, tm.nombre, m.fecha_vencimiento
ORDER BY reservas_activas DESC;


-- =====================================================================
-- CONSULTA 16: Mostrar usuarios con membresía Corporativa y su empresa.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    e.nombre AS empresa,
    e.nit_ruc,
    tm.nombre AS tipo_membresia,
    m.estado AS estado_membresia,
    m.fecha_inicio,
    m.fecha_vencimiento
FROM usuarios u
INNER JOIN membresias m ON m.id_usuario = u.id_usuario
INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
LEFT JOIN empresas e ON e.id_empresa = u.id_empresa
WHERE tm.nombre = 'Corporativa'
ORDER BY e.nombre, u.apellidos;


-- =====================================================================
-- CONSULTA 17: Identificar usuarios con membresía diaria que la han
-- renovado más de 10 veces.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    tm.nombre AS tipo_membresia,
    m.renovaciones,
    m.estado AS estado_membresia
FROM usuarios u
INNER JOIN membresias m ON m.id_usuario = u.id_usuario
INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
WHERE tm.nombre = 'Diaria'
  AND m.renovaciones > 10
ORDER BY m.renovaciones DESC;


-- =====================================================================
-- CONSULTA 18: Mostrar usuarios cuya membresía vence en los próximos 7 días.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    tm.nombre AS tipo_membresia,
    m.fecha_vencimiento,
    TIMESTAMPDIFF(DAY, NOW(), m.fecha_vencimiento) AS dias_restantes
FROM usuarios u
INNER JOIN membresias m ON m.id_usuario = u.id_usuario
INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
WHERE m.estado = 'Activa'
  AND m.fecha_vencimiento BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL 7 DAY)
ORDER BY m.fecha_vencimiento ASC;


-- =====================================================================
-- CONSULTA 19: Listar usuarios que se registraron en el último mes.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    u.fecha_registro,
    e.nombre AS empresa
FROM usuarios u
LEFT JOIN empresas e ON e.id_empresa = u.id_empresa
WHERE u.fecha_registro >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
ORDER BY u.fecha_registro DESC;


-- =====================================================================
-- CONSULTA 20: Mostrar usuarios que nunca han asistido al coworking
-- (0 accesos registrados).
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo,
    u.email,
    u.fecha_registro
FROM usuarios u
LEFT JOIN registros_acceso ra ON ra.id_usuario = u.id_usuario
WHERE ra.id_acceso IS NULL
ORDER BY u.id_usuario;

-- Variante (solo cuenta ingresos exitosos como asistencia; incluiría además
-- a los usuarios con únicamente accesos rechazados):
-- SELECT u.id_usuario, CONCAT(u.nombre, ' ', u.apellidos) AS nombre_completo, u.email
-- FROM usuarios u
-- WHERE NOT EXISTS (SELECT 1 FROM registros_acceso ra
--                   WHERE ra.id_usuario = u.id_usuario
--                     AND ra.estado_validacion = 'Exitoso');