/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Procedimientos almacenados
Archivo: sql/04_procedimientos/01_procedimientos.sql
Procedimientos: 20 (prefijo obligatorio sp_)

Criterios generales (MySQL 8.0+):
- Errores de negocio: SIGNAL SQLSTATE '45000' con mensaje descriptivo.
- Procedimientos que modifican varias tablas: START TRANSACTION / COMMIT y un
  EXIT HANDLER FOR SQLEXCEPTION que hace ROLLBACK y relanza el error (RESIGNAL).
- Ingreso real       = pagos con estado_transaccion = 'Pagado'. Los reembolsos se
                       registran como un pago con monto negativo, de modo que los
                       ingresos netos se calculan con un simple SUM.
- Reserva válida     = 'Pendiente de Confirmación' o 'Confirmada'.
- Membresía vigente  = estado 'Activa' dentro de su rango de fechas.
- Los registros de las tablas log_* se asumen alimentados por los triggers de
  auditoría; estos procedimientos no insertan en ellas para evitar duplicados.
- Guardar este archivo con codificación UTF-8 (hay valores con tilde, como
  'Pendiente de Confirmación').
*/

USE coworking_db;

DELIMITER //

-- =========================================================
-- MEMBRESÍAS (4)
-- =========================================================

-- 1. Registra una membresía nueva. El vencimiento = inicio + duracion_dias del tipo.
--    Rechaza usuarios/tipos inexistentes y membresías que se traslapen con otra vigente.
DROP PROCEDURE IF EXISTS sp_registrar_membresia//
CREATE PROCEDURE sp_registrar_membresia(
    IN p_id_usuario   INT,
    IN p_id_tipo      INT,
    IN p_fecha_inicio DATETIME
)
BEGIN
    DECLARE v_inicio       DATETIME;
    DECLARE v_fin          DATETIME;
    DECLARE v_duracion     INT;
    DECLARE v_contador     INT DEFAULT 0;
    DECLARE v_id_membresia INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_inicio = COALESCE(p_fecha_inicio, NOW());

    SELECT COUNT(*) INTO v_contador FROM usuarios WHERE id_usuario = p_id_usuario;
    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    SET v_duracion = (SELECT duracion_dias FROM tipos_membresia WHERE id_tipo_membresia = p_id_tipo);
    IF v_duracion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El tipo de membresía no existe';
    END IF;

    SET v_fin = DATE_ADD(v_inicio, INTERVAL v_duracion DAY);

    START TRANSACTION;

    -- Bloquea al usuario para serializar registros concurrentes.
    SELECT id_usuario INTO v_contador FROM usuarios WHERE id_usuario = p_id_usuario FOR UPDATE;

    SELECT COUNT(*) INTO v_contador
      FROM membresias
     WHERE id_usuario = p_id_usuario
       AND estado IN ('Activa', 'Suspendida')
       AND fecha_inicio     < v_fin
       AND fecha_vencimiento > v_inicio;

    IF v_contador > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario ya tiene una membresía vigente en ese periodo';
    END IF;

    INSERT INTO membresias (id_usuario, id_tipo_membresia, fecha_inicio, fecha_vencimiento, estado, renovaciones)
    VALUES (p_id_usuario, p_id_tipo, v_inicio, v_fin, 'Activa', 0);

    SET v_id_membresia = LAST_INSERT_ID();

    COMMIT;

    SELECT v_id_membresia AS id_membresia, v_inicio AS fecha_inicio, v_fin AS fecha_vencimiento;
END//

-- 2. Renueva una membresía extendiendo su vencimiento.
--    Si ya venció, la extensión cuenta desde hoy. No permite renovar membresías suspendidas.
DROP PROCEDURE IF EXISTS sp_renovar_membresia//
CREATE PROCEDURE sp_renovar_membresia(
    IN p_id_membresia   INT,
    IN p_dias_extension INT
)
BEGIN
    DECLARE v_estado      VARCHAR(20);
    DECLARE v_vencimiento DATETIME;
    DECLARE v_nuevo       DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_dias_extension IS NULL OR p_dias_extension <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Los días de extensión deben ser mayores a cero';
    END IF;

    START TRANSACTION;

    SELECT estado, fecha_vencimiento
      INTO v_estado, v_vencimiento
      FROM membresias
     WHERE id_membresia = p_id_membresia
       FOR UPDATE;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La membresía no existe';
    END IF;

    IF v_estado = 'Suspendida' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede renovar una membresía suspendida';
    END IF;

    SET v_nuevo = DATE_ADD(GREATEST(v_vencimiento, NOW()), INTERVAL p_dias_extension DAY);

    UPDATE membresias
       SET fecha_vencimiento = v_nuevo,
           estado            = 'Activa',
           renovaciones      = COALESCE(renovaciones, 0) + 1
     WHERE id_membresia = p_id_membresia;

    COMMIT;

    SELECT p_id_membresia AS id_membresia, v_nuevo AS nueva_fecha_vencimiento;
END//

-- 3. Marca como 'Vencida' toda membresía activa cuya fecha de vencimiento ya pasó.
DROP PROCEDURE IF EXISTS sp_actualizar_membresias_vencidas//
CREATE PROCEDURE sp_actualizar_membresias_vencidas()
BEGIN
    DECLARE v_actualizadas INT DEFAULT 0;

    UPDATE membresias
       SET estado = 'Vencida'
     WHERE estado = 'Activa'
       AND fecha_vencimiento < NOW();

    SET v_actualizadas = ROW_COUNT();

    SELECT v_actualizadas AS membresias_vencidas;
END//

-- 4. Suspende membresías activas de usuarios con facturas impagas cuyo
--    vencimiento superó p_dias_limite días.
DROP PROCEDURE IF EXISTS sp_suspender_membresias_morosas//
CREATE PROCEDURE sp_suspender_membresias_morosas(IN p_dias_limite INT)
BEGIN
    DECLARE v_suspendidas INT DEFAULT 0;

    IF p_dias_limite IS NULL OR p_dias_limite < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El límite de días debe ser mayor o igual a cero';
    END IF;

    UPDATE membresias m
       SET m.estado = 'Suspendida'
     WHERE m.estado = 'Activa'
       AND EXISTS (
            SELECT 1
              FROM facturas f
             WHERE f.id_usuario = m.id_usuario
               AND f.estado IN ('Pendiente', 'Vencida')
               AND f.saldo_pendiente > 0
               AND f.fecha_vencimiento < DATE_SUB(NOW(), INTERVAL p_dias_limite DAY)
       );

    SET v_suspendidas = ROW_COUNT();

    SELECT v_suspendidas AS membresias_suspendidas;
END//

-- =========================================================
-- RESERVAS Y ESPACIOS (5)
-- =========================================================

-- 5. Valida si un espacio está libre en un rango.
--    p_disponible = FALSE si el espacio no está 'Disponible', si el rango cruza
--    de día o sale del horario del espacio, o si se traslapa con otra reserva válida.
--    Lanza error si el rango es inválido o el espacio no existe.
DROP PROCEDURE IF EXISTS sp_validar_disponibilidad_espacio//
CREATE PROCEDURE sp_validar_disponibilidad_espacio(
    IN  p_id_espacio INT,
    IN  p_inicio     DATETIME,
    IN  p_fin        DATETIME,
    OUT p_disponible BOOLEAN
)
BEGIN
    DECLARE v_estado     VARCHAR(20);
    DECLARE v_apertura   TIME;
    DECLARE v_cierre     TIME;
    DECLARE v_conflictos INT DEFAULT 0;

    IF p_inicio IS NULL OR p_fin IS NULL OR p_inicio >= p_fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rango de fechas inválido: el inicio debe ser menor al fin';
    END IF;

    SELECT estado, hora_apertura, hora_cierre
      INTO v_estado, v_apertura, v_cierre
      FROM espacios
     WHERE id_espacio = p_id_espacio;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El espacio no existe';
    END IF;

    SET p_disponible = FALSE;

    IF v_estado <> 'Disponible' THEN
        SET p_disponible = FALSE;
    ELSEIF DATE(p_inicio) <> DATE(p_fin)
        OR TIME(p_inicio) < v_apertura
        OR TIME(p_fin)    > v_cierre THEN
        SET p_disponible = FALSE;
    ELSE
        SELECT COUNT(*)
          INTO v_conflictos
          FROM reservas
         WHERE id_espacio   = p_id_espacio
           AND estado IN ('Pendiente de Confirmación', 'Confirmada')
           AND fecha_inicio < p_fin
           AND fecha_fin    > p_inicio;

        SET p_disponible = (v_conflictos = 0);
    END IF;
END//

-- 6. Crea una reserva en estado 'Pendiente de Confirmación'.
--    Exige fecha futura y una membresía activa que cubra todo el rango.
--    Bloquea la fila del espacio para evitar reservas simultáneas solapadas.
DROP PROCEDURE IF EXISTS sp_crear_reserva//
CREATE PROCEDURE sp_crear_reserva(
    IN p_id_usuario INT,
    IN p_id_espacio INT,
    IN p_inicio     DATETIME,
    IN p_fin        DATETIME
)
BEGIN
    DECLARE v_contador    INT DEFAULT 0;
    DECLARE v_disponible  BOOLEAN DEFAULT FALSE;
    DECLARE v_id_reserva  INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_inicio IS NULL OR p_fin IS NULL OR p_inicio >= p_fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rango de fechas inválido: el inicio debe ser menor al fin';
    END IF;

    IF p_inicio < NOW() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se pueden crear reservas en el pasado';
    END IF;

    SELECT COUNT(*) INTO v_contador FROM usuarios WHERE id_usuario = p_id_usuario;
    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    SELECT COUNT(*)
      INTO v_contador
      FROM membresias
     WHERE id_usuario = p_id_usuario
       AND estado = 'Activa'
       AND fecha_inicio      <= p_inicio
       AND fecha_vencimiento >= p_fin;

    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no tiene una membresía activa que cubra la reserva';
    END IF;

    START TRANSACTION;

    SELECT id_espacio INTO v_contador FROM espacios WHERE id_espacio = p_id_espacio FOR UPDATE;

    CALL sp_validar_disponibilidad_espacio(p_id_espacio, p_inicio, p_fin, v_disponible);

    IF NOT v_disponible THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El espacio no está disponible en el horario solicitado';
    END IF;

    INSERT INTO reservas (id_usuario, id_espacio, fecha_inicio, fecha_fin, estado)
    VALUES (p_id_usuario, p_id_espacio, p_inicio, p_fin, 'Pendiente de Confirmación');

    SET v_id_reserva = LAST_INSERT_ID();

    COMMIT;

    SELECT v_id_reserva AS id_reserva;
END//

-- 7. Confirma una reserva pendiente solo si su factura está totalmente pagada.
--    Deja la factura en 'Pagada' con saldo 0 y la reserva en 'Confirmada'.
delimiter //
DROP PROCEDURE IF EXISTS sp_confirmar_reserva_pago//
CREATE PROCEDURE sp_confirmar_reserva_pago(IN p_id_reserva INT)
BEGIN
    DECLARE v_estado      VARCHAR(30);
    DECLARE v_id_factura  INT;
    DECLARE v_monto_total DECIMAL(10,2);
    DECLARE v_pagado      DECIMAL(10,2) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT estado INTO v_estado
      FROM reservas
     WHERE id_reserva = p_id_reserva
       FOR UPDATE;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe';
    END IF;

    IF v_estado <> 'Pendiente de Confirmación' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden confirmar reservas pendientes de confirmación';
    END IF;

    SELECT id_factura, monto_total
      INTO v_id_factura, v_monto_total
      FROM facturas
     WHERE id_reserva = p_id_reserva
       AND estado <> 'Anulada'
     ORDER BY id_factura DESC
     LIMIT 1
       FOR UPDATE;

    IF v_id_factura IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no tiene una factura asociada';
    END IF;

    SELECT COALESCE(SUM(monto), 0)
      INTO v_pagado
      FROM pagos
     WHERE id_factura = v_id_factura
       AND estado_transaccion = 'Pagado';

    IF v_pagado < v_monto_total THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El pago de la reserva está incompleto';
    END IF;

    UPDATE facturas
       SET estado = 'Pagada',
           saldo_pendiente = 0
     WHERE id_factura = v_id_factura;

    UPDATE reservas
       SET estado = 'Confirmada'
     WHERE id_reserva = p_id_reserva;

    COMMIT;

    SELECT p_id_reserva AS id_reserva, v_id_factura AS id_factura, 'Confirmada' AS estado;
END//

-- 8. Cancela una reserva futura y reembolsa un porcentaje de lo pagado.
--    - Sin pagos: la factura pendiente se anula.
--    - Con pagos: se registra un pago negativo (reembolso) con el mismo método del
--      último pago; si el porcentaje es 100 la factura queda 'Anulada'.
--    El registro en log_reservas_canceladas lo hace el trigger de auditoría.
DROP PROCEDURE IF EXISTS sp_cancelar_reserva_reembolso//
CREATE PROCEDURE sp_cancelar_reserva_reembolso(
    IN p_id_reserva          INT,
    IN p_porcentaje_reembolso DECIMAL(5,2)
)
BEGIN
    DECLARE v_estado     VARCHAR(30);
    DECLARE v_inicio     DATETIME;
    DECLARE v_id_factura INT;
    DECLARE v_pagado     DECIMAL(10,2) DEFAULT 0;
    DECLARE v_reembolso  DECIMAL(10,2) DEFAULT 0;
    DECLARE v_metodo     VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_porcentaje_reembolso IS NULL OR p_porcentaje_reembolso < 0 OR p_porcentaje_reembolso > 100 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El porcentaje de reembolso debe estar entre 0 y 100';
    END IF;

    START TRANSACTION;

    SELECT estado, fecha_inicio
      INTO v_estado, v_inicio
      FROM reservas
     WHERE id_reserva = p_id_reserva
       FOR UPDATE;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe';
    END IF;

    IF v_estado NOT IN ('Pendiente de Confirmación', 'Confirmada') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no se puede cancelar en su estado actual';
    END IF;

    IF v_inicio <= NOW() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede cancelar una reserva que ya inició';
    END IF;

    UPDATE reservas
       SET estado = 'Cancelada'
     WHERE id_reserva = p_id_reserva;

    SELECT id_factura
      INTO v_id_factura
      FROM facturas
     WHERE id_reserva = p_id_reserva
       AND estado <> 'Anulada'
     ORDER BY id_factura DESC
     LIMIT 1
       FOR UPDATE;

    IF v_id_factura IS NOT NULL THEN
        SELECT COALESCE(SUM(monto), 0)
          INTO v_pagado
          FROM pagos
         WHERE id_factura = v_id_factura
           AND estado_transaccion = 'Pagado';

        IF v_pagado <= 0 THEN
            UPDATE facturas
               SET estado = 'Anulada',
                   saldo_pendiente = 0,
                   motivo_anulacion = 'Reserva cancelada sin pagos registrados'
             WHERE id_factura = v_id_factura;
        ELSE
            SET v_reembolso = ROUND(v_pagado * p_porcentaje_reembolso / 100, 2);

            IF v_reembolso > 0 THEN
                SET v_metodo = (
                    SELECT metodo_pago
                      FROM pagos
                     WHERE id_factura = v_id_factura
                       AND estado_transaccion = 'Pagado'
                       AND monto > 0
                     ORDER BY fecha_pago DESC, id_pago DESC
                     LIMIT 1
                );

                INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
                VALUES (v_id_factura, v_metodo, -v_reembolso, 'Pagado');
            END IF;

            IF p_porcentaje_reembolso = 100 THEN
                UPDATE facturas
                   SET estado = 'Anulada',
                       saldo_pendiente = 0,
                       motivo_anulacion = 'Reserva cancelada con reembolso del 100%'
                 WHERE id_factura = v_id_factura;
            END IF;
        END IF;
    END IF;

    COMMIT;

    SELECT p_id_reserva AS id_reserva, v_reembolso AS monto_reembolsado;
END//

-- 9. Cancela reservas 'Pendiente de Confirmación' creadas hace más de p_horas_limite
--    horas y anula sus facturas pendientes.
DROP PROCEDURE IF EXISTS sp_liberar_reservas_pendientes//
CREATE PROCEDURE sp_liberar_reservas_pendientes(IN p_horas_limite INT)
BEGIN
    DECLARE v_limite       DATETIME;
    DECLARE v_liberadas    INT DEFAULT 0;
    DECLARE v_anuladas     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_horas_limite IS NULL OR p_horas_limite <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El límite de horas debe ser mayor a cero';
    END IF;

    SET v_limite = DATE_SUB(NOW(), INTERVAL p_horas_limite HOUR);

    START TRANSACTION;

    UPDATE facturas f
      INNER JOIN reservas r ON r.id_reserva = f.id_reserva
       SET f.estado = 'Anulada',
           f.saldo_pendiente = 0,
           f.motivo_anulacion = 'Reserva liberada por falta de confirmación'
     WHERE r.estado = 'Pendiente de Confirmación'
       AND r.fecha_creacion < v_limite
       AND f.estado = 'Pendiente';

    SET v_anuladas = ROW_COUNT();

    UPDATE reservas
       SET estado = 'Cancelada'
     WHERE estado = 'Pendiente de Confirmación'
       AND fecha_creacion < v_limite;

    SET v_liberadas = ROW_COUNT();

    COMMIT;

    SELECT v_liberadas AS reservas_liberadas, v_anuladas AS facturas_anuladas;
END//

-- =========================================================
-- PAGOS Y FACTURACIÓN (4)
-- =========================================================

-- 10. Genera la factura de una membresía (monto = precio del tipo) con su detalle.
--     Vence a los 15 días. Impide duplicar la factura de una misma membresía.
DROP PROCEDURE IF EXISTS sp_generar_factura_membresia//
CREATE PROCEDURE sp_generar_factura_membresia(IN p_id_membresia INT)
BEGIN
    DECLARE v_id_usuario INT;
    DECLARE v_tipo       VARCHAR(50);
    DECLARE v_precio     DECIMAL(10,2);
    DECLARE v_contador   INT DEFAULT 0;
    DECLARE v_id_factura INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT m.id_usuario, CAST(tm.nombre AS CHAR(50)), tm.precio
      INTO v_id_usuario, v_tipo, v_precio
      FROM membresias m
      INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
     WHERE m.id_membresia = p_id_membresia
       FOR UPDATE;

    IF v_id_usuario IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La membresía no existe';
    END IF;

    SELECT COUNT(*)
      INTO v_contador
      FROM facturas
     WHERE id_membresia = p_id_membresia
       AND estado <> 'Anulada';

    IF v_contador > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La membresía ya tiene una factura generada';
    END IF;

    INSERT INTO facturas (id_usuario, id_membresia, monto_total, saldo_pendiente, estado, fecha_vencimiento)
    VALUES (v_id_usuario, p_id_membresia, v_precio, v_precio, 'Pendiente', DATE_ADD(NOW(), INTERVAL 15 DAY));

    SET v_id_factura = LAST_INSERT_ID();

    INSERT INTO detalle_facturas (id_factura, id_servicio, descripcion, cantidad, precio_unitario)
    VALUES (v_id_factura, NULL, CONCAT('Membresía ', v_tipo), 1, v_precio);

    COMMIT;

    SELECT v_id_factura AS id_factura, v_precio AS monto_total;
END//

-- 11. Genera una factura consolidada con los servicios adicionales consumidos en un mes
--     por los usuarios de una empresa. Se emite a nombre del usuario con menor id de la
--     empresa (facturas.id_usuario es obligatorio). La marca [EMP<id>-<aaaa-mm>] en la
--     descripción del detalle evita facturar dos veces el mismo periodo.
DROP PROCEDURE IF EXISTS sp_generar_factura_empresa//
CREATE PROCEDURE sp_generar_factura_empresa(
    IN p_id_empresa INT,
    IN p_mes        INT,
    IN p_anio       INT
)
BEGIN
    DECLARE v_inicio     DATE;
    DECLARE v_periodo    CHAR(7);
    DECLARE v_contador   INT DEFAULT 0;
    DECLARE v_id_rep     INT;
    DECLARE v_id_factura INT;
    DECLARE v_total      DECIMAL(10,2) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12 OR p_anio IS NULL OR p_anio < 2000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Mes o año inválido';
    END IF;

    SET v_inicio  = STR_TO_DATE(CONCAT(p_anio, '-', p_mes, '-01'), '%Y-%m-%d');
    SET v_periodo = DATE_FORMAT(v_inicio, '%Y-%m');

    SELECT COUNT(*) INTO v_contador FROM empresas WHERE id_empresa = p_id_empresa;
    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa no existe';
    END IF;

    SET v_id_rep = (SELECT MIN(id_usuario) FROM usuarios WHERE id_empresa = p_id_empresa);
    IF v_id_rep IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa no tiene usuarios registrados';
    END IF;

    START TRANSACTION;

    SELECT COUNT(*)
      INTO v_contador
      FROM detalle_facturas d
      INNER JOIN facturas f ON f.id_factura = d.id_factura
     WHERE f.estado <> 'Anulada'
       AND d.descripcion LIKE CONCAT('%[EMP', p_id_empresa, '-', v_periodo, ']');

    IF v_contador > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa ya fue facturada para ese periodo';
    END IF;

    SELECT COUNT(*)
      INTO v_contador
      FROM consumos_servicios cs
      INNER JOIN usuarios u ON u.id_usuario = cs.id_usuario
     WHERE u.id_empresa = p_id_empresa
       AND cs.fecha_consumo >= v_inicio
       AND cs.fecha_consumo <  v_inicio + INTERVAL 1 MONTH;

    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa no registra consumos en ese periodo';
    END IF;

    INSERT INTO facturas (id_usuario, monto_total, saldo_pendiente, estado, fecha_vencimiento)
    VALUES (v_id_rep, 0, 0, 'Pendiente', DATE_ADD(NOW(), INTERVAL 30 DAY));

    SET v_id_factura = LAST_INSERT_ID();

    INSERT INTO detalle_facturas (id_factura, id_servicio, descripcion, cantidad, precio_unitario)
    SELECT v_id_factura,
           sa.id_servicio,
           CONCAT('Consumo ', sa.nombre, ' [EMP', p_id_empresa, '-', v_periodo, ']'),
           SUM(COALESCE(cs.cantidad, 1)),
           sa.costo
      FROM consumos_servicios cs
      INNER JOIN usuarios u              ON u.id_usuario = cs.id_usuario
      INNER JOIN servicios_adicionales sa ON sa.id_servicio = cs.id_servicio
     WHERE u.id_empresa = p_id_empresa
       AND cs.fecha_consumo >= v_inicio
       AND cs.fecha_consumo <  v_inicio + INTERVAL 1 MONTH
     GROUP BY sa.id_servicio, sa.nombre, sa.costo;

    SELECT COALESCE(SUM(subtotal), 0) INTO v_total
      FROM detalle_facturas
     WHERE id_factura = v_id_factura;

    UPDATE facturas
       SET monto_total = v_total,
           saldo_pendiente = v_total
     WHERE id_factura = v_id_factura;

    COMMIT;

    SELECT v_id_factura AS id_factura, p_id_empresa AS id_empresa, v_periodo AS periodo, v_total AS monto_total;
END//

-- 12. Aplica un recargo por mora sobre el saldo de las facturas 'Pendiente' vencidas
--     hace más de p_dias_vencidos días. Agrega una línea de detalle, suma el recargo al
--     monto y al saldo, y pasa la factura a 'Vencida' (así no se recarga dos veces).
DROP PROCEDURE IF EXISTS sp_aplicar_recargo_facturas_vencidas//
CREATE PROCEDURE sp_aplicar_recargo_facturas_vencidas(
    IN p_dias_vencidos      INT,
    IN p_porcentaje_recargo DECIMAL(5,2)
)
BEGIN
    DECLARE v_limite   DATETIME;
    DECLARE v_facturas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_dias_vencidos IS NULL OR p_dias_vencidos < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Los días vencidos deben ser mayores o iguales a cero';
    END IF;

    IF p_porcentaje_recargo IS NULL OR p_porcentaje_recargo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El porcentaje de recargo debe ser mayor a cero';
    END IF;

    SET v_limite = DATE_SUB(NOW(), INTERVAL p_dias_vencidos DAY);

    START TRANSACTION;

    INSERT INTO detalle_facturas (id_factura, id_servicio, descripcion, cantidad, precio_unitario)
    SELECT id_factura,
           NULL,
           CONCAT('Recargo por mora ', p_porcentaje_recargo, '%'),
           1,
           ROUND(saldo_pendiente * p_porcentaje_recargo / 100, 2)
      FROM facturas
     WHERE estado = 'Pendiente'
       AND saldo_pendiente > 0
       AND fecha_vencimiento < v_limite;

    UPDATE facturas
       SET monto_total     = monto_total + ROUND(saldo_pendiente * p_porcentaje_recargo / 100, 2),
           saldo_pendiente = saldo_pendiente + ROUND(saldo_pendiente * p_porcentaje_recargo / 100, 2),
           estado          = 'Vencida'
     WHERE estado = 'Pendiente'
       AND saldo_pendiente > 0
       AND fecha_vencimiento < v_limite;

    SET v_facturas = ROW_COUNT();

    COMMIT;

    SELECT v_facturas AS facturas_recargadas;
END//

-- 13. Bloquea los servicios adicionales de un usuario moroso.
--     La columna servicios_adicionales.bloqueado es global (afectaría a todos los
--     usuarios), por eso no se usa. En su lugar se retiran los servicios contratados
--     en sus reservas futuras. Requiere facturas vencidas con saldo pendiente.
DROP PROCEDURE IF EXISTS sp_bloquear_servicios_impago//
CREATE PROCEDURE sp_bloquear_servicios_impago(IN p_id_usuario INT)
BEGIN
    DECLARE v_contador  INT DEFAULT 0;
    DECLARE v_retirados INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_contador FROM usuarios WHERE id_usuario = p_id_usuario;
    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    SELECT COUNT(*)
      INTO v_contador
      FROM facturas
     WHERE id_usuario = p_id_usuario
       AND estado IN ('Pendiente', 'Vencida')
       AND saldo_pendiente > 0
       AND fecha_vencimiento < NOW();

    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no tiene facturas vencidas con saldo pendiente';
    END IF;

    START TRANSACTION;

    DELETE rs
      FROM reserva_servicios rs
      INNER JOIN reservas r ON r.id_reserva = rs.id_reserva
     WHERE r.id_usuario = p_id_usuario
       AND r.estado IN ('Pendiente de Confirmación', 'Confirmada')
       AND r.fecha_inicio > NOW();

    SET v_retirados = ROW_COUNT();

    COMMIT;

    SELECT p_id_usuario AS id_usuario, v_retirados AS servicios_retirados;
END//

-- =========================================================
-- ACCESOS Y ASISTENCIAS (4)
-- =========================================================

-- 14. Registra una entrada (método 'QR' o 'RFID').
--     Siempre deja registro: 'Exitoso' si hay membresía vigente y no hay una entrada
--     abierta hoy; en caso contrario 'Rechazado' con su motivo.
--     Los rechazos se copian a log_accesos_rechazados mediante el trigger de auditoría.
DROP PROCEDURE IF EXISTS sp_registrar_acceso_entrada//
CREATE PROCEDURE sp_registrar_acceso_entrada(
    IN p_id_usuario INT,
    IN p_metodo     VARCHAR(10)
)
BEGIN
    DECLARE v_metodo   VARCHAR(10);
    DECLARE v_contador INT DEFAULT 0;
    DECLARE v_estado   VARCHAR(10) DEFAULT 'Exitoso';
    DECLARE v_motivo   VARCHAR(150) DEFAULT NULL;
    DECLARE v_id       INT;

    SET v_metodo = UPPER(TRIM(p_metodo));

    IF v_metodo IS NULL OR v_metodo NOT IN ('QR', 'RFID') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Método de acceso inválido: use QR o RFID';
    END IF;

    SELECT COUNT(*) INTO v_contador FROM usuarios WHERE id_usuario = p_id_usuario;
    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    SELECT COUNT(*)
      INTO v_contador
      FROM membresias
     WHERE id_usuario = p_id_usuario
       AND estado = 'Activa'
       AND NOW() BETWEEN fecha_inicio AND fecha_vencimiento;

    IF v_contador = 0 THEN
        SET v_estado = 'Rechazado';
        SET v_motivo = 'Membresía inexistente, vencida o suspendida';
    ELSE
        SELECT COUNT(*)
          INTO v_contador
          FROM registros_acceso
         WHERE id_usuario = p_id_usuario
           AND estado_validacion = 'Exitoso'
           AND fecha_hora_salida IS NULL
           AND fecha_hora_entrada >= CURDATE();

        IF v_contador > 0 THEN
            SET v_estado = 'Rechazado';
            SET v_motivo = 'Ya existe una entrada abierta sin salida';
        END IF;
    END IF;

    INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, metodo_acceso, estado_validacion, motivo_rechazo)
    VALUES (p_id_usuario, NOW(), v_metodo, v_estado, v_motivo);

    SET v_id = LAST_INSERT_ID();

    SELECT v_id AS id_acceso, v_estado AS estado_validacion, v_motivo AS motivo_rechazo;
END//

-- 15. Registra la salida sobre la última entrada exitosa del usuario sin salida.
DROP PROCEDURE IF EXISTS sp_registrar_acceso_salida//
CREATE PROCEDURE sp_registrar_acceso_salida(IN p_id_usuario INT)
BEGIN
    DECLARE v_id_acceso INT;

    SET v_id_acceso = (
        SELECT MAX(id_acceso)
          FROM registros_acceso
         WHERE id_usuario = p_id_usuario
           AND estado_validacion = 'Exitoso'
           AND fecha_hora_salida IS NULL
    );

    IF v_id_acceso IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no tiene una entrada abierta';
    END IF;

    UPDATE registros_acceso
       SET fecha_hora_salida = NOW()
     WHERE id_acceso = v_id_acceso;

    SELECT id_acceso,
           fecha_hora_entrada,
           fecha_hora_salida,
           TIMESTAMPDIFF(MINUTE, fecha_hora_entrada, fecha_hora_salida) AS minutos_permanencia
      FROM registros_acceso
     WHERE id_acceso = v_id_acceso;
END//

-- 16. Reporte diario de asistencias. Devuelve dos resultados:
--     (1) resumen del día y (2) detalle de accesos. Si p_fecha es NULL usa hoy.
DROP PROCEDURE IF EXISTS sp_reporte_diario_asistencias//
CREATE PROCEDURE sp_reporte_diario_asistencias(IN p_fecha DATE)
BEGIN
    DECLARE v_fecha DATE;

    SET v_fecha = COALESCE(p_fecha, CURDATE());

    -- Resultado 1: resumen
    SELECT v_fecha                                                          AS fecha,
           COUNT(*)                                                         AS total_accesos,
           COALESCE(SUM(estado_validacion = 'Exitoso'), 0)                  AS exitosos,
           COALESCE(SUM(estado_validacion = 'Rechazado'), 0)                AS rechazados,
           COUNT(DISTINCT CASE WHEN estado_validacion = 'Exitoso' THEN id_usuario END) AS usuarios_distintos,
           COALESCE(SUM(estado_validacion = 'Exitoso' AND fecha_hora_salida IS NULL), 0) AS sin_salida,
           ROUND(AVG(CASE WHEN estado_validacion = 'Exitoso' AND fecha_hora_salida IS NOT NULL
                          THEN TIMESTAMPDIFF(MINUTE, fecha_hora_entrada, fecha_hora_salida) END), 2) AS permanencia_promedio_min
      FROM registros_acceso
     WHERE fecha_hora_entrada >= v_fecha
       AND fecha_hora_entrada <  v_fecha + INTERVAL 1 DAY;

    -- Resultado 2: detalle
    SELECT ra.id_acceso,
           u.identificacion,
           CONCAT(u.nombre, ' ', u.apellidos) AS usuario,
           ra.fecha_hora_entrada,
           ra.fecha_hora_salida,
           ra.metodo_acceso,
           ra.estado_validacion,
           ra.motivo_rechazo
      FROM registros_acceso ra
      INNER JOIN usuarios u ON u.id_usuario = ra.id_usuario
     WHERE ra.fecha_hora_entrada >= v_fecha
       AND ra.fecha_hora_entrada <  v_fecha + INTERVAL 1 DAY
     ORDER BY ra.fecha_hora_entrada;
END//

-- 17. Marca como 'No Show' las reservas confirmadas ya terminadas sin asistencia y
--     penaliza al usuario con una factura equivalente al 20% de la factura de la
--     reserva (vence en 7 días). Si la reserva no tiene factura, solo se marca.
--     El porcentaje se ajusta en v_pct_penalizacion.
DROP PROCEDURE IF EXISTS sp_marcar_no_show_penalizar//
CREATE PROCEDURE sp_marcar_no_show_penalizar()
BEGIN
    DECLARE v_pct_penalizacion DECIMAL(5,2) DEFAULT 20.00;
    DECLARE v_max_factura      INT DEFAULT 0;
    DECLARE v_marcadas         INT DEFAULT 0;
    DECLARE v_penalizadas      INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    DROP TEMPORARY TABLE IF EXISTS tmp_no_show;
    CREATE TEMPORARY TABLE tmp_no_show (
        id_reserva INT PRIMARY KEY,
        id_usuario INT NOT NULL
    );

    START TRANSACTION;

    INSERT INTO tmp_no_show (id_reserva, id_usuario)
    SELECT id_reserva, id_usuario
      FROM reservas
     WHERE estado = 'Confirmada'
       AND asistio = FALSE
       AND fecha_fin < NOW();

    SET v_marcadas = ROW_COUNT();

    UPDATE reservas r
      INNER JOIN tmp_no_show t ON t.id_reserva = r.id_reserva
       SET r.estado = 'No Show';

    SET v_max_factura = (SELECT COALESCE(MAX(id_factura), 0) FROM facturas);

    INSERT INTO facturas (id_usuario, id_reserva, monto_total, saldo_pendiente, estado, fecha_vencimiento)
    SELECT t.id_usuario,
           t.id_reserva,
           ROUND(MAX(f.monto_total) * v_pct_penalizacion / 100, 2),
           ROUND(MAX(f.monto_total) * v_pct_penalizacion / 100, 2),
           'Pendiente',
           DATE_ADD(NOW(), INTERVAL 7 DAY)
      FROM tmp_no_show t
      INNER JOIN facturas f ON f.id_reserva = t.id_reserva
                           AND f.estado <> 'Anulada'
     GROUP BY t.id_usuario, t.id_reserva
    HAVING MAX(f.monto_total) > 0;

    SET v_penalizadas = ROW_COUNT();

    INSERT INTO detalle_facturas (id_factura, id_servicio, descripcion, cantidad, precio_unitario)
    SELECT f.id_factura,
           NULL,
           CONCAT('Penalización por No Show - reserva #', f.id_reserva),
           1,
           f.monto_total
      FROM facturas f
     WHERE f.id_factura > v_max_factura
       AND f.id_reserva IN (SELECT id_reserva FROM tmp_no_show);

    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_no_show;

    SELECT v_marcadas AS reservas_no_show, v_penalizadas AS facturas_penalizacion;
END//

-- =========================================================
-- CORPORATIVOS Y ADMINISTRACIÓN (3)
-- =========================================================

-- 18. Registra empleados de una empresa desde un arreglo JSON. Es todo o nada.
--     Formato: [{"identificacion":"123","nombre":"Ana","apellidos":"Ruiz",
--                "fecha_nacimiento":"1990-05-20","email":"ana@x.com","telefono":"300"}]
--     Campos obligatorios: identificacion, nombre, apellidos, fecha_nacimiento, email.
DROP PROCEDURE IF EXISTS sp_registrar_lote_empleados//
CREATE PROCEDURE sp_registrar_lote_empleados(
    IN p_id_empresa     INT,
    IN p_json_empleados JSON
)
BEGIN
    DECLARE v_contador    INT DEFAULT 0;
    DECLARE v_total       INT DEFAULT 0;
    DECLARE v_invalidos   INT DEFAULT 0;
    DECLARE v_ident_dist  INT DEFAULT 0;
    DECLARE v_email_dist  INT DEFAULT 0;
    DECLARE v_existentes  INT DEFAULT 0;
    DECLARE v_insertados  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_json_empleados IS NULL OR JSON_TYPE(p_json_empleados) <> 'ARRAY' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El parámetro debe ser un arreglo JSON de empleados';
    END IF;

    SELECT COUNT(*) INTO v_contador FROM empresas WHERE id_empresa = p_id_empresa;
    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa no existe';
    END IF;

    SELECT COUNT(*),
           COALESCE(SUM(jt.identificacion IS NULL OR jt.nombre IS NULL OR jt.apellidos IS NULL
                     OR jt.fecha_nacimiento IS NULL OR jt.email IS NULL), 0),
           COUNT(DISTINCT jt.identificacion),
           COUNT(DISTINCT jt.email)
      INTO v_total, v_invalidos, v_ident_dist, v_email_dist
      FROM JSON_TABLE(p_json_empleados, '$[*]' COLUMNS (
               identificacion   VARCHAR(20)  PATH '$.identificacion',
               nombre           VARCHAR(50)  PATH '$.nombre',
               apellidos        VARCHAR(50)  PATH '$.apellidos',
               fecha_nacimiento DATE         PATH '$.fecha_nacimiento',
               email            VARCHAR(100) PATH '$.email'
           )) AS jt;

    IF v_total = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El arreglo de empleados está vacío';
    END IF;

    IF v_invalidos > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Hay empleados con campos obligatorios vacíos o con fecha inválida';
    END IF;

    IF v_ident_dist < v_total OR v_email_dist < v_total THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El lote contiene identificaciones o correos repetidos';
    END IF;

    SELECT COUNT(*)
      INTO v_existentes
      FROM JSON_TABLE(p_json_empleados, '$[*]' COLUMNS (
               identificacion VARCHAR(20)  PATH '$.identificacion',
               email          VARCHAR(100) PATH '$.email'
           )) AS jt
      INNER JOIN usuarios u
              ON u.identificacion = jt.identificacion COLLATE utf8mb4_unicode_ci
              OR u.email          = jt.email          COLLATE utf8mb4_unicode_ci;

    IF v_existentes > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alguna identificación o correo del lote ya está registrado';
    END IF;

    START TRANSACTION;

    INSERT INTO usuarios (id_empresa, identificacion, nombre, apellidos, fecha_nacimiento, email, telefono)
    SELECT p_id_empresa,
           jt.identificacion,
           jt.nombre,
           jt.apellidos,
           jt.fecha_nacimiento,
           jt.email,
           jt.telefono
      FROM JSON_TABLE(p_json_empleados, '$[*]' COLUMNS (
               identificacion   VARCHAR(20)  PATH '$.identificacion',
               nombre           VARCHAR(50)  PATH '$.nombre',
               apellidos        VARCHAR(50)  PATH '$.apellidos',
               fecha_nacimiento DATE         PATH '$.fecha_nacimiento',
               email            VARCHAR(100) PATH '$.email',
               telefono         VARCHAR(25)  PATH '$.telefono'
           )) AS jt;

    SET v_insertados = ROW_COUNT();

    COMMIT;

    SELECT p_id_empresa AS id_empresa, v_insertados AS empleados_registrados;
END//

-- 19. Cancela las reservas futuras de un usuario que será dado de baja y anula sus
--     facturas pendientes. Debe ejecutarse ANTES de eliminar al usuario, porque
--     reservas.id_usuario tiene ON DELETE CASCADE y borraría el historial.
--     No reembolsa pagos ya realizados: para eso use sp_cancelar_reserva_reembolso.
DROP PROCEDURE IF EXISTS sp_cancelar_reservas_usuario_eliminado//
CREATE PROCEDURE sp_cancelar_reservas_usuario_eliminado(IN p_id_usuario INT)
BEGIN
    DECLARE v_contador INT DEFAULT 0;
    DECLARE v_facturas INT DEFAULT 0;
    DECLARE v_reservas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_contador FROM usuarios WHERE id_usuario = p_id_usuario;
    IF v_contador = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    START TRANSACTION;

    UPDATE facturas f
      INNER JOIN reservas r ON r.id_reserva = f.id_reserva
       SET f.estado = 'Anulada',
           f.saldo_pendiente = 0,
           f.motivo_anulacion = 'Usuario dado de baja: reserva cancelada'
     WHERE r.id_usuario = p_id_usuario
       AND r.estado IN ('Pendiente de Confirmación', 'Confirmada')
       AND r.fecha_fin >= NOW()
       AND f.estado = 'Pendiente';

    SET v_facturas = ROW_COUNT();

    UPDATE reservas
       SET estado = 'Cancelada'
     WHERE id_usuario = p_id_usuario
       AND estado IN ('Pendiente de Confirmación', 'Confirmada')
       AND fecha_fin >= NOW();

    SET v_reservas = ROW_COUNT();

    COMMIT;

    SELECT p_id_usuario AS id_usuario, v_reservas AS reservas_canceladas, v_facturas AS facturas_anuladas;
END//

-- 20. Reporte de ingresos mensuales con acumulado y porcentaje acumulado del total.
--     Los ingresos son netos: los reembolsos (pagos negativos) se restan.
DROP PROCEDURE IF EXISTS sp_reporte_ingresos_acumulados//
CREATE PROCEDURE sp_reporte_ingresos_acumulados()
BEGIN
    WITH ingresos_mensuales AS (
        SELECT DATE_FORMAT(fecha_pago, '%Y-%m') AS mes,
               COUNT(*)                         AS pagos,
               SUM(monto)                       AS ingreso_mes
          FROM pagos
         WHERE estado_transaccion = 'Pagado'
         GROUP BY DATE_FORMAT(fecha_pago, '%Y-%m')
    )
    SELECT mes,
           pagos,
           ingreso_mes,
           SUM(ingreso_mes) OVER (ORDER BY mes) AS ingreso_acumulado,
           ROUND(100 * SUM(ingreso_mes) OVER (ORDER BY mes)
                 / NULLIF(SUM(ingreso_mes) OVER (), 0), 2) AS porcentaje_acumulado
      FROM ingresos_mensuales
     ORDER BY mes;
END//

DELIMITER ;

-- =========================================================
-- Ejemplos de uso
-- =========================================================
-- CALL sp_registrar_membresia(1, 2, NOW());
-- CALL sp_validar_disponibilidad_espacio(1, '2026-10-05 09:00:00', '2026-10-05 11:00:00', @disp); SELECT @disp;
-- CALL sp_crear_reserva(1, 1, '2026-10-05 09:00:00', '2026-10-05 11:00:00');
-- CALL sp_registrar_acceso_entrada(1, 'QR');
-- CALL sp_registrar_lote_empleados(1, '[{"identificacion":"100","nombre":"Ana","apellidos":"Ruiz","fecha_nacimiento":"1990-05-20","email":"ana@empresa.com"}]');
-- CALL sp_reporte_ingresos_acumulados();

-- =========================================================================
-- CASOS DE PRUEBA INTEGRALES PARA LOS 20 PROCEDIMIENTOS ALMACENADOS
-- =========================================================================

-- MÓDULO: MEMBRESÍAS (Procedimientos 1 a 4)

-- 1. sp_registrar_membresia
CALL sp_registrar_membresia(28, 2, '2026-10-29 08:00:00');
-- CASO DE ERROR: 
CALL sp_registrar_membresia(9999, 2, NOW());
-- CASO DE ERROR: 
CALL sp_registrar_membresia(1, 2, '2026-09-10 08:00:00');

-- 2. sp_renovar_membresia
CALL sp_renovar_membresia(11, 30);
-- CASO DE ERROR: 
CALL sp_renovar_membresia(11, 0);
-- CASO DE ERROR: 
CALL sp_renovar_membresia(13, 15);

-- 3. sp_actualizar_membresias_vencidas
CALL sp_actualizar_membresias_vencidas();

-- 4. sp_suspender_membresias_morosas
CALL sp_suspender_membresias_morosas(0);
-- CASO DE ERROR: 
CALL sp_suspender_membresias_morosas(-1);


-- MÓDULO: RESERVAS Y ESPACIOS (Procedimientos 5 a 9)

-- 5. sp_validar_disponibilidad_espacio
CALL sp_validar_disponibilidad_espacio(1, '2026-10-05 09:00:00', '2026-10-05 11:00:00', @disp);
SELECT @disp AS espacio_disponible;
-- CASO DE ERROR: 
CALL sp_validar_disponibilidad_espacio(1, '2026-10-05 11:00:00', '2026-10-05 09:00:00', @disp);

-- 6. sp_crear_reserva
CALL sp_crear_reserva(12, 1, '2026-10-06 09:00:00', '2026-10-06 11:00:00');
-- CASO DE ERROR: 
CALL sp_crear_reserva(11, 1, '2025-01-01 09:00:00', '2025-01-01 11:00:00');

-- 7. sp_confirmar_reserva_pago
CALL sp_confirmar_reserva_pago(33);

-- 8. sp_cancelar_reserva_reembolso
CALL sp_cancelar_reserva_reembolso(34, 50.00);
-- CASO DE ERROR: CALL sp_cancelar_reserva_reembolso(34, 150.00);

-- 9. sp_liberar_reservas_pendientes
CALL sp_liberar_reservas_pendientes(1);
-- CASO DE ERROR: CALL sp_liberar_reservas_pendientes(0);


-- MÓDULO: PAGOS Y FACTURACIÓN (Procedimientos 10 a 13)

-- 10. sp_generar_factura_membresia
CALL sp_generar_factura_membresia(25);
-- CASO DE ERROR: CALL sp_generar_factura_membresia(1);

-- 11. sp_generar_factura_empresa
CALL sp_generar_factura_empresa(1, 8, 2026);
-- CASO DE ERROR: CALL sp_generar_factura_empresa(1, 13, 2026);

-- 12. sp_aplicar_recargo_facturas_vencidas
CALL sp_aplicar_recargo_facturas_vencidas(0, 10.00);
-- CASO DE ERROR: CALL sp_aplicar_recargo_facturas_vencidas(0, 0.00);

-- 13. sp_bloquear_servicios_impago
CALL sp_bloquear_servicios_impago(3);
-- CASO DE ERROR: CALL sp_bloquear_servicios_impago(1);


-- MÓDULO: ACCESOS Y ASISTENCIAS (Procedimientos 14 a 17)

-- 14. sp_registrar_acceso_entrada
CALL sp_registrar_acceso_entrada(9, 'QR');
-- CASO DE ERROR: CALL sp_registrar_acceso_entrada(9, 'FRACTAL');

-- 15. sp_registrar_acceso_salida
CALL sp_registrar_acceso_salida(9);
-- CASO DE ERROR: CALL sp_registrar_acceso_salida(28);

-- 16. sp_reporte_diario_asistencias
CALL sp_reporte_diario_asistencias('2026-09-30');
-- CALL sp_reporte_diario_asistencias(NULL);

-- 17. sp_marcar_no_show_penalizar
CALL sp_marcar_no_show_penalizar();


-- MÓDULO: CORPORATIVOS Y ADMINISTRACIÓN (Procedimientos 18 a 20)

-- 18. sp_registrar_lote_empleados
CALL sp_registrar_lote_empleados(2, '[{"identificacion":"999111","nombre":"Carlos","apellidos":"Pérez","fecha_nacimiento":"1995-04-10","email":"carlos.perez@creativa.co","telefono":"3009998877"}]');
-- CASO DE ERROR: CALL sp_registrar_lote_empleados(2, '{"identificacion":"999111"}');

-- 19. sp_cancelar_reservas_usuario_eliminado
CALL sp_cancelar_reservas_usuario_eliminado(4);
-- CASO DE ERROR: CALL sp_cancelar_reservas_usuario_eliminado(9999);

-- 20. sp_reporte_ingresos_acumulados
CALL sp_reporte_ingresos_acumulados();