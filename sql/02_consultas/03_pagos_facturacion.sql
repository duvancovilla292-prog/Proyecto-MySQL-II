/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Consultas - Pagos y Facturación
Archivo: sql/02_consultas/03_pagos_facturacion.sql
Autor: [Nombre del autor]
Grupo: [Nombre del grupo]

Descripción:
Consultas 41 a 60 sobre pagos, facturas, ingresos por concepto, métodos de
pago y facturación por empresa.

Requisitos:
Ejecutar previamente 00_ddl/01_estructura.sql y 01_dml/01_datos_iniciales.sql.

Criterio de "ingreso" o "recaudo":
Suma de los pagos con estado_transaccion = 'Pagado' (incluye pagos parciales).
*/

USE coworking_db;


-- =====================================================================
-- CONSULTA 41: Pagos con tarjeta
-- Lista todos los pagos realizados con método 'Tarjeta'.
-- =====================================================================
SELECT
    p.id_pago,
    p.id_factura,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    p.metodo_pago,
    p.monto,
    p.fecha_pago
FROM pagos p
INNER JOIN facturas f ON f.id_factura = p.id_factura
INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
WHERE p.metodo_pago = 'Tarjeta'
  AND p.estado_transaccion = 'Pagado'
ORDER BY p.fecha_pago DESC;


-- =====================================================================
-- CONSULTA 42: Pagos pendientes de usuarios
-- Lista los pagos en estado 'Pendiente' junto con el usuario y la factura.
-- =====================================================================
SELECT
    p.id_pago,
    p.id_factura,
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    p.metodo_pago,
    p.monto,
    p.fecha_pago
FROM pagos p
INNER JOIN facturas f ON f.id_factura = p.id_factura
INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
WHERE p.estado_transaccion = 'Pendiente'
ORDER BY p.fecha_pago;


-- =====================================================================
-- CONSULTA 43: Pagos cancelados en los últimos 3 meses
-- Muestra los pagos con estado 'Cancelado' registrados en los últimos 3 meses.
-- =====================================================================
SELECT
    p.id_pago,
    p.id_factura,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    p.metodo_pago,
    p.monto,
    p.fecha_pago
FROM pagos p
INNER JOIN facturas f ON f.id_factura = p.id_factura
INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
WHERE p.estado_transaccion = 'Cancelado'
  AND p.fecha_pago >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
ORDER BY p.fecha_pago DESC;


-- =====================================================================
-- CONSULTA 44: Facturas generadas por membresías
-- Lista las facturas asociadas a una membresía (id_membresia IS NOT NULL).
-- =====================================================================
SELECT
    f.id_factura,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    m.id_membresia,
    tm.nombre AS tipo_membresia,
    f.monto_total,
    f.saldo_pendiente,
    f.estado,
    f.fecha_emision,
    f.fecha_vencimiento
FROM facturas f
INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
INNER JOIN membresias m ON m.id_membresia = f.id_membresia
INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
WHERE f.id_membresia IS NOT NULL
ORDER BY f.fecha_emision DESC;


-- =====================================================================
-- CONSULTA 45: Facturas generadas por reservas
-- Lista las facturas asociadas a una reserva (id_reserva IS NOT NULL).
-- =====================================================================
SELECT
    f.id_factura,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    r.id_reserva,
    e.nombre AS espacio,
    r.fecha_inicio,
    f.monto_total,
    f.saldo_pendiente,
    f.estado,
    f.fecha_emision
FROM facturas f
INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
INNER JOIN reservas r ON r.id_reserva = f.id_reserva
INNER JOIN espacios e ON e.id_espacio = r.id_espacio
WHERE f.id_reserva IS NOT NULL
ORDER BY f.fecha_emision DESC;


-- =====================================================================
-- CONSULTA 46: Ingresos por membresías en el último mes
-- Suma los pagos exitosos del último mes sobre facturas de membresías.
-- =====================================================================
SELECT
    COUNT(p.id_pago) AS total_pagos,
    COALESCE(SUM(p.monto), 0) AS ingresos_membresias_ultimo_mes
FROM pagos p
INNER JOIN facturas f ON f.id_factura = p.id_factura
WHERE f.id_membresia IS NOT NULL
  AND p.estado_transaccion = 'Pagado'
  AND p.fecha_pago >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
  AND p.fecha_pago <  DATE_ADD(CURDATE(), INTERVAL 1 DAY);


-- =====================================================================
-- CONSULTA 47: Ingresos por reservas en el último mes
-- Suma los pagos exitosos del último mes sobre facturas de reservas.
-- =====================================================================
SELECT
    COUNT(p.id_pago) AS total_pagos,
    COALESCE(SUM(p.monto), 0) AS ingresos_reservas_ultimo_mes
FROM pagos p
INNER JOIN facturas f ON f.id_factura = p.id_factura
WHERE f.id_reserva IS NOT NULL
  AND p.estado_transaccion = 'Pagado'
  AND p.fecha_pago >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
  AND p.fecha_pago <  DATE_ADD(CURDATE(), INTERVAL 1 DAY);


-- =====================================================================
-- CONSULTA 48: Ingresos por servicios adicionales
-- Total facturado por cada servicio adicional (líneas de detalle de
-- facturas no anuladas). Los servicios sin ventas aparecen con 0.
-- =====================================================================
SELECT
    s.id_servicio,
    s.nombre AS servicio,
    COALESCE(SUM(CASE WHEN f.id_factura IS NOT NULL THEN d.cantidad END), 0) AS unidades_facturadas,
    COALESCE(SUM(CASE WHEN f.id_factura IS NOT NULL THEN d.subtotal END), 0) AS total_facturado
FROM servicios_adicionales s
LEFT JOIN detalle_facturas d ON d.id_servicio = s.id_servicio
LEFT JOIN facturas f
       ON f.id_factura = d.id_factura
      AND f.estado <> 'Anulada'
GROUP BY s.id_servicio, s.nombre
ORDER BY total_facturado DESC;


-- =====================================================================
-- CONSULTA 49: Usuarios que nunca han pagado con PayPal
-- Usuarios sin ningún pago exitoso por PayPal.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    (SELECT COUNT(*)
       FROM pagos p
      INNER JOIN facturas f ON f.id_factura = p.id_factura
      WHERE f.id_usuario = u.id_usuario
        AND p.estado_transaccion = 'Pagado') AS pagos_realizados
FROM usuarios u
WHERE NOT EXISTS (
    SELECT 1
    FROM pagos p
    INNER JOIN facturas f ON f.id_factura = p.id_factura
    WHERE f.id_usuario = u.id_usuario
      AND p.metodo_pago = 'PayPal'
      AND p.estado_transaccion = 'Pagado'
)
ORDER BY u.id_usuario;


-- =====================================================================
-- CONSULTA 50: Promedio de gasto por usuario
-- Promedio del total pagado por usuario, entre quienes han pagado y entre
-- todos los usuarios registrados.
-- =====================================================================
SELECT
    ROUND(AVG(t.total_pagado), 2) AS promedio_usuarios_con_pagos,
    ROUND(SUM(t.total_pagado) / (SELECT COUNT(*) FROM usuarios), 2) AS promedio_todos_los_usuarios
FROM (
    SELECT
        f.id_usuario,
        SUM(p.monto) AS total_pagado
    FROM pagos p
    INNER JOIN facturas f ON f.id_factura = p.id_factura
    WHERE p.estado_transaccion = 'Pagado'
    GROUP BY f.id_usuario
) t;


-- =====================================================================
-- CONSULTA 51: Top 5 de usuarios que más han pagado
-- Los cinco usuarios con mayor suma de pagos exitosos.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    COUNT(p.id_pago) AS total_pagos,
    SUM(p.monto) AS total_pagado
FROM usuarios u
INNER JOIN facturas f ON f.id_usuario = u.id_usuario
INNER JOIN pagos p ON p.id_factura = f.id_factura
WHERE p.estado_transaccion = 'Pagado'
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email
ORDER BY total_pagado DESC
LIMIT 5;


-- =====================================================================
-- CONSULTA 52: Facturas con monto mayor a $1000
-- Lista las facturas cuyo monto_total supera 1000.
-- =====================================================================
SELECT
    f.id_factura,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    f.monto_total,
    f.saldo_pendiente,
    f.estado,
    f.fecha_emision
FROM facturas f
INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
WHERE f.monto_total > 1000
ORDER BY f.monto_total DESC;


-- =====================================================================
-- CONSULTA 53: Pagos realizados después del vencimiento de la factura
-- Pagos exitosos cuya fecha_pago es posterior a la fecha_vencimiento.
-- =====================================================================
SELECT
    p.id_pago,
    p.id_factura,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    p.monto,
    p.fecha_pago,
    f.fecha_vencimiento,
    TIMESTAMPDIFF(DAY, f.fecha_vencimiento, p.fecha_pago) AS dias_de_retraso
FROM pagos p
INNER JOIN facturas f ON f.id_factura = p.id_factura
INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
WHERE p.estado_transaccion = 'Pagado'
  AND p.fecha_pago > f.fecha_vencimiento
ORDER BY dias_de_retraso DESC;


-- =====================================================================
-- CONSULTA 54: Total recaudado en el año actual
-- Suma de pagos exitosos con fecha de pago dentro del año en curso.
-- =====================================================================
SELECT
    YEAR(CURDATE()) AS anio,
    COUNT(p.id_pago) AS total_pagos,
    COALESCE(SUM(p.monto), 0) AS total_recaudado
FROM pagos p
WHERE p.estado_transaccion = 'Pagado'
  AND p.fecha_pago >= MAKEDATE(YEAR(CURDATE()), 1)
  AND p.fecha_pago <  MAKEDATE(YEAR(CURDATE()) + 1, 1);


-- =====================================================================
-- CONSULTA 55: Facturas anuladas y su motivo
-- Lista las facturas en estado 'Anulada' con el motivo de anulación.
-- =====================================================================
SELECT
    f.id_factura,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    f.monto_total,
    f.motivo_anulacion,
    f.fecha_emision
FROM facturas f
INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
WHERE f.estado = 'Anulada'
ORDER BY f.fecha_emision DESC;


-- =====================================================================
-- CONSULTA 56: Usuarios con facturas pendientes mayores a $200
-- Usuarios con facturas 'Pendiente' cuyo saldo_pendiente supera 200.
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    COUNT(f.id_factura) AS facturas_pendientes,
    SUM(f.saldo_pendiente) AS saldo_pendiente_total
FROM usuarios u
INNER JOIN facturas f ON f.id_usuario = u.id_usuario
WHERE f.estado = 'Pendiente'
  AND f.saldo_pendiente > 200
GROUP BY u.id_usuario, u.nombre, u.apellidos, u.email
ORDER BY saldo_pendiente_total DESC;


-- =====================================================================
-- CONSULTA 57: Usuarios que han pagado más de una vez el mismo servicio
-- Usuarios con el mismo servicio adicional en más de una factura que
-- tenga al menos un pago exitoso (incluye pagos parciales).
-- =====================================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    s.nombre AS servicio,
    COUNT(DISTINCT f.id_factura) AS facturas_pagadas_con_el_servicio,
    SUM(d.cantidad) AS unidades_totales
FROM usuarios u
INNER JOIN facturas f ON f.id_usuario = u.id_usuario
INNER JOIN detalle_facturas d ON d.id_factura = f.id_factura
INNER JOIN servicios_adicionales s ON s.id_servicio = d.id_servicio
WHERE EXISTS (
    SELECT 1
    FROM pagos p
    WHERE p.id_factura = f.id_factura
      AND p.estado_transaccion = 'Pagado'
)
GROUP BY u.id_usuario, u.nombre, u.apellidos, s.id_servicio, s.nombre
HAVING COUNT(DISTINCT f.id_factura) > 1
ORDER BY facturas_pagadas_con_el_servicio DESC, u.id_usuario;

-- Variante (cuenta las facturas no anuladas que incluyen el servicio,
-- hayan sido pagadas o no): reemplazar el bloque WHERE EXISTS (...) por
--   WHERE f.estado <> 'Anulada'


-- =====================================================================
-- CONSULTA 58: Ingresos por cada método de pago
-- Total recaudado, número de pagos y porcentaje por método de pago.
-- =====================================================================
SELECT
    p.metodo_pago,
    COUNT(p.id_pago) AS total_pagos,
    SUM(p.monto) AS total_recaudado,
    ROUND(SUM(p.monto) / SUM(SUM(p.monto)) OVER () * 100, 2) AS porcentaje_del_total
FROM pagos p
WHERE p.estado_transaccion = 'Pagado'
GROUP BY p.metodo_pago
ORDER BY total_recaudado DESC;


-- =====================================================================
-- CONSULTA 59: Facturación acumulada por empresa
-- Total facturado (sin anuladas), cobrado y pendiente por empresa, sumando
-- las facturas de todos sus usuarios.
-- =====================================================================
SELECT
    e.id_empresa,
    e.nombre AS empresa,
    COUNT(f.id_factura) AS total_facturas,
    COALESCE(SUM(f.monto_total), 0) AS total_facturado,
    COALESCE(SUM(f.monto_total - f.saldo_pendiente), 0) AS total_cobrado,
    COALESCE(SUM(f.saldo_pendiente), 0) AS saldo_pendiente
FROM empresas e
LEFT JOIN usuarios u ON u.id_empresa = e.id_empresa
LEFT JOIN facturas f
       ON f.id_usuario = u.id_usuario
      AND f.estado <> 'Anulada'
GROUP BY e.id_empresa, e.nombre
ORDER BY total_facturado DESC;


-- =====================================================================
-- CONSULTA 60: Ingresos netos por mes del último año
-- Ingresos por mes de los últimos 12 meses (mes en curso incluido),
-- considerando solo pagos exitosos y separados por concepto.
-- =====================================================================
SELECT
    DATE_FORMAT(p.fecha_pago, '%Y-%m') AS mes,
    COUNT(p.id_pago) AS total_pagos,
    SUM(CASE WHEN f.id_membresia IS NOT NULL THEN p.monto ELSE 0 END) AS ingresos_membresias,
    SUM(CASE WHEN f.id_reserva IS NOT NULL THEN p.monto ELSE 0 END) AS ingresos_reservas,
    SUM(p.monto) AS ingresos_netos
FROM pagos p
INNER JOIN facturas f ON f.id_factura = p.id_factura
WHERE p.estado_transaccion = 'Pagado'
  AND p.fecha_pago >= DATE_SUB(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 11 MONTH)
  AND p.fecha_pago <  DATE_ADD(CURDATE(), INTERVAL 1 DAY)
GROUP BY DATE_FORMAT(p.fecha_pago, '%Y-%m')
ORDER BY mes;