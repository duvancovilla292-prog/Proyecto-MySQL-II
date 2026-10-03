/*
Pruebas de los 20 triggers trg_*
Requisito: haber ejecutado 01_estructura.sql y 01_triggers.sql (este último crea usuarios.ultimo_acceso).

Cómo funciona:
- Todo corre dentro de una transacción y al final se hace ROLLBACK, así no queda ningún dato de prueba.
- Crea sus propios datos (usuarios TEST-U1 y TEST-U2, espacio 'TEST sala').
- PARTE A: cada prueba hace una acción y un SELECT con dos columnas:
      resultado -> lo que dejó el trigger
      esperado  -> lo que debería dar
  Si ambas coinciden, el trigger funciona.
- PARTE B: pruebas que DEBEN FALLAR con un mensaje. Ejecútalas una por una
  (selecciona la línea y ejecútala) en la MISMA sesión, antes del ROLLBACK final.
*/

USE coworking_db;
START TRANSACTION;

-- =========================================================
-- DATOS DE PRUEBA
-- =========================================================
INSERT IGNORE INTO tipos_membresia (nombre, descripcion, precio, duracion_dias)
VALUES ('Diaria', 'Prueba', 10, 1), ('Mensual', 'Prueba', 100, 30);
SET @tDiaria  = (SELECT id_tipo_membresia FROM tipos_membresia WHERE nombre = 'Diaria');
SET @tMensual = (SELECT id_tipo_membresia FROM tipos_membresia WHERE nombre = 'Mensual');

INSERT INTO tipos_espacio (nombre, descripcion) VALUES ('TEST tipo', 'Prueba');
SET @tesp = LAST_INSERT_ID();
INSERT INTO espacios (id_tipo_espacio, nombre, capacidad_maxima) VALUES (@tesp, 'TEST sala', 10);
SET @esp = LAST_INSERT_ID();

INSERT INTO usuarios (identificacion, nombre, apellidos, fecha_nacimiento, email)
VALUES ('TEST-U1', 'Test', 'Uno', '1990-01-01', 'test.u1@prueba.com');
SET @u1 = LAST_INSERT_ID();
INSERT INTO usuarios (identificacion, nombre, apellidos, fecha_nacimiento, email)
VALUES ('TEST-U2', 'Test', 'Dos', '1990-01-01', 'test.u2@prueba.com');
SET @u2 = LAST_INSERT_ID();

-- =========================================================
-- PARTE A: PRUEBAS QUE DEBEN FUNCIONAR
-- =========================================================

-- ---------- 1. trg_ins_membresia_vencimiento ----------
-- Insertamos SIN fecha_vencimiento: el trigger la calcula con duracion_dias.
INSERT INTO membresias (id_usuario, id_tipo_membresia, fecha_inicio)
VALUES (@u1, @tMensual, NOW());
SET @m1 = LAST_INSERT_ID();

SELECT 'T1' AS prueba,
       DATEDIFF(fecha_vencimiento, fecha_inicio) AS resultado,
       (SELECT duracion_dias FROM tipos_membresia WHERE id_tipo_membresia = @tMensual) AS esperado
  FROM membresias WHERE id_membresia = @m1;

-- ---------- 4. trg_upd_membresia_log ----------
UPDATE membresias SET id_tipo_membresia = @tDiaria WHERE id_membresia = @m1;

SELECT 'T4' AS prueba,
       (SELECT COUNT(*) FROM log_cambios_membresia
         WHERE id_usuario = @u1 AND id_tipo_anterior = @tMensual AND id_tipo_nuevo = @tDiaria) AS resultado,
       1 AS esperado;

-- ---------- 3. trg_upd_membresia_suspender ----------
-- Factura de membresía que pasa a 'Vencida' con saldo -> la membresía queda Suspendida.
INSERT INTO facturas (id_usuario, id_membresia, monto_total, saldo_pendiente, estado, fecha_vencimiento)
VALUES (@u1, @m1, 100, 100, 'Pendiente', NOW() + INTERVAL 5 DAY);
SET @f1 = LAST_INSERT_ID();

UPDATE facturas SET estado = 'Vencida' WHERE id_factura = @f1;

SELECT 'T3' AS prueba,
       (SELECT estado FROM membresias WHERE id_membresia = @m1) AS resultado,
       'Suspendida' AS esperado;

-- ---------- 11 (caso válido), 14 y 2 ----------
-- Pago completo de la factura vencida:
--   T11 lo valida, T14 deja saldo 0 y factura 'Pagada', T2 reactiva la membresía.
INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
VALUES (@f1, 'Efectivo', 100, 'Pagado');

SELECT 'T14' AS prueba,
       (SELECT CONCAT(estado, '/', saldo_pendiente) FROM facturas WHERE id_factura = @f1) AS resultado,
       'Pagada/0.00' AS esperado;

SELECT 'T2' AS prueba,
       (SELECT estado FROM membresias WHERE id_membresia = @m1) AS resultado,
       'Activa' AS esperado;

-- ---------- 14 (pago parcial) ----------
INSERT INTO facturas (id_usuario, monto_total, saldo_pendiente, estado, fecha_vencimiento)
VALUES (@u1, 80, 80, 'Pendiente', NOW() + INTERVAL 5 DAY);
SET @f3 = LAST_INSERT_ID();

INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
VALUES (@f3, 'Tarjeta', 30, 'Pagado');
SET @p1 = LAST_INSERT_ID();

SELECT 'T14 parcial' AS prueba,
       (SELECT CONCAT(estado, '/', saldo_pendiente) FROM facturas WHERE id_factura = @f3) AS resultado,
       'Pendiente/50.00' AS esperado;

-- ---------- 12. trg_upd_factura_pagada ----------
-- Pago 'Pendiente' que luego pasa a 'Pagado'.
INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
VALUES (@f3, 'Tarjeta', 50, 'Pendiente');
SET @p2 = LAST_INSERT_ID();

UPDATE pagos SET estado_transaccion = 'Pagado' WHERE id_pago = @p2;

SELECT 'T12' AS prueba,
       (SELECT CONCAT(estado, '/', saldo_pendiente) FROM facturas WHERE id_factura = @f3) AS resultado,
       'Pagada/0.00' AS esperado;

-- ---------- 15. trg_upd_pago_anulado_log ----------
UPDATE pagos SET estado_transaccion = 'Cancelado' WHERE id_pago = @p1;

SELECT 'T15' AS prueba,
       (SELECT COUNT(*) FROM log_pagos_anulados WHERE id_pago = @p1) AS resultado,
       1 AS esperado;

-- ---------- 7. trg_ins_reserva_estado_inicial ----------
-- Intentamos insertarla 'Confirmada' y asistio = TRUE: el trigger lo fuerza a Pendiente / 0.
INSERT INTO reservas (id_usuario, id_espacio, fecha_inicio, fecha_fin, estado, asistio)
VALUES (@u1, @esp, NOW() + INTERVAL 48 HOUR, NOW() + INTERVAL 51 HOUR, 'Confirmada', TRUE);
SET @r1 = LAST_INSERT_ID();

SELECT 'T7' AS prueba,
       (SELECT CONCAT(estado, '/', asistio) FROM reservas WHERE id_reserva = @r1) AS resultado,
       'Pendiente de Confirmación/0' AS esperado;

-- ---------- 8. trg_upd_reserva_pago_confirmar ----------
INSERT INTO facturas (id_usuario, id_reserva, monto_total, saldo_pendiente, estado, fecha_vencimiento)
VALUES (@u1, @r1, 50, 50, 'Pendiente', NOW() + INTERVAL 5 DAY);
SET @f2 = LAST_INSERT_ID();

INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
VALUES (@f2, 'Transferencia', 50, 'Pagado');

SELECT 'T8' AS prueba,
       (SELECT estado FROM reservas WHERE id_reserva = @r1) AS resultado,
       'Confirmada' AS esperado;

-- ---------- 10. trg_upd_reserva_cancelada_log ----------
INSERT INTO reservas (id_usuario, id_espacio, fecha_inicio, fecha_fin)
VALUES (@u1, @esp, NOW() + INTERVAL 120 HOUR, NOW() + INTERVAL 122 HOUR);
SET @r2 = LAST_INSERT_ID();

UPDATE reservas SET estado = 'Cancelada' WHERE id_reserva = @r2;

SELECT 'T10' AS prueba,
       (SELECT motivo FROM log_reservas_canceladas WHERE id_reserva = @r2) AS resultado,
       'Cancelada desde estado: Pendiente de Confirmación' AS esperado;

-- ---------- 9. trg_del_membresia_cancelar_reservas (y 5 en caso permitido) ----------
-- Usuario 2: una membresía y una reserva pendiente futura. Al borrar la membresía
-- (sin otra vigente) la reserva se cancela.
INSERT INTO membresias (id_usuario, id_tipo_membresia, fecha_inicio)
VALUES (@u2, @tMensual, NOW());
SET @m2 = LAST_INSERT_ID();

INSERT INTO reservas (id_usuario, id_espacio, fecha_inicio, fecha_fin)
VALUES (@u2, @esp, NOW() + INTERVAL 24 HOUR, NOW() + INTERVAL 26 HOUR);
SET @r3 = LAST_INSERT_ID();

DELETE FROM membresias WHERE id_membresia = @m2;

SELECT 'T9' AS prueba,
       (SELECT estado FROM reservas WHERE id_reserva = @r3) AS resultado,
       'Cancelada' AS esperado;

-- ---------- 16, 17 (caso válido) y 18 ----------
-- Reserva de u1 que cubre el momento actual, confirmada pagando su factura.
INSERT INTO reservas (id_usuario, id_espacio, fecha_inicio, fecha_fin)
VALUES (@u1, @esp, NOW() - INTERVAL 1 HOUR, NOW() + INTERVAL 1 HOUR);
SET @r4 = LAST_INSERT_ID();

INSERT INTO facturas (id_usuario, id_reserva, monto_total, saldo_pendiente, estado, fecha_vencimiento)
VALUES (@u1, @r4, 20, 20, 'Pendiente', NOW() + INTERVAL 5 DAY);
SET @f4 = LAST_INSERT_ID();

INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
VALUES (@f4, 'Efectivo', 20, 'Pagado');

-- Primer acceso de u1 (sin salida a propósito, lo usa la prueba 19).
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, metodo_acceso, estado_validacion)
VALUES (@u1, NOW(), 'QR', 'Exitoso');
SET @a1 = LAST_INSERT_ID();

SELECT 'T17 valido' AS prueba,
       (SELECT estado_validacion FROM registros_acceso WHERE id_acceso = @a1) AS resultado,
       'Exitoso' AS esperado;

SELECT 'T16' AS prueba,
       (SELECT asistio FROM reservas WHERE id_reserva = @r4) AS resultado,
       1 AS esperado;

SELECT 'T18' AS prueba,
       (SELECT ultimo_acceso FROM usuarios WHERE id_usuario = @u1)
         = (SELECT fecha_hora_entrada FROM registros_acceso WHERE id_acceso = @a1) AS resultado,
       1 AS esperado;

-- ---------- 19. trg_ins_acceso_auto_salida ----------
-- Segundo acceso del mismo día sin que el primero tenga salida -> Rechazado.
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, metodo_acceso, estado_validacion)
VALUES (@u1, NOW() + INTERVAL 1 MINUTE, 'QR', 'Exitoso');
SET @a2 = LAST_INSERT_ID();

SELECT 'T19' AS prueba,
       (SELECT CONCAT(estado_validacion, ' / ', motivo_rechazo) FROM registros_acceso WHERE id_acceso = @a2) AS resultado,
       'Rechazado / Ya existe una entrada abierta sin salida' AS esperado;

-- ---------- 17 (caso rechazo) ----------
-- u2 ya no tiene membresía (se borró en T9) ni reserva confirmada.
INSERT INTO registros_acceso (id_usuario, fecha_hora_entrada, metodo_acceso, estado_validacion)
VALUES (@u2, NOW(), 'RFID', 'Exitoso');
SET @a3 = LAST_INSERT_ID();

SELECT 'T17 rechazo' AS prueba,
       (SELECT CONCAT(estado_validacion, ' / ', motivo_rechazo) FROM registros_acceso WHERE id_acceso = @a3) AS resultado,
       'Rechazado / Sin membresía activa ni reserva válida' AS esperado;

-- ---------- 20. trg_ins_acceso_rechazado_log ----------
-- Se esperan 2 filas: la de T19 (u1) y la de T17 (u2).
SELECT 'T20' AS prueba,
       (SELECT COUNT(*) FROM log_accesos_rechazados WHERE id_usuario IN (@u1, @u2)) AS resultado,
       2 AS esperado;

-- =========================================================
-- PARTE B: PRUEBAS QUE DEBEN FALLAR (ejecutar una por una)
-- Cada una debe lanzar el error indicado. Si se ejecuta sin error, el trigger falla.
-- =========================================================

-- 5. trg_del_membresia_bloquear
--    Error esperado: No se puede eliminar la membresía: el usuario tiene reservas confirmadas activas
DELETE FROM membresias WHERE id_membresia = @m1;

-- 6a. trg_ins_reserva_validar_duplicada (solapamiento con la reserva @r1)
--     Error esperado: El espacio ya tiene una reserva en ese horario
INSERT INTO reservas (id_usuario, id_espacio, fecha_inicio, fecha_fin)
VALUES (@u2, @esp, NOW() + INTERVAL 49 HOUR, NOW() + INTERVAL 50 HOUR);

-- 6b. trg_ins_reserva_validar_duplicada (rango inválido)
--     Error esperado: Rango de fechas inválido: el inicio debe ser menor al fin
INSERT INTO reservas (id_usuario, id_espacio, fecha_inicio, fecha_fin)
VALUES (@u2, @esp, NOW() + INTERVAL 200 HOUR, NOW() + INTERVAL 199 HOUR);

-- 11a. trg_ins_pago_crear_factura (factura inexistente)
--      Error esperado: La factura asociada al pago no existe
INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
VALUES (999999, 'Efectivo', 10, 'Pagado');

-- 11b. trg_ins_pago_crear_factura (monto cero)
--      Error esperado: El monto del pago debe ser distinto de cero
INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
VALUES (@f3, 'Efectivo', 0, 'Pagado');

-- 11c. trg_ins_pago_crear_factura (excede el saldo; @f3 ya tiene saldo 0)
--      Error esperado: El pago excede el saldo pendiente de la factura
INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
VALUES (@f3, 'Efectivo', 10, 'Pagado');

-- 11d. trg_ins_pago_crear_factura (factura anulada)
--      Error esperado: No se puede registrar un pago sobre una factura anulada
INSERT INTO facturas (id_usuario, monto_total, saldo_pendiente, estado, fecha_vencimiento)
VALUES (@u1, 40, 40, 'Anulada', NOW() + INTERVAL 5 DAY);
SET @f5 = LAST_INSERT_ID();
INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion)
VALUES (@f5, 'Efectivo', 10, 'Pagado');

-- 13. trg_del_pago_bloquear (@f3 está 'Pagada')
--     Error esperado: No se puede eliminar un pago de una factura pagada
DELETE FROM pagos WHERE id_pago = @p2;

-- =========================================================
-- LIMPIEZA: deshace todos los datos de prueba
-- =========================================================
ROLLBACK;
