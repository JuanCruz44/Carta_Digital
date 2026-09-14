# Diagrama ER — borrador (Fase B0)

> Borrador inicial del modelo de datos. Se actualizará en Fase B7 para reflejar
> lo realmente implementado (RLS y funciones incluidas).

```mermaid
erDiagram
    auth_users ||--o| users : "perfil 1:1"
    users ||--o{ restaurant_users : "pertenece a"
    restaurants ||--o{ restaurant_users : "tiene"
    restaurants ||--o{ categories : "tiene"
    restaurants ||--o{ products : "tiene"
    restaurants ||--o{ tables : "tiene"
    restaurants ||--o{ nfc_tags : "tiene"
    restaurants ||--o{ sessions : "tiene"
    restaurants ||--o{ orders : "tiene"
    categories ||--o{ products : "agrupa"
    tables ||--o{ nfc_tags : "apuntado por"
    tables ||--o{ sessions : "ocupada en"
    tables ||--o{ orders : "recibe"
    sessions ||--o{ orders : "origina"
    orders ||--o{ order_items : "contiene"
    products ||--o{ order_items : "pedido en"

    restaurants {
        uuid id PK
        text name
        text slug UK
        bool is_active
        bool orders_enabled "toggle pedidos ON/OFF (B8/F8)"
        timestamptz created_at
        timestamptz updated_at
    }
    users {
        uuid id PK "= auth.users.id"
        text email
        text full_name
        bool is_superadmin
        timestamptz created_at
        timestamptz updated_at
    }
    restaurant_users {
        uuid id PK
        uuid restaurant_id FK
        uuid user_id FK
        enum role "admin | kitchen"
        timestamptz created_at
    }
    categories {
        uuid id PK
        uuid restaurant_id FK
        text name
        int sort_order
        bool is_active
        timestamptz created_at
        timestamptz updated_at
    }
    products {
        uuid id PK
        uuid restaurant_id FK
        uuid category_id FK
        text name
        text description
        numeric price
        text image_url
        bool is_available
        int sort_order
        timestamptz created_at
        timestamptz updated_at
    }
    tables {
        uuid id PK
        uuid restaurant_id FK
        text label
        bool is_active
        timestamptz created_at
        timestamptz updated_at
    }
    nfc_tags {
        uuid id PK
        text tag_uid UK "identificador físico del NFC/QR"
        uuid restaurant_id FK
        uuid table_id FK "reasignable sin tocar el tag físico"
        bool is_active
        timestamptz created_at
        timestamptz updated_at
    }
    sessions {
        uuid id PK
        uuid restaurant_id FK
        uuid table_id FK
        uuid nfc_tag_id FK
        uuid token UK "lo guarda el cliente"
        timestamptz expires_at
        timestamptz created_at
    }
    orders {
        uuid id PK
        uuid restaurant_id FK
        uuid table_id FK
        uuid session_id FK
        enum status "pendiente | en_proceso | terminado"
        numeric total "calculado por el servidor"
        timestamptz created_at
        timestamptz updated_at
    }
    order_items {
        uuid id PK
        uuid restaurant_id FK
        uuid order_id FK
        uuid product_id FK
        text product_name "snapshot al momento del pedido"
        numeric unit_price "snapshot, calculado por el servidor"
        int quantity
        numeric line_total
        timestamptz created_at
    }
```

## Notas de diseño

- **`auth_users`** representa `auth.users` de Supabase (no se crea ni se toca:
  la gestiona Supabase Auth). Nuestra tabla `users` es el perfil público 1:1.
- **`orders_enabled`** en `restaurants` es el toggle "Pedidos desde la mesa"
  ON/OFF del superadmin (Fase F8). El backend rechaza pedidos si está en `false`
  (Fase B3), aunque el cliente intente forzar la petición.
- **Integridad multi-tenant por FK compuesta**: `products` referencia
  `(restaurant_id, category_id)` → `categories(restaurant_id, id)`, y
  `order_items` referencia `(restaurant_id, product_id)` → `products(...)` y
  `(restaurant_id, order_id)` → `orders(...)`. Así la base rechaza, por ejemplo,
  meter en un pedido un producto de otro restaurante (test de Fase B1).
- **`sessions.token`** es lo que el cliente guarda tras resolver el NFC; con
  `expires_at` se controla la expiración (Fase B4).
- **Snapshots en `order_items`** (`product_name`, `unit_price`): si el admin
  cambia el precio o el nombre después, el pedido histórico no se altera.
