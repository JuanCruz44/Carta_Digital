-- =============================================================================
-- Fase B1 — Modelo de datos completo
-- Carta Digital · esquema núcleo, catálogo, mesas/NFC/sesión y pedidos.
-- Convenciones: ver backend/docs/conventions.md
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tipos enum
-- -----------------------------------------------------------------------------
create type public.restaurant_user_role as enum ('admin', 'kitchen');
create type public.order_status         as enum ('pendiente', 'en_proceso', 'terminado');

-- -----------------------------------------------------------------------------
-- Trigger genérico para mantener updated_at
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =============================================================================
-- Núcleo: restaurants, users (perfil de auth), restaurant_users
-- =============================================================================

create table public.restaurants (
  id             uuid        primary key default gen_random_uuid(),
  name           text        not null,
  slug           text        not null unique,
  is_active      boolean     not null default true,
  orders_enabled boolean     not null default true,   -- toggle "Pedidos desde la mesa"
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- Perfil público 1:1 con auth.users. La gestión de credenciales es de Supabase Auth.
create table public.users (
  id            uuid        primary key references auth.users (id) on delete cascade,
  email         text,
  full_name     text,
  is_superadmin boolean     not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.restaurant_users (
  id            uuid                        primary key default gen_random_uuid(),
  restaurant_id uuid                        not null references public.restaurants (id) on delete cascade,
  user_id       uuid                        not null references public.users (id)       on delete cascade,
  role          public.restaurant_user_role not null,
  created_at    timestamptz                 not null default now(),
  unique (restaurant_id, user_id)
);

create index idx_restaurant_users_restaurant_id on public.restaurant_users (restaurant_id);
create index idx_restaurant_users_user_id        on public.restaurant_users (user_id);

-- =============================================================================
-- Catálogo: categories, products
-- =============================================================================

create table public.categories (
  id            uuid        primary key default gen_random_uuid(),
  restaurant_id uuid        not null references public.restaurants (id) on delete cascade,
  name          text        not null,
  sort_order    integer     not null default 0,
  is_active     boolean     not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- permite que products referencie (restaurant_id, category_id)
  unique (restaurant_id, id)
);

create index idx_categories_restaurant_id on public.categories (restaurant_id);

create table public.products (
  id            uuid          primary key default gen_random_uuid(),
  restaurant_id uuid          not null references public.restaurants (id) on delete cascade,
  category_id   uuid          not null,
  name          text          not null,
  description   text,
  price         numeric(10,2) not null check (price >= 0),
  image_url     text,
  is_available  boolean       not null default true,
  sort_order    integer       not null default 0,
  created_at    timestamptz   not null default now(),
  updated_at    timestamptz   not null default now(),
  -- la categoría debe pertenecer al MISMO restaurante (integridad multi-tenant en la base)
  foreign key (restaurant_id, category_id)
    references public.categories (restaurant_id, id) on delete restrict,
  -- permite que order_items referencie (restaurant_id, product_id)
  unique (restaurant_id, id)
);

create index idx_products_restaurant_id on public.products (restaurant_id);
create index idx_products_category_id   on public.products (category_id);

-- =============================================================================
-- Mesas, NFC y sesiones
-- =============================================================================

create table public.tables (
  id            uuid        primary key default gen_random_uuid(),
  restaurant_id uuid        not null references public.restaurants (id) on delete cascade,
  label         text        not null,          -- ej. "Mesa 1", "Barra 3"
  is_active     boolean     not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (restaurant_id, id),
  unique (restaurant_id, label)
);

create index idx_tables_restaurant_id on public.tables (restaurant_id);

create table public.nfc_tags (
  id            uuid        primary key default gen_random_uuid(),
  tag_uid       text        not null unique,    -- identificador físico del tag NFC / QR
  restaurant_id uuid        not null references public.restaurants (id) on delete cascade,
  table_id      uuid,                            -- reasignable sin tocar el tag físico
  is_active     boolean     not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- la mesa apuntada debe ser del mismo restaurante. Si se borra la mesa, el tag
  -- queda sin mesa (solo se anula table_id; restaurant_id se conserva).
  foreign key (restaurant_id, table_id)
    references public.tables (restaurant_id, id) on delete set null (table_id)
);

create index idx_nfc_tags_restaurant_id on public.nfc_tags (restaurant_id);
create index idx_nfc_tags_table_id       on public.nfc_tags (table_id);

create table public.sessions (
  id            uuid        primary key default gen_random_uuid(),
  restaurant_id uuid        not null references public.restaurants (id) on delete cascade,
  table_id      uuid        not null,
  nfc_tag_id    uuid        references public.nfc_tags (id) on delete set null,
  token         uuid        not null default gen_random_uuid() unique,  -- lo guarda el cliente
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  foreign key (restaurant_id, table_id)
    references public.tables (restaurant_id, id) on delete cascade,
  -- permite que orders referencie (restaurant_id, session_id)
  unique (restaurant_id, id)
);

create index idx_sessions_restaurant_id on public.sessions (restaurant_id);
create index idx_sessions_token          on public.sessions (token);

-- =============================================================================
-- Pedidos
-- =============================================================================

create table public.orders (
  id            uuid                primary key default gen_random_uuid(),
  restaurant_id uuid                not null references public.restaurants (id) on delete cascade,
  table_id      uuid                not null,
  session_id    uuid                not null,
  status        public.order_status not null default 'pendiente',
  total         numeric(10,2)       not null default 0 check (total >= 0),
  created_at    timestamptz         not null default now(),
  updated_at    timestamptz         not null default now(),
  foreign key (restaurant_id, table_id)
    references public.tables (restaurant_id, id) on delete restrict,
  foreign key (restaurant_id, session_id)
    references public.sessions (restaurant_id, id) on delete restrict,
  -- permite que order_items referencie (restaurant_id, order_id)
  unique (restaurant_id, id)
);

create index idx_orders_restaurant_id        on public.orders (restaurant_id);
create index idx_orders_restaurant_status    on public.orders (restaurant_id, status);
create index idx_orders_session_id           on public.orders (session_id);

create table public.order_items (
  id            uuid          primary key default gen_random_uuid(),
  restaurant_id uuid          not null,
  order_id      uuid          not null,
  product_id    uuid          not null,
  product_name  text          not null,               -- snapshot al momento del pedido
  unit_price    numeric(10,2) not null check (unit_price >= 0),  -- snapshot (server)
  quantity      integer       not null check (quantity > 0),
  line_total    numeric(10,2) not null check (line_total >= 0),
  created_at    timestamptz   not null default now(),
  -- el pedido y el producto deben ser del mismo restaurante
  foreign key (restaurant_id, order_id)
    references public.orders (restaurant_id, id) on delete cascade,
  foreign key (restaurant_id, product_id)
    references public.products (restaurant_id, id) on delete restrict
);

create index idx_order_items_order_id   on public.order_items (order_id);
create index idx_order_items_product_id on public.order_items (product_id);

-- =============================================================================
-- Triggers de updated_at
-- =============================================================================
create trigger trg_restaurants_updated_at
  before update on public.restaurants
  for each row execute function public.set_updated_at();

create trigger trg_users_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();

create trigger trg_categories_updated_at
  before update on public.categories
  for each row execute function public.set_updated_at();

create trigger trg_products_updated_at
  before update on public.products
  for each row execute function public.set_updated_at();

create trigger trg_tables_updated_at
  before update on public.tables
  for each row execute function public.set_updated_at();

create trigger trg_nfc_tags_updated_at
  before update on public.nfc_tags
  for each row execute function public.set_updated_at();

create trigger trg_orders_updated_at
  before update on public.orders
  for each row execute function public.set_updated_at();
