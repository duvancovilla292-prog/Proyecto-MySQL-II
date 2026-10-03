/*
Pruebas de las 20 funciones fn_*
Cada SELECT devuelve dos columnas:
  funcion -> lo que devuelve la función
  control -> la misma cifra calculada a mano con una consulta normal
Si ambas columnas coinciden, la función está bien.

Cambia los ids (usuario 1, espacio 1, empresa 1) y mes/año (9, 2026)
por valores que tengan datos en tu base.
*/

USE coworking_db;

-- ================= MEMBRESÍAS =================

-- 1. fn_membresia_activa
SELECT fn_membresia_activa(1) AS funcion,
       (SELECT COUNT(*) > 0 FROM membresias
         WHERE id_usuario = 1 AND estado = 'Activa'
           AND NOW() BETWEEN fecha_inicio AND fecha_vencimiento) AS control;

-- 2. fn_dias_restantes_membresia
SELECT fn_dias_restantes_membresia(1) AS funcion,
       (SELECT COALESCE(GREATEST(DATEDIFF(DATE(MAX(fecha_vencimiento)), CURDATE()), 0), 0)
          FROM membresias
         WHERE id_usuario = 1 AND estado = 'Activa'
           AND fecha_vencimiento >= NOW()) AS control;

-- 3. fn_tipo_membresia
SELECT fn_tipo_membresia(1) AS funcion,
       (SELECT tm.nombre FROM membresias m
          JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
         WHERE m.id_usuario = 1
         ORDER BY m.fecha_inicio DESC, m.id_membresia DESC LIMIT 1) AS control;

-- 4. fn_renovaciones_membresia
SELECT fn_renovaciones_membresia(1) AS funcion,
       (SELECT renovaciones FROM membresias
         WHERE id_usuario = 1
         ORDER BY fecha_inicio DESC, id_membresia DESC LIMIT 1) AS control;

-- 5. fn_estado_membresia
--    El control muestra estado guardado y vencimiento: si es 'Activa' pero ya venció, la función debe dar 'Vencida'.
SELECT fn_estado_membresia(1) AS funcion,
       (SELECT CONCAT(estado, ' / vence ', fecha_vencimiento) FROM membresias
         WHERE id_usuario = 1
         ORDER BY fecha_inicio DESC, id_membresia DESC LIMIT 1) AS control;

-- ================= RESERVAS =================

-- 6. fn_total_reservas
SELECT fn_total_reservas(1) AS funcion,
       (SELECT COUNT(*) FROM reservas
         WHERE id_usuario = 1 AND estado <> 'Cancelada') AS control;

-- 7. fn_horas_reservadas
SELECT fn_horas_reservadas(1, 9, 2026) AS funcion,
       (SELECT ROUND(COALESCE(SUM(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)), 0) / 60, 2)
          FROM reservas
         WHERE id_usuario = 1 AND estado <> 'Cancelada'
           AND MONTH(fecha_inicio) = 9 AND YEAR(fecha_inicio) = 2026) AS control;

-- 8. fn_espacio_mas_reservado
SELECT fn_espacio_mas_reservado() AS funcion,
       (SELECT id_espacio FROM reservas
         WHERE estado <> 'Cancelada'
         GROUP BY id_espacio
         ORDER BY COUNT(*) DESC, id_espacio ASC LIMIT 1) AS control;

-- 9. fn_reservas_activas
SELECT fn_reservas_activas(1) AS funcion,
       (SELECT COUNT(*) FROM reservas
         WHERE id_usuario = 1
           AND estado IN ('Pendiente de Confirmación', 'Confirmada')
           AND fecha_fin >= NOW()) AS control;

-- 10. fn_duracion_promedio_reservas
SELECT fn_duracion_promedio_reservas(1) AS funcion,
       (SELECT ROUND(COALESCE(AVG(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)), 0) / 60, 2)
          FROM reservas
         WHERE id_espacio = 1 AND estado <> 'Cancelada') AS control;

-- ================= PAGOS Y FACTURACIÓN =================

-- 11. fn_total_pagado
SELECT fn_total_pagado(1) AS funcion,
       (SELECT COALESCE(SUM(p.monto), 0)
          FROM pagos p JOIN facturas f ON f.id_factura = p.id_factura
         WHERE f.id_usuario = 1 AND p.estado_transaccion = 'Pagado') AS control;

-- 12. fn_ingresos_por_mes
SELECT fn_ingresos_por_mes(9, 2026) AS funcion,
       (SELECT COALESCE(SUM(monto), 0) FROM pagos
         WHERE estado_transaccion = 'Pagado'
           AND MONTH(fecha_pago) = 9 AND YEAR(fecha_pago) = 2026) AS control;

-- 13. fn_ingresos_por_membresias
SELECT fn_ingresos_por_membresias() AS funcion,
       (SELECT COALESCE(SUM(p.monto), 0)
          FROM pagos p JOIN facturas f ON f.id_factura = p.id_factura
         WHERE f.id_membresia IS NOT NULL AND p.estado_transaccion = 'Pagado') AS control;

-- 14. fn_ingresos_por_reservas
SELECT fn_ingresos_por_reservas() AS funcion,
       (SELECT COALESCE(SUM(p.monto), 0)
          FROM pagos p JOIN facturas f ON f.id_factura = p.id_factura
         WHERE f.id_reserva IS NOT NULL AND p.estado_transaccion = 'Pagado') AS control;

-- 15. fn_ingresos_por_empresa
SELECT fn_ingresos_por_empresa(1) AS funcion,
       (SELECT COALESCE(SUM(p.monto), 0)
          FROM pagos p
          JOIN facturas f ON f.id_factura = p.id_factura
          JOIN usuarios u ON u.id_usuario = f.id_usuario
         WHERE u.id_empresa = 1 AND p.estado_transaccion = 'Pagado') AS control;

-- ================= ACCESOS Y ASISTENCIAS =================

-- 16. fn_total_asistencias
SELECT fn_total_asistencias(1) AS funcion,
       (SELECT COUNT(*) FROM registros_acceso
         WHERE id_usuario = 1 AND estado_validacion = 'Exitoso') AS control;

-- 17. fn_asistencias_mes
SELECT fn_asistencias_mes(1, 9, 2026) AS funcion,
       (SELECT COUNT(*) FROM registros_acceso
         WHERE id_usuario = 1 AND estado_validacion = 'Exitoso'
           AND MONTH(fecha_hora_entrada) = 9 AND YEAR(fecha_hora_entrada) = 2026) AS control;

-- 18. fn_top_usuario_asistencias
SELECT fn_top_usuario_asistencias() AS funcion,
       (SELECT id_usuario FROM registros_acceso
         WHERE estado_validacion = 'Exitoso'
         GROUP BY id_usuario
         ORDER BY COUNT(*) DESC, id_usuario ASC LIMIT 1) AS control;

-- 19. fn_ultima_asistencia
SELECT fn_ultima_asistencia(1) AS funcion,
       (SELECT MAX(fecha_hora_entrada) FROM registros_acceso
         WHERE id_usuario = 1 AND estado_validacion = 'Exitoso') AS control;

-- 20. fn_promedio_asistencias
SELECT fn_promedio_asistencias() AS funcion,
       ROUND((SELECT COUNT(*) FROM registros_acceso WHERE estado_validacion = 'Exitoso')
             / NULLIF((SELECT COUNT(*) FROM usuarios), 0), 2) AS control;

-- ================= CASOS LÍMITE (usuario/espacio/empresa inexistente) =================
-- Esperado: 0, 0, 'Sin membresía', 0, 'Sin membresía', 0, 0.00, 0, 0.00, 0.00, 0.00, 0, 0 y NULL en la última
SELECT fn_membresia_activa(999999)           AS activa,
       fn_dias_restantes_membresia(999999)   AS dias,
       fn_tipo_membresia(999999)             AS tipo,
       fn_renovaciones_membresia(999999)     AS renov,
       fn_estado_membresia(999999)           AS estado,
       fn_total_reservas(999999)             AS reservas,
       fn_horas_reservadas(999999, 9, 2026)  AS horas,
       fn_reservas_activas(999999)           AS reservas_activas,
       fn_duracion_promedio_reservas(999999) AS duracion,
       fn_total_pagado(999999)               AS pagado,
       fn_ingresos_por_empresa(999999)       AS ing_empresa,
       fn_total_asistencias(999999)          AS asist,
       fn_asistencias_mes(999999, 9, 2026)   AS asist_mes,
       fn_ultima_asistencia(999999)          AS ultima;

-- Mes inválido: debe devolver 0 sin error
SELECT fn_horas_reservadas(1, 13, 2026) AS horas,
       fn_ingresos_por_mes(13, 2026)    AS ingresos,
       fn_asistencias_mes(1, 13, 2026)  AS asist;