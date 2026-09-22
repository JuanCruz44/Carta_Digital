# API del backend — funciones RPC y acceso a datos

Manual de consumo del backend para el frontend (Angular). Describe qué funciones
hay, qué reciben y qué devuelven, quién puede llamarlas, y cómo leer datos
directamente respetando la seguridad (RLS).

> Base de datos: Supabase / PostgreSQL. Todas las funciones se invocan con
> `supabase.rpc('nombre', { parametros })` usando la librería `@supabase/supabase-js`.

## Conexión

```ts
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  environment.SUPABASE_URL,       // https://<ref>.supabase.co
  environment.SUPABASE_ANON_KEY   // clave pública anon (respeta RLS)
);
```

- El **cliente de mesa** usa la clave `anon` sin iniciar sesión (rol `anon`).
- **Admin / cocina / superadmin** usan la misma app pero **logueados** con
  Supabase Auth (rol `authenticated`); su rol real se resuelve en el backend.
- La clave `service_role` **jamás** va en el frontend.

---

## Funciones RPC

### `resolve_nfc_tag` — abrir sesión al escanear la mesa
Quién la usa: **cliente (anon)**.

| Parámetro | Tipo | Descripción |
|---|---|---|
| `p_tag_uid` | `text` | Identificador del tag NFC/QR escaneado |

Devuelve (`jsonb`):
```json
{
  "session_token": "uuid",
  "expires_at": "2026-01-01T12:00:00Z",
  "restaurant": { "id": "uuid", "name": "Bar Lindo", "slug": "bar-lindo" },
  "table": { "id": "uuid", "label": "Mesa 3" }
}
```
Guardá `session_token` (memoria/localStorage) y usalo en `create_order`.

```ts
const { data, error } = await supabase.rpc('resolve_nfc_tag', { p_tag_uid: 'bar-lindo-mesa-3' });
```
Errores: `P0101` inválido · `P0102` desactivado · `P0103` sin mesa · `P0104` restaurante inactivo.

---

### `create_order` — crear un pedido
Quién la usa: **cliente (anon)**, con una sesión válida.

| Parámetro | Tipo | Descripción |
|---|---|---|
| `p_session_token` | `uuid` | Token devuelto por `resolve_nfc_tag` |
| `p_items` | `jsonb` | Lista de `{ "product_id": uuid, "quantity": int }` |

Devuelve (`jsonb`):
```json
{ "order_id": "uuid", "status": "pendiente", "total": 11500, "item_count": 2 }
```

```ts
const { data, error } = await supabase.rpc('create_order', {
  p_session_token: token,
  p_items: [
    { product_id: 'b0000000-0000-0000-0000-000000000301', quantity: 2 },
    { product_id: 'b0000000-0000-0000-0000-000000000308', quantity: 1 }
  ]
});
```
El **total lo calcula el servidor** leyendo el precio real de cada producto:
cualquier `price` que mande el cliente se ignora. El pedido se considera
"enviado" solo si `error` es `null`.

Errores: `P0001` sesión inválida · `P0002` expirada · `P0003` restaurante inactivo ·
`P0004` pedidos deshabilitados · `P0005` sin productos · `P0006` cantidad inválida ·
`P0007` producto inexistente/no disponible.

---

### `set_order_status` — cambiar el estado de un pedido
Quién la usa: **cocina / admin (authenticated)** del restaurante del pedido.

| Parámetro | Tipo | Descripción |
|---|---|---|
| `p_order_id` | `uuid` | Pedido a actualizar |
| `p_status` | `order_status` | `'pendiente'` · `'en_proceso'` · `'terminado'` |

Devuelve: `{ "order_id": "uuid", "status": "en_proceso" }`

```ts
const { data, error } = await supabase.rpc('set_order_status', {
  p_order_id: orderId, p_status: 'en_proceso'
});
```
Errores: `P0008` pedido inexistente · `P0009` sin permiso (el cliente nunca puede).

---

### `reassign_nfc_tag` — mover un tag a otra mesa
Quién la usa: **admin (authenticated)** del restaurante.

| Parámetro | Tipo | Descripción |
|---|---|---|
| `p_tag_id` | `uuid` | Tag a reasignar |
| `p_table_id` | `uuid` | Mesa destino (del mismo restaurante) |

Devuelve: `{ "tag_id": "uuid", "table_id": "uuid", "table_label": "Mesa 8" }`

Errores: `P0101` tag inexistente · `P0105` sin permiso · `P0106` mesa de otro restaurante.

---

## Lectura directa de datos (con RLS)

Estas tablas se leen directamente con `supabase.from('tabla').select()`; la
seguridad (RLS) filtra automáticamente qué filas ve cada rol.

| Tabla | Cliente (anon) ve | Staff (authenticated) ve |
|---|---|---|
| `restaurants` | activos | el suyo + activos |
| `categories` | activas de restaurantes activos | todas las suyas |
| `products` | solo disponibles | todos los suyos |
| `tables`, `nfc_tags` | — | los de su restaurante |
| `orders`, `order_items` | — | los de su restaurante |

Ejemplo — menú del cliente (solo productos disponibles, ya filtrado por RLS):
```ts
const { data } = await supabase
  .from('products')
  .select('id, name, description, price, image_url, category_id')
  .eq('restaurant_id', restaurantId)
  .order('sort_order');
```

Escritura de catálogo (categorías/productos/mesas/tags): permitida solo al
**admin** del restaurante, también vía `supabase.from(...).insert/update/delete`.

---

## Tiempo real (Realtime)

`orders` y `order_items` transmiten cambios. La cocina se suscribe y recibe
**solo los pedidos de su restaurante** (lo garantiza RLS):

```ts
supabase
  .channel('cocina-pedidos')
  .on('postgres_changes',
      { event: '*', schema: 'public', table: 'orders' },
      (payload) => actualizarTablero(payload))
  .subscribe();
```

---

## Datos de prueba (seed "Bar Lindo")

- Restaurante `Bar Lindo` — id `b0000000-0000-0000-0000-000000000001`.
- Tags NFC: `bar-lindo-mesa-1` … `bar-lindo-mesa-5`.
- Productos: ids `...000000000301` … `...00000000030b` (2 marcados no disponibles).
- Usuarios (crear/confirmar en Authentication; contraseña definida por el equipo):
  - `superadmin@barlindo.test` (superadmin)
  - `admin@barlindo.test` (admin de Bar Lindo)
  - `cocina@barlindo.test` (cocina de Bar Lindo)

## Códigos de error (referencia rápida)

| Código | Significado |
|---|---|
| P0001 | Sesión inválida |
| P0002 | Sesión expirada |
| P0003 | Restaurante inactivo |
| P0004 | Pedidos deshabilitados |
| P0005 | Pedido sin productos |
| P0006 | Cantidad inválida |
| P0007 | Producto inexistente o no disponible |
| P0008 | Pedido inexistente |
| P0009 | Sin permiso para cambiar el estado |
| P0101 | Tag NFC inexistente / código inválido |
| P0102 | Tag desactivado |
| P0103 | Tag sin mesa asignada |
| P0104 | Restaurante inactivo (al escanear) |
| P0105 | Sin permiso para reasignar el tag |
| P0106 | Mesa destino de otro restaurante |
