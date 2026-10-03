/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Funciones almacenadas
Archivo: sql/03_funciones/01_funciones.sql
Funciones: 20 (prefijo obligatorio fn_)

Criterios generales (MySQL 8.0+):
- Todas las funciones leen tablas, por lo que se declaran
  NOT DETERMINISTIC READS SQL DATA (su resultado cambia con los datos o con NOW()).
  Una función DETERMINISTIC solo aplicaría si dependiera únicamente de sus parámetros.
- Ingreso real         = pagos con estado_transaccion = 'Pagado'.
- Reserva válida       = cualquier reserva distinta de 'Cancelada'.
- Asistencia           = registro en registros_acceso con estado_validacion = 'Exitoso'.
- Membresía vigente    = estado 'Activa' y NOW() entre fecha_inicio y fecha_vencimiento.
- Las agregaciones numéricas devuelven 0 cuando no hay datos (COALESCE);
  las funciones que devuelven un id o una fecha devuelven NULL cuando no existe resultado.
*/

USE coworking_db;

DELIMITER //

-- =========================================================
-- MEMBRESÍAS
-- =========================================================

-- 1. Indica si el usuario tiene una membresía vigente (1 = sí, 0 = no).
DROP FUNCTION IF EXISTS fn_membresia_activa//
CREATE FUNCTION fn_membresia_activa(p_id_usuario INT)
RETURNS BOOLEAN
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;

    SELECT COUNT(*)
      INTO v_total
      FROM membresias
     WHERE id_usuario = p_id_usuario
       AND estado = 'Activa'
       AND NOW() BETWEEN fecha_inicio AND fecha_vencimiento;

    RETURN COALESCE(v_total, 0) > 0;
END//

-- 2. Días que le quedan a la membresía vigente con vencimiento más lejano (0 si no tiene).
DROP FUNCTION IF EXISTS fn_dias_restantes_membresia//
CREATE FUNCTION fn_dias_restantes_membresia(p_id_usuario INT)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_vencimiento DATETIME;

    SELECT MAX(fecha_vencimiento)
      INTO v_vencimiento
      FROM membresias
     WHERE id_usuario = p_id_usuario
       AND estado = 'Activa'
       AND fecha_vencimiento >= NOW();

    IF v_vencimiento IS NULL THEN
        RETURN 0;
    END IF;

    RETURN GREATEST(DATEDIFF(DATE(v_vencimiento), CURDATE()), 0);
END//

-- 3. Nombre del tipo de la membresía más reciente del usuario ('Sin membresía' si no tiene).
DROP FUNCTION IF EXISTS fn_tipo_membresia//
CREATE FUNCTION fn_tipo_membresia(p_id_usuario INT)
RETURNS VARCHAR(50)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_tipo VARCHAR(50);

    SET v_tipo = (
        SELECT CAST(tm.nombre AS CHAR(50))
          FROM membresias m
          INNER JOIN tipos_membresia tm
                  ON tm.id_tipo_membresia = m.id_tipo_membresia
         WHERE m.id_usuario = p_id_usuario
         ORDER BY m.fecha_inicio DESC, m.id_membresia DESC
         LIMIT 1
    );

    RETURN COALESCE(v_tipo, 'Sin membresía');
END//

-- 4. Número de renovaciones de la membresía más reciente del usuario (0 si no tiene).
DROP FUNCTION IF EXISTS fn_renovaciones_membresia//
CREATE FUNCTION fn_renovaciones_membresia(p_id_usuario INT)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_renovaciones INT;

    SET v_renovaciones = (
        SELECT renovaciones
          FROM membresias
         WHERE id_usuario = p_id_usuario
         ORDER BY fecha_inicio DESC, id_membresia DESC
         LIMIT 1
    );

    RETURN COALESCE(v_renovaciones, 0);
END//

-- 5. Estado real de la membresía más reciente.
--    Si figura 'Activa' pero ya pasó su vencimiento se informa 'Vencida'.
--    Devuelve 'Sin membresía' cuando el usuario no tiene ninguna.
DROP FUNCTION IF EXISTS fn_estado_membresia//
CREATE FUNCTION fn_estado_membresia(p_id_usuario INT)
RETURNS VARCHAR(20)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_estado      VARCHAR(20);
    DECLARE v_vencimiento DATETIME;

    SELECT CAST(estado AS CHAR(20)), fecha_vencimiento
      INTO v_estado, v_vencimiento
      FROM (
            SELECT estado, fecha_vencimiento
              FROM membresias
             WHERE id_usuario = p_id_usuario
             ORDER BY fecha_inicio DESC, id_membresia DESC
             LIMIT 1
           ) ultima;

    IF v_estado IS NULL THEN
        RETURN 'Sin membresía';
    END IF;

    IF v_estado = 'Activa' AND v_vencimiento < NOW() THEN
        RETURN 'Vencida';
    END IF;

    RETURN v_estado;
END//

-- =========================================================
-- RESERVAS
-- =========================================================

-- 6. Total de reservas válidas (no canceladas) del usuario.
DROP FUNCTION IF EXISTS fn_total_reservas//
CREATE FUNCTION fn_total_reservas(p_id_usuario INT)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;

    SELECT COUNT(*)
      INTO v_total
      FROM reservas
     WHERE id_usuario = p_id_usuario
       AND estado <> 'Cancelada';

    RETURN COALESCE(v_total, 0);
END//

-- 7. Horas reservadas por el usuario en un mes y año (según fecha_inicio; excluye canceladas).
DROP FUNCTION IF EXISTS fn_horas_reservadas//
CREATE FUNCTION fn_horas_reservadas(p_id_usuario INT, p_mes INT, p_anio INT)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_inicio DATE;
    DECLARE v_horas  DECIMAL(10,2) DEFAULT 0;

    SET v_inicio = STR_TO_DATE(CONCAT(p_anio, '-', p_mes, '-01'), '%Y-%m-%d');

    IF v_inicio IS NULL THEN
        RETURN 0;
    END IF;

    SELECT ROUND(COALESCE(SUM(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)), 0) / 60, 2)
      INTO v_horas
      FROM reservas
     WHERE id_usuario = p_id_usuario
       AND estado <> 'Cancelada'
       AND fecha_inicio >= v_inicio
       AND fecha_inicio <  v_inicio + INTERVAL 1 MONTH;

    RETURN COALESCE(v_horas, 0);
END//

-- 8. Id del espacio con más reservas válidas (desempate: menor id; NULL si no hay reservas).
DROP FUNCTION IF EXISTS fn_espacio_mas_reservado//
CREATE FUNCTION fn_espacio_mas_reservado()
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_id_espacio INT;

    SET v_id_espacio = (
        SELECT id_espacio
          FROM reservas
         WHERE estado <> 'Cancelada'
         GROUP BY id_espacio
         ORDER BY COUNT(*) DESC, id_espacio ASC
         LIMIT 1
    );

    RETURN v_id_espacio;
END//

-- 9. Reservas activas del usuario: pendientes o confirmadas que aún no han terminado.
DROP FUNCTION IF EXISTS fn_reservas_activas//
CREATE FUNCTION fn_reservas_activas(p_id_usuario INT)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;

    SELECT COUNT(*)
      INTO v_total
      FROM reservas
     WHERE id_usuario = p_id_usuario
       AND estado IN ('Pendiente de Confirmación', 'Confirmada')
       AND fecha_fin >= NOW();

    RETURN COALESCE(v_total, 0);
END//

-- 10. Duración promedio, en horas, de las reservas válidas de un espacio (0 si no tiene).
DROP FUNCTION IF EXISTS fn_duracion_promedio_reservas//
CREATE FUNCTION fn_duracion_promedio_reservas(p_id_espacio INT)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_promedio DECIMAL(10,2) DEFAULT 0;

    SELECT ROUND(COALESCE(AVG(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)), 0) / 60, 2)
      INTO v_promedio
      FROM reservas
     WHERE id_espacio = p_id_espacio
       AND estado <> 'Cancelada';

    RETURN COALESCE(v_promedio, 0);
END//

-- =========================================================
-- PAGOS Y FACTURACIÓN
-- =========================================================

-- 11. Total pagado por el usuario (pagos con estado 'Pagado' sobre sus facturas).
DROP FUNCTION IF EXISTS fn_total_pagado//
CREATE FUNCTION fn_total_pagado(p_id_usuario INT)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10,2) DEFAULT 0;

    SELECT COALESCE(SUM(p.monto), 0)
      INTO v_total
      FROM pagos p
      INNER JOIN facturas f ON f.id_factura = p.id_factura
     WHERE f.id_usuario = p_id_usuario
       AND p.estado_transaccion = 'Pagado';

    RETURN COALESCE(v_total, 0);
END//

-- 12. Ingresos cobrados en un mes y año (según fecha_pago).
DROP FUNCTION IF EXISTS fn_ingresos_por_mes//
CREATE FUNCTION fn_ingresos_por_mes(p_mes INT, p_anio INT)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_inicio DATE;
    DECLARE v_total  DECIMAL(10,2) DEFAULT 0;

    SET v_inicio = STR_TO_DATE(CONCAT(p_anio, '-', p_mes, '-01'), '%Y-%m-%d');

    IF v_inicio IS NULL THEN
        RETURN 0;
    END IF;

    SELECT COALESCE(SUM(monto), 0)
      INTO v_total
      FROM pagos
     WHERE estado_transaccion = 'Pagado'
       AND fecha_pago >= v_inicio
       AND fecha_pago <  v_inicio + INTERVAL 1 MONTH;

    RETURN COALESCE(v_total, 0);
END//

-- 13. Ingresos totales cobrados por facturas asociadas a membresías.
DROP FUNCTION IF EXISTS fn_ingresos_por_membresias//
CREATE FUNCTION fn_ingresos_por_membresias()
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10,2) DEFAULT 0;

    SELECT COALESCE(SUM(p.monto), 0)
      INTO v_total
      FROM pagos p
      INNER JOIN facturas f ON f.id_factura = p.id_factura
     WHERE f.id_membresia IS NOT NULL
       AND p.estado_transaccion = 'Pagado';

    RETURN COALESCE(v_total, 0);
END//

-- 14. Ingresos totales cobrados por facturas asociadas a reservas.
DROP FUNCTION IF EXISTS fn_ingresos_por_reservas//
CREATE FUNCTION fn_ingresos_por_reservas()
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10,2) DEFAULT 0;

    SELECT COALESCE(SUM(p.monto), 0)
      INTO v_total
      FROM pagos p
      INNER JOIN facturas f ON f.id_factura = p.id_factura
     WHERE f.id_reserva IS NOT NULL
       AND p.estado_transaccion = 'Pagado';

    RETURN COALESCE(v_total, 0);
END//

-- 15. Ingresos totales cobrados a los usuarios de una empresa.
DROP FUNCTION IF EXISTS fn_ingresos_por_empresa//
CREATE FUNCTION fn_ingresos_por_empresa(p_id_empresa INT)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10,2) DEFAULT 0;

    SELECT COALESCE(SUM(p.monto), 0)
      INTO v_total
      FROM pagos p
      INNER JOIN facturas f ON f.id_factura = p.id_factura
      INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
     WHERE u.id_empresa = p_id_empresa
       AND p.estado_transaccion = 'Pagado';

    RETURN COALESCE(v_total, 0);
END//

-- =========================================================
-- ACCESOS Y ASISTENCIAS
-- =========================================================

-- 16. Total de asistencias (accesos exitosos) del usuario.
DROP FUNCTION IF EXISTS fn_total_asistencias//
CREATE FUNCTION fn_total_asistencias(p_id_usuario INT)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;

    SELECT COUNT(*)
      INTO v_total
      FROM registros_acceso
     WHERE id_usuario = p_id_usuario
       AND estado_validacion = 'Exitoso';

    RETURN COALESCE(v_total, 0);
END//

-- 17. Asistencias del usuario en un mes y año.
DROP FUNCTION IF EXISTS fn_asistencias_mes//
CREATE FUNCTION fn_asistencias_mes(p_id_usuario INT, p_mes INT, p_anio INT)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_inicio DATE;
    DECLARE v_total  INT DEFAULT 0;

    SET v_inicio = STR_TO_DATE(CONCAT(p_anio, '-', p_mes, '-01'), '%Y-%m-%d');

    IF v_inicio IS NULL THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*)
      INTO v_total
      FROM registros_acceso
     WHERE id_usuario = p_id_usuario
       AND estado_validacion = 'Exitoso'
       AND fecha_hora_entrada >= v_inicio
       AND fecha_hora_entrada <  v_inicio + INTERVAL 1 MONTH;

    RETURN COALESCE(v_total, 0);
END//

-- 18. Id del usuario con más asistencias (desempate: menor id; NULL si no hay asistencias).
DROP FUNCTION IF EXISTS fn_top_usuario_asistencias//
CREATE FUNCTION fn_top_usuario_asistencias()
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_id_usuario INT;

    SET v_id_usuario = (
        SELECT id_usuario
          FROM registros_acceso
         WHERE estado_validacion = 'Exitoso'
         GROUP BY id_usuario
         ORDER BY COUNT(*) DESC, id_usuario ASC
         LIMIT 1
    );

    RETURN v_id_usuario;
END//

-- 19. Fecha y hora de la última asistencia del usuario (NULL si nunca ha asistido).
DROP FUNCTION IF EXISTS fn_ultima_asistencia//
CREATE FUNCTION fn_ultima_asistencia(p_id_usuario INT)
RETURNS DATETIME
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ultima DATETIME;

    SELECT MAX(fecha_hora_entrada)
      INTO v_ultima
      FROM registros_acceso
     WHERE id_usuario = p_id_usuario
       AND estado_validacion = 'Exitoso';

    RETURN v_ultima;
END//

-- 20. Promedio de asistencias por usuario registrado (total de asistencias / total de usuarios).
DROP FUNCTION IF EXISTS fn_promedio_asistencias//
CREATE FUNCTION fn_promedio_asistencias()
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_asistencias INT DEFAULT 0;
    DECLARE v_usuarios    INT DEFAULT 0;

    SELECT COUNT(*) INTO v_asistencias
      FROM registros_acceso
     WHERE estado_validacion = 'Exitoso';

    SELECT COUNT(*) INTO v_usuarios
      FROM usuarios;

    IF COALESCE(v_usuarios, 0) = 0 THEN
        RETURN 0;
    END IF;

    RETURN ROUND(COALESCE(v_asistencias, 0) / v_usuarios, 2);
END//

DELIMITER ;

-- =========================================================
-- Ejemplos de uso
-- =========================================================
-- SELECT fn_membresia_activa(1), fn_dias_restantes_membresia(1), fn_tipo_membresia(1);
-- SELECT fn_horas_reservadas(1, 9, 2026), fn_ingresos_por_mes(9, 2026);
-- SELECT fn_top_usuario_asistencias(), fn_promedio_asistencias();