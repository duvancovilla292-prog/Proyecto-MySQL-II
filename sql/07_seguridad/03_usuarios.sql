/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Seguridad - Usuarios
Archivo: sql/07_seguridad/03_usuarios.sql

Descripción:
Crea una cuenta de ejemplo por rol, les asigna su rol y lo activa por defecto.
Enlaza las cuentas de 'usr_cliente' y 'usr_gerente' con su registro en la
tabla usuarios (necesario para las vistas de seguridad por fila).

IMPORTANTE (seguridad):
- Las contraseñas son SOLO de ejemplo para entornos de desarrollo. Cámbielas
  antes de pasar a producción y no las versione en el repositorio.
- Las cuentas se restringen a 'localhost'. Para acceso remoto use el host o
  subred específica de la aplicación (evite '%').
- Se exige rotación de contraseña (90 días), bloqueo temporal tras 5 intentos
  fallidos y no reutilización de las últimas 5 contraseñas.
- Si el servidor usa validate_password, las contraseñas deben cumplir su política.

Ejecutar DESPUÉS de 01_roles.sql y 02_permisos.sql, como root o administrador.
*/

USE coworking_db;

-- =========================================================
-- 1. CREACIÓN DE USUARIOS
-- =========================================================

-- Administrador del Coworking
CREATE USER IF NOT EXISTS 'usr_admin'@'localhost'
    IDENTIFIED BY 'Adm!n_Cw#2026x';

-- Recepcionista
CREATE USER IF NOT EXISTS 'usr_recepcion'@'localhost'
    IDENTIFIED BY 'Recep!_Cw#2026x';

-- Usuario final (cliente)
CREATE USER IF NOT EXISTS 'usr_cliente'@'localhost'
    IDENTIFIED BY 'Client!_Cw#2026x';

-- Gerente Corporativo
CREATE USER IF NOT EXISTS 'usr_gerente'@'localhost'
    IDENTIFIED BY 'Gerent!_Cw#2026x';

-- Contador
CREATE USER IF NOT EXISTS 'usr_contador'@'localhost'
    IDENTIFIED BY 'Conta!_Cw#2026x';

-- =========================================================
-- 2. ASIGNACIÓN DE ROLES
-- =========================================================

GRANT 'rol_administrador'      TO 'usr_admin'@'localhost';
GRANT 'rol_recepcionista'      TO 'usr_recepcion'@'localhost';
GRANT 'rol_usuario'            TO 'usr_cliente'@'localhost';
GRANT 'rol_gerente_corporativo' TO 'usr_gerente'@'localhost';
GRANT 'rol_contador'           TO 'usr_contador'@'localhost';

-- =========================================================
-- 3. ACTIVACIÓN DEL ROL POR DEFECTO
--    (sin esto el rol no se activa al iniciar sesión)
-- =========================================================

SET DEFAULT ROLE ALL TO 'usr_admin'@'localhost';
SET DEFAULT ROLE ALL TO 'usr_recepcion'@'localhost';
SET DEFAULT ROLE ALL TO 'usr_cliente'@'localhost';
SET DEFAULT ROLE ALL TO 'usr_gerente'@'localhost';
SET DEFAULT ROLE ALL TO 'usr_contador'@'localhost';

-- =========================================================
-- 4. VÍNCULO CUENTA MYSQL -> USUARIO DEL SISTEMA
--    Solo para roles con datos filtrados por fila (cliente y gerente).
--    Ajuste los correos a registros EXISTENTES en la tabla usuarios.
--    Si el correo no existe, no se inserta nada y las vistas devuelven
--    vacío (comportamiento seguro por defecto).
--    El gerente debe pertenecer a una empresa (usuarios.id_empresa).
-- =========================================================

SET @email_cliente = 'cliente@ejemplo.com';
SET @email_gerente = 'gerente@ejemplo.com';

REPLACE INTO seg_mapeo_cuentas (nombre_cuenta, id_usuario)
SELECT 'usr_cliente', id_usuario FROM usuarios WHERE email = @email_cliente;

REPLACE INTO seg_mapeo_cuentas (nombre_cuenta, id_usuario)
SELECT 'usr_gerente', id_usuario FROM usuarios WHERE email = @email_gerente;

-- =========================================================
-- Verificación
-- =========================================================
-- SHOW GRANTS FOR 'usr_cliente'@'localhost' USING 'rol_usuario';
-- SELECT * FROM seg_mapeo_cuentas;
-- Conectado como usr_cliente:   SELECT CURRENT_ROLE();  SELECT * FROM coworking_db.v_mis_reservas;
-- Conectado como usr_gerente:   SELECT * FROM coworking_db.v_empresa_empleados;
