/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: Seguridad - Roles
Archivo: sql/07_seguridad/01_roles.sql

Descripción:
Crea los 5 roles funcionales del sistema (MySQL 8.0+). Los roles son solo
contenedores de privilegios: los privilegios se asignan en 02_permisos.sql y
los roles se vinculan a cuentas en 03_usuarios.sql.

Convención: todos los roles llevan el prefijo obligatorio rol_.

Orden de ejecución (como root o cuenta con CREATE ROLE / ROLE_ADMIN):
  1) 01_roles.sql  2) 02_permisos.sql  3) 03_usuarios.sql
Requisito previo: estructura, funciones y procedimientos ya creados.
*/

-- =========================================================
-- CREACIÓN DE ROLES
-- =========================================================

-- Administrador del Coworking: acceso total sobre coworking_db.
CREATE ROLE IF NOT EXISTS 'rol_administrador';

-- Recepcionista: gestión de usuarios, membresías, reservas y accesos.
CREATE ROLE IF NOT EXISTS 'rol_recepcionista';

-- Usuario final: consulta de sus propios datos, creación de reservas y
-- visualización de sus facturas.
CREATE ROLE IF NOT EXISTS 'rol_usuario';

-- Gerente Corporativo: empleados de su empresa, reservas y facturación consolidada.
CREATE ROLE IF NOT EXISTS 'rol_gerente_corporativo';

-- Contador: gestión de pagos, facturas y reportes financieros.
CREATE ROLE IF NOT EXISTS 'rol_contador';

-- =========================================================
-- Verificación
-- =========================================================
-- SELECT User AS rol FROM mysql.user WHERE User LIKE 'rol\_%' AND authentication_string = '';
