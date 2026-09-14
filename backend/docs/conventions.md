# Convenciones del backend (Fase B0)

Estas reglas aplican a todo el esquema, migraciones y funciones. El objetivo es
que el modelo sea predecible y que el frontend pueda alinear sus interfaces
TypeScript 1:1 con la base.

## Nombres

- **Tablas**: `snake_case`, en plural. Ej: `restaurants`, `order_items`.
- **Columnas**: `snake_case`, en singular. Ej: `restaurant_id`, `is_active`.
- **Claves foráneas**: `<entidad_singular>_id`. Ej: `category_id`, `table_id`.
- **Enums (tipos)**: `snake_case` singular. Ej: `order_status`.
- **Funciones RPC**: `snake_case`, verbo primero. Ej: `create_order`,
  `resolve_nfc_tag`, `set_order_status`.
- **Índices**: `idx_<tabla>_<columnas>`. Ej: `idx_products_restaurant_id`.

## Claves primarias

- Toda tabla usa `id uuid primary key default gen_random_uuid()`.

## Timestamps

- `created_at timestamptz not null default now()` en todas las tablas.
- `updated_at timestamptz not null default now()` en tablas mutables, mantenido
  por el trigger `set_updated_at()` (definido en la primera migración).
- Fechas siempre en `timestamptz` (UTC), nunca `timestamp` sin zona.

## Estados

- Se modelan con **tipos enum** de PostgreSQL, no con texto libre.
- `order_status`: `pendiente`, `en_proceso`, `terminado`.
- `restaurant_user_role`: `admin`, `kitchen`.
  (El rol `superadmin` es global y se marca con `users.is_superadmin`, no vive
  en `restaurant_users` porque no está atado a un restaurante.)

## Multi-tenant (aislamiento por restaurante)

- Casi toda tabla de dominio lleva `restaurant_id`.
- La pertenencia al mismo restaurante se garantiza a nivel de base con
  **claves foráneas compuestas** `(restaurant_id, id)`, no con triggers ni con
  validación en la aplicación. Ejemplo: un `order_item` solo puede referenciar
  un `product` del mismo `restaurant_id` que su `order`.
- Además, la Fase B2 agrega Row Level Security (RLS) para que ningún rol pueda
  leer/escribir datos de un restaurante ajeno.

## Dinero

- Precios y totales: `numeric(10,2)`. Nunca `float`/`double`.
- El total de un pedido **siempre** lo calcula el servidor (Fase B3); el precio
  que envíe el cliente se ignora.

## Migraciones

- Versionadas en `backend/supabase/migrations/`, prefijo timestamp
  `YYYYMMDDHHMMSS_descripcion.sql`.
- Nunca se edita una migración ya aplicada; los cambios van en una migración
  nueva.
- El dashboard de Supabase no es la fuente de verdad: todo cambio de esquema
  pasa por una migración en el repo.
