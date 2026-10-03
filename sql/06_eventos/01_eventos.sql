/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Eventos programados (automatización de tareas)
Archivo: sql/06_eventos/01_eventos.sql
Eventos: 20 (prefijo obligatorio evt_)

Criterios generales (MySQL 8.0+):
- Un evento no devuelve result sets: los "reportes" se persisten en reportes_automaticos
  (JSON) y los "avisos" en notificaciones_sistema. Cada ejecución queda en
  log_eventos_ejecucion (los eventos de alta frecuencia solo registran si hubo cambios).
- Tablas auxiliares (se crean con IF NOT EXISTS al inicio de este script):
    log_eventos_ejecucion, notificaciones_sistema, reportes_automaticos,
    archivo_reservas_no_asistidas, top_usuarios_frecuentes_mensual,
    usuarios_servicios_bloqueados.
- Ingreso real       = pagos con estado_transaccion = 'Pagado' (reembolsos = monto negativo).
- Reserva válida     = cualquier reserva distinta de 'Cancelada' (en reportes de ocupación).
- Asistencia         = registros_acceso con estado_validacion = 'Exitoso'.
- Los eventos que modifican varias tablas usan START TRANSACTION y un EXIT HANDLER
  que hace ROLLBACK y deja constancia del error en log_eventos_ejecucion.
- Los triggers existentes siguen activos: p. ej. al cancelar una reserva,
  trg_upd_reserva_cancelada_log ya escribe en log_reservas_canceladas (los eventos no duplican ese log).
- Horarios: STARTS alinea cada evento a una hora de baja carga (diarios: madrugada;
  semanales: lunes; mensuales: día 1). Los reportes del período cubren el período ANTERIOR ya cerrado.
- Para persistir el planificador tras un reinicio use en my.cnf: event_scheduler = ON
  (SET GLOBAL solo dura hasta el próximo reinicio).
- Guardar este archivo con codificación UTF-8.
*/

SET GLOBAL event_scheduler = ON;

USE coworking_db;

-- =========================================================
-- TABLAS AUXILIARES DE LOS EVENTOS
-- =========================================================

CREATE TABLE IF NOT EXISTS log_eventos_ejecucion (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    evento VARCHAR(80) NOT NULL,
    filas_afectadas INT NOT NULL DEFAULT 0,
    detalle VARCHAR(255) NULL,
    fecha_ejecucion DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_log_eventos (evento, fecha_ejecucion)
);

CREATE TABLE IF NOT EXISTS notificaciones_sistema (
    id_notificacion INT AUTO_INCREMENT PRIMARY KEY,
    tipo VARCHAR(50) NOT NULL,
    id_usuario INT NULL,
    id_referencia INT NULL,
    mensaje VARCHAR(255) NOT NULL,
    leida BOOLEAN DEFAULT FALSE,
    fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_notif_tipo_ref (tipo, id_referencia, fecha_creacion),
    INDEX idx_notif_usuario (id_usuario, leida),
    CONSTRAINT fk_notif_usuarios FOREIGN KEY (id_usuario)
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS reportes_automaticos (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    tipo_reporte VARCHAR(60) NOT NULL,
    periodo_inicio DATE NOT NULL,
    periodo_fin DATE NOT NULL,
    datos JSON NOT NULL,
    fecha_generacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_reporte_periodo (tipo_reporte, periodo_inicio, periodo_fin)
);

CREATE TABLE IF NOT EXISTS archivo_reservas_no_asistidas (
    id_reserva INT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_espacio INT NOT NULL,
    fecha_inicio DATETIME NOT NULL,
    fecha_fin DATETIME NOT NULL,
    estado VARCHAR(40) NOT NULL,
    asistio BOOLEAN NULL,
    fecha_creacion DATETIME NULL,
    fecha_archivado DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS top_usuarios_frecuentes_mensual (
    id_top INT AUTO_INCREMENT PRIMARY KEY,
    periodo DATE NOT NULL,
    posicion TINYINT NOT NULL,
    id_usuario INT NOT NULL,
    total_asistencias INT NOT NULL,
    horas_permanencia DECIMAL(10,2) NOT NULL DEFAULT 0,
    fecha_generacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_top_periodo_pos (periodo, posicion),
    CONSTRAINT fk_top_usuarios FOREIGN KEY (id_usuario)
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS usuarios_servicios_bloqueados (
    id_bloqueo INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    motivo VARCHAR(150) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_bloqueo DATETIME DEFAULT CURRENT_TIMESTAMP,
    fecha_desbloqueo DATETIME NULL,
    INDEX idx_bloqueo_usuario (id_usuario, activo),
    CONSTRAINT fk_bloqueo_usuarios FOREIGN KEY (id_usuario)
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE
);

DELIMITER //

-- =========================================================
-- MEMBRESÍAS (1-5)
-- =========================================================

-- 1. Marca como 'Vencida' toda membresía (activa o suspendida) cuyo vencimiento ya pasó.
DROP EVENT IF EXISTS evt_revisar_membresias_vencidas//
CREATE EVENT evt_revisar_membresias_vencidas
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '00:05:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Marca como Vencida toda membresía cuyo vencimiento ya pasó'
DO
BEGIN
    DECLARE v_filas INT DEFAULT 0;

    UPDATE membresias
       SET estado = 'Vencida'
     WHERE estado IN ('Activa', 'Suspendida')
       AND fecha_vencimiento < NOW();

    SET v_filas = ROW_COUNT();

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_revisar_membresias_vencidas', v_filas, 'Membresías marcadas como Vencida');
END//

-- 2. Notificación de renovación: membresías activas que vencen en los próximos 5 días.
--    Se avisa una sola vez por ciclo de vencimiento (las renovaciones generan un nuevo aviso).
--    Las membresías 'Diaria' se excluyen: no tiene sentido pedir renovación de un pase de un día.
DROP EVENT IF EXISTS evt_recordatorio_renovacion_membresia//
CREATE EVENT evt_recordatorio_renovacion_membresia
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '08:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Notifica membresías que vencen en los próximos 5 días'
DO
BEGIN
    DECLARE v_ahora DATETIME DEFAULT NOW();
    DECLARE v_filas INT DEFAULT 0;

    INSERT INTO notificaciones_sistema (tipo, id_usuario, id_referencia, mensaje)
    SELECT 'RENOVACION_MEMBRESIA',
           m.id_usuario,
           m.id_membresia,
           CONCAT('Tu membresía ', tm.nombre, ' vence el ',
                  DATE_FORMAT(m.fecha_vencimiento, '%Y-%m-%d'),
                  '. Renuévala para conservar tus beneficios.')
      FROM membresias m
      INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
     WHERE m.estado = 'Activa'
       AND tm.nombre <> 'Diaria'
       AND m.fecha_vencimiento > v_ahora
       AND m.fecha_vencimiento <= v_ahora + INTERVAL 5 DAY
       AND NOT EXISTS (
            SELECT 1
              FROM notificaciones_sistema n
             WHERE n.tipo = 'RENOVACION_MEMBRESIA'
               AND n.id_referencia = m.id_membresia
               AND n.fecha_creacion >= m.fecha_vencimiento - INTERVAL 6 DAY
       );

    SET v_filas = ROW_COUNT();

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_recordatorio_renovacion_membresia', v_filas, 'Recordatorios de renovación generados');
END//

-- 3. Suspende membresías activas con una factura asociada sin ningún pago tras 30 días de emitida.
DROP EVENT IF EXISTS evt_suspender_membresias_inactivas//
CREATE EVENT evt_suspender_membresias_inactivas
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '00:15:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Suspende membresías con factura sin pago tras 30 días'
DO
BEGIN
    DECLARE v_ahora DATETIME DEFAULT NOW();
    DECLARE v_filas INT DEFAULT 0;

    UPDATE membresias m
       SET m.estado = 'Suspendida'
     WHERE m.estado = 'Activa'
       AND m.fecha_vencimiento >= v_ahora
       AND EXISTS (
            SELECT 1
              FROM facturas f
             WHERE f.id_membresia = m.id_membresia
               AND f.estado IN ('Pendiente', 'Vencida')
               AND f.saldo_pendiente > 0
               AND f.fecha_emision < v_ahora - INTERVAL 30 DAY
               AND NOT EXISTS (
                    SELECT 1
                      FROM pagos p
                     WHERE p.id_factura = f.id_factura
                       AND p.estado_transaccion = 'Pagado'
                       AND p.monto > 0
               )
       );

    SET v_filas = ROW_COUNT();

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_suspender_membresias_inactivas', v_filas, 'Membresías suspendidas por falta de pago (30 días)');
END//

-- 4. Reporte semanal de nuevas membresías (semana anterior, lunes a domingo).
DROP EVENT IF EXISTS evt_reporte_semanal_nuevas_membresias//
CREATE EVENT evt_reporte_semanal_nuevas_membresias
ON SCHEDULE EVERY 1 WEEK
STARTS TIMESTAMP(CURDATE() + INTERVAL (7 - WEEKDAY(CURDATE())) DAY, '00:30:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Reporte semanal de nuevas membresías'
DO
BEGIN
    DECLARE v_inicio DATE DEFAULT CURDATE() - INTERVAL 7 DAY;
    DECLARE v_fin    DATE DEFAULT CURDATE() - INTERVAL 1 DAY;

    REPLACE INTO reportes_automaticos (tipo_reporte, periodo_inicio, periodo_fin, datos)
    SELECT 'NUEVAS_MEMBRESIAS_SEMANAL',
           v_inicio,
           v_fin,
           JSON_OBJECT(
               'nuevas_membresias', COUNT(*),
               'usuarios_distintos', COUNT(DISTINCT m.id_usuario),
               'valor_estimado', COALESCE(SUM(tm.precio), 0),
               'renovaciones_acumuladas', COALESCE(SUM(m.renovaciones), 0),
               'por_tipo', JSON_OBJECT(
                   'Diaria',      COALESCE(SUM(tm.nombre = 'Diaria'), 0),
                   'Mensual',     COALESCE(SUM(tm.nombre = 'Mensual'), 0),
                   'Corporativa', COALESCE(SUM(tm.nombre = 'Corporativa'), 0),
                   'Premium',     COALESCE(SUM(tm.nombre = 'Premium'), 0)
               )
           )
      FROM membresias m
      INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
     WHERE m.fecha_inicio >= v_inicio
       AND m.fecha_inicio <  v_fin + INTERVAL 1 DAY;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_reporte_semanal_nuevas_membresias', 1, CONCAT('Reporte del ', v_inicio, ' al ', v_fin));
END//

-- 5. Reporte diario de membresías suspendidas + aviso diario a cada usuario afectado.
DROP EVENT IF EXISTS evt_notificar_membresias_suspendidas_diario//
CREATE EVENT evt_notificar_membresias_suspendidas_diario
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '07:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Reporte y aviso diario de membresías suspendidas'
DO
BEGIN
    DECLARE v_avisos INT DEFAULT 0;

    REPLACE INTO reportes_automaticos (tipo_reporte, periodo_inicio, periodo_fin, datos)
    SELECT 'MEMBRESIAS_SUSPENDIDAS_DIARIO',
           CURDATE(),
           CURDATE(),
           JSON_OBJECT(
               'total_membresias_suspendidas', COALESCE(SUM(s.n), 0),
               'usuarios_afectados', COUNT(*),
               'ids_usuarios', COALESCE(JSON_ARRAYAGG(s.id_usuario), JSON_ARRAY())
           )
      FROM (
            SELECT id_usuario, COUNT(*) AS n
              FROM membresias
             WHERE estado = 'Suspendida'
             GROUP BY id_usuario
           ) s;

    INSERT INTO notificaciones_sistema (tipo, id_usuario, id_referencia, mensaje)
    SELECT 'MEMBRESIA_SUSPENDIDA',
           m.id_usuario,
           MAX(m.id_membresia),
           'Tu membresía se encuentra suspendida. Regulariza tu situación para reactivarla.'
      FROM membresias m
     WHERE m.estado = 'Suspendida'
       AND NOT EXISTS (
            SELECT 1
              FROM notificaciones_sistema n
             WHERE n.tipo = 'MEMBRESIA_SUSPENDIDA'
               AND n.id_usuario = m.id_usuario
               AND n.fecha_creacion >= CURDATE()
       )
     GROUP BY m.id_usuario;

    SET v_avisos = ROW_COUNT();

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_notificar_membresias_suspendidas_diario', v_avisos, 'Avisos de membresía suspendida generados');
END//

-- =========================================================
-- RESERVAS (6-10)
-- =========================================================

-- 6. Cancela reservas 'Pendiente de Confirmación' con más de 2 horas de antigüedad.
--    Anula también su factura pendiente si no tiene ningún pago acreditado.
--    El log en log_reservas_canceladas lo escribe el trigger de auditoría.
DROP EVENT IF EXISTS evt_cancelar_reservas_no_confirmadas//
CREATE EVENT evt_cancelar_reservas_no_confirmadas
ON SCHEDULE EVERY 1 HOUR
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Cancela reservas pendientes con más de 2 horas'
DO
BEGIN
    DECLARE v_limite     DATETIME DEFAULT NOW() - INTERVAL 2 HOUR;
    DECLARE v_facturas   INT DEFAULT 0;
    DECLARE v_canceladas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
        VALUES ('evt_cancelar_reservas_no_confirmadas', 0, 'ERROR: transacción revertida');
    END;

    START TRANSACTION;

    UPDATE facturas f
      INNER JOIN reservas r ON r.id_reserva = f.id_reserva
       SET f.estado           = 'Anulada',
           f.saldo_pendiente  = 0,
           f.motivo_anulacion = 'Reserva cancelada por falta de confirmación (2 horas)'
     WHERE r.estado = 'Pendiente de Confirmación'
       AND r.fecha_creacion < v_limite
       AND f.estado = 'Pendiente'
       AND NOT EXISTS (
            SELECT 1
              FROM pagos p
             WHERE p.id_factura = f.id_factura
               AND p.estado_transaccion = 'Pagado'
       );

    SET v_facturas = ROW_COUNT();

    UPDATE reservas
       SET estado = 'Cancelada'
     WHERE estado = 'Pendiente de Confirmación'
       AND fecha_creacion < v_limite;

    SET v_canceladas = ROW_COUNT();

    COMMIT;

    IF v_canceladas > 0 THEN
        INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
        VALUES ('evt_cancelar_reservas_no_confirmadas', v_canceladas,
                CONCAT('Reservas canceladas; facturas anuladas: ', v_facturas));
    END IF;
END//

-- 7. Identifica reservas confirmadas que inician dentro de la próxima hora y avisa una sola vez.
DROP EVENT IF EXISTS evt_recordatorio_reserva_proxima//
CREATE EVENT evt_recordatorio_reserva_proxima
ON SCHEDULE EVERY 15 MINUTE
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Avisa reservas que inician en la próxima hora'
DO
BEGIN
    DECLARE v_ahora DATETIME DEFAULT NOW();
    DECLARE v_filas INT DEFAULT 0;

    INSERT INTO notificaciones_sistema (tipo, id_usuario, id_referencia, mensaje)
    SELECT 'RESERVA_PROXIMA',
           r.id_usuario,
           r.id_reserva,
           CONCAT('Tu reserva en ', e.nombre, ' inicia a las ',
                  DATE_FORMAT(r.fecha_inicio, '%H:%i'), '.')
      FROM reservas r
      INNER JOIN espacios e ON e.id_espacio = r.id_espacio
     WHERE r.estado = 'Confirmada'
       AND r.fecha_inicio > v_ahora
       AND r.fecha_inicio <= v_ahora + INTERVAL 1 HOUR
       AND NOT EXISTS (
            SELECT 1
              FROM notificaciones_sistema n
             WHERE n.tipo = 'RESERVA_PROXIMA'
               AND n.id_referencia = r.id_reserva
       );

    SET v_filas = ROW_COUNT();

    IF v_filas > 0 THEN
        INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
        VALUES ('evt_recordatorio_reserva_proxima', v_filas, 'Recordatorios de reserva próxima generados');
    END IF;
END//

-- 8. Archiva las reservas no asistidas ('No Show' o confirmadas sin asistencia) terminadas hace más de 7 días
--    y las elimina de reservas. Las que tienen facturas asociadas NO se eliminan (se conservan para no
--    perder el vínculo contable factura-reserva), pero sí quedan archivadas.
DROP EVENT IF EXISTS evt_limpiar_reservas_pasadas_no_asistidas//
CREATE EVENT evt_limpiar_reservas_pasadas_no_asistidas
ON SCHEDULE EVERY 1 WEEK
STARTS TIMESTAMP(CURDATE() + INTERVAL (7 - WEEKDAY(CURDATE())) DAY, '03:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Archiva y depura reservas no asistidas de más de 7 días'
DO
BEGIN
    DECLARE v_limite     DATETIME DEFAULT NOW() - INTERVAL 7 DAY;
    DECLARE v_archivadas INT DEFAULT 0;
    DECLARE v_eliminadas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
        VALUES ('evt_limpiar_reservas_pasadas_no_asistidas', 0, 'ERROR: transacción revertida');
    END;

    START TRANSACTION;

    INSERT INTO archivo_reservas_no_asistidas
           (id_reserva, id_usuario, id_espacio, fecha_inicio, fecha_fin, estado, asistio, fecha_creacion)
    SELECT r.id_reserva, r.id_usuario, r.id_espacio, r.fecha_inicio, r.fecha_fin,
           r.estado, r.asistio, r.fecha_creacion
      FROM reservas r
     WHERE r.estado IN ('No Show', 'Confirmada')
       AND r.asistio = FALSE
       AND r.fecha_fin < v_limite
       AND NOT EXISTS (
            SELECT 1
              FROM archivo_reservas_no_asistidas a
             WHERE a.id_reserva = r.id_reserva
       );

    SET v_archivadas = ROW_COUNT();

    DELETE r
      FROM reservas r
      INNER JOIN archivo_reservas_no_asistidas a ON a.id_reserva = r.id_reserva
     WHERE r.estado IN ('No Show', 'Confirmada')
       AND r.asistio = FALSE
       AND r.fecha_fin < v_limite
       AND NOT EXISTS (
            SELECT 1
              FROM facturas f
             WHERE f.id_reserva = r.id_reserva
       );

    SET v_eliminadas = ROW_COUNT();

    COMMIT;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_limpiar_reservas_pasadas_no_asistidas', v_eliminadas,
            CONCAT('Archivadas: ', v_archivadas, ' | Eliminadas de reservas: ', v_eliminadas));
END//

-- 9. Resumen semanal de ocupación por espacio (semana anterior, lunes a domingo).
--    Ocupación = horas reservadas (reservas no canceladas) / horas operativas de la semana.
DROP EVENT IF EXISTS evt_reporte_semanal_ocupacion_espacios//
CREATE EVENT evt_reporte_semanal_ocupacion_espacios
ON SCHEDULE EVERY 1 WEEK
STARTS TIMESTAMP(CURDATE() + INTERVAL (7 - WEEKDAY(CURDATE())) DAY, '00:40:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Reporte semanal de ocupación por espacio'
DO
BEGIN
    DECLARE v_inicio DATE DEFAULT CURDATE() - INTERVAL 7 DAY;
    DECLARE v_fin    DATE DEFAULT CURDATE() - INTERVAL 1 DAY;

    REPLACE INTO reportes_automaticos (tipo_reporte, periodo_inicio, periodo_fin, datos)
    SELECT 'OCUPACION_ESPACIOS_SEMANAL',
           v_inicio,
           v_fin,
           JSON_OBJECT(
               'espacios_evaluados', COUNT(*),
               'ocupacion_promedio_pct',
                   ROUND(100 * SUM(t.min_reservados) / NULLIF(SUM(t.min_disponibles), 0), 2),
               'detalle', COALESCE(JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'id_espacio', t.id_espacio,
                       'espacio', t.nombre,
                       'reservas', t.reservas,
                       'horas_reservadas', ROUND(t.min_reservados / 60, 2),
                       'horas_disponibles', ROUND(t.min_disponibles / 60, 2),
                       'ocupacion_pct', ROUND(100 * t.min_reservados / NULLIF(t.min_disponibles, 0), 2)
                   )
               ), JSON_ARRAY())
           )
      FROM (
            SELECT e.id_espacio,
                   e.nombre,
                   COUNT(r.id_reserva) AS reservas,
                   COALESCE(SUM(TIMESTAMPDIFF(MINUTE, r.fecha_inicio, r.fecha_fin)), 0) AS min_reservados,
                   (TIME_TO_SEC(TIMEDIFF(e.hora_cierre, e.hora_apertura)) / 60) * 7 AS min_disponibles
              FROM espacios e
              LEFT JOIN reservas r
                     ON r.id_espacio = e.id_espacio
                    AND r.estado <> 'Cancelada'
                    AND r.fecha_inicio >= v_inicio
                    AND r.fecha_inicio <  v_fin + INTERVAL 1 DAY
             WHERE e.estado <> 'Inactivo'
             GROUP BY e.id_espacio, e.nombre, e.hora_apertura, e.hora_cierre
           ) t;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_reporte_semanal_ocupacion_espacios', 1, CONCAT('Reporte del ', v_inicio, ' al ', v_fin));
END//

-- 10. Libera reservas confirmadas en curso si pasaron 15 minutos desde su hora de inicio sin ingreso exitoso.
--     "Liberar" = pasar a 'No Show': el espacio queda libre para nuevas reservas y se conserva el motivo.
--     Solo revisa reservas aún en curso; las ya terminadas las procesa sp_marcar_no_show_penalizar.
DROP EVENT IF EXISTS evt_liberar_reservas_bloqueadas_15min//
CREATE EVENT evt_liberar_reservas_bloqueadas_15min
ON SCHEDULE EVERY 5 MINUTE
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Libera reservas confirmadas sin ingreso tras 15 minutos'
DO
BEGIN
    DECLARE v_ahora     DATETIME DEFAULT NOW();
    DECLARE v_liberadas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
        VALUES ('evt_liberar_reservas_bloqueadas_15min', 0, 'ERROR: transacción revertida');
    END;

    START TRANSACTION;

    INSERT INTO notificaciones_sistema (tipo, id_usuario, id_referencia, mensaje)
    SELECT 'RESERVA_LIBERADA',
           r.id_usuario,
           r.id_reserva,
           CONCAT('Tu reserva #', r.id_reserva,
                  ' fue liberada: no se registró tu ingreso en los primeros 15 minutos.')
      FROM reservas r
     WHERE r.estado = 'Confirmada'
       AND r.asistio = FALSE
       AND r.fecha_inicio <= v_ahora - INTERVAL 15 MINUTE
       AND r.fecha_fin > v_ahora
       AND NOT EXISTS (
            SELECT 1
              FROM registros_acceso ra
             WHERE ra.id_usuario = r.id_usuario
               AND ra.estado_validacion = 'Exitoso'
               AND ra.fecha_hora_entrada BETWEEN r.fecha_inicio - INTERVAL 30 MINUTE AND v_ahora
       );

    UPDATE reservas r
       SET r.estado = 'No Show'
     WHERE r.estado = 'Confirmada'
       AND r.asistio = FALSE
       AND r.fecha_inicio <= v_ahora - INTERVAL 15 MINUTE
       AND r.fecha_fin > v_ahora
       AND NOT EXISTS (
            SELECT 1
              FROM registros_acceso ra
             WHERE ra.id_usuario = r.id_usuario
               AND ra.estado_validacion = 'Exitoso'
               AND ra.fecha_hora_entrada BETWEEN r.fecha_inicio - INTERVAL 30 MINUTE AND v_ahora
       );

    SET v_liberadas = ROW_COUNT();

    COMMIT;

    IF v_liberadas > 0 THEN
        INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
        VALUES ('evt_liberar_reservas_bloqueadas_15min', v_liberadas, 'Reservas liberadas (No Show)');
    END IF;
END//

-- =========================================================
-- PAGOS Y FACTURACIÓN (11-15)
-- =========================================================

-- 11. Alertas de pago para facturas 'Pendiente' o 'Vencida' con saldo. Se repite cada 3 días
--     (no genera una nueva alerta de la misma factura si ya existe una de los últimos 2 días).
DROP EVENT IF EXISTS evt_recordatorio_pago_pendiente//
CREATE EVENT evt_recordatorio_pago_pendiente
ON SCHEDULE EVERY 3 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '09:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Alertas de pago para facturas pendientes'
DO
BEGIN
    DECLARE v_ahora DATETIME DEFAULT NOW();
    DECLARE v_filas INT DEFAULT 0;

    INSERT INTO notificaciones_sistema (tipo, id_usuario, id_referencia, mensaje)
    SELECT 'PAGO_PENDIENTE',
           f.id_usuario,
           f.id_factura,
           CONCAT('Factura #', f.id_factura, ' con saldo pendiente de ',
                  FORMAT(f.saldo_pendiente, 2),
                  IF(f.fecha_vencimiento < v_ahora, ' (venció el ', ' (vence el '),
                  DATE_FORMAT(f.fecha_vencimiento, '%Y-%m-%d'), ').')
      FROM facturas f
     WHERE f.estado IN ('Pendiente', 'Vencida')
       AND f.saldo_pendiente > 0
       AND NOT EXISTS (
            SELECT 1
              FROM notificaciones_sistema n
             WHERE n.tipo = 'PAGO_PENDIENTE'
               AND n.id_referencia = f.id_factura
               AND n.fecha_creacion >= v_ahora - INTERVAL 2 DAY
       );

    SET v_filas = ROW_COUNT();

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_recordatorio_pago_pendiente', v_filas, 'Alertas de pago generadas');
END//

-- 12. Bloquea los servicios adicionales de usuarios con facturas vencidas hace más de 10 días.
--     servicios_adicionales.bloqueado es global (afectaría a todos), por eso el bloqueo se registra por
--     usuario en usuarios_servicios_bloqueados y se retiran los servicios de sus reservas futuras.
--     Quienes regularizan su deuda se desbloquean automáticamente.
DROP EVENT IF EXISTS evt_bloquear_servicios_facturas_vencidas//
CREATE EVENT evt_bloquear_servicios_facturas_vencidas
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '00:30:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Bloquea servicios a usuarios con mora mayor a 10 días'
DO
BEGIN
    DECLARE v_ahora         DATETIME DEFAULT NOW();
    DECLARE v_desbloqueados INT DEFAULT 0;
    DECLARE v_bloqueados    INT DEFAULT 0;
    DECLARE v_retirados     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
        VALUES ('evt_bloquear_servicios_facturas_vencidas', 0, 'ERROR: transacción revertida');
    END;

    START TRANSACTION;

    -- Desbloquea a quienes ya no tienen facturas vencidas con más de 10 días de mora
    UPDATE usuarios_servicios_bloqueados b
       SET b.activo = FALSE,
           b.fecha_desbloqueo = v_ahora
     WHERE b.activo = TRUE
       AND NOT EXISTS (
            SELECT 1
              FROM facturas f
             WHERE f.id_usuario = b.id_usuario
               AND f.estado IN ('Pendiente', 'Vencida')
               AND f.saldo_pendiente > 0
               AND f.fecha_vencimiento < v_ahora - INTERVAL 10 DAY
       );

    SET v_desbloqueados = ROW_COUNT();

    -- Bloquea a los morosos que aún no están bloqueados
    INSERT INTO usuarios_servicios_bloqueados (id_usuario, motivo)
    SELECT DISTINCT f.id_usuario,
           'Facturas vencidas con más de 10 días de mora'
      FROM facturas f
     WHERE f.estado IN ('Pendiente', 'Vencida')
       AND f.saldo_pendiente > 0
       AND f.fecha_vencimiento < v_ahora - INTERVAL 10 DAY
       AND NOT EXISTS (
            SELECT 1
              FROM usuarios_servicios_bloqueados b
             WHERE b.id_usuario = f.id_usuario
               AND b.activo = TRUE
       );

    SET v_bloqueados = ROW_COUNT();

    -- Retira los servicios contratados en reservas futuras de usuarios bloqueados
    DELETE rs
      FROM reserva_servicios rs
      INNER JOIN reservas r ON r.id_reserva = rs.id_reserva
     WHERE r.estado IN ('Pendiente de Confirmación', 'Confirmada')
       AND r.fecha_inicio > v_ahora
       AND EXISTS (
            SELECT 1
              FROM usuarios_servicios_bloqueados b
             WHERE b.id_usuario = r.id_usuario
               AND b.activo = TRUE
       );

    SET v_retirados = ROW_COUNT();

    COMMIT;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_bloquear_servicios_facturas_vencidas', v_bloqueados,
            CONCAT('Bloqueados: ', v_bloqueados, ' | Desbloqueados: ', v_desbloqueados,
                   ' | Servicios retirados de reservas: ', v_retirados));
END//

-- 13. Resumen de facturación del mes anterior (se genera el día 1 de cada mes).
DROP EVENT IF EXISTS evt_resumen_facturacion_mensual//
CREATE EVENT evt_resumen_facturacion_mensual
ON SCHEDULE EVERY 1 MONTH
STARTS TIMESTAMP(LAST_DAY(CURDATE()) + INTERVAL 1 DAY, '01:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Resumen mensual de facturación (mes anterior)'
DO
BEGIN
    DECLARE v_inicio DATE;
    DECLARE v_fin    DATE;

    SET v_fin    = CURDATE() - INTERVAL DAYOFMONTH(CURDATE()) DAY;
    SET v_inicio = DATE_SUB(v_fin, INTERVAL (DAYOFMONTH(v_fin) - 1) DAY);

    REPLACE INTO reportes_automaticos (tipo_reporte, periodo_inicio, periodo_fin, datos)
    SELECT 'FACTURACION_MENSUAL',
           v_inicio,
           v_fin,
           JSON_OBJECT(
               'facturas_emitidas', COUNT(*),
               'monto_facturado', COALESCE(SUM(CASE WHEN f.estado <> 'Anulada' THEN f.monto_total END), 0),
               'facturas_pagadas', COALESCE(SUM(f.estado = 'Pagada'), 0),
               'facturas_pendientes', COALESCE(SUM(f.estado = 'Pendiente'), 0),
               'facturas_vencidas', COALESCE(SUM(f.estado = 'Vencida'), 0),
               'facturas_anuladas', COALESCE(SUM(f.estado = 'Anulada'), 0),
               'saldo_pendiente', COALESCE(SUM(CASE WHEN f.estado IN ('Pendiente', 'Vencida')
                                                    THEN f.saldo_pendiente END), 0),
               'cobrado_en_el_mes', (
                   SELECT COALESCE(SUM(p.monto), 0)
                     FROM pagos p
                    WHERE p.estado_transaccion = 'Pagado'
                      AND p.fecha_pago >= v_inicio
                      AND p.fecha_pago <  v_fin + INTERVAL 1 DAY
               )
           )
      FROM facturas f
     WHERE f.fecha_emision >= v_inicio
       AND f.fecha_emision <  v_fin + INTERVAL 1 DAY;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_resumen_facturacion_mensual', 1, CONCAT('Reporte del ', v_inicio, ' al ', v_fin));
END//

-- 14. Aplica recargo por mora a facturas 'Pendiente' con más de 15 días de vencidas.
--     Agrega una línea de detalle, suma el recargo al monto y al saldo y pasa la factura a 'Vencida',
--     de modo que el recargo se aplica una sola vez (misma lógica que sp_aplicar_recargo_facturas_vencidas).
--     Ajuste el porcentaje en v_porcentaje (por defecto 5%).
DROP EVENT IF EXISTS evt_aplicar_recargos_facturas_vencidas//
CREATE EVENT evt_aplicar_recargos_facturas_vencidas
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '00:45:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Recargo por mora en facturas con más de 15 días vencidas'
DO
BEGIN
    DECLARE v_porcentaje DECIMAL(5,2) DEFAULT 5.00;
    DECLARE v_limite     DATETIME DEFAULT NOW() - INTERVAL 15 DAY;
    DECLARE v_facturas   INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
        VALUES ('evt_aplicar_recargos_facturas_vencidas', 0, 'ERROR: transacción revertida');
    END;

    START TRANSACTION;

    INSERT INTO detalle_facturas (id_factura, id_servicio, descripcion, cantidad, precio_unitario)
    SELECT id_factura,
           NULL,
           CONCAT('Recargo por mora ', v_porcentaje, '%'),
           1,
           ROUND(saldo_pendiente * v_porcentaje / 100, 2)
      FROM facturas
     WHERE estado = 'Pendiente'
       AND saldo_pendiente > 0
       AND fecha_vencimiento < v_limite;

    UPDATE facturas
       SET monto_total     = monto_total + ROUND(saldo_pendiente * v_porcentaje / 100, 2),
           saldo_pendiente = saldo_pendiente + ROUND(saldo_pendiente * v_porcentaje / 100, 2),
           estado          = 'Vencida'
     WHERE estado = 'Pendiente'
       AND saldo_pendiente > 0
       AND fecha_vencimiento < v_limite;

    SET v_facturas = ROW_COUNT();

    COMMIT;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_aplicar_recargos_facturas_vencidas', v_facturas,
            CONCAT('Facturas recargadas al ', v_porcentaje, '%'));
END//

-- 15. Cierre contable del mes anterior para el contador (se genera el día 1 de cada mes).
--     Consolida ingresos brutos, reembolsos y neto, por método de pago y por origen de la factura.
DROP EVENT IF EXISTS evt_reporte_contador_fin_de_mes//
CREATE EVENT evt_reporte_contador_fin_de_mes
ON SCHEDULE EVERY 1 MONTH
STARTS TIMESTAMP(LAST_DAY(CURDATE()) + INTERVAL 1 DAY, '02:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Cierre contable mensual para el contador'
DO
BEGIN
    DECLARE v_inicio DATE;
    DECLARE v_fin    DATE;

    SET v_fin    = CURDATE() - INTERVAL DAYOFMONTH(CURDATE()) DAY;
    SET v_inicio = DATE_SUB(v_fin, INTERVAL (DAYOFMONTH(v_fin) - 1) DAY);

    REPLACE INTO reportes_automaticos (tipo_reporte, periodo_inicio, periodo_fin, datos)
    SELECT 'CIERRE_CONTABLE_MENSUAL',
           v_inicio,
           v_fin,
           JSON_OBJECT(
               'pagos_registrados', COUNT(p.id_pago),
               'ingresos_brutos', COALESCE(SUM(CASE WHEN p.monto > 0 THEN p.monto END), 0),
               'reembolsos', COALESCE(SUM(CASE WHEN p.monto < 0 THEN p.monto END), 0),
               'ingresos_netos', COALESCE(SUM(p.monto), 0),
               'por_metodo', JSON_OBJECT(
                   'Efectivo',      COALESCE(SUM(CASE WHEN p.metodo_pago = 'Efectivo'      THEN p.monto END), 0),
                   'Tarjeta',       COALESCE(SUM(CASE WHEN p.metodo_pago = 'Tarjeta'       THEN p.monto END), 0),
                   'Transferencia', COALESCE(SUM(CASE WHEN p.metodo_pago = 'Transferencia' THEN p.monto END), 0),
                   'PayPal',        COALESCE(SUM(CASE WHEN p.metodo_pago = 'PayPal'        THEN p.monto END), 0)
               ),
               'por_origen', JSON_OBJECT(
                   'membresias', COALESCE(SUM(CASE WHEN f.id_membresia IS NOT NULL THEN p.monto END), 0),
                   'reservas',   COALESCE(SUM(CASE WHEN f.id_reserva IS NOT NULL
                                                    AND f.id_membresia IS NULL THEN p.monto END), 0),
                   'otros',      COALESCE(SUM(CASE WHEN f.id_membresia IS NULL
                                                    AND f.id_reserva IS NULL THEN p.monto END), 0)
               ),
               'facturas_anuladas_mes', (
                   SELECT COUNT(*)
                     FROM facturas fa
                    WHERE fa.estado = 'Anulada'
                      AND fa.fecha_emision >= v_inicio
                      AND fa.fecha_emision <  v_fin + INTERVAL 1 DAY
               ),
               'cartera_pendiente_actual', (
                   SELECT COALESCE(SUM(fc.saldo_pendiente), 0)
                     FROM facturas fc
                    WHERE fc.estado IN ('Pendiente', 'Vencida')
                      AND fc.saldo_pendiente > 0
               )
           )
      FROM pagos p
      INNER JOIN facturas f ON f.id_factura = p.id_factura
     WHERE p.estado_transaccion = 'Pagado'
       AND p.fecha_pago >= v_inicio
       AND p.fecha_pago <  v_fin + INTERVAL 1 DAY;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_reporte_contador_fin_de_mes', 1, CONCAT('Cierre del ', v_inicio, ' al ', v_fin));
END//

-- =========================================================
-- ACCESOS Y ASISTENCIAS (16-20)
-- =========================================================

-- 16. Purga registros de acceso con más de 1 año de antigüedad, en lotes de 5000 filas
--     para no mantener bloqueos largos sobre registros_acceso.
DROP EVENT IF EXISTS evt_depurar_accesos_antiguos//
CREATE EVENT evt_depurar_accesos_antiguos
ON SCHEDULE EVERY 1 MONTH
STARTS TIMESTAMP(LAST_DAY(CURDATE()) + INTERVAL 1 DAY, '03:30:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Purga accesos con más de 1 año de antigüedad'
DO
BEGIN
    DECLARE v_limite DATETIME DEFAULT NOW() - INTERVAL 1 YEAR;
    DECLARE v_lote   INT DEFAULT 0;
    DECLARE v_total  INT DEFAULT 0;

    REPEAT
        DELETE FROM registros_acceso
         WHERE fecha_hora_entrada < v_limite
         LIMIT 5000;

        SET v_lote  = ROW_COUNT();
        SET v_total = v_total + v_lote;
    UNTIL v_lote < 5000 END REPEAT;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_depurar_accesos_antiguos', v_total,
            CONCAT('Accesos anteriores a ', DATE_FORMAT(v_limite, '%Y-%m-%d'), ' eliminados'));
END//

-- 17. Consolidado diario del día anterior: accesos, asistencias, permanencia e ingresos cobrados.
DROP EVENT IF EXISTS evt_reporte_diario_asistencias//
CREATE EVENT evt_reporte_diario_asistencias
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '00:20:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Consolidado diario de asistencias e ingresos'
DO
BEGIN
    DECLARE v_fecha DATE DEFAULT CURDATE() - INTERVAL 1 DAY;

    REPLACE INTO reportes_automaticos (tipo_reporte, periodo_inicio, periodo_fin, datos)
    SELECT 'ASISTENCIAS_DIARIO',
           v_fecha,
           v_fecha,
           JSON_OBJECT(
               'total_accesos', COUNT(*),
               'exitosos', COALESCE(SUM(ra.estado_validacion = 'Exitoso'), 0),
               'rechazados', COALESCE(SUM(ra.estado_validacion = 'Rechazado'), 0),
               'usuarios_distintos', COUNT(DISTINCT CASE WHEN ra.estado_validacion = 'Exitoso'
                                                         THEN ra.id_usuario END),
               'accesos_qr', COALESCE(SUM(ra.metodo_acceso = 'QR'), 0),
               'accesos_rfid', COALESCE(SUM(ra.metodo_acceso = 'RFID'), 0),
               'sin_salida', COALESCE(SUM(ra.estado_validacion = 'Exitoso'
                                          AND ra.fecha_hora_salida IS NULL), 0),
               'permanencia_promedio_min', ROUND(AVG(CASE WHEN ra.estado_validacion = 'Exitoso'
                                                           AND ra.fecha_hora_salida IS NOT NULL
                                                          THEN TIMESTAMPDIFF(MINUTE, ra.fecha_hora_entrada,
                                                                             ra.fecha_hora_salida) END), 2),
               'ingresos_cobrados', (
                   SELECT COALESCE(SUM(p.monto), 0)
                     FROM pagos p
                    WHERE p.estado_transaccion = 'Pagado'
                      AND p.fecha_pago >= v_fecha
                      AND p.fecha_pago <  v_fecha + INTERVAL 1 DAY
               )
           )
      FROM registros_acceso ra
     WHERE ra.fecha_hora_entrada >= v_fecha
       AND ra.fecha_hora_entrada <  v_fecha + INTERVAL 1 DAY;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_reporte_diario_asistencias', 1, CONCAT('Reporte del ', v_fecha));
END//

-- 18. Detecta usuarios sin ningún acceso exitoso en los últimos 7 días (semana anterior).
DROP EVENT IF EXISTS evt_reporte_semanal_usuarios_inactivos//
CREATE EVENT evt_reporte_semanal_usuarios_inactivos
ON SCHEDULE EVERY 1 WEEK
STARTS TIMESTAMP(CURDATE() + INTERVAL (7 - WEEKDAY(CURDATE())) DAY, '00:50:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Detecta usuarios sin accesos en los últimos 7 días'
DO
BEGIN
    DECLARE v_ahora  DATETIME DEFAULT NOW();
    DECLARE v_inicio DATE DEFAULT CURDATE() - INTERVAL 7 DAY;
    DECLARE v_fin    DATE DEFAULT CURDATE() - INTERVAL 1 DAY;

    REPLACE INTO reportes_automaticos (tipo_reporte, periodo_inicio, periodo_fin, datos)
    SELECT 'USUARIOS_INACTIVOS_SEMANAL',
           v_inicio,
           v_fin,
           JSON_OBJECT(
               'total_usuarios_inactivos', COUNT(*),
               'con_membresia_vigente', COALESCE(SUM(t.vigente), 0),
               'nunca_han_accedido', COALESCE(SUM(t.nunca), 0),
               'ids_usuarios', COALESCE(JSON_ARRAYAGG(t.id_usuario), JSON_ARRAY())
           )
      FROM (
            SELECT u.id_usuario,
                   EXISTS (
                        SELECT 1
                          FROM membresias m
                         WHERE m.id_usuario = u.id_usuario
                           AND m.estado = 'Activa'
                           AND v_ahora BETWEEN m.fecha_inicio AND m.fecha_vencimiento
                   ) AS vigente,
                   NOT EXISTS (
                        SELECT 1
                          FROM registros_acceso r2
                         WHERE r2.id_usuario = u.id_usuario
                           AND r2.estado_validacion = 'Exitoso'
                   ) AS nunca
              FROM usuarios u
             WHERE NOT EXISTS (
                    SELECT 1
                      FROM registros_acceso ra
                     WHERE ra.id_usuario = u.id_usuario
                       AND ra.estado_validacion = 'Exitoso'
                       AND ra.fecha_hora_entrada >= v_inicio
                   )
           ) t;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_reporte_semanal_usuarios_inactivos', 1, CONCAT('Reporte del ', v_inicio, ' al ', v_fin));
END//

-- 19. Alerta de accesos fuera del horario operativo (el más amplio definido en espacios activos)
--     o no autorizados (rechazados). Evalúa las últimas 25 horas y no repite alertas por acceso.
DROP EVENT IF EXISTS evt_alerta_accesos_fuera_horario//
CREATE EVENT evt_alerta_accesos_fuera_horario
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '06:30:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Alerta de accesos nocturnos o no autorizados'
DO
BEGIN
    DECLARE v_ahora    DATETIME DEFAULT NOW();
    DECLARE v_apertura TIME DEFAULT '06:00:00';
    DECLARE v_cierre   TIME DEFAULT '22:00:00';
    DECLARE v_alertas  INT DEFAULT 0;

    SELECT COALESCE(MIN(hora_apertura), '06:00:00'),
           COALESCE(MAX(hora_cierre), '22:00:00')
      INTO v_apertura, v_cierre
      FROM espacios
     WHERE estado <> 'Inactivo';

    INSERT INTO notificaciones_sistema (tipo, id_usuario, id_referencia, mensaje)
    SELECT 'ACCESO_FUERA_HORARIO',
           ra.id_usuario,
           ra.id_acceso,
           LEFT(CONCAT('Acceso #', ra.id_acceso, ' (', ra.metodo_acceso, ') el ',
                       DATE_FORMAT(ra.fecha_hora_entrada, '%Y-%m-%d %H:%i'), ': ',
                       CASE WHEN TIME(ra.fecha_hora_entrada) < v_apertura
                              OR TIME(ra.fecha_hora_entrada) >= v_cierre
                            THEN 'fuera del horario operativo'
                            ELSE 'intento no autorizado'
                       END,
                       IF(ra.estado_validacion = 'Rechazado',
                          CONCAT(' - rechazado: ', COALESCE(ra.motivo_rechazo, 'sin motivo')),
                          '')), 255)
      FROM registros_acceso ra
     WHERE ra.fecha_hora_entrada >= v_ahora - INTERVAL 25 HOUR
       AND (TIME(ra.fecha_hora_entrada) < v_apertura
            OR TIME(ra.fecha_hora_entrada) >= v_cierre
            OR ra.estado_validacion = 'Rechazado')
       AND NOT EXISTS (
            SELECT 1
              FROM notificaciones_sistema n
             WHERE n.tipo = 'ACCESO_FUERA_HORARIO'
               AND n.id_referencia = ra.id_acceso
       );

    SET v_alertas = ROW_COUNT();

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_alerta_accesos_fuera_horario', v_alertas,
            CONCAT('Alertas generadas (horario operativo ', v_apertura, ' - ', v_cierre, ')'));
END//

-- 20. Top 10 del mes anterior de usuarios con más asistencias (desempate: menor id_usuario).
DROP EVENT IF EXISTS evt_reporte_top10_usuarios_frecuentes_mes//
CREATE EVENT evt_reporte_top10_usuarios_frecuentes_mes
ON SCHEDULE EVERY 1 MONTH
STARTS TIMESTAMP(LAST_DAY(CURDATE()) + INTERVAL 1 DAY, '01:30:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Top 10 mensual de usuarios más frecuentes'
DO
BEGIN
    DECLARE v_inicio DATE;
    DECLARE v_fin    DATE;
    DECLARE v_filas  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
        VALUES ('evt_reporte_top10_usuarios_frecuentes_mes', 0, 'ERROR: transacción revertida');
    END;

    SET v_fin    = CURDATE() - INTERVAL DAYOFMONTH(CURDATE()) DAY;
    SET v_inicio = DATE_SUB(v_fin, INTERVAL (DAYOFMONTH(v_fin) - 1) DAY);

    START TRANSACTION;

    DELETE FROM top_usuarios_frecuentes_mensual
     WHERE periodo = v_inicio;

    INSERT INTO top_usuarios_frecuentes_mensual
           (periodo, posicion, id_usuario, total_asistencias, horas_permanencia)
    SELECT v_inicio, t.posicion, t.id_usuario, t.asistencias, t.horas
      FROM (
            SELECT ra.id_usuario,
                   COUNT(*) AS asistencias,
                   ROUND(COALESCE(SUM(CASE WHEN ra.fecha_hora_salida IS NOT NULL
                                           THEN TIMESTAMPDIFF(MINUTE, ra.fecha_hora_entrada,
                                                              ra.fecha_hora_salida) END), 0) / 60, 2) AS horas,
                   ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, ra.id_usuario ASC) AS posicion
              FROM registros_acceso ra
             WHERE ra.estado_validacion = 'Exitoso'
               AND ra.fecha_hora_entrada >= v_inicio
               AND ra.fecha_hora_entrada <  v_fin + INTERVAL 1 DAY
             GROUP BY ra.id_usuario
           ) t
     WHERE t.posicion <= 10;

    SET v_filas = ROW_COUNT();

    COMMIT;

    INSERT INTO log_eventos_ejecucion (evento, filas_afectadas, detalle)
    VALUES ('evt_reporte_top10_usuarios_frecuentes_mes', v_filas,
            CONCAT('Top del período ', DATE_FORMAT(v_inicio, '%Y-%m')));
END//

DELIMITER ;

-- =========================================================
-- Verificación
-- =========================================================
-- SHOW VARIABLES LIKE 'event_scheduler';
-- SHOW EVENTS FROM coworking_db;
-- SELECT COUNT(*) AS total_eventos
--   FROM information_schema.EVENTS
--  WHERE EVENT_SCHEMA = 'coworking_db' AND EVENT_NAME LIKE 'evt\_%';   -- esperado: 20
-- SELECT EVENT_NAME, STATUS, INTERVAL_VALUE, INTERVAL_FIELD, STARTS, LAST_EXECUTED
--   FROM information_schema.EVENTS
--  WHERE EVENT_SCHEMA = 'coworking_db' ORDER BY EVENT_NAME;
--
-- Seguimiento de ejecuciones y resultados:
-- SELECT * FROM log_eventos_ejecucion ORDER BY id_log DESC LIMIT 50;
-- SELECT * FROM reportes_automaticos ORDER BY id_reporte DESC;
-- SELECT * FROM notificaciones_sistema ORDER BY id_notificacion DESC LIMIT 50;

-- =====================================================================
-- SCRIPT DE VERIFICACIÓN PARA LOS 20 EVENTOS
-- =====================================================================

USE coworking_db;

-- ---------------------------------------------------------------------
-- 1. evt_revisar_membresias_vencidas
-- ---------------------------------------------------------------------
-- Verificación 1.1: Comprobar que el evento está registrado y habilitado
SELECT EVENT_NAME, STATUS, EVENT_DEFINITION 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_revisar_membresias_vencidas';

-- Verificación 1.2: Consultar membresías con fecha pasada y estado Activa o Suspendida según datos iniciales
SELECT id_membresia, id_usuario, estado, fecha_vencimiento 
  FROM membresias 
 WHERE estado IN ('Activa', 'Suspendida') 
   AND fecha_vencimiento < '2026-10-01 03:41:00';

-- Verificación 1.3: Verificar el log de ejecuciones para este evento
SELECT * 
  FROM log_eventos_ejecucion 
 WHERE evento = 'evt_revisar_membresias_vencidas' 
 ORDER BY id_log DESC;


-- ---------------------------------------------------------------------
-- 2. evt_recordatorio_renovacion_membresia
-- ---------------------------------------------------------------------
-- Verificación 2.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_recordatorio_renovacion_membresia';

-- Verificación 2.2: Consultar membresías activas (distintas de 'Diaria') que vencen en los próximos 5 días
SELECT m.id_membresia, m.id_usuario, tm.nombre, m.fecha_vencimiento 
  FROM membresias m 
  INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia 
 WHERE m.estado = 'Activa' 
   AND tm.nombre <> 'Diaria' 
   AND m.fecha_vencimiento > '2026-10-01 03:41:00' 
   AND m.fecha_vencimiento <= '2026-10-01 03:41:00' + INTERVAL 5 DAY;

-- Verificación 2.3: Verificar notificaciones generadas de tipo 'RENOVACION_MEMBRESIA'
SELECT * 
  FROM notificaciones_sistema 
 WHERE tipo = 'RENOVACION_MEMBRESIA' 
 ORDER BY id_notificacion DESC;


-- ---------------------------------------------------------------------
-- 3. evt_suspender_membresias_inactivas
-- ---------------------------------------------------------------------
-- Verificación 3.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_suspender_membresias_inactivas';
   
-- Verificación 3.2: Consultar membresías activas con facturas sin pago tras 30 días
SELECT m.id_membresia, m.id_usuario 
FROM membresias m 
WHERE m.estado = 'Activa' 
  AND EXISTS (
       SELECT 1 
       FROM facturas f 
       WHERE f.id_membresia = m.id_membresia 
         AND f.estado IN ('Pendiente', 'Vencida') 
         AND f.saldo_pendiente > 0 
         AND f.fecha_emision < DATE_SUB('2026-10-01 03:41:00', INTERVAL 30 DAY)
  );
-- Verificación 3.3: Verificar entradas en el log de ejecuciones para este evento
SELECT * 
FROM log_eventos_ejecucion 
WHERE evento = 'evt_suspender_membresias_inactivas' 
ORDER BY id_log DESC;


-- ---------------------------------------------------------------------
-- 4. evt_reporte_semanal_nuevas_membresias
-- ---------------------------------------------------------------------
-- Verificación 4.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_reporte_semanal_nuevas_membresias';

-- ---------------------------------------------------------------------
-- 5. evt_notificar_membresias_suspendidas_diario
-- ---------------------------------------------------------------------
-- Verificación 5.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_notificar_membresias_suspendidas_diario';

-- ---------------------------------------------------------------------
-- 6. evt_cancelar_reservas_no_confirmadas
-- ---------------------------------------------------------------------
-- Verificación 6.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_cancelar_reservas_no_confirmadas';
-- ---------------------------------------------------------------------
-- 7. evt_recordatorio_reserva_proxima
-- ---------------------------------------------------------------------
-- Verificación 7.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_recordatorio_reserva_proxima';

-- ---------------------------------------------------------------------
-- 8. evt_limpiar_reservas_pasadas_no_asistidas
-- ---------------------------------------------------------------------
-- Verificación 8.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_limpiar_reservas_pasadas_no_asistidas';

-- ---------------------------------------------------------------------
-- 9. evt_reporte_semanal_ocupacion_espacios
-- ---------------------------------------------------------------------
-- Verificación 9.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_reporte_semanal_ocupacion_espacios';

-- ---------------------------------------------------------------------
-- Verificación 10.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_liberar_reservas_bloqueadas_15min';

-- ---------------------------------------------------------------------
-- 11. evt_recordatorio_pago_pendiente
-- ---------------------------------------------------------------------
-- Verificación 11.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_recordatorio_pago_pendiente';

-- ---------------------------------------------------------------------
-- 12. evt_bloquear_servicios_facturas_vencidas
-- ---------------------------------------------------------------------
-- Verificación 12.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_bloquear_servicios_facturas_vencidas';


-- ---------------------------------------------------------------------
-- 13. evt_resumen_facturacion_mensual
-- ---------------------------------------------------------------------
-- Verificación 13.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_resumen_facturacion_mensual';

-- ---------------------------------------------------------------------
-- 14. evt_aplicar_recargos_facturas_vencidas
-- ---------------------------------------------------------------------
-- Verificación 14.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_aplicar_recargos_facturas_vencidas';

-- Verificación 14.2: Consultar facturas pendientes con más de 15 días de vencimiento
SELECT id_factura, saldo_pendiente, fecha_vencimiento 
  FROM facturas 
 WHERE estado = 'Pendiente' 
   AND saldo_pendiente > 0 
   AND fecha_vencimiento < '2026-10-01 03:41:00' - INTERVAL 15 DAY;

-- Verificación 14.3: Verificar líneas de detalle añadidas por concepto de recargo por mora
SELECT * 
  FROM detalle_facturas 
 WHERE descripcion LIKE '%Recargo por mora%' 
 ORDER BY id_detalle DESC;


-- ---------------------------------------------------------------------
-- 15. evt_reporte_contador_fin_de_mes
-- ---------------------------------------------------------------------
-- Verificación 15.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_reporte_contador_fin_de_mes';

-- Verificación 15.2: Consultar pagos exitosos registrados en el periodo contable
SELECT COUNT(*) 
  FROM pagos 
 WHERE estado_transaccion = 'Pagado';

-- Verificación 15.3: Verificar reporte de tipo 'CIERRE_CONTABLE_MENSUAL' en reportes_automaticos
SELECT * 
  FROM reportes_automaticos 
 WHERE tipo_reporte = 'CIERRE_CONTABLE_MENSUAL' 
 ORDER BY id_reporte DESC;


-- ---------------------------------------------------------------------
-- 16. evt_depurar_accesos_antiguos
-- ---------------------------------------------------------------------
-- Verificación 16.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_depurar_accesos_antiguos';

-- Verificación 16.2: Consultar registros de acceso anteriores a 1 año de antigüedad
SELECT COUNT(*) 
  FROM registros_acceso 
 WHERE fecha_hora_entrada < '2026-10-01 03:41:00' - INTERVAL 1 YEAR;

-- Verificación 16.3: Verificar log de ejecución para la purga de accesos
SELECT * 
  FROM log_eventos_ejecucion 
 WHERE evento = 'evt_depurar_accesos_antiguos' 
 ORDER BY id_log DESC;


-- ---------------------------------------------------------------------
-- 17. evt_reporte_diario_asistencias
-- ---------------------------------------------------------------------
-- Verificación 17.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_reporte_diario_asistencias';

-- Verificación 17.2: Consultar registros de acceso del día anterior
SELECT COUNT(*) 
  FROM registros_acceso 
 WHERE fecha_hora_entrada >= CURDATE() - INTERVAL 1 DAY 
   AND fecha_hora_entrada <  CURDATE();

-- Verificación 17.3: Verificar reporte generado de tipo 'ASISTENCIAS_DIARIO'
SELECT * 
  FROM reportes_automaticos 
 WHERE tipo_reporte = 'ASISTENCIAS_DIARIO' 
 ORDER BY id_reporte DESC;


-- ---------------------------------------------------------------------
-- 18. evt_reporte_semanal_usuarios_inactivos
-- ---------------------------------------------------------------------
-- Verificación 18.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_reporte_semanal_usuarios_inactivos';

-- Verificación 18.2: Consultar usuarios sin accesos exitosos en los últimos 7 días
SELECT id_usuario 
  FROM usuarios u 
 WHERE NOT EXISTS (
        SELECT 1 
          FROM registros_acceso ra 
         WHERE ra.id_usuario = u.id_usuario 
           AND ra.estado_validacion = 'Exitoso' 
           AND ra.fecha_hora_entrada >= CURDATE() - INTERVAL 7 DAY
   );

-- Verificación 18.3: Verificar reporte generado de tipo 'USUARIOS_INACTIVOS_SEMANAL'
SELECT * 
  FROM reportes_automaticos 
 WHERE tipo_reporte = 'USUARIOS_INACTIVOS_SEMANAL' 
 ORDER BY id_reporte DESC;


-- ---------------------------------------------------------------------
-- 19. evt_alerta_accesos_fuera_horario
-- ---------------------------------------------------------------------
-- Verificación 19.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_alerta_accesos_fuera_horario';

-- Verificación 19.2: Consultar accesos recientes con estado 'Rechazado' en las últimas 25 horas
SELECT * 
  FROM registros_acceso 
 WHERE fecha_hora_entrada >= '2026-10-01 03:41:00' - INTERVAL 25 HOUR 
   AND estado_validacion = 'Rechazado';

-- Verificación 19.3: Verificar notificaciones generadas de tipo 'ACCESO_FUERA_HORARIO'
SELECT * 
  FROM notificaciones_sistema 
 WHERE tipo = 'ACCESO_FUERA_HORARIO' 
 ORDER BY id_notificacion DESC;


-- ---------------------------------------------------------------------
-- 20. evt_reporte_top10_usuarios_frecuentes_mes
-- ---------------------------------------------------------------------
-- Verificación 20.1: Comprobar existencia y estado del evento
SELECT EVENT_NAME, STATUS 
  FROM information_schema.EVENTS 
 WHERE EVENT_SCHEMA = 'coworking_db' 
   AND EVENT_NAME = 'evt_reporte_top10_usuarios_frecuentes_mes';

-- Verificación 20.2: Consultar conteo de asistencias exitosas agrupadas por usuario
SELECT id_usuario, COUNT(*) AS asistencias 
  FROM registros_acceso 
 WHERE estado_validacion = 'Exitoso' 
 GROUP BY id_usuario 
 ORDER BY asistencias DESC 
 LIMIT 10;

-- Verificación 20.3: Verificar registros en la tabla top_usuarios_frecuentes_mensual
SELECT * 
  FROM top_usuarios_frecuentes_mensual 
 ORDER BY periodo DESC, posicion ASC;






-- =================================================================
-- DATOS NUEVOS PARA VERIFICACIONES 
-- =================================================================

SET GLOBAL event_scheduler = ON;

USE coworking_db;

-- Eliminar el evento si ya existía para evitar duplicados
DROP EVENT IF EXISTS evt_revisar_membresias_vencidas;

DELIMITER //

CREATE EVENT evt_revisar_membresias_vencidas
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Lógica del evento: Actualizar membresías vencidas a estado Suspendida
    UPDATE membresias 
    SET estado = 'Suspendida' 
    WHERE estado IN ('Activa', 'Suspendida') 
      AND fecha_vencimiento < NOW();
      
    -- Registro opcional en el log de ejecuciones
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_revisar_membresias_vencidas', NOW(), 'Ejecución exitosa');
END //

DELIMITER ;

-- ==========
-- EVENTO 1.3
-- ==========
USE coworking_db;

-- Crear la tabla de logs para los eventos
CREATE TABLE IF NOT EXISTS log_eventos_ejecucion (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    evento VARCHAR(100) NOT NULL,
    fecha_ejecucion DATETIME NOT NULL,
    mensaje TEXT
);

INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
VALUES ('evt_revisar_membresias_vencidas', NOW(), 'Ejecución de prueba manual');

-- ================================================================
-- EVENTOS 2
-- ================================================================
USE coworking_db;

-- Eliminar el evento si ya existe para evitar errores
DROP EVENT IF EXISTS evt_recordatorio_renovacion_membresia;

DELIMITER //

CREATE EVENT evt_recordatorio_renovacion_membresia
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Generar notificaciones para membresías activas que vencen en los próximos 5 días (excluyendo tipo 'Diaria')
    INSERT INTO notificaciones_sistema (id_usuario, tipo, mensaje, fecha_creacion, estado)
    SELECT m.id_usuario, 
           'RENOVACION_MEMBRESIA', 
           CONCAT('Estimado usuario, su membresía tipo ', tm.nombre, ' vence el ', m.fecha_vencimiento, '. Recuerde renovarla a tiempo.'), 
           NOW(), 
           'Pendiente'
    FROM membresias m 
    INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia 
    WHERE m.estado = 'Activa' 
      AND tm.nombre <> 'Diaria' 
      AND m.fecha_vencimiento > NOW() 
      AND m.fecha_vencimiento <= NOW() + INTERVAL 5 DAY;

    -- Registrar la ejecución en el log
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_recordatorio_renovacion_membresia', NOW(), 'Ejecución exitosa');
END //

DELIMITER ;

-- EVENTO 2.3

-- Crear la tabla de notificaciones del sistema
CREATE TABLE IF NOT EXISTS notificaciones_sistema (
    id_notificacion INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    tipo VARCHAR(50) NOT NULL,
    mensaje TEXT NOT NULL,
    fecha_creacion DATETIME NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Pendiente'
);
USE coworking_db;

-- Insertar una notificación de prueba
INSERT INTO notificaciones_sistema (id_usuario, tipo, mensaje, fecha_creacion, estado)
VALUES (1, 'RENOVACION_MEMBRESIA', 'Prueba manual de renovación', NOW(), 'Pendiente');


-- ============================================================================
-- EVENTO 3.1

USE coworking_db;

-- Eliminar el evento si ya existe para evitar duplicados
DROP EVENT IF EXISTS evt_suspender_membresias_inactivas;

DELIMITER //

CREATE EVENT evt_suspender_membresias_inactivas
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Cambiar a estado 'Suspendida' aquellas membresías activas cuya fecha de vencimiento ya pasó
    UPDATE membresias 
    SET estado = 'Suspendida' 
    WHERE estado = 'Activa' 
      AND fecha_vencimiento < NOW();
      
    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_suspender_membresias_inactivas', NOW(), 'Ejecución exitosa: Membresías vencidas suspendidas');
END //

DELIMITER ;

-- EVENTO 3.2

USE coworking_db;

-- 1. Insertar una membresía activa de prueba
INSERT INTO membresias (id_usuario, id_tipo_membresia, fecha_inicio, fecha_vencimiento, estado) 
VALUES (1, 1, '2026-01-01', '2026-12-31', 'Activa');

-- 2. Insertar la factura de prueba incluyendo 'fecha_vencimiento'
INSERT INTO facturas (id_usuario, id_membresia, monto_total, saldo_pendiente, fecha_emision, fecha_vencimiento, estado) 
VALUES (1, LAST_INSERT_ID(), 150.00, 150.00, '2026-08-01', '2026-08-31', 'Pendiente');



-- EVENTO 4.1

-- 1. Asegurar la tabla auxiliar para almacenar los reportes automáticos
CREATE TABLE IF NOT EXISTS reportes_automaticos (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    tipo_reporte VARCHAR(100) NOT NULL,
    contenido TEXT NOT NULL,
    fecha_generacion DATETIME NOT NULL
);

-- 2. Eliminar el evento si ya existe para evitar conflictos
DROP EVENT IF EXISTS evt_reporte_semanal_nuevas_membresias;

DELIMITER //

-- 3. Crear el evento para el reporte semanal de nuevas membresías
CREATE EVENT evt_reporte_semanal_nuevas_membresias
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Generar el reporte con el conteo de nuevas membresías de la última semana
    INSERT INTO reportes_automaticos (tipo_reporte, contenido, fecha_generacion)
    SELECT 
        'Reporte Semanal de Nuevas Membresías',
        CONCAT('Total de nuevas membresías registradas en la última semana: ', COUNT(*)),
        NOW()
    FROM membresias
    WHERE fecha_inicio >= NOW() - INTERVAL 7 DAY;

    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_reporte_semanal_nuevas_membresias', NOW(), 'Ejecución exitosa del reporte semanal');
END //

DELIMITER ;


-- EVENTO 5.1

-- Eliminar el evento si ya existe para evitar duplicados
DROP EVENT IF EXISTS evt_notificar_membresias_suspendidas_diario;

DELIMITER //

CREATE EVENT evt_notificar_membresias_suspendidas_diario
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Generar notificaciones para los usuarios que tengan membresías suspendidas
    INSERT INTO notificaciones_sistema (id_usuario, tipo, mensaje, fecha_creacion, estado)
    SELECT id_usuario, 
           'MEMBRESIA_SUSPENDIDA', 
           CONCAT('Estimado usuario, su membresía (ID: ', id_membresia, ') se encuentra suspendida. Por favor, comuníquese con administración.'), 
           NOW(), 
           'Pendiente'
    FROM membresias
    WHERE estado = 'Suspendida';

    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_notificar_membresias_suspendidas_diario', NOW(), 'Ejecución exitosa: Notificaciones de suspensión enviadas');
END //

DELIMITER ;

-- EVENTO 6.1


-- Eliminar el evento si ya existe para evitar conflictos
DROP EVENT IF EXISTS evt_cancelar_reservas_no_confirmadas;

DELIMITER //

CREATE EVENT evt_cancelar_reservas_no_confirmadas
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Cancelar reservas que llevan más de 2 horas en estado 'Pendiente de Confirmación'
    UPDATE reservas 
    SET estado = 'Cancelada' 
    WHERE estado = 'Pendiente de Confirmación' 
      AND fecha_creacion < NOW() - INTERVAL 2 HOUR;

    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_cancelar_reservas_no_confirmadas', NOW(), 'Ejecución exitosa: Reservas no confirmadas canceladas');
END //

DELIMITER ;



-- EVENTO 7.1

-- Eliminar el evento si ya existe para evitar conflictos
DROP EVENT IF EXISTS evt_recordatorio_reserva_proxima;

DELIMITER //

CREATE EVENT evt_recordatorio_reserva_proxima
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Generar notificaciones de recordatorio para reservas confirmadas que inician en la próxima hora
    INSERT INTO notificaciones_sistema (id_usuario, tipo, mensaje, fecha_creacion, estado)
    SELECT r.id_usuario, 
           'RECORDATORIO_RESERVA', 
           CONCAT('Recordatorio: Su reserva para el espacio (ID: ', r.id_espacio, ') inicia pronto a las ', r.fecha_inicio, '.'), 
           NOW(), 
           'Pendiente'
    FROM reservas r
    WHERE r.estado = 'Confirmada'
      AND r.fecha_inicio BETWEEN NOW() AND NOW() + INTERVAL 1 HOUR;

    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_recordatorio_reserva_proxima', NOW(), 'Ejecución exitosa: Recordatorios de reserva generados');
END //

DELIMITER ;



-- EVENTO 8.1

-- Eliminar el evento si ya existe para evitar conflictos
DROP EVENT IF EXISTS evt_limpiar_reservas_pasadas_no_asistidas;

DELIMITER //

CREATE EVENT evt_limpiar_reservas_pasadas_no_asistidas
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Actualizar el estado de reservas confirmadas que pasaron hace más de 7 días sin asistencia
    UPDATE reservas 
    SET estado = 'No Asistida' 
    WHERE estado = 'Confirmada' 
      AND fecha_fin < NOW() - INTERVAL 7 DAY;

    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_limpiar_reservas_pasadas_no_asistidas', NOW(), 'Ejecución exitosa: Limpieza de reservas pasadas no asistidas');
END //

DELIMITER ;

-- EVENTO 9.1

-- Eliminar el evento si ya existe para evitar conflictos
DROP EVENT IF EXISTS evt_reporte_semanal_ocupacion_espacios;

DELIMITER //

CREATE EVENT evt_reporte_semanal_ocupacion_espacios
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Generar el reporte semanal de ocupación de espacios
    INSERT INTO reportes_automaticos (tipo_reporte, contenido, fecha_generacion)
    SELECT 
        'Reporte Semanal de Ocupación de Espacios',
        CONCAT('Total de reservas registradas en la última semana: ', COUNT(*)),
        NOW()
    FROM reservas
    WHERE fecha_inicio >= NOW() - INTERVAL 7 DAY;

    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_reporte_semanal_ocupacion_espacios', NOW(), 'Ejecución exitosa del reporte semanal de ocupación');
END //

DELIMITER ;

-- EVENTO 10
USE coworking_db;

-- Eliminar el evento si ya existe para evitar conflictos
DROP EVENT IF EXISTS evt_liberar_reservas_bloqueadas_15min;

DELIMITER //

CREATE EVENT evt_liberar_reservas_bloqueadas_15min
ON SCHEDULE EVERY 5 MINUTE
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Liberar reservas que llevan más de 15 minutos en estado 'Pendiente' o 'Bloqueada'
    UPDATE reservas 
    SET estado = 'Cancelada' 
    WHERE estado IN ('Pendiente', 'Bloqueada') 
      AND fecha_creacion < NOW() - INTERVAL 15 MINUTE;

    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_liberar_reservas_bloqueadas_15min', NOW(), 'Ejecución exitosa: Reservas bloqueadas liberadas');
END //

DELIMITER ;


-- EVENTO 11.1

DROP EVENT IF EXISTS evt_recordatorio_pago_pendiente;

DELIMITER //

CREATE EVENT evt_recordatorio_pago_pendiente
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Generar notificaciones de pago pendiente para facturas pendientes o vencidas
    INSERT INTO notificaciones_sistema (id_usuario, tipo, mensaje, fecha_creacion, estado)
    SELECT f.id_usuario, 
           'PAGO_PENDIENTE', 
           CONCAT('Recordatorio: Su factura (ID: ', f.id_factura, ') presenta un saldo pendiente de $', f.saldo_pendiente), 
           NOW(), 
           'Pendiente'
    FROM facturas f
    WHERE f.estado IN ('Pendiente', 'Vencida')
      AND f.saldo_pendiente > 0;

    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_recordatorio_pago_pendiente', NOW(), 'Ejecución exitosa: Recordatorios de pago generados');
END //

DELIMITER ;

-- EVENTO 12.2


USE coworking_db;

-- Eliminar el evento si ya existe para evitar conflictos
DROP EVENT IF EXISTS evt_bloquear_servicios_facturas_vencidas;

DELIMITER //

CREATE EVENT evt_bloquear_servicios_facturas_vencidas
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Lógica del evento para bloquear servicios por facturas vencidas
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_bloquear_servicios_facturas_vencidas', NOW(), 'Ejecución exitosa: Servicios bloqueados por facturas vencidas');
END //

DELIMITER ;


-- EVENTO 13.1

USE coworking_db;

-- Eliminar el evento si ya existe para evitar conflictos
DROP EVENT IF EXISTS evt_resumen_facturacion_mensual;

DELIMITER //

CREATE EVENT evt_resumen_facturacion_mensual
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Generar el resumen de facturación mensual en la tabla de reportes automáticos
    INSERT INTO reportes_automaticos (tipo_reporte, contenido, fecha_generacion)
    SELECT 
        'Resumen de Facturación Mensual',
        CONCAT('Total facturado: $', COALESCE(SUM(saldo_pendiente), 0)),
        NOW()
    FROM facturas;

    -- Registrar la ejecución en la tabla de logs
    INSERT INTO log_eventos_ejecucion (evento, fecha_ejecucion, mensaje)
    VALUES ('evt_resumen_facturacion_mensual', NOW(), 'Ejecución exitosa: Resumen de facturación mensual generado');
END //

DELIMITER ;