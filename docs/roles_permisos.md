# Roles, permisos y matriz de accesos

**Proyecto:** ID 1791 · Gestión de Coworking y Oficinas Compartidas
**Base de datos:** `coworking_db` (MySQL 8.0+)
**Scripts fuente:** [`sql/07_seguridad/01_roles.sql`](../sql/07_seguridad/01_roles.sql) · [`02_permisos.sql`](../sql/07_seguridad/02_permisos.sql) · [`03_usuarios.sql`](../sql/07_seguridad/03_usuarios.sql)

---

## Contenido

1. [Modelo de seguridad](#1-modelo-de-seguridad)
2. [Leyenda](#2-leyenda)
3. [Detalle por rol](#3-detalle-por-rol)
4. [Matriz CRUD por entidad](#4-matriz-crud-por-entidad)
5. [Matriz de procedimientos y funciones](#5-matriz-de-procedimientos-y-funciones)
6. [Usuarios de ejemplo](#6-usuarios-de-ejemplo)
7. [Operación y mantenimiento](#7-operación-y-mantenimiento)
8. [Limitaciones y decisiones de diseño](#8-limitaciones-y-decisiones-de-diseño)

---

## 1. Modelo de seguridad

### 1.1 Principios

| Principio | Implementación |
|---|---|
| **Mínimo privilegio** | Cada rol recibe solo lo necesario; ningún rol tiene privilegios globales (`*.*`) ni `WITH GRANT OPTION`. |
| **Escritura por procedimientos** | Los `sp_*` usan `SQL SECURITY DEFINER` (valor por defecto). El rol solo necesita `EXECUTE`; no requiere `INSERT/UPDATE` sobre las tablas que el procedimiento modifica, ni sobre las que tocan los triggers. |
| **Seguridad por fila mediante vistas** | MySQL no tiene *row-level security*. Los roles `rol_usuario` y `rol_gerente_corporativo` acceden solo a vistas que filtran por la cuenta conectada (`USER()`). No tienen privilegios sobre las tablas base. |
| **Privilegios por columna** | Se limitan columnas sensibles o que mantienen los triggers (p. ej. `usuarios.identificacion`, `facturas.saldo_pendiente`). |
| **Seguro por defecto** | Si una cuenta no está en `seg_mapeo_cuentas`, las vistas devuelven 0 filas. |
| **Funciones `fn_*` restringidas** | Reciben un id arbitrario; por eso no se conceden a roles de alcance limitado (cliente y gerente). |

### 1.2 Mecanismo de filtrado por fila

```
Cuenta MySQL (usr_cliente@localhost)
        │  USER() → 'usr_cliente'
        ▼
seg_mapeo_cuentas (nombre_cuenta → id_usuario)
        │
        ▼
v_seg_sesion  →  (id_usuario, id_empresa)
        │
        ├──► v_mi_perfil, v_mis_membresias, v_mis_reservas, v_mis_facturas,
        │    v_mis_detalle_facturas, v_mis_pagos, v_mis_accesos          (rol_usuario)
        └──► v_empresa_empleados, v_empresa_membresias, v_empresa_reservas,
             v_empresa_facturas, v_empresa_facturacion_resumen            (rol_gerente_corporativo)
```

- `seg_mapeo_cuentas` se administra solo con `rol_administrador`.
- El **gerente** ve a los usuarios cuyo `usuarios.id_empresa` coincide con el de su propio registro; por eso el usuario vinculado debe pertenecer a una empresa.

### 1.3 Wrapper anti-suplantación

`sp_crear_reserva` recibe `p_id_usuario`. Concederlo a un cliente permitiría reservar a nombre de otra persona. Por eso `rol_usuario` ejecuta `sp_mi_crear_reserva(p_id_espacio, p_inicio, p_fin)`, que resuelve el usuario desde la sesión y delega en `sp_crear_reserva`.

---

## 2. Leyenda

| Símbolo | Significado |
|:---:|---|
| **C** | Crear (`INSERT`) |
| **R** | Leer (`SELECT`) |
| **U** | Actualizar (`UPDATE`) |
| **D** | Eliminar (`DELETE`) |
| **sp** | La operación se realiza **solo a través de procedimientos** almacenados (sin privilegio directo sobre la tabla) |
| **v** | Acceso mediante **vista filtrada** (solo datos propios o de su empresa) |
| **col** | Privilegio limitado a **columnas** específicas |
| **—** | Sin acceso |

---

## 3. Detalle por rol

### 3.1 `rol_administrador` · Administrador del Coworking

| Aspecto | Detalle |
|---|---|
| Concesión | `GRANT ALL PRIVILEGES ON coworking_db.* TO rol_administrador;` |
| Alcance | Todas las tablas, vistas, funciones, procedimientos, triggers y eventos de `coworking_db`. |
| Incluye exclusivamente | Tablas de eventos (`log_eventos_ejecucion`, `notificaciones_sistema`, `reportes_automaticos`, etc.), `seg_mapeo_cuentas`, `sp_marcar_no_show_penalizar`, `sp_cancelar_reservas_usuario_eliminado`. |
| Restricciones | Sin privilegios globales (no administra otras bases) y sin `WITH GRANT OPTION`. La creación de cuentas y roles la hace el DBA (`root`). |

### 3.2 `rol_recepcionista` · Recepcionista

**Responsabilidad:** atención diaria: alta y actualización de usuarios, membresías, reservas y control de accesos.

| Categoría | Privilegios |
|---|---|
| Usuarios | `SELECT`, `INSERT` sobre `usuarios`; `UPDATE` solo en las columnas `id_empresa`, `nombre`, `apellidos`, `fecha_nacimiento`, `email`, `telefono` (no puede cambiar `identificacion`). Sin `DELETE`. |
| Catálogos | `SELECT` en `empresas`, `tipos_membresia`, `tipos_espacio`, `espacios`, `servicios_adicionales`. |
| Membresías y reservas | `SELECT` en `membresias` y `reservas`. Escritura **solo vía procedimientos**. |
| Servicios | `SELECT`, `INSERT` en `reserva_servicios` y `consumos_servicios`. |
| Accesos | `SELECT` en `registros_acceso` y `log_accesos_rechazados`. Registro solo vía `sp_registrar_acceso_*`. |
| Facturación | `SELECT` en `facturas` (consultar estado de pago). **Sin acceso** a `pagos`, `detalle_facturas` ni ingresos. |
| Procedimientos | `sp_registrar_membresia`, `sp_renovar_membresia`, `sp_actualizar_membresias_vencidas`, `sp_validar_disponibilidad_espacio`, `sp_crear_reserva`, `sp_confirmar_reserva_pago`, `sp_liberar_reservas_pendientes`, `sp_registrar_acceso_entrada`, `sp_registrar_acceso_salida`, `sp_reporte_diario_asistencias`, `sp_registrar_lote_empleados`. |
| Funciones | 15 funciones operativas de membresías, reservas y asistencias. **Excluidas** las financieras (`fn_total_pagado` y `fn_ingresos_*`). |
| No puede | Cancelar reservas con reembolso, generar facturas, registrar pagos, eliminar datos. |

### 3.3 `rol_usuario` · Usuario final

**Responsabilidad:** consultar su propia información, reservar espacios y revisar sus facturas.

| Categoría | Privilegios |
|---|---|
| Datos propios (vistas) | `SELECT` en `v_mi_perfil`, `v_mis_membresias`, `v_mis_reservas`, `v_mis_facturas`, `v_mis_detalle_facturas`, `v_mis_pagos`, `v_mis_accesos`. |
| Catálogos públicos | `SELECT` en `tipos_espacio`, `espacios`, `tipos_membresia`, `servicios_adicionales`. |
| Procedimientos | `sp_mi_crear_reserva` (solo a su nombre) y `sp_validar_disponibilidad_espacio`. |
| Funciones | Ninguna. |
| No puede | Acceder a tablas base, ver datos de otros usuarios, modificar su perfil, pagar ni cancelar desde la base de datos. |

### 3.4 `rol_gerente_corporativo` · Gerente Corporativo

**Responsabilidad:** supervisión de los empleados de su empresa (solo lectura).

| Categoría | Privilegios |
|---|---|
| Empleados | `SELECT` en `v_empresa_empleados` (nombre, apellidos, email, teléfono; **sin** `identificacion` ni `fecha_nacimiento`). |
| Membresías y reservas | `SELECT` en `v_empresa_membresias` y `v_empresa_reservas`. |
| Facturación | `SELECT` en `v_empresa_facturas` y en `v_empresa_facturacion_resumen` (consolidado por periodo `AAAA-MM` y estado). |
| Procedimientos y funciones | Ninguno. |
| No puede | Ver otras empresas, acceder a tablas base, ni a pagos individuales ni a accesos físicos. |

### 3.5 `rol_contador` · Contador

**Responsabilidad:** emisión y control de facturas, pagos y reportes financieros.

| Categoría | Privilegios |
|---|---|
| Facturas | `SELECT`, `INSERT` en `facturas`; `UPDATE` solo en `estado`, `motivo_anulacion`, `fecha_vencimiento` (no `saldo_pendiente`: lo mantienen los triggers). Sin `DELETE`. |
| Detalle de facturas | `SELECT`, `INSERT`, `UPDATE`. |
| Pagos | `SELECT`, `INSERT`; `UPDATE` solo en `estado_transaccion`. Sin `DELETE` (además lo bloquea `trg_del_pago_bloquear` en facturas pagadas). |
| Auditoría | `SELECT` en `log_pagos_anulados`. |
| Contexto de conciliación | `SELECT` en `empresas`, `tipos_membresia`, `servicios_adicionales`, `membresias`, `reservas`, `consumos_servicios`; y `SELECT` en `usuarios` **solo** en las columnas `id_usuario`, `id_empresa`, `identificacion`, `nombre`, `apellidos`, `email`. |
| Reportes (vistas) | `v_reporte_ingresos_mensuales` (ingreso neto por mes) y `v_reporte_cartera_pendiente` (facturas con saldo y días de mora). |
| Procedimientos | `sp_generar_factura_membresia`, `sp_generar_factura_empresa`, `sp_aplicar_recargo_facturas_vencidas`, `sp_bloquear_servicios_impago`, `sp_suspender_membresias_morosas`, `sp_cancelar_reserva_reembolso`, `sp_reporte_ingresos_acumulados`. |
| Funciones | `fn_total_pagado`, `fn_ingresos_por_mes`, `fn_ingresos_por_membresias`, `fn_ingresos_por_reservas`, `fn_ingresos_por_empresa`. |
| No puede | Registrar accesos, gestionar usuarios, ver fecha de nacimiento o teléfono de usuarios, ni crear reservas. |

---

## 4. Matriz CRUD por entidad

Cada tabla muestra los privilegios de los cinco roles sobre la entidad.
`rol_administrador` tiene `ALL PRIVILEGES` sobre todas las entidades.

### 4.1 `usuarios`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | Acceso total. |
| `rol_recepcionista` | ✅ | ✅ | ✅ `col` | ❌ | `UPDATE` en `id_empresa`, `nombre`, `apellidos`, `fecha_nacimiento`, `email`, `telefono`. Alta masiva vía `sp_registrar_lote_empleados`. |
| `rol_usuario` | ❌ | ✅ `v` | ❌ | ❌ | Solo su registro (`v_mi_perfil`). |
| `rol_gerente_corporativo` | ❌ | ✅ `v` | ❌ | ❌ | Solo empleados de su empresa (`v_empresa_empleados`), sin identificación ni fecha de nacimiento. |
| `rol_contador` | ❌ | ✅ `col` | ❌ | ❌ | Columnas: `id_usuario`, `id_empresa`, `identificacion`, `nombre`, `apellidos`, `email`. |

### 4.2 `empresas`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | Acceso total. |
| `rol_recepcionista` | ❌ | ✅ | ❌ | ❌ | Consulta para asociar usuarios. |
| `rol_usuario` | ❌ | ❌ | ❌ | ❌ | |
| `rol_gerente_corporativo` | ❌ | ❌ | ❌ | ❌ | Sus datos de empresa se ven a través de las vistas `v_empresa_*`. |
| `rol_contador` | ❌ | ✅ | ❌ | ❌ | Conciliación y facturación por empresa. |

### 4.3 Catálogos: `tipos_membresia`, `tipos_espacio`, `espacios`, `servicios_adicionales`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | Gestión de precios, espacios y servicios. |
| `rol_recepcionista` | ❌ | ✅ | ❌ | ❌ | Las cuatro tablas. |
| `rol_usuario` | ❌ | ✅ | ❌ | ❌ | Las cuatro tablas (catálogo público para reservar). |
| `rol_gerente_corporativo` | ❌ | ❌ | ❌ | ❌ | |
| `rol_contador` | ❌ | ✅ | ❌ | ❌ | Solo `tipos_membresia` y `servicios_adicionales`. |

### 4.4 `membresias`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | `trg_del_membresia_bloquear` impide borrar si hay reservas confirmadas vigentes. |
| `rol_recepcionista` | ✅ `sp` | ✅ | ✅ `sp` | ❌ | `sp_registrar_membresia`, `sp_renovar_membresia`, `sp_actualizar_membresias_vencidas`. |
| `rol_usuario` | ❌ | ✅ `v` | ❌ | ❌ | `v_mis_membresias`. |
| `rol_gerente_corporativo` | ❌ | ✅ `v` | ❌ | ❌ | `v_empresa_membresias`. |
| `rol_contador` | ❌ | ✅ | ✅ `sp` | ❌ | Suspensión por mora con `sp_suspender_membresias_morosas`. |

### 4.5 `reservas`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | También `sp_marcar_no_show_penalizar` y `sp_cancelar_reservas_usuario_eliminado`. |
| `rol_recepcionista` | ✅ `sp` | ✅ | ✅ `sp` | ❌ | `sp_crear_reserva`, `sp_confirmar_reserva_pago`, `sp_liberar_reservas_pendientes`. No cancela con reembolso. |
| `rol_usuario` | ✅ `sp` | ✅ `v` | ❌ | ❌ | Crea solo a su nombre con `sp_mi_crear_reserva`; consulta vía `v_mis_reservas`. |
| `rol_gerente_corporativo` | ❌ | ✅ `v` | ❌ | ❌ | `v_empresa_reservas`. |
| `rol_contador` | ❌ | ✅ | ✅ `sp` | ❌ | Cancelación con reembolso vía `sp_cancelar_reserva_reembolso`. |

### 4.6 `reserva_servicios` y `consumos_servicios`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | |
| `rol_recepcionista` | ✅ | ✅ | ❌ | ❌ | Registra servicios y consumos en recepción. |
| `rol_usuario` | ❌ | ❌ | ❌ | ❌ | |
| `rol_gerente_corporativo` | ❌ | ❌ | ❌ | ❌ | |
| `rol_contador` | ❌ | ✅ | ❌ | ❌ | Solo `consumos_servicios` (base de la facturación consolidada). |

### 4.7 `facturas`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | |
| `rol_recepcionista` | ❌ | ✅ | ❌ | ❌ | Consulta de estado de pago. |
| `rol_usuario` | ❌ | ✅ `v` | ❌ | ❌ | `v_mis_facturas`. |
| `rol_gerente_corporativo` | ❌ | ✅ `v` | ❌ | ❌ | `v_empresa_facturas` y consolidado `v_empresa_facturacion_resumen`. |
| `rol_contador` | ✅ | ✅ | ✅ `col` | ❌ | `UPDATE` en `estado`, `motivo_anulacion`, `fecha_vencimiento`. Emisión con `sp_generar_factura_*`. |

### 4.8 `detalle_facturas`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | |
| `rol_recepcionista` | ❌ | ❌ | ❌ | ❌ | |
| `rol_usuario` | ❌ | ✅ `v` | ❌ | ❌ | `v_mis_detalle_facturas`. |
| `rol_gerente_corporativo` | ❌ | ❌ | ❌ | ❌ | Solo ve el consolidado. |
| `rol_contador` | ✅ | ✅ | ✅ | ❌ | `subtotal` es columna generada. |

### 4.9 `pagos`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | `trg_del_pago_bloquear` impide borrar pagos de facturas `Pagada`. |
| `rol_recepcionista` | ❌ | ❌ | ❌ | ❌ | |
| `rol_usuario` | ❌ | ✅ `v` | ❌ | ❌ | `v_mis_pagos`. |
| `rol_gerente_corporativo` | ❌ | ❌ | ❌ | ❌ | |
| `rol_contador` | ✅ | ✅ | ✅ `col` | ❌ | `UPDATE` solo en `estado_transaccion`. Los triggers recalculan saldo y estado de la factura. |

### 4.10 `registros_acceso`

| Rol | C | R | U | D | Observaciones |
|---|:---:|:---:|:---:|:---:|---|
| `rol_administrador` | ✅ | ✅ | ✅ | ✅ | `evt_depurar_accesos_antiguos` purga registros de más de 1 año. |
| `rol_recepcionista` | ✅ `sp` | ✅ | ✅ `sp` | ❌ | `sp_registrar_acceso_entrada` (alta) y `sp_registrar_acceso_salida` (marca la salida). |
| `rol_usuario` | ❌ | ✅ `v` | ❌ | ❌ | `v_mis_accesos`. |
| `rol_gerente_corporativo` | ❌ | ❌ | ❌ | ❌ | |
| `rol_contador` | ❌ | ❌ | ❌ | ❌ | |

### 4.11 Tablas de auditoría (`log_*`)

| Tabla | Admin | Recepcionista | Usuario | Gerente | Contador |
|---|:---:|:---:|:---:|:---:|:---:|
| `log_cambios_membresia` | CRUD | — | — | — | — |
| `log_reservas_canceladas` | CRUD | — | — | — | — |
| `log_pagos_anulados` | CRUD | — | — | — | R |
| `log_accesos_rechazados` | CRUD | R | — | — | — |

> Las tablas `log_*` las alimentan los triggers con los privilegios del definidor; ningún rol (salvo el administrador) necesita escribir en ellas.

### 4.12 Resumen consolidado

| Entidad | Admin | Recepcionista | Usuario | Gerente | Contador |
|---|:---:|:---:|:---:|:---:|:---:|
| `usuarios` | CRUD | C R U(col) | R(v) | R(v) | R(col) |
| `empresas` | CRUD | R | — | — | R |
| Catálogos (4 tablas) | CRUD | R | R | — | R (2 de 4) |
| `membresias` | CRUD | R + C/U(sp) | R(v) | R(v) | R + U(sp) |
| `reservas` | CRUD | R + C/U(sp) | R(v) + C(sp) | R(v) | R + U(sp) |
| `reserva_servicios` / `consumos_servicios` | CRUD | C R | — | — | R (solo consumos) |
| `facturas` | CRUD | R | R(v) | R(v) | C R U(col) |
| `detalle_facturas` | CRUD | — | R(v) | — | C R U |
| `pagos` | CRUD | — | R(v) | — | C R U(col) |
| `registros_acceso` | CRUD | R + C/U(sp) | R(v) | — | — |
| `log_*` | CRUD | R (accesos) | — | — | R (pagos) |

---

## 5. Matriz de procedimientos y funciones

### 5.1 Procedimientos almacenados (`EXECUTE`)

| Procedimiento | Admin | Recep. | Usuario | Gerente | Contador |
|---|:---:|:---:|:---:|:---:|:---:|
| `sp_registrar_membresia` | ✅ | ✅ | — | — | — |
| `sp_renovar_membresia` | ✅ | ✅ | — | — | — |
| `sp_actualizar_membresias_vencidas` | ✅ | ✅ | — | — | — |
| `sp_suspender_membresias_morosas` | ✅ | — | — | — | ✅ |
| `sp_validar_disponibilidad_espacio` | ✅ | ✅ | ✅ | — | — |
| `sp_crear_reserva` | ✅ | ✅ | — | — | — |
| `sp_mi_crear_reserva` (wrapper) | ✅ | — | ✅ | — | — |
| `sp_confirmar_reserva_pago` | ✅ | ✅ | — | — | — |
| `sp_cancelar_reserva_reembolso` | ✅ | — | — | — | ✅ |
| `sp_liberar_reservas_pendientes` | ✅ | ✅ | — | — | — |
| `sp_generar_factura_membresia` | ✅ | — | — | — | ✅ |
| `sp_generar_factura_empresa` | ✅ | — | — | — | ✅ |
| `sp_aplicar_recargo_facturas_vencidas` | ✅ | — | — | — | ✅ |
| `sp_bloquear_servicios_impago` | ✅ | — | — | — | ✅ |
| `sp_registrar_acceso_entrada` | ✅ | ✅ | — | — | — |
| `sp_registrar_acceso_salida` | ✅ | ✅ | — | — | — |
| `sp_reporte_diario_asistencias` | ✅ | ✅ | — | — | — |
| `sp_marcar_no_show_penalizar` | ✅ | — | — | — | — |
| `sp_registrar_lote_empleados` | ✅ | ✅ | — | — | — |
| `sp_cancelar_reservas_usuario_eliminado` | ✅ | — | — | — | — |
| `sp_reporte_ingresos_acumulados` | ✅ | — | — | — | ✅ |

### 5.2 Funciones (`EXECUTE`)

| Grupo | Admin | Recep. | Usuario | Gerente | Contador |
|---|:---:|:---:|:---:|:---:|:---:|
| Membresías (`fn_membresia_activa`, `fn_dias_restantes_membresia`, `fn_tipo_membresia`, `fn_renovaciones_membresia`, `fn_estado_membresia`) | ✅ | ✅ | — | — | — |
| Reservas (`fn_total_reservas`, `fn_horas_reservadas`, `fn_espacio_mas_reservado`, `fn_reservas_activas`, `fn_duracion_promedio_reservas`) | ✅ | ✅ | — | — | — |
| Asistencias (`fn_total_asistencias`, `fn_asistencias_mes`, `fn_top_usuario_asistencias`, `fn_ultima_asistencia`, `fn_promedio_asistencias`) | ✅ | ✅ | — | — | — |
| Financieras (`fn_total_pagado`, `fn_ingresos_por_mes`, `fn_ingresos_por_membresias`, `fn_ingresos_por_reservas`, `fn_ingresos_por_empresa`) | ✅ | — | — | — | ✅ |

### 5.3 Vistas

| Vista | Rol con acceso |
|---|---|
| `v_mi_perfil`, `v_mis_membresias`, `v_mis_reservas`, `v_mis_facturas`, `v_mis_detalle_facturas`, `v_mis_pagos`, `v_mis_accesos` | `rol_usuario` |
| `v_empresa_empleados`, `v_empresa_membresias`, `v_empresa_reservas`, `v_empresa_facturas`, `v_empresa_facturacion_resumen` | `rol_gerente_corporativo` |
| `v_reporte_ingresos_mensuales`, `v_reporte_cartera_pendiente` | `rol_contador` |
| `v_seg_sesion` | Interna (solo `rol_administrador`; las demás vistas la consultan con privilegios del definidor) |

---

## 6. Usuarios de ejemplo

| Cuenta | Rol | Vinculación a `usuarios` |
|---|---|---|
| `usr_admin@localhost` | `rol_administrador` | No aplica |
| `usr_recepcion@localhost` | `rol_recepcionista` | No aplica |
| `usr_cliente@localhost` | `rol_usuario` | **Requerida** (`seg_mapeo_cuentas`, variable `@email_cliente`) |
| `usr_gerente@localhost` | `rol_gerente_corporativo` | **Requerida**; el usuario debe tener `id_empresa` (variable `@email_gerente`) |
| `usr_contador@localhost` | `rol_contador` | No aplica |

Política de cuentas aplicada a todas:

| Parámetro | Valor |
|---|---|
| Host | `localhost` (use el host o subred específica de la aplicación para acceso remoto; evite `%`) |
| Caducidad de contraseña | 90 días (`PASSWORD EXPIRE INTERVAL 90 DAY`) |
| Historial | No reutilizar las últimas 5 (`PASSWORD HISTORY 5`) |
| Bloqueo | 5 intentos fallidos → 1 día (`FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1`) |
| Rol por defecto | `SET DEFAULT ROLE ALL` (el rol se activa al iniciar sesión) |

> ⚠️ Las contraseñas de `03_usuarios.sql` son **solo de ejemplo**. Cámbielas antes de cualquier uso fuera de desarrollo y no las suba al repositorio.

---

## 7. Operación y mantenimiento

### 7.1 Verificar privilegios

```sql
SHOW GRANTS FOR 'usr_recepcion'@'localhost' USING 'rol_recepcionista';
SHOW GRANTS FOR 'rol_contador';
```

### 7.2 Probar el aislamiento por fila

```sql
-- Conectado como usr_cliente
SELECT CURRENT_ROLE();
SELECT * FROM coworking_db.v_mis_reservas;        -- solo sus reservas
SELECT * FROM coworking_db.usuarios;              -- ERROR 1142: acceso denegado

-- Conectado como usr_gerente
SELECT * FROM coworking_db.v_empresa_empleados;   -- solo su empresa
```

### 7.3 Alta de un nuevo cliente

```sql
-- 1) Cuenta y rol
CREATE USER 'usr_ana'@'localhost' IDENTIFIED BY '<contraseña_segura>'
    PASSWORD EXPIRE INTERVAL 90 DAY PASSWORD HISTORY 5
    FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
GRANT 'rol_usuario' TO 'usr_ana'@'localhost';
SET DEFAULT ROLE ALL TO 'usr_ana'@'localhost';

-- 2) Vínculo con su registro en usuarios
REPLACE INTO coworking_db.seg_mapeo_cuentas (nombre_cuenta, id_usuario)
SELECT 'usr_ana', id_usuario FROM coworking_db.usuarios WHERE email = 'ana@ejemplo.com';
```

Para un gerente, use `rol_gerente_corporativo`: el usuario vinculado debe tener `id_empresa`.

### 7.4 Baja o cambio de rol

```sql
REVOKE 'rol_recepcionista' FROM 'usr_recepcion'@'localhost';
DELETE FROM coworking_db.seg_mapeo_cuentas WHERE nombre_cuenta = 'usr_cliente';
DROP USER 'usr_cliente'@'localhost';
```

### 7.5 Orden de despliegue

Ejecute `01_roles.sql` → `02_permisos.sql` → `03_usuarios.sql` **después** de crear estructura, funciones, procedimientos, triggers y eventos: `02_permisos.sql` concede `EXECUTE` sobre rutinas y `SELECT` sobre tablas que deben existir.

---

## 8. Limitaciones y decisiones de diseño

| Tema | Decisión |
|---|---|
| Cancelación de reservas | Un recepcionista solo libera reservas pendientes. La cancelación con reembolso mueve dinero y se reserva al contador y al administrador. Si el negocio requiere que recepción cancele, puede concederse `sp_cancelar_reserva_reembolso` a `rol_recepcionista`. |
| `sp_crear_reserva` para recepción | Recibe `p_id_usuario`: es intencional, porque el recepcionista reserva en nombre de clientes. Los clientes usan el wrapper `sp_mi_crear_reserva`. |
| Perfil del cliente | `rol_usuario` no puede modificar su perfil desde la base de datos; las actualizaciones las hace recepción. |
| Gerente | Solo lectura. No genera facturas ni cancela reservas. `sp_generar_factura_empresa` y las funciones `fn_ingresos_por_empresa` se conceden al contador porque reciben un id de empresa arbitrario. |
| Filtrado por `USER()` | Depende de que el nombre de la cuenta MySQL coincida con `seg_mapeo_cuentas.nombre_cuenta` (máx. 32 caracteres). Si varias cuentas de aplicación comparten un único usuario MySQL, el filtrado por fila no distingue personas: en ese caso, implemente la autorización en la capa de aplicación. |
| Tablas auxiliares de eventos | Solo las gestiona el administrador y los eventos; ningún otro rol tiene acceso. |
| Triggers y eventos | Se ejecutan con privilegios de su definidor, no de quien dispara la acción. |
| Procedimientos `DEFINER` | Si el usuario que crea los procedimientos se elimina, los `sp_*` dejan de ejecutarse. Cree los objetos con una cuenta estable de despliegue. |
