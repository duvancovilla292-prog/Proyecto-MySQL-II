/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: DML - Datos Iniciales
Archivo: 01_datos_iniciales.sql

Descripción:
Inserción de datos maestros, catálogos y transaccionales para pruebas del sistema.

Requisitos:
Ejecutar previamente 00_ddl/01_estructura.sql.
*/

USE coworking_db;

SET NAMES utf8mb4;

/* Fecha de referencia de los datos: 2026-09-30 (miércoles) */

-- =====================================================================
-- TABLA: tipos_membresia
-- =====================================================================
INSERT INTO tipos_membresia (id_tipo_membresia, nombre, descripcion, precio, duracion_dias) VALUES
(1, 'Diaria',      'Acceso por un día a escritorios flexibles, internet estándar y zonas comunes.', 25.00, 1),
(2, 'Mensual',     'Acceso mensual a escritorios flexibles, zonas comunes y 4 horas de sala de reuniones.', 350.00, 30),
(3, 'Corporativa', 'Plan para equipos de empresa con acceso multiusuario, prioridad en reservas y facturación centralizada.', 1200.00, 30),
(4, 'Premium',      'Acceso 24/7, locker incluido, internet premium y descuentos en salas de reuniones y eventos.', 650.00, 30);

-- =====================================================================
-- TABLA: tipos_espacio
-- =====================================================================
INSERT INTO tipos_espacio (id_tipo_espacio, nombre, descripcion) VALUES
(1, 'Escritorios flexibles', 'Puestos de trabajo compartidos en áreas abiertas, sin asignación fija.'),
(2, 'Oficinas privadas',     'Oficinas cerradas y equipadas para equipos pequeños.'),
(3, 'Salas de reuniones',    'Salas equipadas con pantalla, pizarra y conferencia para reuniones y talleres.'),
(4, 'Salas de eventos',      'Auditorios y terrazas para eventos, capacitaciones y lanzamientos.');

-- =====================================================================
-- TABLA: servicios_adicionales
-- =====================================================================
INSERT INTO servicios_adicionales (id_servicio, nombre, costo, bloqueado) VALUES
(1, 'Internet premium',   15.00, FALSE),
(2, 'Lockers',            10.00, FALSE),
(3, 'Café ilimitado',     20.00, FALSE),
(4, 'Impresiones',         5.00, FALSE),
(5, 'Uso de proyector',   30.00, FALSE),
(6, 'Catering ejecutivo', 120.00, TRUE);

-- =====================================================================
-- TABLA: empresas
-- =====================================================================
INSERT INTO empresas (id_empresa, nombre, nit_ruc, telefono, direccion, fecha_registro) VALUES
(1, 'TechNova Solutions SAS',        '900123456-1', '6017001001', 'Calle 93 #13-24, Bogotá',         '2023-02-01 09:00:00'),
(2, 'Creativa Studio Ltda',          '900234567-2', '6047002002', 'Carrera 43A #7-50, Medellín',     '2023-09-01 10:30:00'),
(3, 'AgroData Colombia SAS',         '900345678-3', '6027003003', 'Avenida 6N #25-40, Cali',         '2024-11-05 11:15:00'),
(4, 'FinanzasPlus S.A.',             '900456789-4', '6017004004', 'Carrera 7 #71-21, Bogotá',        '2023-02-20 08:45:00'),
(5, 'Legal Partners & Asociados',    '900567890-5', '6057005005', 'Calle 77B #57-141, Barranquilla', '2024-02-15 14:00:00'),
(6, 'EduFuture Labs SAS',            '900678901-6', '6017006006', 'Calle 100 #19-54, Bogotá',        '2026-03-10 16:20:00');

-- =====================================================================
-- TABLA: usuarios
-- (1-11 TechNova, 12-15 Creativa, 16-18 AgroData, 19-20 FinanzasPlus,
--  21-22 Legal Partners, 23 EduFuture, 24-30 independientes.
--  Recientes: 11, 15, 18, 27, 28, 29. Sin reservas ni accesos: 28 y 29.)
-- =====================================================================
INSERT INTO usuarios (id_usuario, id_empresa, identificacion, nombre, apellidos, fecha_nacimiento, email, telefono, fecha_registro) VALUES
(1,  1,    '1098100001', 'Carlos',       'Méndez',     '1988-03-12', 'carlos.mendez@technova.co',       '3001110001', '2023-02-10 09:15:00'),
(2,  1,    '1098100002', 'Laura',        'Gómez',      '1991-07-25', 'laura.gomez@technova.co',         '3001110002', '2023-05-18 10:00:00'),
(3,  1,    '1098100003', 'Andrés',       'Rojas',      '1985-11-02', 'andres.rojas@technova.co',        '3001110003', '2023-08-22 11:30:00'),
(4,  1,    '1098100004', 'Valentina',    'Ruiz',       '1993-04-18', 'valentina.ruiz@technova.co',      '3001110004', '2024-01-09 09:45:00'),
(5,  1,    '1098100005', 'Santiago',     'Herrera',    '1990-09-30', 'santiago.herrera@technova.co',    '3001110005', '2024-03-14 08:50:00'),
(6,  1,    '1098100006', 'Camila',       'Torres',     '1995-01-14', 'camila.torres@technova.co',       '3001110006', '2024-06-02 13:10:00'),
(7,  1,    '1098100007', 'Juan Pablo',   'Cárdenas',   '1987-06-21', 'juanpablo.cardenas@technova.co',  '3001110007', '2024-09-19 15:40:00'),
(8,  1,    '1098100008', 'Daniela',      'Ortiz',      '1996-12-05', 'daniela.ortiz@technova.co',       '3001110008', '2025-02-11 10:25:00'),
(9,  1,    '1098100009', 'Felipe',       'Castaño',    '1992-08-09', 'felipe.castano@technova.co',      '3001110009', '2025-06-30 12:00:00'),
(10, 1,    '1098100010', 'Mariana',      'Silva',      '1998-02-27', 'mariana.silva@technova.co',       '3001110010', '2026-01-20 09:05:00'),
(11, 1,    '1098100011', 'Sebastián',    'Vargas',     '2000-05-16', 'sebastian.vargas@technova.co',    '3001110011', '2026-09-12 09:30:00'),
(12, 2,    '1098100012', 'Isabella',     'Moreno',     '1994-10-11', 'isabella.moreno@creativastudio.co','3002220012', '2023-09-05 10:10:00'),
(13, 2,    '1098100013', 'Mateo',        'Jiménez',    '1989-03-03', 'mateo.jimenez@creativastudio.co', '3002220013', '2024-04-17 11:20:00'),
(14, 2,    '1098100014', 'Sofía',        'Navarro',    '1997-07-19', 'sofia.navarro@creativastudio.co', '3002220014', '2025-03-08 14:35:00'),
(15, 2,    '1098100015', 'Nicolás',      'Peña',       '1999-09-08', 'nicolas.pena@creativastudio.co',  '3002220015', '2026-09-05 08:40:00'),
(16, 3,    '1098100016', 'Paula',        'Restrepo',   '1991-01-31', 'paula.restrepo@agrodata.co',      '3003330016', '2024-11-12 09:00:00'),
(17, 3,    '1098100017', 'David',        'Quintero',   '1986-04-22', 'david.quintero@agrodata.co',      '3003330017', '2025-05-21 10:45:00'),
(18, 3,    '1098100018', 'Natalia',      'Duarte',     '2001-11-13', 'natalia.duarte@agrodata.co',      '3003330018', '2026-09-18 16:05:00'),
(19, 4,    '1098100019', 'Ricardo',      'Salazar',    '1982-05-05', 'ricardo.salazar@finanzasplus.co', '3004440019', '2023-03-01 08:30:00'),
(20, 4,    '1098100020', 'Gabriela',     'Ospina',     '1993-06-28', 'gabriela.ospina@finanzasplus.co', '3004440020', '2025-08-14 11:55:00'),
(21, 5,    '1098100021', 'Esteban',      'Correa',     '1984-12-19', 'esteban.correa@legalpartners.co', '3005550021', '2024-02-27 15:10:00'),
(22, 5,    '1098100022', 'Lucía',        'Mejía',      '1990-03-07', 'lucia.mejia@legalpartners.co',    '3005550022', '2025-10-09 09:20:00'),
(23, 6,    '1098100023', 'Tomás',        'Giraldo',    '1997-08-24', 'tomas.giraldo@edufuture.co',      '3006660023', '2026-03-15 10:00:00'),
(24, NULL, '1098100024', 'Andrea',       'Patiño',     '1987-02-14', 'andrea.patino@gmail.com',         '3107770024', '2023-01-25 09:00:00'),
(25, NULL, '1098100025', 'Julián',       'Bermúdez',   '1992-10-30', 'julian.bermudez@outlook.com',     '3107770025', '2023-07-07 13:45:00'),
(26, NULL, '1098100026', 'Karen',        'Pardo',      '1995-05-09', 'karen.pardo@gmail.com',           '3107770026', '2025-01-16 10:30:00'),
(27, NULL, '1098100027', 'Óscar',        'Lozano',     '1998-12-01', 'oscar.lozano@hotmail.com',        '3107770027', '2026-09-22 12:15:00'),
(28, NULL, '1098100028', 'Mónica',       'Arias',      '1994-09-17', 'monica.arias@gmail.com',          '3107770028', '2026-09-27 17:00:00'),
(29, NULL, '1098100029', 'Hugo',         'Benítez',    '1989-07-07', 'hugo.benitez@yahoo.com',          '3107770029', '2026-09-28 09:10:00'),
(30, NULL, '1098100030', 'Diana',        'Cifuentes',  '1996-03-22', 'diana.cifuentes@gmail.com',       '3107770030', '2024-08-03 10:00:00');

-- =====================================================================
-- TABLA: espacios
-- =====================================================================
INSERT INTO espacios (id_espacio, id_tipo_espacio, nombre, capacidad_maxima, hora_apertura, hora_cierre, estado) VALUES
(1,  1, 'Escritorio Flex A',          20,  '06:00:00', '22:00:00', 'Disponible'),
(2,  1, 'Escritorio Flex B',          15,  '06:00:00', '22:00:00', 'Disponible'),
(3,  1, 'Escritorio Flex Silencioso', 10,  '06:00:00', '22:00:00', 'Disponible'),
(4,  2, 'Oficina Privada 101',         4,  '06:00:00', '22:00:00', 'Disponible'),
(5,  2, 'Oficina Privada 102',         6,  '06:00:00', '22:00:00', 'Disponible'),
(6,  2, 'Oficina Privada 201',         8,  '06:00:00', '22:00:00', 'Mantenimiento'),
(7,  3, 'Sala Reuniones Andes',        8,  '06:00:00', '22:00:00', 'Disponible'),
(8,  3, 'Sala Reuniones Caribe',      12,  '06:00:00', '22:00:00', 'Disponible'),
(9,  3, 'Sala Reuniones Pacífico',     6,  '06:00:00', '22:00:00', 'Disponible'),
(10, 4, 'Auditorio Principal',       100,  '07:00:00', '23:00:00', 'Disponible'),
(11, 4, 'Terraza de Eventos',         60,  '08:00:00', '23:00:00', 'Disponible'),
(12, 3, 'Sala Reuniones Amazonas',    10,  '06:00:00', '22:00:00', 'Inactivo');

-- =====================================================================
-- TABLA: membresias
-- (1-28 corresponden a los usuarios 1-28; 29 = usuario 30;
--  30, 31 y 32 son membresías previas vencidas de los usuarios 1, 3 y 19)
-- =====================================================================
INSERT INTO membresias (id_membresia, id_usuario, id_tipo_membresia, fecha_inicio, fecha_vencimiento, estado, renovaciones) VALUES
(1,  1,  3, '2026-09-06 08:00:00', '2026-10-06 08:00:00', 'Activa',     11),
(2,  2,  3, '2026-09-10 08:00:00', '2026-10-10 08:00:00', 'Activa',      9),
(3,  3,  4, '2026-09-03 08:00:00', '2026-10-03 08:00:00', 'Activa',      8),
(4,  4,  4, '2026-09-15 08:00:00', '2026-10-15 08:00:00', 'Activa',      5),
(5,  5,  2, '2026-09-01 08:00:00', '2026-10-01 08:00:00', 'Activa',     12),
(6,  6,  2, '2026-08-01 08:00:00', '2026-08-31 08:00:00', 'Vencida',     6),
(7,  7,  3, '2026-09-20 08:00:00', '2026-10-20 08:00:00', 'Activa',      3),
(8,  8,  2, '2026-09-05 08:00:00', '2026-10-05 08:00:00', 'Activa',      7),
(9,  9,  1, '2026-09-30 08:00:00', '2026-10-01 08:00:00', 'Activa',     15),
(10, 10, 2, '2026-09-12 08:00:00', '2026-10-12 08:00:00', 'Activa',      2),
(11, 11, 2, '2026-09-12 09:30:00', '2026-10-12 09:30:00', 'Activa',      0),
(12, 12, 4, '2026-09-08 08:00:00', '2026-10-08 08:00:00', 'Activa',     10),
(13, 13, 2, '2026-08-20 08:00:00', '2026-09-19 08:00:00', 'Suspendida',  4),
(14, 14, 3, '2026-09-02 08:00:00', '2026-10-02 08:00:00', 'Activa',      6),
(15, 15, 1, '2026-09-30 08:00:00', '2026-10-01 08:00:00', 'Activa',      0),
(16, 16, 2, '2026-07-01 08:00:00', '2026-07-31 08:00:00', 'Vencida',     3),
(17, 17, 4, '2026-09-18 08:00:00', '2026-10-18 08:00:00', 'Activa',      4),
(18, 18, 1, '2026-09-29 08:00:00', '2026-09-30 08:00:00', 'Vencida',     1),
(19, 19, 3, '2026-09-04 08:00:00', '2026-10-04 08:00:00', 'Activa',     18),
(20, 20, 2, '2026-09-25 08:00:00', '2026-10-25 08:00:00', 'Activa',      1),
(21, 21, 4, '2026-08-15 08:00:00', '2026-09-14 08:00:00', 'Vencida',     7),
(22, 22, 2, '2026-09-10 08:00:00', '2026-10-10 08:00:00', 'Suspendida',  2),
(23, 23, 2, '2026-09-14 08:00:00', '2026-10-14 08:00:00', 'Activa',      1),
(24, 24, 1, '2026-09-28 08:00:00', '2026-09-29 08:00:00', 'Vencida',    34),
(25, 25, 1, '2026-09-30 08:00:00', '2026-10-01 08:00:00', 'Activa',     27),
(26, 26, 2, '2026-09-06 08:00:00', '2026-10-06 08:00:00', 'Activa',      8),
(27, 27, 1, '2026-09-30 08:00:00', '2026-10-01 08:00:00', 'Activa',      3),
(28, 28, 2, '2026-09-28 08:00:00', '2026-10-28 08:00:00', 'Activa',      0),
(29, 30, 1, '2026-09-27 08:00:00', '2026-09-28 08:00:00', 'Vencida',    11),
(30, 1,  3, '2026-08-06 08:00:00', '2026-09-05 08:00:00', 'Vencida',    10),
(31, 3,  4, '2026-08-03 08:00:00', '2026-09-02 08:00:00', 'Vencida',     7),
(32, 19, 3, '2026-08-04 08:00:00', '2026-09-03 08:00:00', 'Vencida',    17);


-- =====================================================================
-- TABLA: reservas
-- Casos: hoy (1-4, 32), fin de semana (11-14, 26, 27, 36-38), horario pico
-- (1, 2, 5, 6, 9, 10...), > 8 horas (4, 13, 15, 22, 24, 26, 35), eventos
-- últimos 6 meses (21-26), exceso de capacidad (16-20: 5 reservas
-- simultáneas en la Oficina Privada 101, capacidad máxima 4).
-- =====================================================================
INSERT INTO reservas (id_reserva, id_usuario, id_espacio, fecha_inicio, fecha_fin, estado, asistio, fecha_creacion) VALUES
(1,  1,  7,  '2026-09-30 09:00:00', '2026-09-30 11:00:00', 'Confirmada',               FALSE, '2026-09-28 10:00:00'),
(2,  2,  8,  '2026-09-30 10:00:00', '2026-09-30 11:30:00', 'Confirmada',               FALSE, '2026-09-27 15:30:00'),
(3,  4,  9,  '2026-09-30 14:00:00', '2026-09-30 16:00:00', 'Pendiente de Confirmación', FALSE, '2026-09-30 08:15:00'),
(4,  12, 1,  '2026-09-30 08:00:00', '2026-09-30 17:00:00', 'Confirmada',               FALSE, '2026-09-29 18:00:00'),
(5,  10, 7,  '2026-09-29 09:00:00', '2026-09-29 11:00:00', 'Confirmada',               TRUE,  '2026-09-26 09:30:00'),
(6,  5,  7,  '2026-09-28 09:30:00', '2026-09-28 10:30:00', 'Confirmada',               TRUE,  '2026-09-25 11:00:00'),
(7,  13, 8,  '2026-09-28 09:00:00', '2026-09-28 10:00:00', 'Cancelada',                FALSE, '2026-09-24 16:20:00'),
(8,  17, 9,  '2026-09-25 10:00:00', '2026-09-25 11:00:00', 'No Show',                  FALSE, '2026-09-23 12:00:00'),
(9,  19, 8,  '2026-09-24 09:00:00', '2026-09-24 11:00:00', 'Confirmada',               TRUE,  '2026-09-21 10:10:00'),
(10, 20, 7,  '2026-09-23 10:00:00', '2026-09-23 12:00:00', 'Confirmada',               TRUE,  '2026-09-22 09:00:00'),
(11, 30, 1,  '2026-09-26 09:00:00', '2026-09-26 18:00:00', 'Confirmada',               TRUE,  '2026-09-24 20:00:00'),
(12, 30, 3,  '2026-09-27 10:00:00', '2026-09-27 16:00:00', 'Confirmada',               TRUE,  '2026-09-25 19:30:00'),
(13, 24, 2,  '2026-09-19 08:00:00', '2026-09-19 17:30:00', 'Confirmada',               TRUE,  '2026-09-16 21:00:00'),
(14, 25, 1,  '2026-09-20 09:00:00', '2026-09-20 13:00:00', 'Confirmada',               TRUE,  '2026-09-18 18:45:00'),
(15, 22, 5,  '2026-09-22 08:00:00', '2026-09-22 18:00:00', 'Confirmada',               TRUE,  '2026-09-19 09:40:00'),
(16, 3,  4,  '2026-09-15 10:00:00', '2026-09-15 12:00:00', 'Confirmada',               TRUE,  '2026-09-11 10:00:00'),
(17, 6,  4,  '2026-09-15 10:00:00', '2026-09-15 12:00:00', 'Confirmada',               TRUE,  '2026-09-11 10:05:00'),
(18, 7,  4,  '2026-09-15 10:00:00', '2026-09-15 12:00:00', 'Confirmada',               TRUE,  '2026-09-11 10:10:00'),
(19, 8,  4,  '2026-09-15 10:00:00', '2026-09-15 12:00:00', 'Pendiente de Confirmación', FALSE, '2026-09-11 10:15:00'),
(20, 9,  4,  '2026-09-15 10:00:00', '2026-09-15 12:00:00', 'Confirmada',               FALSE, '2026-09-11 10:20:00'),
(21, 19, 10, '2026-04-18 18:00:00', '2026-04-18 23:00:00', 'Confirmada',               TRUE,  '2026-03-20 11:00:00'),
(22, 1,  10, '2026-05-23 09:00:00', '2026-05-23 18:00:00', 'Confirmada',               TRUE,  '2026-04-25 09:30:00'),
(23, 14, 11, '2026-06-20 17:00:00', '2026-06-20 23:00:00', 'Confirmada',               TRUE,  '2026-05-22 14:15:00'),
(24, 21, 10, '2026-07-25 08:00:00', '2026-07-25 20:00:00', 'Confirmada',               TRUE,  '2026-06-26 10:45:00'),
(25, 12, 11, '2026-08-22 18:00:00', '2026-08-22 23:00:00', 'Cancelada',                FALSE, '2026-07-24 16:00:00'),
(26, 2,  10, '2026-09-19 10:00:00', '2026-09-19 19:00:00', 'Confirmada',               TRUE,  '2026-08-20 09:00:00'),
(27, 26, 11, '2026-10-03 16:00:00', '2026-10-03 22:00:00', 'Pendiente de Confirmación', FALSE, '2026-09-29 11:30:00'),
(28, 23, 10, '2026-10-10 09:00:00', '2026-10-10 13:00:00', 'Pendiente de Confirmación', FALSE, '2026-09-30 09:00:00'),
(29, 16, 8,  '2026-09-10 11:00:00', '2026-09-10 12:00:00', 'No Show',                  FALSE, '2026-09-08 15:00:00'),
(30, 18, 9,  '2026-09-18 09:00:00', '2026-09-18 10:30:00', 'Cancelada',                FALSE, '2026-09-17 17:10:00'),
(31, 11, 7,  '2026-09-17 10:00:00', '2026-09-17 11:00:00', 'Confirmada',               TRUE,  '2026-09-14 10:00:00'),
(32, 15, 3,  '2026-09-30 09:00:00', '2026-09-30 12:00:00', 'Confirmada',               FALSE, '2026-09-30 07:50:00'),
(33, 27, 2,  '2026-10-01 09:00:00', '2026-10-01 18:00:00', 'Pendiente de Confirmación', FALSE, '2026-09-30 10:00:00'),
(34, 4,  8,  '2026-10-02 09:00:00', '2026-10-02 11:00:00', 'Confirmada',               FALSE, '2026-09-29 16:40:00'),
(35, 7,  5,  '2026-09-14 08:00:00', '2026-09-14 17:00:00', 'Confirmada',               TRUE,  '2026-09-10 09:00:00'),
(36, 26, 1,  '2026-09-12 09:00:00', '2026-09-12 14:00:00', 'Confirmada',               TRUE,  '2026-09-09 13:00:00'),
(37, 26, 1,  '2026-09-13 09:00:00', '2026-09-13 14:00:00', 'Confirmada',               TRUE,  '2026-09-09 13:05:00'),
(38, 24, 3,  '2026-09-06 10:00:00', '2026-09-06 15:00:00', 'Confirmada',               TRUE,  '2026-09-03 19:00:00'),
(39, 20, 9,  '2026-09-16 09:00:00', '2026-09-16 10:00:00', 'No Show',                  FALSE, '2026-09-15 12:00:00'),
(40, 10, 7,  '2026-09-09 09:00:00', '2026-09-09 11:00:00', 'Confirmada',               TRUE,  '2026-09-07 08:30:00'),
(41, 5,  8,  '2026-09-08 10:00:00', '2026-09-08 11:00:00', 'Cancelada',                FALSE, '2026-09-04 11:30:00'),
(42, 2,  8,  '2026-08-14 09:00:00', '2026-08-14 11:00:00', 'Confirmada',               TRUE,  '2026-08-11 10:00:00'),
(43, 21, 6,  '2026-09-21 09:00:00', '2026-09-21 17:00:00', 'Cancelada',                FALSE, '2026-09-18 16:00:00');



-- =====================================================================
-- TABLA: reserva_servicios
-- =====================================================================
INSERT INTO reserva_servicios (id_reserva, id_servicio, cantidad) VALUES
(1,  5, 1),
(1,  3, 8),
(2,  5, 1),
(2,  4, 30),
(4,  2, 1),
(4,  1, 1),
(5,  5, 1),
(9,  5, 1),
(9,  4, 6),
(10, 4, 20),
(11, 1, 1),
(13, 3, 1),
(15, 1, 1),
(15, 2, 1),
(15, 3, 1),
(21, 5, 1),
(21, 3, 6),
(22, 5, 2),
(22, 3, 7),
(23, 5, 1),
(23, 3, 6),
(24, 5, 1),
(24, 3, 8),
(26, 5, 2),
(26, 3, 7),
(31, 5, 1),
(34, 5, 1),
(35, 3, 1);

-- =====================================================================
-- TABLA: consumos_servicios
-- =====================================================================
INSERT INTO consumos_servicios (id_usuario, id_servicio, cantidad, fecha_consumo) VALUES
(1,  1, 1,   '2026-09-30 08:15:00'),
(1,  3, 1,   '2026-09-30 08:20:00'),
(1,  4, 120, '2026-08-14 16:00:00'),
(2,  3, 1,   '2026-09-29 09:10:00'),
(2,  4, 25,  '2026-09-28 11:00:00'),
(2,  1, 1,   '2026-08-12 09:05:00'),
(3,  2, 1,   '2026-09-29 08:10:00'),
(4,  1, 1,   '2026-09-28 09:05:00'),
(5,  3, 2,   '2026-09-28 10:00:00'),
(7,  4, 40,  '2026-09-22 10:30:00'),
(8,  3, 1,   '2026-09-29 09:00:00'),
(9,  1, 1,   '2026-09-30 08:30:00'),
(10, 4, 10,  '2026-09-29 10:00:00'),
(11, 4, 3,   '2026-09-17 10:15:00'),
(12, 3, 1,   '2026-09-30 08:10:00'),
(14, 5, 1,   '2026-09-25 10:00:00'),
(17, 4, 5,   '2026-09-22 11:00:00'),
(19, 4, 15,  '2026-09-24 09:30:00'),
(19, 3, 1,   '2026-09-18 09:20:00'),
(20, 1, 1,   '2026-09-23 10:00:00'),
(22, 3, 1,   '2026-09-22 08:30:00'),
(22, 2, 1,   '2026-09-22 08:35:00'),
(24, 3, 1,   '2026-09-19 08:30:00'),
(25, 3, 1,   '2026-09-20 09:20:00'),
(26, 3, 1,   '2026-09-13 09:15:00'),
(30, 3, 1,   '2026-09-27 10:15:00'),
(30, 2, 1,   '2026-09-26 09:10:00');

-- =====================================================================
-- TABLA: facturas
-- (1-21 y 38-48: membresías; 22-37: reservas.
--  Incluye montos > 1000, saldos pendientes > 200 y pagos parciales.)
-- =====================================================================
INSERT INTO facturas (id_factura, id_usuario, id_membresia, id_reserva, monto_total, saldo_pendiente, estado, motivo_anulacion, fecha_emision, fecha_vencimiento) VALUES
(1,  1,  1,    NULL, 1200.00,    0.00, 'Pagada',    NULL, '2026-09-06 08:30:00', '2026-09-21 23:59:59'),
(2,  2,  2,    NULL, 1200.00,    0.00, 'Pagada',    NULL, '2026-09-10 08:30:00', '2026-09-25 23:59:59'),
(3,  3,  3,    NULL,  650.00,  650.00, 'Vencida',   NULL, '2026-09-03 08:30:00', '2026-09-18 23:59:59'),
(4,  4,  4,    NULL,  650.00,  350.00, 'Pendiente', NULL, '2026-09-15 08:30:00', '2026-10-15 23:59:59'),
(5,  5,  5,    NULL,  350.00,    0.00, 'Pagada',    NULL, '2026-09-01 08:30:00', '2026-09-16 23:59:59'),
(6,  6,  6,    NULL,  350.00,  350.00, 'Vencida',   NULL, '2026-08-01 08:30:00', '2026-08-16 23:59:59'),
(7,  7,  7,    NULL, 1200.00, 1200.00, 'Pendiente', NULL, '2026-09-20 08:30:00', '2026-10-20 23:59:59'),
(8,  8,  8,    NULL,  350.00,    0.00, 'Pagada',    NULL, '2026-09-05 08:30:00', '2026-09-20 23:59:59'),
(9,  9,  9,    NULL,   25.00,    0.00, 'Pagada',    NULL, '2026-09-30 08:05:00', '2026-10-01 23:59:59'),
(10, 12, 12,   NULL,  650.00,    0.00, 'Pagada',    NULL, '2026-09-08 08:30:00', '2026-09-23 23:59:59'),
(11, 13, 13,   NULL,  350.00,    0.00, 'Anulada',   'Anulada por suspensión de la membresía', '2026-08-20 08:30:00', '2026-09-04 23:59:59'),
(12, 14, 14,   NULL, 1200.00,    0.00, 'Pagada',    NULL, '2026-09-02 08:30:00', '2026-09-17 23:59:59'),
(13, 17, 17,   NULL,  650.00,  650.00, 'Pendiente', NULL, '2026-09-18 08:30:00', '2026-10-18 23:59:59'),
(14, 19, 19,   NULL, 1200.00,  600.00, 'Pendiente', NULL, '2026-09-04 08:30:00', '2026-10-04 23:59:59'),
(15, 20, 20,   NULL,  350.00,    0.00, 'Pagada',    NULL, '2026-09-25 08:30:00', '2026-10-10 23:59:59'),
(16, 21, 21,   NULL,  650.00,  650.00, 'Vencida',   NULL, '2026-08-15 08:30:00', '2026-08-30 23:59:59'),
(17, 24, 24,   NULL,   25.00,    0.00, 'Pagada',    NULL, '2026-09-28 08:05:00', '2026-09-29 23:59:59'),
(18, 25, 25,   NULL,   25.00,    0.00, 'Pagada',    NULL, '2026-09-30 08:05:00', '2026-10-01 23:59:59'),
(19, 26, 26,   NULL,  350.00,    0.00, 'Pagada',    NULL, '2026-09-06 08:30:00', '2026-09-21 23:59:59'),
(20, 16, 16,   NULL,  350.00,    0.00, 'Pagada',    NULL, '2026-07-01 08:30:00', '2026-07-16 23:59:59'),
(21, 23, 23,   NULL,  350.00,  350.00, 'Pendiente', NULL, '2026-09-14 08:30:00', '2026-10-14 23:59:59'),
(22, 19, NULL, 21,  1800.00,    0.00, 'Pagada',    NULL, '2026-04-18 23:30:00', '2026-05-03 23:59:59'),
(23, 1,  NULL, 22,  2400.00,    0.00, 'Pagada',    NULL, '2026-05-23 18:30:00', '2026-06-07 23:59:59'),
(24, 14, NULL, 23,  1650.00,    0.00, 'Pagada',    NULL, '2026-06-20 23:30:00', '2026-07-05 23:59:59'),
(25, 21, NULL, 24,  2800.00, 1400.00, 'Vencida',   NULL, '2026-07-25 20:30:00', '2026-08-09 23:59:59'),
(26, 12, NULL, 25,  1500.00,    0.00, 'Anulada',   'Reserva cancelada por el cliente', '2026-07-24 16:10:00', '2026-08-08 23:59:59'),
(27, 2,  NULL, 26,  2700.00, 2700.00, 'Pendiente', NULL, '2026-09-19 19:30:00', '2026-10-19 23:59:59'),
(28, 30, NULL, 11,    90.00,    0.00, 'Pagada',    NULL, '2026-09-26 18:15:00', '2026-10-11 23:59:59'),
(29, 30, NULL, 12,    75.00,    0.00, 'Pagada',    NULL, '2026-09-27 16:15:00', '2026-10-12 23:59:59'),
(30, 22, NULL, 15,   180.00,    0.00, 'Pagada',    NULL, '2026-09-22 18:15:00', '2026-10-07 23:59:59'),
(31, 24, NULL, 13,    95.00,   95.00, 'Vencida',   NULL, '2026-09-19 17:45:00', '2026-09-26 23:59:59'),
(32, 10, NULL, 5,     60.00,    0.00, 'Pagada',    NULL, '2026-09-29 11:15:00', '2026-10-14 23:59:59'),
(33, 19, NULL, 9,    120.00,  120.00, 'Pendiente', NULL, '2026-09-24 11:15:00', '2026-10-09 23:59:59'),
(34, 3,  NULL, 16,    80.00,    0.00, 'Pagada',    NULL, '2026-09-15 12:15:00', '2026-09-30 23:59:59'),
(35, 17, NULL, 8,     45.00,   45.00, 'Pendiente', NULL, '2026-09-25 11:15:00', '2026-10-10 23:59:59'),
(36, 26, NULL, 36,    50.00,    0.00, 'Pagada',    NULL, '2026-09-12 14:15:00', '2026-09-27 23:59:59'),
(37, 2,  NULL, 42,   140.00,    0.00, 'Pagada',    NULL, '2026-08-14 11:15:00', '2026-08-29 23:59:59'),
(38, 28, 28,   NULL,  350.00,  350.00, 'Pendiente', NULL, '2026-09-28 08:30:00', '2026-10-13 23:59:59'),
(39, 27, 27,   NULL,   25.00,    0.00, 'Pagada',    NULL, '2026-09-30 08:05:00', '2026-10-01 23:59:59'),
(40, 30, 29,   NULL,   25.00,    0.00, 'Pagada',    NULL, '2026-09-27 08:05:00', '2026-09-28 23:59:59'),
(41, 1,  30,   NULL, 1200.00,    0.00, 'Pagada',    NULL, '2026-08-06 08:30:00', '2026-08-21 23:59:59'),
(42, 3,  31,   NULL,  650.00,    0.00, 'Pagada',    NULL, '2026-08-03 08:30:00', '2026-08-18 23:59:59'),
(43, 19, 32,   NULL, 1200.00,    0.00, 'Pagada',    NULL, '2026-08-04 08:30:00', '2026-08-19 23:59:59'),
(44, 15, 15,   NULL,   25.00,    0.00, 'Pagada',    NULL, '2026-09-30 08:05:00', '2026-10-01 23:59:59'),
(45, 11, 11,   NULL,  350.00,    0.00, 'Pagada',    NULL, '2026-09-12 09:40:00', '2026-09-27 23:59:59'),
(46, 10, 10,   NULL,  350.00,    0.00, 'Pagada',    NULL, '2026-09-12 08:30:00', '2026-09-27 23:59:59'),
(47, 22, 22,   NULL,  350.00,  350.00, 'Pendiente', NULL, '2026-09-10 08:30:00', '2026-10-10 23:59:59'),
(48, 18, 18,   NULL,   25.00,    0.00, 'Pagada',    NULL, '2026-09-29 08:05:00', '2026-09-30 23:59:59');

-- =====================================================================
-- TABLA: detalle_facturas
-- (subtotal es columna generada; no se inserta)
-- =====================================================================
INSERT INTO detalle_facturas (id_factura, id_servicio, descripcion, cantidad, precio_unitario) VALUES
(1,  NULL, 'Membresía Corporativa - septiembre 2026', 1, 1200.00),
(2,  NULL, 'Membresía Corporativa - septiembre 2026', 1, 1200.00),
(3,  NULL, 'Membresía Premium - septiembre 2026',      1,  650.00),
(4,  NULL, 'Membresía Premium - septiembre 2026',      1,  650.00),
(5,  NULL, 'Membresía Mensual - septiembre 2026',      1,  350.00),
(6,  NULL, 'Membresía Mensual - agosto 2026',          1,  350.00),
(7,  NULL, 'Membresía Corporativa - septiembre 2026', 1, 1200.00),
(8,  NULL, 'Membresía Mensual - septiembre 2026',      1,  350.00),
(9,  NULL, 'Membresía Diaria',                         1,   25.00),
(10, NULL, 'Membresía Premium - septiembre 2026',      1,  650.00),
(11, NULL, 'Membresía Mensual - agosto 2026',          1,  350.00),
(12, NULL, 'Membresía Corporativa - septiembre 2026', 1, 1200.00),
(13, NULL, 'Membresía Premium - septiembre 2026',      1,  650.00),
(14, NULL, 'Membresía Corporativa - septiembre 2026', 1, 1200.00),
(15, NULL, 'Membresía Mensual - septiembre 2026',      1,  350.00),
(16, NULL, 'Membresía Premium - agosto 2026',          1,  650.00),
(17, NULL, 'Membresía Diaria',                         1,   25.00),
(18, NULL, 'Membresía Diaria',                         1,   25.00),
(19, NULL, 'Membresía Mensual - septiembre 2026',      1,  350.00),
(20, NULL, 'Membresía Mensual - julio 2026',           1,  350.00),
(21, NULL, 'Membresía Mensual - septiembre 2026',      1,  350.00),
(22, NULL, 'Alquiler Auditorio Principal (5 horas)',   1, 1650.00),
(22, 5,    'Uso de proyector',                         1,   30.00),
(22, 3,    'Café ilimitado',                           6,   20.00),
(23, NULL, 'Alquiler Auditorio Principal (9 horas)',   1, 2200.00),
(23, 5,    'Uso de proyector',                         2,   30.00),
(23, 3,    'Café ilimitado',                           7,   20.00),
(24, NULL, 'Alquiler Terraza de Eventos (6 horas)',    1, 1500.00),
(24, 5,    'Uso de proyector',                         1,   30.00),
(24, 3,    'Café ilimitado',                           6,   20.00),
(25, NULL, 'Alquiler Auditorio Principal (12 horas)',  1, 2610.00),
(25, 5,    'Uso de proyector',                         1,   30.00),
(25, 3,    'Café ilimitado',                           8,   20.00),
(26, NULL, 'Alquiler Terraza de Eventos (5 horas)',    1, 1500.00),
(27, NULL, 'Alquiler Auditorio Principal (9 horas)',   1, 2500.00),
(27, 5,    'Uso de proyector',                         2,   30.00),
(27, 3,    'Café ilimitado',                           7,   20.00),
(28, NULL, 'Reserva Escritorio Flex A (9 horas)',      1,   75.00),
(28, 1,    'Internet premium',                         1,   15.00),
(29, NULL, 'Reserva Escritorio Flex Silencioso (6 horas)', 1, 75.00),
(30, NULL, 'Reserva Oficina Privada 102 (10 horas)',   1,  135.00),
(30, 1,    'Internet premium',                         1,   15.00),
(30, 2,    'Lockers',                                  1,   10.00),
(30, 3,    'Café ilimitado',                           1,   20.00),
(31, NULL, 'Reserva Escritorio Flex B (9.5 horas)',    1,   95.00),
(32, NULL, 'Reserva Sala Reuniones Andes (2 horas)',   1,   30.00),
(32, 5,    'Uso de proyector',                         1,   30.00),
(33, NULL, 'Reserva Sala Reuniones Caribe (2 horas)',  1,   60.00),
(33, 5,    'Uso de proyector',                         1,   30.00),
(33, 4,    'Impresiones',                              6,    5.00),
(34, NULL, 'Reserva Oficina Privada 101 (2 horas)',    1,   80.00),
(35, NULL, 'Reserva Sala Reuniones Pacífico (1 hora)', 1,   45.00),
(36, NULL, 'Reserva Escritorio Flex A (5 horas)',      1,   50.00),
(37, NULL, 'Reserva Sala Reuniones Caribe (2 horas)',  1,  110.00),
(37, 5,    'Uso de proyector',                         1,   30.00),
(38, NULL, 'Membresía Mensual - septiembre 2026',      1,  350.00),
(39, NULL, 'Membresía Diaria',                         1,   25.00),
(40, NULL, 'Membresía Diaria',                         1,   25.00),
(41, NULL, 'Membresía Corporativa - agosto 2026',      1, 1200.00),
(42, NULL, 'Membresía Premium - agosto 2026',          1,  650.00),
(43, NULL, 'Membresía Corporativa - agosto 2026',      1, 1200.00),
(44, NULL, 'Membresía Diaria',                         1,   25.00),
(45, NULL, 'Membresía Mensual - septiembre 2026',      1,  350.00),
(46, NULL, 'Membresía Mensual - septiembre 2026',      1,  350.00),
(47, NULL, 'Membresía Mensual - septiembre 2026',      1,  350.00),
(48, NULL, 'Membresía Diaria',                         1,   25.00);

-- =====================================================================
-- TABLA: pagos
-- (Pagos parciales: facturas 4, 14 y 25. PayPal solo lo usan los
--  usuarios 12, 14, 26 y 2; el resto nunca ha pagado con PayPal.)
-- =====================================================================
INSERT INTO pagos (id_factura, metodo_pago, monto, estado_transaccion, fecha_pago) VALUES
(1,  'Tarjeta',       1200.00, 'Pagado',    '2026-09-06 09:10:00'),
(2,  'Transferencia', 1200.00, 'Pagado',    '2026-09-11 10:00:00'),
(3,  'Tarjeta',        650.00, 'Cancelado', '2026-09-05 12:00:00'),
(4,  'Efectivo',       300.00, 'Pagado',    '2026-09-15 09:30:00'),
(5,  'Efectivo',       350.00, 'Pagado',    '2026-09-01 09:00:00'),
(6,  'Tarjeta',        350.00, 'Cancelado', '2026-08-10 14:20:00'),
(7,  'Transferencia', 1200.00, 'Pendiente', '2026-09-29 16:00:00'),
(8,  'Tarjeta',        350.00, 'Pagado',    '2026-09-05 09:15:00'),
(9,  'Efectivo',        25.00, 'Pagado',    '2026-09-30 08:10:00'),
(10, 'PayPal',         650.00, 'Pagado',    '2026-09-08 09:40:00'),
(12, 'PayPal',        1200.00, 'Pagado',    '2026-09-03 10:20:00'),
(14, 'Transferencia',  600.00, 'Pagado',    '2026-09-05 11:00:00'),
(15, 'Tarjeta',        350.00, 'Pagado',    '2026-09-25 09:00:00'),
(17, 'Efectivo',        25.00, 'Pagado',    '2026-09-28 08:10:00'),
(18, 'Efectivo',        25.00, 'Pagado',    '2026-09-30 08:10:00'),
(19, 'PayPal',         350.00, 'Pagado',    '2026-09-06 10:00:00'),
(20, 'Transferencia',  350.00, 'Pagado',    '2026-07-02 09:30:00'),
(22, 'Transferencia', 1800.00, 'Pagado',    '2026-04-20 10:00:00'),
(23, 'Transferencia', 2400.00, 'Pagado',    '2026-05-25 11:00:00'),
(24, 'PayPal',        1650.00, 'Pagado',    '2026-06-22 15:30:00'),
(25, 'Tarjeta',       1400.00, 'Pagado',    '2026-07-28 12:00:00'),
(28, 'Efectivo',        90.00, 'Pagado',    '2026-09-26 18:20:00'),
(29, 'Efectivo',        75.00, 'Pagado',    '2026-09-27 16:20:00'),
(30, 'Tarjeta',        180.00, 'Pagado',    '2026-09-22 18:30:00'),
(32, 'Efectivo',        60.00, 'Pagado',    '2026-09-29 11:30:00'),
(34, 'Tarjeta',         80.00, 'Pagado',    '2026-09-15 12:30:00'),
(36, 'PayPal',          50.00, 'Pagado',    '2026-09-12 14:30:00'),
(37, 'PayPal',         140.00, 'Pagado',    '2026-08-14 11:30:00'),
(39, 'Efectivo',        25.00, 'Pagado',    '2026-09-30 08:10:00'),
(40, 'Efectivo',        25.00, 'Pagado',    '2026-09-27 08:10:00'),
(41, 'Tarjeta',       1200.00, 'Pagado',    '2026-08-06 09:30:00'),
(42, 'Transferencia',  650.00, 'Pagado',    '2026-08-04 10:00:00'),
(43, 'Transferencia', 1200.00, 'Pagado',    '2026-08-05 10:00:00'),
(44, 'Efectivo',        25.00, 'Pagado',    '2026-09-30 08:10:00'),
(45, 'Tarjeta',        350.00, 'Pagado',    '2026-09-12 09:50:00'),
(46, 'Transferencia',  350.00, 'Pagado',    '2026-09-12 09:00:00'),
(48, 'Efectivo',        25.00, 'Pagado',    '2026-09-29 08:10:00');

