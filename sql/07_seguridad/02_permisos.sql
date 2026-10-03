/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Seguridad - Permisos
Archivo: sql/07_seguridad/02_permisos.sql

Descripción:
Asigna privilegios a los 5 roles aplicando el principio de MENOR PRIVILEGIO.

Criterios de diseño:
- Las escrituras de negocio se hacen a través de procedimientos almacenados
  (GRANT EXECUTE), no con INSERT/UPDATE directos. Los sp_* se ejecutan con
  SQL SECURITY DEFINER (valor por defecto), por lo que el rol NO necesita
  privilegios sobre las tablas que el procedimiento modifica internamente
  (tampoco sobre las que tocan los triggers).
- MySQL no tiene seguridad por fila (RLS). Para 'rol_usuario' y
  'rol_gerente_corporativo' se usa una capa de VISTAS que filtra por la cuenta
  conectada (USER()) mediante la tabla de mapeo seg_mapeo_cuentas. Estos roles
  NO reciben privilegios sobre las tablas base.
- Las funciones fn_* reciben un id arbitrario como parámetro; por eso NO se
  conceden a roles de alcance restringido (rol_usuario, rol_gerente_corporativo):
  permitirían consultar datos de otros usuarios/empresas.
- Se usan privilegios a nivel de columna cuando hay campos que no deben
  modificarse (p. ej. identificacion).
- Ningún rol recibe WITH GRANT OPTION ni privilegios globales (*.*).

Ejecutar DESPUÉS de 01_roles.sql y con la base creada (estructura, funciones,
procedimientos). Ejecutar como root o cuenta administradora.
*/

USE coworking_db;

-- =========================================================
-- 1. CAPA DE SEGURIDAD POR FILA (mapeo + vistas + wrapper)
-- =========================================================

-- 1.1 Mapeo cuenta MySQL -> usuario del sistema.
--     Solo lo administra rol_administrador (ALL sobre la BD).
CREATE TABLE IF NOT EXISTS seg_mapeo_cuentas (
    nombre_cuenta    VARCHAR(32) NOT NULL PRIMARY KEY,  -- parte de usuario de la cuenta MySQL
    id_usuario       INT NOT NULL,                      -- fila en usuarios
    fecha_asignacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_seg_mapeo_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 1.2 Sesión actual: usuario del sistema y empresa de la cuenta conectada.
--     Sin mapeo => 0 filas => todas las vistas devuelven vacío (seguro por defecto).
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_seg_sesion AS
SELECT m.id_usuario, u.id_empresa
  FROM seg_mapeo_cuentas m
  INNER JOIN usuarios u ON u.id_usuario = m.id_usuario
 WHERE m.nombre_cuenta = SUBSTRING_INDEX(USER(), '@', 1);

-- ---------------------------------------------------------
-- 1.3 Vistas para rol_usuario (solo datos propios)
-- ---------------------------------------------------------
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mi_perfil AS
SELECT u.id_usuario, u.identificacion, u.nombre, u.apellidos,
       u.fecha_nacimiento, u.email, u.telefono, u.id_empresa, u.fecha_registro
  FROM usuarios u
 WHERE u.id_usuario = (SELECT id_usuario FROM v_seg_sesion);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_membresias AS
SELECT m.id_membresia, tm.nombre AS tipo_membresia, tm.precio,
       m.fecha_inicio, m.fecha_vencimiento, m.estado, m.renovaciones
  FROM membresias m
  INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
 WHERE m.id_usuario = (SELECT id_usuario FROM v_seg_sesion);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_reservas AS
SELECT r.id_reserva, r.id_espacio, e.nombre AS espacio, te.nombre AS tipo_espacio,
       r.fecha_inicio, r.fecha_fin, r.estado, r.asistio, r.fecha_creacion
  FROM reservas r
  INNER JOIN espacios e       ON e.id_espacio = r.id_espacio
  INNER JOIN tipos_espacio te ON te.id_tipo_espacio = e.id_tipo_espacio
 WHERE r.id_usuario = (SELECT id_usuario FROM v_seg_sesion);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_facturas AS
SELECT f.id_factura, f.id_membresia, f.id_reserva, f.monto_total,
       f.saldo_pendiente, f.estado, f.fecha_emision, f.fecha_vencimiento
  FROM facturas f
 WHERE f.id_usuario = (SELECT id_usuario FROM v_seg_sesion);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_detalle_facturas AS
SELECT d.id_detalle, d.id_factura, d.descripcion, d.cantidad,
       d.precio_unitario, d.subtotal
  FROM detalle_facturas d
  INNER JOIN facturas f ON f.id_factura = d.id_factura
 WHERE f.id_usuario = (SELECT id_usuario FROM v_seg_sesion);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_pagos AS
SELECT p.id_pago, p.id_factura, p.metodo_pago, p.monto,
       p.estado_transaccion, p.fecha_pago
  FROM pagos p
  INNER JOIN facturas f ON f.id_factura = p.id_factura
 WHERE f.id_usuario = (SELECT id_usuario FROM v_seg_sesion);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_accesos AS
SELECT a.id_acceso, a.fecha_hora_entrada, a.fecha_hora_salida,
       a.metodo_acceso, a.estado_validacion, a.motivo_rechazo
  FROM registros_acceso a
 WHERE a.id_usuario = (SELECT id_usuario FROM v_seg_sesion);

-- ---------------------------------------------------------
-- 1.4 Vistas para rol_gerente_corporativo (solo su empresa)
--     No se exponen fecha_nacimiento ni identificacion de los empleados.
-- ---------------------------------------------------------
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_empresa_empleados AS
SELECT u.id_usuario, u.nombre, u.apellidos, u.email, u.telefono, u.fecha_registro
  FROM usuarios u
 WHERE u.id_empresa = (SELECT id_empresa FROM v_seg_sesion);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_empresa_membresias AS
SELECT m.id_membresia, m.id_usuario, CONCAT(u.nombre, ' ', u.apellidos) AS empleado,
       tm.nombre AS tipo_membresia, m.fecha_inicio, m.fecha_vencimiento,
       m.estado, m.renovaciones
  FROM membresias m
  INNER JOIN usuarios u         ON u.id_usuario = m.id_usuario
  INNER JOIN tipos_membresia tm ON tm.id_tipo_membresia = m.id_tipo_membresia
 WHERE u.id_empresa = (SELECT id_empresa FROM v_seg_sesion);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_empresa_reservas AS
SELECT r.id_reserva, r.id_usuario, CONCAT(u.nombre, ' ', u.apellidos) AS empleado,
       e.nombre AS espacio, r.fecha_inicio, r.fecha_fin, r.estado, r.asistio
  FROM reservas r
  INNER JOIN usuarios u ON u.id_usuario = r.id_usuario
  INNER JOIN espacios e ON e.id_espacio = r.id_espacio
 WHERE u.id_empresa = (SELECT id_empresa FROM v_seg_sesion);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_empresa_facturas AS
SELECT f.id_factura, f.id_usuario, CONCAT(u.nombre, ' ', u.apellidos) AS empleado,
       f.monto_total, f.saldo_pendiente, f.estado, f.fecha_emision, f.fecha_vencimiento
  FROM facturas f
  INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
 WHERE u.id_empresa = (SELECT id_empresa FROM v_seg_sesion);

-- Facturación consolidada por periodo (AAAA-MM) y estado.
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_empresa_facturacion_resumen AS
SELECT DATE_FORMAT(f.fecha_emision, '%Y-%m') AS periodo,
       f.estado,
       COUNT(*)              AS total_facturas,
       SUM(f.monto_total)    AS monto_facturado,
       SUM(f.saldo_pendiente) AS saldo_pendiente
  FROM facturas f
  INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
 WHERE u.id_empresa = (SELECT id_empresa FROM v_seg_sesion)
 GROUP BY DATE_FORMAT(f.fecha_emision, '%Y-%m'), f.estado;

-- ---------------------------------------------------------
-- 1.5 Vistas de reportes financieros (rol_contador)
-- ---------------------------------------------------------
-- Ingreso neto mensual: pagos 'Pagado' (los reembolsos son pagos negativos).
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_reporte_ingresos_mensuales AS
SELECT DATE_FORMAT(p.fecha_pago, '%Y-%m') AS periodo,
       COUNT(*)        AS total_movimientos,
       SUM(p.monto)    AS ingreso_neto
  FROM pagos p
 WHERE p.estado_transaccion = 'Pagado'
 GROUP BY DATE_FORMAT(p.fecha_pago, '%Y-%m');

-- Cartera: facturas con saldo por cobrar.
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_reporte_cartera_pendiente AS
SELECT f.id_factura, f.id_usuario, CONCAT(u.nombre, ' ', u.apellidos) AS cliente,
       u.id_empresa, f.monto_total, f.saldo_pendiente, f.estado,
       f.fecha_emision, f.fecha_vencimiento,
       GREATEST(DATEDIFF(CURDATE(), DATE(f.fecha_vencimiento)), 0) AS dias_mora
  FROM facturas f
  INNER JOIN usuarios u ON u.id_usuario = f.id_usuario
 WHERE f.estado IN ('Pendiente', 'Vencida')
   AND f.saldo_pendiente > 0;

-- 1.6 Wrapper seguro para crear reservas.
--     sp_crear_reserva recibe p_id_usuario: entregarlo directo permitiría
--     reservar a nombre de otra persona. Este wrapper resuelve el usuario
--     desde la cuenta conectada y delega en sp_crear_reserva.
DELIMITER //

DROP PROCEDURE IF EXISTS sp_mi_crear_reserva//
CREATE PROCEDURE sp_mi_crear_reserva(
    IN p_id_espacio INT,
    IN p_inicio     DATETIME,
    IN p_fin        DATETIME
)
BEGIN
    DECLARE v_id_usuario INT;

    SELECT id_usuario INTO v_id_usuario FROM v_seg_sesion LIMIT 1;

    IF v_id_usuario IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La cuenta no está asociada a ningún usuario del coworking.';
    END IF;

    CALL sp_crear_reserva(v_id_usuario, p_id_espacio, p_inicio, p_fin);
END//

DELIMITER ;

-- =========================================================
-- 2. rol_administrador  (acceso total a coworking_db)
-- =========================================================
-- ALL PRIVILEGES a nivel de base: tablas, vistas, rutinas, triggers y eventos.
-- Sin privilegios globales y sin WITH GRANT OPTION.
GRANT ALL PRIVILEGES ON coworking_db.* TO 'rol_administrador';

-- =========================================================
-- 3. rol_recepcionista
--    Gestión de usuarios, membresías, reservas y accesos.
-- =========================================================

-- 3.1 Usuarios: alta y modificación de datos de contacto (sin DELETE ni cambio de identificación).
GRANT SELECT, INSERT ON coworking_db.usuarios TO 'rol_recepcionista';
GRANT UPDATE (id_empresa, nombre, apellidos, fecha_nacimiento, email, telefono)
      ON coworking_db.usuarios TO 'rol_recepcionista';
GRANT SELECT ON coworking_db.empresas TO 'rol_recepcionista';

-- 3.2 Catálogos (solo lectura).
GRANT SELECT ON coworking_db.tipos_membresia       TO 'rol_recepcionista';
GRANT SELECT ON coworking_db.tipos_espacio         TO 'rol_recepcionista';
GRANT SELECT ON coworking_db.espacios              TO 'rol_recepcionista';
GRANT SELECT ON coworking_db.servicios_adicionales TO 'rol_recepcionista';

-- 3.3 Membresías, reservas, accesos: lectura; escritura solo vía procedimientos.
GRANT SELECT ON coworking_db.membresias          TO 'rol_recepcionista';
GRANT SELECT ON coworking_db.reservas            TO 'rol_recepcionista';
GRANT SELECT, INSERT ON coworking_db.reserva_servicios  TO 'rol_recepcionista';
GRANT SELECT, INSERT ON coworking_db.consumos_servicios TO 'rol_recepcionista';
GRANT SELECT ON coworking_db.registros_acceso    TO 'rol_recepcionista';
GRANT SELECT ON coworking_db.log_accesos_rechazados TO 'rol_recepcionista';

-- 3.4 Facturas: solo consulta de estado de pago (no ve el detalle de pagos).
GRANT SELECT ON coworking_db.facturas TO 'rol_recepcionista';

-- 3.5 Procedimientos permitidos.
GRANT EXECUTE ON PROCEDURE coworking_db.sp_registrar_membresia          TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_renovar_membresia            TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_actualizar_membresias_vencidas TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_validar_disponibilidad_espacio TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_crear_reserva                TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_confirmar_reserva_pago       TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_liberar_reservas_pendientes  TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_registrar_acceso_entrada     TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_registrar_acceso_salida      TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_reporte_diario_asistencias   TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_registrar_lote_empleados     TO 'rol_recepcionista';

-- 3.6 Funciones de consulta operativa (sin funciones de ingresos).
GRANT EXECUTE ON FUNCTION coworking_db.fn_membresia_activa           TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_dias_restantes_membresia   TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_tipo_membresia             TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_renovaciones_membresia     TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_estado_membresia           TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_total_reservas             TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_horas_reservadas           TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_espacio_mas_reservado      TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_reservas_activas           TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_duracion_promedio_reservas TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_total_asistencias          TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_asistencias_mes            TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_top_usuario_asistencias    TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_ultima_asistencia          TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION coworking_db.fn_promedio_asistencias       TO 'rol_recepcionista';

-- =========================================================
-- 4. rol_usuario
--    Consulta propia, creación de reservas y visualización de sus facturas.
--    Sin acceso a tablas base con datos personales: solo vistas filtradas.
-- =========================================================

-- 4.1 Datos propios (vistas con filtro por cuenta conectada).
GRANT SELECT ON coworking_db.v_mi_perfil             TO 'rol_usuario';
GRANT SELECT ON coworking_db.v_mis_membresias        TO 'rol_usuario';
GRANT SELECT ON coworking_db.v_mis_reservas          TO 'rol_usuario';
GRANT SELECT ON coworking_db.v_mis_facturas          TO 'rol_usuario';
GRANT SELECT ON coworking_db.v_mis_detalle_facturas  TO 'rol_usuario';
GRANT SELECT ON coworking_db.v_mis_pagos             TO 'rol_usuario';
GRANT SELECT ON coworking_db.v_mis_accesos           TO 'rol_usuario';

-- 4.2 Catálogos públicos necesarios para reservar (sin datos personales).
GRANT SELECT ON coworking_db.tipos_espacio         TO 'rol_usuario';
GRANT SELECT ON coworking_db.espacios              TO 'rol_usuario';
GRANT SELECT ON coworking_db.tipos_membresia       TO 'rol_usuario';
GRANT SELECT ON coworking_db.servicios_adicionales TO 'rol_usuario';

-- 4.3 Crear reservas: solo a su nombre (wrapper) y consultar disponibilidad.
GRANT EXECUTE ON PROCEDURE coworking_db.sp_mi_crear_reserva                TO 'rol_usuario';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_validar_disponibilidad_espacio  TO 'rol_usuario';

-- =========================================================
-- 5. rol_gerente_corporativo
--    Empleados de su empresa, reservas y facturación consolidada (solo lectura).
-- =========================================================
GRANT SELECT ON coworking_db.v_empresa_empleados            TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking_db.v_empresa_membresias           TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking_db.v_empresa_reservas             TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking_db.v_empresa_facturas             TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking_db.v_empresa_facturacion_resumen  TO 'rol_gerente_corporativo';

-- =========================================================
-- 6. rol_contador
--    Gestión de pagos, facturas y reportes financieros.
-- =========================================================

-- 6.1 Facturación y pagos. Saldos y estados de pago los mantienen los triggers;
--     por eso no se permite UPDATE sobre saldo_pendiente ni DELETE.
GRANT SELECT, INSERT ON coworking_db.facturas TO 'rol_contador';
GRANT UPDATE (estado, motivo_anulacion, fecha_vencimiento)
      ON coworking_db.facturas TO 'rol_contador';
GRANT SELECT, INSERT, UPDATE ON coworking_db.detalle_facturas TO 'rol_contador';
GRANT SELECT, INSERT ON coworking_db.pagos TO 'rol_contador';
GRANT UPDATE (estado_transaccion) ON coworking_db.pagos TO 'rol_contador';
GRANT SELECT ON coworking_db.log_pagos_anulados TO 'rol_contador';

-- 6.2 Contexto para conciliar (solo lectura y columnas mínimas de usuarios).
GRANT SELECT (id_usuario, id_empresa, identificacion, nombre, apellidos, email)
      ON coworking_db.usuarios TO 'rol_contador';
GRANT SELECT ON coworking_db.empresas              TO 'rol_contador';
GRANT SELECT ON coworking_db.tipos_membresia       TO 'rol_contador';
GRANT SELECT ON coworking_db.servicios_adicionales TO 'rol_contador';
GRANT SELECT ON coworking_db.membresias            TO 'rol_contador';
GRANT SELECT ON coworking_db.reservas              TO 'rol_contador';
GRANT SELECT ON coworking_db.consumos_servicios    TO 'rol_contador';

-- 6.3 Reportes financieros (vistas).
GRANT SELECT ON coworking_db.v_reporte_ingresos_mensuales TO 'rol_contador';
GRANT SELECT ON coworking_db.v_reporte_cartera_pendiente  TO 'rol_contador';

-- 6.4 Procedimientos financieros.
GRANT EXECUTE ON PROCEDURE coworking_db.sp_generar_factura_membresia        TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_generar_factura_empresa          TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_aplicar_recargo_facturas_vencidas TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_bloquear_servicios_impago        TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_suspender_membresias_morosas     TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_cancelar_reserva_reembolso       TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_db.sp_reporte_ingresos_acumulados      TO 'rol_contador';

-- 6.5 Funciones financieras.
GRANT EXECUTE ON FUNCTION coworking_db.fn_total_pagado             TO 'rol_contador';
GRANT EXECUTE ON FUNCTION coworking_db.fn_ingresos_por_mes         TO 'rol_contador';
GRANT EXECUTE ON FUNCTION coworking_db.fn_ingresos_por_membresias  TO 'rol_contador';
GRANT EXECUTE ON FUNCTION coworking_db.fn_ingresos_por_reservas    TO 'rol_contador';
GRANT EXECUTE ON FUNCTION coworking_db.fn_ingresos_por_empresa     TO 'rol_contador';

-- =========================================================
-- Verificación
-- =========================================================
-- SHOW GRANTS FOR 'rol_recepcionista';
-- SHOW GRANTS FOR 'rol_usuario';
-- SHOW GRANTS FOR 'rol_contador';
