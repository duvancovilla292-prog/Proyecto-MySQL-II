/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Consultas - Análisis Avanzado
Archivo: sql/02_consultas/05_consultas_avanzadas.sql
Consultas: 81 a 100

Criterios generales (MySQL 8.0+):
- Ingreso real  = pagos con estado_transaccion = 'Pagado'.
- Facturación   = monto_total de facturas que no están 'Anulada'.
- Reserva válida = cualquier reserva distinta de 'Cancelada'.
- Membresía vigente = estado 'Activa' con fecha_vencimiento >= NOW().
*/

USE coworking_db;

-- =========================================================
-- 81. Mostrar los usuarios con el mayor gasto acumulado (subconsulta con SUM).
-- =========================================================
SELECT
    g.id_usuario,
    g.usuario,
    g.gasto_acumulado
FROM (
    SELECT
        u.id_usuario,
        CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
        (SELECT SUM(p.monto)
           FROM pagos p
           INNER JOIN facturas f ON f.id_factura = p.id_factura
          WHERE f.id_usuario = u.id_usuario
            AND p.estado_transaccion = 'Pagado') AS gasto_acumulado
    FROM usuarios u
) g
WHERE g.gasto_acumulado IS NOT NULL
ORDER BY g.gasto_acumulado DESC
LIMIT 10;

-- =========================================================
-- 82. Mostrar los espacios más ocupados considerando reservas confirmadas
--     y asistencias reales.
-- =========================================================
WITH uso_espacio AS (
    SELECT
        r.id_espacio,
        COUNT(*)                                                      AS reservas_confirmadas,
        SUM(r.asistio)                                                AS asistencias_reales,
        ROUND(SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60, 2) AS horas_reservadas
    FROM reservas r
    WHERE r.estado = 'Confirmada'
    GROUP BY r.id_espacio
)
SELECT
    e.id_espacio,
    e.nombre AS espacio,
    te.nombre AS tipo_espacio,
    ue.reservas_confirmadas,
    ue.asistencias_reales,
    ue.horas_reservadas
FROM uso_espacio ue
INNER JOIN espacios e       ON e.id_espacio = ue.id_espacio
INNER JOIN tipos_espacio te ON te.id_tipo_espacio = e.id_tipo_espacio
ORDER BY ue.asistencias_reales DESC, ue.reservas_confirmadas DESC;

-- =========================================================
-- 83. Calcular el promedio de ingresos por usuario usando subconsultas.
-- =========================================================
SELECT
    COUNT(*)                          AS total_usuarios,
    SUM(t.ingreso_usuario)            AS ingresos_totales,
    ROUND(AVG(t.ingreso_usuario), 2)  AS promedio_todos_los_usuarios,
    ROUND(AVG(NULLIF(t.ingreso_usuario, 0)), 2) AS promedio_usuarios_que_pagaron
FROM (
    SELECT
        u.id_usuario,
        COALESCE((SELECT SUM(p.monto)
                    FROM pagos p
                    INNER JOIN facturas f ON f.id_factura = p.id_factura
                   WHERE f.id_usuario = u.id_usuario
                     AND p.estado_transaccion = 'Pagado'), 0) AS ingreso_usuario
    FROM usuarios u
) t;

-- =========================================================
-- 84. Listar usuarios que tienen reservas activas y facturas pendientes
--     al mismo tiempo.
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    u.email,
    (SELECT COUNT(*)
       FROM reservas r
      WHERE r.id_usuario = u.id_usuario
        AND r.estado IN ('Pendiente de Confirmación', 'Confirmada')
        AND r.fecha_fin >= NOW())      AS reservas_activas,
    (SELECT SUM(f.saldo_pendiente)
       FROM facturas f
      WHERE f.id_usuario = u.id_usuario
        AND f.estado = 'Pendiente')    AS saldo_pendiente_total
FROM usuarios u
WHERE EXISTS (
        SELECT 1
        FROM reservas r
        WHERE r.id_usuario = u.id_usuario
          AND r.estado IN ('Pendiente de Confirmación', 'Confirmada')
          AND r.fecha_fin >= NOW()
    )
  AND EXISTS (
        SELECT 1
        FROM facturas f
        WHERE f.id_usuario = u.id_usuario
          AND f.estado = 'Pendiente'
    )
ORDER BY saldo_pendiente_total DESC;

-- =========================================================
-- 85. Mostrar empresas cuyos empleados generan más del 20% de los
--     ingresos totales (HAVING / CTE).
-- =========================================================
WITH ingresos_usuario AS (
    SELECT
        f.id_usuario,
        SUM(p.monto) AS ingresos
    FROM pagos p
    INNER JOIN facturas f ON f.id_factura = p.id_factura
    WHERE p.estado_transaccion = 'Pagado'
    GROUP BY f.id_usuario
),
ingresos_globales AS (
    SELECT SUM(ingresos) AS total_ingresos
    FROM ingresos_usuario
)
SELECT
    e.id_empresa,
    e.nombre AS empresa,
    SUM(iu.ingresos)                                          AS ingresos_empresa,
    ROUND(100 * SUM(iu.ingresos) / ig.total_ingresos, 2)      AS porcentaje_del_total
FROM empresas e
INNER JOIN usuarios u           ON u.id_empresa = e.id_empresa
INNER JOIN ingresos_usuario iu  ON iu.id_usuario = u.id_usuario
CROSS JOIN ingresos_globales ig
GROUP BY e.id_empresa, e.nombre, ig.total_ingresos
HAVING SUM(iu.ingresos) > 0.20 * ig.total_ingresos
ORDER BY ingresos_empresa DESC;

-- =========================================================
-- 86. Mostrar el top 5 de usuarios que más usan servicios adicionales.
--     (Consumos directos + servicios contratados en reservas.)
-- =========================================================
WITH usos_servicio AS (
    SELECT
        cs.id_usuario,
        cs.id_servicio,
        COALESCE(cs.cantidad, 1) AS cantidad
    FROM consumos_servicios cs
    UNION ALL
    SELECT
        r.id_usuario,
        rs.id_servicio,
        COALESCE(rs.cantidad, 1) AS cantidad
    FROM reserva_servicios rs
    INNER JOIN reservas r ON r.id_reserva = rs.id_reserva
)
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    SUM(us.cantidad)                   AS total_unidades,
    COUNT(DISTINCT us.id_servicio)     AS servicios_distintos
FROM usos_servicio us
INNER JOIN usuarios u ON u.id_usuario = us.id_usuario
GROUP BY u.id_usuario, u.nombre, u.apellidos
ORDER BY total_unidades DESC, servicios_distintos DESC
LIMIT 5;

-- =========================================================
-- 87. Mostrar reservas que generaron facturas mayores al promedio
--     de facturación.
-- =========================================================
SELECT
    r.id_reserva,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    es.nombre                          AS espacio,
    r.fecha_inicio,
    f.id_factura,
    f.monto_total,
    (SELECT ROUND(AVG(f2.monto_total), 2)
       FROM facturas f2
      WHERE f2.estado <> 'Anulada')    AS promedio_facturacion
FROM reservas r
INNER JOIN facturas f  ON f.id_reserva = r.id_reserva
INNER JOIN usuarios u  ON u.id_usuario = r.id_usuario
INNER JOIN espacios es ON es.id_espacio = r.id_espacio
WHERE f.estado <> 'Anulada'
  AND f.monto_total > (SELECT AVG(f3.monto_total)
                         FROM facturas f3
                        WHERE f3.estado <> 'Anulada')
ORDER BY f.monto_total DESC;

-- =========================================================
-- 88. Calcular el porcentaje de ocupación global del coworking por mes.
--     Ocupación = horas reservadas confirmadas / horas disponibles
--     (horas de operación diarias de los espacios no inactivos x días del mes).
-- =========================================================
WITH capacidad AS (
    SELECT
        SUM(TIME_TO_SEC(TIMEDIFF(hora_cierre, hora_apertura))) / 3600 AS horas_diarias
    FROM espacios
    WHERE estado <> 'Inactivo'
),
reservado AS (
    SELECT
        DATE_FORMAT(fecha_inicio, '%Y-%m')                AS mes,
        DAY(LAST_DAY(MIN(fecha_inicio)))                  AS dias_mes,
        SUM(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)) / 60 AS horas_reservadas
    FROM reservas
    WHERE estado = 'Confirmada'
    GROUP BY DATE_FORMAT(fecha_inicio, '%Y-%m')
)
SELECT
    rv.mes,
    ROUND(rv.horas_reservadas, 2)                              AS horas_reservadas,
    ROUND(c.horas_diarias * rv.dias_mes, 2)                    AS horas_disponibles,
    ROUND(100 * rv.horas_reservadas / (c.horas_diarias * rv.dias_mes), 2) AS porcentaje_ocupacion
FROM reservado rv
CROSS JOIN capacidad c
ORDER BY rv.mes;

-- =========================================================
-- 89. Mostrar usuarios que tienen más horas de reserva que el promedio
--     del sistema.
-- =========================================================
WITH horas_usuario AS (
    SELECT
        id_usuario,
        SUM(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)) / 60 AS horas
    FROM reservas
    WHERE estado <> 'Cancelada'
    GROUP BY id_usuario
)
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    ROUND(h.horas, 2)                  AS horas_reservadas,
    ROUND((SELECT AVG(horas) FROM horas_usuario), 2) AS promedio_sistema
FROM horas_usuario h
INNER JOIN usuarios u ON u.id_usuario = h.id_usuario
WHERE h.horas > (SELECT AVG(horas) FROM horas_usuario)
ORDER BY h.horas DESC;

-- =========================================================
-- 90. Mostrar el top 3 de salas más usadas en el último trimestre.
--     (Tipos de espacio cuyo nombre empieza por "Sala"; últimos 3 meses.)
-- =========================================================
WITH uso_salas AS (
    SELECT
        e.id_espacio,
        e.nombre AS sala,
        te.nombre AS tipo_espacio,
        COUNT(*) AS total_reservas,
        ROUND(SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)) / 60, 2) AS horas_reservadas
    FROM reservas r
    INNER JOIN espacios e       ON e.id_espacio = r.id_espacio
    INNER JOIN tipos_espacio te ON te.id_tipo_espacio = e.id_tipo_espacio
    WHERE te.nombre LIKE 'Sala%'
      AND r.estado <> 'Cancelada'
      AND r.fecha_inicio >= CURDATE() - INTERVAL 3 MONTH
    GROUP BY e.id_espacio, e.nombre, te.nombre
),
ranking AS (
    SELECT
        us.*,
        DENSE_RANK() OVER (ORDER BY total_reservas DESC, horas_reservadas DESC) AS posicion
    FROM uso_salas us
)
SELECT
    posicion,
    id_espacio,
    sala,
    tipo_espacio,
    total_reservas,
    horas_reservadas
FROM ranking
WHERE posicion <= 3
ORDER BY posicion, sala;

-- =========================================================
-- 91. Calcular ingresos promedio por tipo de membresía (agrupado con AVG).
-- =========================================================
WITH ingreso_membresia AS (
    SELECT
        m.id_membresia,
        m.id_tipo_membresia,
        COALESCE(SUM(p.monto), 0) AS ingreso
    FROM membresias m
    LEFT JOIN facturas f ON f.id_membresia = m.id_membresia
                        AND f.estado <> 'Anulada'
    LEFT JOIN pagos p    ON p.id_factura = f.id_factura
                        AND p.estado_transaccion = 'Pagado'
    GROUP BY m.id_membresia, m.id_tipo_membresia
)
SELECT
    tm.nombre                    AS tipo_membresia,
    COUNT(*)                     AS total_membresias,
    ROUND(SUM(im.ingreso), 2)    AS ingreso_total,
    ROUND(AVG(im.ingreso), 2)    AS ingreso_promedio
FROM ingreso_membresia im
INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = im.id_tipo_membresia
GROUP BY tm.id_tipo_membresia, tm.nombre
ORDER BY ingreso_promedio DESC;

-- =========================================================
-- 92. Mostrar usuarios que pagan solo con un método de pago
--     (subconsulta con HAVING COUNT(DISTINCT metodo_pago) = 1).
-- =========================================================
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    mp.metodo_unico,
    mp.total_pagos,
    mp.monto_total
FROM usuarios u
INNER JOIN (
    SELECT
        f.id_usuario,
        MIN(p.metodo_pago) AS metodo_unico,
        COUNT(*)           AS total_pagos,
        SUM(p.monto)       AS monto_total
    FROM pagos p
    INNER JOIN facturas f ON f.id_factura = p.id_factura
    WHERE p.estado_transaccion = 'Pagado'
    GROUP BY f.id_usuario
    HAVING COUNT(DISTINCT p.metodo_pago) = 1
) mp ON mp.id_usuario = u.id_usuario
ORDER BY mp.total_pagos DESC;

-- =========================================================
-- 93. Mostrar reservas canceladas por usuarios que nunca asistieron.
--     (Sin reservas con asistencia y sin accesos exitosos.)
-- =========================================================
SELECT
    r.id_reserva,
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    es.nombre                          AS espacio,
    r.fecha_inicio,
    r.fecha_fin,
    lrc.motivo,
    lrc.fecha_cancelacion
FROM reservas r
INNER JOIN usuarios u  ON u.id_usuario = r.id_usuario
INNER JOIN espacios es ON es.id_espacio = r.id_espacio
LEFT JOIN log_reservas_canceladas lrc ON lrc.id_reserva = r.id_reserva
WHERE r.estado = 'Cancelada'
  AND NOT EXISTS (
        SELECT 1
        FROM reservas r2
        WHERE r2.id_usuario = r.id_usuario
          AND r2.asistio = TRUE
    )
  AND NOT EXISTS (
        SELECT 1
        FROM registros_acceso ra
        WHERE ra.id_usuario = r.id_usuario
          AND ra.estado_validacion = 'Exitoso'
    )
ORDER BY r.fecha_inicio DESC;

-- =========================================================
-- 94. Mostrar facturas con pagos parciales y calcular saldo pendiente exacto.
-- =========================================================
SELECT
    f.id_factura,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    f.monto_total,
    SUM(p.monto)                       AS total_pagado,
    f.monto_total - SUM(p.monto)       AS saldo_pendiente_exacto,
    f.saldo_pendiente                  AS saldo_registrado,
    f.estado
FROM facturas f
INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
INNER JOIN pagos p    ON p.id_factura = f.id_factura
                     AND p.estado_transaccion = 'Pagado'
WHERE f.estado <> 'Anulada'
GROUP BY f.id_factura, u.nombre, u.apellidos, f.monto_total, f.saldo_pendiente, f.estado
HAVING SUM(p.monto) > 0
   AND SUM(p.monto) < f.monto_total
ORDER BY saldo_pendiente_exacto DESC;

-- =========================================================
-- 95. Calcular la facturación total de cada empresa y ordenarla
--     de mayor a menor.
-- =========================================================
SELECT
    e.id_empresa,
    e.nombre                          AS empresa,
    COUNT(DISTINCT u.id_usuario)      AS usuarios,
    COUNT(f.id_factura)               AS facturas,
    COALESCE(SUM(f.monto_total), 0)   AS facturacion_total
FROM empresas e
LEFT JOIN usuarios u ON u.id_empresa = e.id_empresa
LEFT JOIN facturas f ON f.id_usuario = u.id_usuario
                    AND f.estado <> 'Anulada'
GROUP BY e.id_empresa, e.nombre
ORDER BY facturacion_total DESC;

-- =========================================================
-- 96. Identificar usuarios que superan en reservas al promedio de
--     su propia empresa.
-- =========================================================
WITH reservas_usuario AS (
    SELECT
        u.id_usuario,
        u.id_empresa,
        CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
        COUNT(r.id_reserva)                AS total_reservas
    FROM usuarios u
    LEFT JOIN reservas r ON r.id_usuario = u.id_usuario
                        AND r.estado <> 'Cancelada'
    WHERE u.id_empresa IS NOT NULL
    GROUP BY u.id_usuario, u.id_empresa, u.nombre, u.apellidos
),
con_promedio AS (
    SELECT
        ru.*,
        AVG(ru.total_reservas) OVER (PARTITION BY ru.id_empresa) AS promedio_empresa
    FROM reservas_usuario ru
)
SELECT
    e.nombre AS empresa,
    cp.id_usuario,
    cp.usuario,
    cp.total_reservas,
    ROUND(cp.promedio_empresa, 2) AS promedio_empresa
FROM con_promedio cp
INNER JOIN empresas e ON e.id_empresa = cp.id_empresa
WHERE cp.total_reservas > cp.promedio_empresa
ORDER BY e.nombre, cp.total_reservas DESC;

-- =========================================================
-- 97. Mostrar las 3 empresas con más empleados activos en el coworking.
--     (Empleado activo = usuario con membresía vigente.)
-- =========================================================
WITH empleados_activos AS (
    SELECT
        e.id_empresa,
        e.nombre AS empresa,
        COUNT(DISTINCT u.id_usuario) AS empleados_activos
    FROM empresas e
    INNER JOIN usuarios u   ON u.id_empresa = e.id_empresa
    INNER JOIN membresias m ON m.id_usuario = u.id_usuario
                           AND m.estado = 'Activa'
                           AND m.fecha_vencimiento >= NOW()
    GROUP BY e.id_empresa, e.nombre
),
ranking AS (
    SELECT
        ea.*,
        DENSE_RANK() OVER (ORDER BY ea.empleados_activos DESC) AS posicion
    FROM empleados_activos ea
)
SELECT
    posicion,
    id_empresa,
    empresa,
    empleados_activos
FROM ranking
WHERE posicion <= 3
ORDER BY posicion, empresa;

-- =========================================================
-- 98. Calcular el porcentaje de usuarios activos frente al total
--     de registrados.
-- =========================================================
SELECT
    t.total_usuarios,
    t.usuarios_activos,
    ROUND(100 * t.usuarios_activos / t.total_usuarios, 2) AS porcentaje_activos
FROM (
    SELECT
        (SELECT COUNT(*) FROM usuarios) AS total_usuarios,
        (SELECT COUNT(DISTINCT m.id_usuario)
           FROM membresias m
          WHERE m.estado = 'Activa'
            AND m.fecha_vencimiento >= NOW()) AS usuarios_activos
) t;

-- =========================================================
-- 99. Mostrar ingresos mensuales acumulados con función de ventana
--     (SUM(...) OVER (ORDER BY mes)).
-- =========================================================
WITH ingresos_mensuales AS (
    SELECT
        DATE_FORMAT(fecha_pago, '%Y-%m') AS mes,
        SUM(monto)                       AS ingreso_mes
    FROM pagos
    WHERE estado_transaccion = 'Pagado'
    GROUP BY DATE_FORMAT(fecha_pago, '%Y-%m')
)
SELECT
    mes,
    ingreso_mes,
    SUM(ingreso_mes) OVER (ORDER BY mes) AS ingreso_acumulado
FROM ingresos_mensuales
ORDER BY mes;

-- =========================================================
-- 100. Mostrar usuarios con más de 10 reservas, más de $500 en facturación
--      y membresía activa (múltiples JOINs y filtros agregados).
-- =========================================================
WITH reservas_usuario AS (
    SELECT
        id_usuario,
        COUNT(*) AS total_reservas
    FROM reservas
    WHERE estado <> 'Cancelada'
    GROUP BY id_usuario
    HAVING COUNT(*) > 10
),
facturacion_usuario AS (
    SELECT
        id_usuario,
        SUM(monto_total) AS facturacion_total
    FROM facturas
    WHERE estado <> 'Anulada'
    GROUP BY id_usuario
    HAVING SUM(monto_total) > 500
)
SELECT
    u.id_usuario,
    CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
    ru.total_reservas,
    fu.facturacion_total,
    tm.nombre                          AS tipo_membresia,
    m.fecha_vencimiento
FROM usuarios u
INNER JOIN reservas_usuario ru     ON ru.id_usuario = u.id_usuario
INNER JOIN facturacion_usuario fu  ON fu.id_usuario = u.id_usuario
INNER JOIN membresias m            ON m.id_usuario = u.id_usuario
                                  AND m.estado = 'Activa'
                                  AND m.fecha_vencimiento >= NOW()
INNER JOIN tipos_membresia tm      ON tm.id_tipo_membresia = m.id_tipo_membresia
ORDER BY fu.facturacion_total DESC;