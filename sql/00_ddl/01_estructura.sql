/*
Proyecto: Gestión de Coworking y Oficinas Compartidas
Módulo: DDL - Estructura Completa de la Base de Datos
Archivo: 01_estructura.sql

Descripción:
Esquema optimizado para soportar la totalidad de requerimientos de negocio, 
consultas analíticas, auditoría por triggers y tareas automatizadas por eventos.
*/

DROP DATABASE IF EXISTS coworking_db;
CREATE DATABASE coworking_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE coworking_db;

-- =========================================
-- 1. TABLAS MAESTRAS Y CATÁLOGOS
-- =========================================

CREATE TABLE empresas (
    id_empresa INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    nit_ruc VARCHAR(30) NOT NULL UNIQUE,
    telefono VARCHAR(25),
    direccion VARCHAR(150),
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tipos_membresia (
    id_tipo_membresia INT AUTO_INCREMENT PRIMARY KEY,
    nombre ENUM('Diaria', 'Mensual', 'Corporativa', 'Premium') NOT NULL UNIQUE,
    descripcion TEXT,
    precio DECIMAL(10,2) NOT NULL,
    duracion_dias INT NOT NULL
);

CREATE TABLE tipos_espacio (
    id_tipo_espacio INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE, -- Escritorios flexibles, Oficinas privadas, Salas de reuniones, Salas de eventos
    descripcion TEXT
);

CREATE TABLE servicios_adicionales (
    id_servicio INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(60) NOT NULL UNIQUE, -- Internet premium, Lockers, Café ilimitado, Impresiones, Uso de proyector
    costo DECIMAL(10,2) NOT NULL,
    bloqueado BOOLEAN DEFAULT FALSE
);

-- =========================================
-- 2. ENTIDADES PRINCIPALES
-- =========================================

CREATE TABLE usuarios (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    id_empresa INT NULL,
    identificacion VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(50) NOT NULL,
    apellidos VARCHAR(50) NOT NULL,
    fecha_nacimiento DATE NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    telefono VARCHAR(25),
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_usuarios_empresas FOREIGN KEY (id_empresa) 
        REFERENCES empresas(id_empresa) ON DELETE SET NULL
);

CREATE TABLE espacios (
    id_espacio INT AUTO_INCREMENT PRIMARY KEY,
    id_tipo_espacio INT NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    capacidad_maxima INT NOT NULL,
    hora_apertura TIME DEFAULT '06:00:00',
    hora_cierre TIME DEFAULT '22:00:00',
    estado ENUM('Disponible', 'Mantenimiento', 'Inactivo') DEFAULT 'Disponible',
    CONSTRAINT fk_espacios_tipos FOREIGN KEY (id_tipo_espacio) 
        REFERENCES tipos_espacio(id_tipo_espacio)
);

CREATE TABLE membresias (
    id_membresia INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_tipo_membresia INT NOT NULL,
    fecha_inicio DATETIME NOT NULL,
    fecha_vencimiento DATETIME NOT NULL,
    estado ENUM('Activa', 'Suspendida', 'Vencida') DEFAULT 'Activa',
    renovaciones INT DEFAULT 0,
    CONSTRAINT fk_membresias_usuarios FOREIGN KEY (id_usuario) 
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    CONSTRAINT fk_membresias_tipos FOREIGN KEY (id_tipo_membresia) 
        REFERENCES tipos_membresia(id_tipo_membresia)
);

CREATE TABLE reservas (
    id_reserva INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_espacio INT NOT NULL,
    fecha_inicio DATETIME NOT NULL,
    fecha_fin DATETIME NOT NULL,
    estado ENUM('Pendiente de Confirmación', 'Confirmada', 'Cancelada', 'No Show') DEFAULT 'Pendiente de Confirmación',
    asistio BOOLEAN DEFAULT FALSE,
    fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reservas_usuarios FOREIGN KEY (id_usuario) 
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    CONSTRAINT fk_reservas_espacios FOREIGN KEY (id_espacio) 
        REFERENCES espacios(id_espacio)
);

CREATE TABLE reserva_servicios (
    id_reserva_servicio INT AUTO_INCREMENT PRIMARY KEY,
    id_reserva INT NOT NULL,
    id_servicio INT NOT NULL,
    cantidad INT DEFAULT 1,
    CONSTRAINT fk_rs_reserva FOREIGN KEY (id_reserva) 
        REFERENCES reservas(id_reserva) ON DELETE CASCADE,
    CONSTRAINT fk_rs_servicio FOREIGN KEY (id_servicio) 
        REFERENCES servicios_adicionales(id_servicio)
);

CREATE TABLE consumos_servicios (
    id_consumo INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_servicio INT NOT NULL,
    cantidad INT DEFAULT 1,
    fecha_consumo DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_consumos_usuarios FOREIGN KEY (id_usuario) 
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    CONSTRAINT fk_consumos_servicios FOREIGN KEY (id_servicio) 
        REFERENCES servicios_adicionales(id_servicio)
);

-- =========================================
-- 3. FACTURACIÓN Y PAGOS
-- =========================================

CREATE TABLE facturas (
    id_factura INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_membresia INT NULL,
    id_reserva INT NULL,
    monto_total DECIMAL(10,2) NOT NULL,
    saldo_pendiente DECIMAL(10,2) NOT NULL,
    estado ENUM('Pendiente', 'Pagada', 'Anulada', 'Vencida') DEFAULT 'Pendiente',
    motivo_anulacion VARCHAR(255) NULL,
    fecha_emision DATETIME DEFAULT CURRENT_TIMESTAMP,
    fecha_vencimiento DATETIME NOT NULL,
    CONSTRAINT fk_facturas_usuarios FOREIGN KEY (id_usuario) 
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    CONSTRAINT fk_facturas_membresias FOREIGN KEY (id_membresia) 
        REFERENCES membresias(id_membresia) ON DELETE SET NULL,
    CONSTRAINT fk_facturas_reservas FOREIGN KEY (id_reserva) 
        REFERENCES reservas(id_reserva) ON DELETE SET NULL
);

CREATE TABLE detalle_facturas (
    id_detalle INT AUTO_INCREMENT PRIMARY KEY,
    id_factura INT NOT NULL,
    id_servicio INT NULL,
    descripcion VARCHAR(150) NOT NULL,
    cantidad INT DEFAULT 1,
    precio_unitario DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    CONSTRAINT fk_detalle_factura FOREIGN KEY (id_factura) 
        REFERENCES facturas(id_factura) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_servicio FOREIGN KEY (id_servicio) 
        REFERENCES servicios_adicionales(id_servicio) ON DELETE SET NULL
);

CREATE TABLE pagos (
    id_pago INT AUTO_INCREMENT PRIMARY KEY,
    id_factura INT NOT NULL,
    metodo_pago ENUM('Efectivo', 'Tarjeta', 'Transferencia', 'PayPal') NOT NULL,
    monto DECIMAL(10,2) NOT NULL,
    estado_transaccion ENUM('Pagado', 'Pendiente', 'Cancelado') DEFAULT 'Pendiente',
    fecha_pago DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pagos_facturas FOREIGN KEY (id_factura) 
        REFERENCES facturas(id_factura) ON DELETE CASCADE
);

-- =========================================
-- 4. CONTROL DE ACCESO
-- =========================================

CREATE TABLE registros_acceso (
    id_acceso INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    fecha_hora_entrada DATETIME NOT NULL,
    fecha_hora_salida DATETIME NULL,
    metodo_acceso ENUM('QR', 'RFID') NOT NULL,
    estado_validacion ENUM('Exitoso', 'Rechazado') NOT NULL,
    motivo_rechazo VARCHAR(150) NULL,
    CONSTRAINT fk_accesos_usuarios FOREIGN KEY (id_usuario) 
        REFERENCES usuarios(id_usuario) ON DELETE CASCADE
);

-- =========================================
-- 5. TABLAS DE AUDITORÍA Y LOGS (TRIGGERS)
-- =========================================

CREATE TABLE log_cambios_membresia (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_tipo_anterior INT NOT NULL,
    id_tipo_nuevo INT NOT NULL,
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_log_mem_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
);

CREATE TABLE log_reservas_canceladas (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_reserva INT NOT NULL,
    id_usuario INT NOT NULL,
    motivo VARCHAR(255),
    fecha_cancelacion DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE log_pagos_anulados (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_pago INT NOT NULL,
    id_factura INT NOT NULL,
    monto DECIMAL(10,2) NOT NULL,
    fecha_anulacion DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE log_accesos_rechazados (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NULL,
    metodo_acceso VARCHAR(20),
    motivo VARCHAR(150),
    fecha_intento DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 6. ÍNDICES SECUNDARIOS
-- =========================================

CREATE INDEX idx_membresia_estado ON membresias (estado, fecha_vencimiento);
CREATE INDEX idx_reservas_fechas ON reservas (id_espacio, fecha_inicio, fecha_fin, estado);
CREATE INDEX idx_accesos_usuario ON registros_acceso (id_usuario, fecha_hora_entrada);
CREATE INDEX idx_pagos_factura ON pagos (id_factura, estado_transaccion);
CREATE INDEX idx_facturas_cliente ON facturas (id_usuario, estado);