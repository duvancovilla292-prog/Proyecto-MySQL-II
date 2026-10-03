/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Triggers (integridad de datos y auditoría)
Archivo: sql/05_triggers/01_triggers.sql
Triggers: 20 (prefijo obligatorio trg_)

Criterios generales (MySQL 8.0+):
- Un trigger no puede modificar la tabla que lo disparó (error 1442), pero sí otras
  tablas, y esas modificaciones pueden disparar a su vez otros triggers.
- Los borrados/actualizaciones en cascada por clave foránea NO activan triggers en MySQL.
  Por eso borrar un usuario (ON DELETE CASCADE) no dispara los triggers de membresías,
  reservas o pagos.
- Cadena de pagos:
    INSERT pagos -> trg_ins_pago_crear_factura (valida)
                 -> trg_upd_factura_saldo_parcial (resta saldo y marca 'Pagada')
                 -> facturas AFTER UPDATE: trg_upd_membresia_pago_activa,
                    trg_upd_reserva_pago_confirmar, trg_upd_membresia_suspender
- Los reembolsos (pagos con monto negativo, ver sp_cancelar_reserva_reembolso) no
  modifican el saldo de la factura.
- El orden de los triggers BEFORE INSERT sobre registros_acceso se fija con FOLLOWS.

Advertencias de carga de datos:
- trg_ins_reserva_estado_inicial fuerza 'Pendiente de Confirmación' en todo INSERT de
  reservas, y trg_ins_acceso_validar_membresia puede convertir accesos a 'Rechazado'.
  Cargue los datos históricos/de prueba ANTES de crear los triggers.
- El trigger 18 necesita la columna usuarios.ultimo_acceso; el bloque siguiente la crea
  si no existe y la rellena con el último acceso exitoso de cada usuario.
*/

USE coworking_db;

DELIMITER //

-- =========================================================
-- MÓDULO MEMBRESÍAS (1-5)
-- =========================================================

-- 1. BEFORE INSERT en membresias: si no se indica el vencimiento, lo calcula como
--    fecha_inicio + duracion_dias del tipo. Si tampoco hay fecha_inicio usa NOW().
DROP TRIGGER IF EXISTS trg_ins_membresia_vencimiento//
CREATE TRIGGER trg_ins_membresia_vencimiento
BEFORE INSERT ON membresias
FOR EACH ROW
BEGIN
    DECLARE v_duracion INT;

    IF NEW.fecha_inicio IS NULL OR YEAR(NEW.fecha_inicio) = 0 THEN
        SET NEW.fecha_inicio = NOW();
    END IF;

    IF NEW.fecha_vencimiento IS NULL OR YEAR(NEW.fecha_vencimiento) = 0 THEN
        SET v_duracion = (SELECT duracion_dias
                            FROM tipos_membresia
                           WHERE id_tipo_membresia = NEW.id_tipo_membresia);

        IF v_duracion IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El tipo de membresía no existe';
        END IF;

        SET NEW.fecha_vencimiento = DATE_ADD(NEW.fecha_inicio, INTERVAL v_duracion DAY);
    END IF;
END//

-- 2. AFTER UPDATE en facturas: cuando una factura de membresía pasa a 'Pagada',
--    reactiva la membresía suspendida o vencida (si aún está en fecha) siempre que el
--    usuario no tenga otras facturas vencidas con saldo.
DROP TRIGGER IF EXISTS trg_upd_membresia_pago_activa//
CREATE TRIGGER trg_upd_membresia_pago_activa
AFTER UPDATE ON facturas
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Pagada'
       AND OLD.estado <> 'Pagada'
       AND NEW.id_membresia IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
              FROM facturas f
             WHERE f.id_usuario = NEW.id_usuario
               AND f.id_factura <> NEW.id_factura
               AND f.estado IN ('Pendiente', 'Vencida')
               AND f.saldo_pendiente > 0
               AND f.fecha_vencimiento < NOW()
       ) THEN
        UPDATE membresias
           SET estado = 'Activa'
         WHERE id_membresia = NEW.id_membresia
           AND estado IN ('Suspendida', 'Vencida')
           AND fecha_vencimiento >= NOW();
    END IF;
END//

-- 3. AFTER UPDATE en facturas: cuando una factura de membresía pasa a 'Vencida' con
--    saldo pendiente (falta de pago a tiempo, p. ej. tras sp_aplicar_recargo_facturas_vencidas),
--    suspende la membresía activa asociada.
DROP TRIGGER IF EXISTS trg_upd_membresia_suspender//
CREATE TRIGGER trg_upd_membresia_suspender
AFTER UPDATE ON facturas
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Vencida'
       AND OLD.estado <> 'Vencida'
       AND NEW.saldo_pendiente > 0
       AND NEW.id_membresia IS NOT NULL THEN
        UPDATE membresias
           SET estado = 'Suspendida'
         WHERE id_membresia = NEW.id_membresia
           AND estado = 'Activa';
    END IF;
END//

-- 4. AFTER UPDATE en membresias: registra en log_cambios_membresia todo cambio de tipo.
DROP TRIGGER IF EXISTS trg_upd_membresia_log//
CREATE TRIGGER trg_upd_membresia_log
AFTER UPDATE ON membresias
FOR EACH ROW
BEGIN
    IF NEW.id_tipo_membresia <> OLD.id_tipo_membresia THEN
        INSERT INTO log_cambios_membresia (id_usuario, id_tipo_anterior, id_tipo_nuevo)
        VALUES (NEW.id_usuario, OLD.id_tipo_membresia, NEW.id_tipo_membresia);
    END IF;
END//

-- 5. BEFORE DELETE en membresias: impide eliminarla si el usuario tiene reservas
--    confirmadas que aún no terminan (están pagadas; deben cancelarse con reembolso
--    antes). Las reservas pendientes las cancela el trigger 9.
DROP TRIGGER IF EXISTS trg_del_membresia_bloquear//
CREATE TRIGGER trg_del_membresia_bloquear
BEFORE DELETE ON membresias
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1
          FROM reservas
         WHERE id_usuario = OLD.id_usuario
           AND estado = 'Confirmada'
           AND fecha_fin >= NOW()
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar la membresía: el usuario tiene reservas confirmadas activas';
    END IF;
END//

-- =========================================================
-- MÓDULO RESERVAS (6-10)
-- =========================================================

-- 6. BEFORE INSERT en reservas: valida el rango y rechaza solapamientos con reservas
--    pendientes o confirmadas del mismo espacio.
DROP TRIGGER IF EXISTS trg_ins_reserva_validar_duplicada//
CREATE TRIGGER trg_ins_reserva_validar_duplicada
BEFORE INSERT ON reservas
FOR EACH ROW
BEGIN
    IF NEW.fecha_inicio >= NEW.fecha_fin THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Rango de fechas inválido: el inicio debe ser menor al fin';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM reservas r
         WHERE r.id_espacio   = NEW.id_espacio
           AND r.estado IN ('Pendiente de Confirmación', 'Confirmada')
           AND r.fecha_inicio < NEW.fecha_fin
           AND r.fecha_fin    > NEW.fecha_inicio
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El espacio ya tiene una reserva en ese horario';
    END IF;
END//

-- 7. BEFORE INSERT en reservas: toda reserva nace 'Pendiente de Confirmación' y sin asistencia.
DROP TRIGGER IF EXISTS trg_ins_reserva_estado_inicial//
CREATE TRIGGER trg_ins_reserva_estado_inicial
BEFORE INSERT ON reservas
FOR EACH ROW
BEGIN
    SET NEW.estado  = 'Pendiente de Confirmación';
    SET NEW.asistio = FALSE;
END//

-- 8. AFTER UPDATE en facturas: cuando una factura de reserva pasa a 'Pagada',
--    confirma la reserva si estaba pendiente.
DROP TRIGGER IF EXISTS trg_upd_reserva_pago_confirmar//
CREATE TRIGGER trg_upd_reserva_pago_confirmar
AFTER UPDATE ON facturas
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Pagada'
       AND OLD.estado <> 'Pagada'
       AND NEW.id_reserva IS NOT NULL THEN
        UPDATE reservas
           SET estado = 'Confirmada'
         WHERE id_reserva = NEW.id_reserva
           AND estado = 'Pendiente de Confirmación';
    END IF;
END//

-- 9. AFTER DELETE en membresias: cancela las reservas pendientes futuras del usuario
--    si tras el borrado ya no le queda ninguna membresía vigente.
DROP TRIGGER IF EXISTS trg_del_membresia_cancelar_reservas//
CREATE TRIGGER trg_del_membresia_cancelar_reservas
AFTER DELETE ON membresias
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM membresias
         WHERE id_usuario = OLD.id_usuario
           AND estado = 'Activa'
           AND fecha_vencimiento >= NOW()
    ) THEN
        UPDATE reservas
           SET estado = 'Cancelada'
         WHERE id_usuario = OLD.id_usuario
           AND estado = 'Pendiente de Confirmación'
           AND fecha_fin >= NOW();
    END IF;
END//

-- 10. AFTER UPDATE en reservas: al pasar a 'Cancelada' registra el evento en
--     log_reservas_canceladas (incluye el estado desde el que se canceló).
DROP TRIGGER IF EXISTS trg_upd_reserva_cancelada_log//
CREATE TRIGGER trg_upd_reserva_cancelada_log
AFTER UPDATE ON reservas
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Cancelada' AND OLD.estado <> 'Cancelada' THEN
        INSERT INTO log_reservas_canceladas (id_reserva, id_usuario, motivo)
        VALUES (NEW.id_reserva, NEW.id_usuario, CONCAT('Cancelada desde estado: ', OLD.estado));
    END IF;
END//

-- =========================================================
-- MÓDULO PAGOS Y FACTURACIÓN (11-15)
-- =========================================================

-- 11. BEFORE INSERT en pagos: valida la factura del pago. La factura debe existir, no
--     estar anulada (salvo reembolsos negativos), el monto no puede ser cero y un pago
--     'Pagado' no puede exceder el saldo pendiente. No genera facturas: la factura debe
--     existir (FK); se emite con sp_generar_factura_membresia / sp_generar_factura_empresa.
DROP TRIGGER IF EXISTS trg_ins_pago_crear_factura//
CREATE TRIGGER trg_ins_pago_crear_factura
BEFORE INSERT ON pagos
FOR EACH ROW
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_saldo  DECIMAL(10,2);

    SET v_estado = (SELECT CAST(estado AS CHAR(20)) FROM facturas WHERE id_factura = NEW.id_factura);
    SET v_saldo  = (SELECT saldo_pendiente          FROM facturas WHERE id_factura = NEW.id_factura);

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La factura asociada al pago no existe';
    END IF;

    IF NEW.monto = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El monto del pago debe ser distinto de cero';
    END IF;

    IF NEW.monto > 0 AND v_estado = 'Anulada' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede registrar un pago sobre una factura anulada';
    END IF;

    IF NEW.monto > 0 AND NEW.estado_transaccion = 'Pagado' AND NEW.monto > v_saldo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El pago excede el saldo pendiente de la factura';
    END IF;
END//

-- 12. AFTER UPDATE en pagos: cuando un pago pasa a 'Pagado' (por ejemplo desde
--     'Pendiente') descuenta el saldo y marca la factura 'Pagada' si queda en 0.
--     Nota: en el UPDATE, 'estado' se asigna antes que 'saldo_pendiente' para que el
--     CASE use el saldo original (MySQL evalúa las asignaciones de izquierda a derecha).
DROP TRIGGER IF EXISTS trg_upd_factura_pagada//
CREATE TRIGGER trg_upd_factura_pagada
AFTER UPDATE ON pagos
FOR EACH ROW
BEGIN
    IF OLD.estado_transaccion <> 'Pagado'
       AND NEW.estado_transaccion = 'Pagado'
       AND NEW.monto > 0 THEN
        UPDATE facturas
           SET estado = CASE
                            WHEN saldo_pendiente - NEW.monto <= 0
                             AND estado IN ('Pendiente', 'Vencida') THEN 'Pagada'
                            ELSE estado
                        END,
               saldo_pendiente = GREATEST(saldo_pendiente - NEW.monto, 0)
         WHERE id_factura = NEW.id_factura;
    END IF;
END//

-- 13. BEFORE DELETE en pagos: impide borrar pagos de una factura ya 'Pagada'.
DROP TRIGGER IF EXISTS trg_del_pago_bloquear//
CREATE TRIGGER trg_del_pago_bloquear
BEFORE DELETE ON pagos
FOR EACH ROW
BEGIN
    IF (SELECT estado FROM facturas WHERE id_factura = OLD.id_factura) = 'Pagada' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar un pago de una factura pagada';
    END IF;
END//

-- 14. AFTER INSERT en pagos: un pago 'Pagado' positivo resta su monto del saldo pendiente
--     y deja la factura en 'Pagada' cuando el saldo llega a 0. Ignora reembolsos (monto < 0)
--     y pagos que no están en estado 'Pagado'.
DROP TRIGGER IF EXISTS trg_upd_factura_saldo_parcial//
CREATE TRIGGER trg_upd_factura_saldo_parcial
AFTER INSERT ON pagos
FOR EACH ROW
BEGIN
    IF NEW.estado_transaccion = 'Pagado' AND NEW.monto > 0 THEN
        UPDATE facturas
           SET estado = CASE
                            WHEN saldo_pendiente - NEW.monto <= 0
                             AND estado IN ('Pendiente', 'Vencida') THEN 'Pagada'
                            ELSE estado
                        END,
               saldo_pendiente = GREATEST(saldo_pendiente - NEW.monto, 0)
         WHERE id_factura = NEW.id_factura;
    END IF;
END//

-- 15. AFTER UPDATE en pagos: al pasar a 'Cancelado' registra el pago en log_pagos_anulados.
DROP TRIGGER IF EXISTS trg_upd_pago_anulado_log//
CREATE TRIGGER trg_upd_pago_anulado_log
AFTER UPDATE ON pagos
FOR EACH ROW
BEGIN
    IF NEW.estado_transaccion = 'Cancelado' AND OLD.estado_transaccion <> 'Cancelado' THEN
        INSERT INTO log_pagos_anulados (id_pago, id_factura, monto)
        VALUES (NEW.id_pago, NEW.id_factura, NEW.monto);
    END IF;
END//

-- =========================================================
-- MÓDULO ACCESOS (16-20)
-- =========================================================

-- 16. AFTER INSERT en registros_acceso: en un acceso exitoso marca asistio = TRUE en la
--     reserva confirmada del usuario que cubre ese momento (tolerancia: 30 min antes del inicio).
DROP TRIGGER IF EXISTS trg_ins_acceso_asistencia//
CREATE TRIGGER trg_ins_acceso_asistencia
AFTER INSERT ON registros_acceso
FOR EACH ROW
BEGIN
    IF NEW.estado_validacion = 'Exitoso' THEN
        UPDATE reservas
           SET asistio = TRUE
         WHERE id_usuario = NEW.id_usuario
           AND estado = 'Confirmada'
           AND asistio = FALSE
           AND NEW.fecha_hora_entrada BETWEEN DATE_SUB(fecha_inicio, INTERVAL 30 MINUTE) AND fecha_fin;
    END IF;
END//

-- 17. BEFORE INSERT en registros_acceso: si un acceso 'Exitoso' no tiene membresía activa
--     ni reserva confirmada válida en ese momento, lo convierte en 'Rechazado' con su
--     motivo (queda como intento fallido y lo recoge el trigger 20).
DROP TRIGGER IF EXISTS trg_ins_acceso_validar_membresia//
CREATE TRIGGER trg_ins_acceso_validar_membresia
BEFORE INSERT ON registros_acceso
FOR EACH ROW
BEGIN
    DECLARE v_membresias INT DEFAULT 0;
    DECLARE v_reservas   INT DEFAULT 0;

    IF NEW.estado_validacion = 'Exitoso' THEN
        SELECT COUNT(*)
          INTO v_membresias
          FROM membresias
         WHERE id_usuario = NEW.id_usuario
           AND estado = 'Activa'
           AND NEW.fecha_hora_entrada BETWEEN fecha_inicio AND fecha_vencimiento;

        IF v_membresias = 0 THEN
            SELECT COUNT(*)
              INTO v_reservas
              FROM reservas
             WHERE id_usuario = NEW.id_usuario
               AND estado = 'Confirmada'
               AND NEW.fecha_hora_entrada BETWEEN DATE_SUB(fecha_inicio, INTERVAL 30 MINUTE) AND fecha_fin;

            IF v_reservas = 0 THEN
                SET NEW.estado_validacion = 'Rechazado';
                SET NEW.motivo_rechazo    = 'Sin membresía activa ni reserva válida';
                SET NEW.fecha_hora_salida = NULL;
            END IF;
        END IF;
    END IF;
END//

-- 18. AFTER INSERT en registros_acceso: actualiza usuarios.ultimo_acceso con la entrada
--     exitosa más reciente.
DROP TRIGGER IF EXISTS trg_ins_acceso_ultima_fecha//
CREATE TRIGGER trg_ins_acceso_ultima_fecha
AFTER INSERT ON registros_acceso
FOR EACH ROW
BEGIN
    IF NEW.estado_validacion = 'Exitoso' THEN
        UPDATE usuarios
           SET ultimo_acceso = NEW.fecha_hora_entrada
         WHERE id_usuario = NEW.id_usuario
           AND (ultimo_acceso IS NULL OR ultimo_acceso < NEW.fecha_hora_entrada);
    END IF;
END//

-- 19. BEFORE INSERT en registros_acceso: control de entradas abiertas.
--     LIMITACIÓN DE MYSQL: un trigger no puede actualizar registros_acceso (la tabla que lo
--     dispara), por lo que NO es posible asignar aquí la salida de la entrada previa.
--     Lo que sí hace: si el usuario ya tiene hoy una entrada exitosa sin salida, el nuevo
--     acceso se registra como 'Rechazado' para no dejar dos entradas abiertas. Las entradas
--     abiertas de días anteriores no bloquean. Se ejecuta después del trigger 17.
DROP TRIGGER IF EXISTS trg_ins_acceso_auto_salida//
CREATE TRIGGER trg_ins_acceso_auto_salida
BEFORE INSERT ON registros_acceso
FOR EACH ROW
FOLLOWS trg_ins_acceso_validar_membresia
BEGIN
    IF NEW.estado_validacion = 'Exitoso'
       AND EXISTS (
            SELECT 1
              FROM registros_acceso ra
             WHERE ra.id_usuario = NEW.id_usuario
               AND ra.estado_validacion = 'Exitoso'
               AND ra.fecha_hora_salida IS NULL
               AND ra.fecha_hora_entrada >= DATE(NEW.fecha_hora_entrada)
               AND ra.fecha_hora_entrada <  NEW.fecha_hora_entrada
       ) THEN
        SET NEW.estado_validacion = 'Rechazado';
        SET NEW.motivo_rechazo    = 'Ya existe una entrada abierta sin salida';
        SET NEW.fecha_hora_salida = NULL;
    END IF;
END//

-- 20. AFTER INSERT en registros_acceso: todo acceso 'Rechazado' (incluidos los que
--     convierten los triggers 17 y 19) se copia a log_accesos_rechazados.
DROP TRIGGER IF EXISTS trg_ins_acceso_rechazado_log//
CREATE TRIGGER trg_ins_acceso_rechazado_log
AFTER INSERT ON registros_acceso
FOR EACH ROW
BEGIN
    IF NEW.estado_validacion = 'Rechazado' THEN
        INSERT INTO log_accesos_rechazados (id_usuario, metodo_acceso, motivo)
        VALUES (NEW.id_usuario, NEW.metodo_acceso, NEW.motivo_rechazo);
    END IF;
END//

DELIMITER ;

-- =========================================================
-- Verificación
-- =========================================================
-- SHOW TRIGGERS FROM coworking_db;
-- SELECT TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_TIMING
--   FROM information_schema.TRIGGERS
--  WHERE TRIGGER_SCHEMA = 'coworking_db' AND TRIGGER_NAME LIKE 'trg\_%'
--  ORDER BY EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION;

-- =========================================================
-- PREPARACIÓN: columna usuarios.ultimo_acceso (requerida por el trigger 18)
-- =========================================================
SET @existe_col := (
    SELECT COUNT(*)
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'usuarios'
       AND COLUMN_NAME  = 'ultimo_acceso'
);
SET @ddl := IF(@existe_col = 0,
               'ALTER TABLE usuarios ADD COLUMN ultimo_acceso DATETIME NULL AFTER telefono',
               'SELECT ''La columna usuarios.ultimo_acceso ya existe'' AS info');
PREPARE stmt_ultimo_acceso FROM @ddl;
EXECUTE stmt_ultimo_acceso;
DEALLOCATE PREPARE stmt_ultimo_acceso;

UPDATE usuarios u
   SET u.ultimo_acceso = (
        SELECT MAX(ra.fecha_hora_entrada)
          FROM registros_acceso ra
         WHERE ra.id_usuario = u.id_usuario
           AND ra.estado_validacion = 'Exitoso'
   );
