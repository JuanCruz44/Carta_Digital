-- =============================================================================
-- Carta Digital — Schema SQL completo del backend (export único, Fase B7)
--
-- Generado a partir de las migraciones versionadas de supabase/migrations/,
-- en orden. Recrea todo el backend desde cero: tablas, tipos, claves foráneas,
-- triggers, políticas RLS, funciones RPC y Realtime.
--
-- Requiere un entorno Supabase (usa el esquema auth y la publicación
-- supabase_realtime, que Supabase provee). Fuente de verdad = las migraciones;
-- este archivo es una vista consolidada de solo lectura.
-- =============================================================================


-- #############################################################################
-- # Origen: supabase/migrations/20260911120000_b1_core_schema.sql
-- #############################################################################

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

-- #############################################################################
-- # Origen: supabase/migrations/20260917120000_b2_rls.sql
-- #############################################################################

-- =============================================================================
-- Fase B2 — Seguridad: roles y Row Level Security (RLS)
-- Carta Digital · aislamiento multi-tenant y permisos por rol.
--
-- Roles:
--   - superadmin: global (public.users.is_superadmin = true).
--   - admin / kitchen: por restaurante (public.restaurant_users.role).
--   - cliente: anónimo (rol anon), solo lectura del menú público.
--
-- El cliente NUNCA escribe directo: crear sesión/pedido se hará por funciones
-- SECURITY DEFINER (Fase B3/B4), que corren como dueño y omiten RLS.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Perfil automático al registrarse un usuario en Supabase Auth
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- Funciones ayudantes (SECURITY DEFINER: omiten RLS, evitan recursión)
-- -----------------------------------------------------------------------------
create or replace function public.is_superadmin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.is_superadmin = true
  );
$$;

create or replace function public.is_restaurant_admin(p_restaurant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.restaurant_users ru
    where ru.restaurant_id = p_restaurant_id
      and ru.user_id = auth.uid()
      and ru.role = 'admin'
  );
$$;

create or replace function public.is_restaurant_staff(p_restaurant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.restaurant_users ru
    where ru.restaurant_id = p_restaurant_id
      and ru.user_id = auth.uid()
  );
$$;

-- =============================================================================
-- restaurants
-- =============================================================================
alter table public.restaurants enable row level security;
grant select on public.restaurants to anon, authenticated;
grant insert, update, delete on public.restaurants to authenticated;

-- Lectura pública: cualquiera ve los restaurantes activos (para mostrar el menú).
create policy restaurants_select_public on public.restaurants
  for select to anon, authenticated
  using (is_active = true);

-- El staff ve su propio restaurante aunque esté inactivo; el superadmin ve todo.
create policy restaurants_select_member on public.restaurants
  for select to authenticated
  using (public.is_restaurant_staff(id) or public.is_superadmin());

-- Solo el superadmin crea/edita/borra restaurantes (incluye el toggle de pedidos).
create policy restaurants_write_superadmin on public.restaurants
  for all to authenticated
  using (public.is_superadmin())
  with check (public.is_superadmin());

-- =============================================================================
-- users (perfil)
-- =============================================================================
alter table public.users enable row level security;
grant select on public.users to authenticated;

-- Cada uno ve su propio perfil; el superadmin ve todos.
create policy users_select_self on public.users
  for select to authenticated
  using (id = auth.uid() or public.is_superadmin());

-- =============================================================================
-- restaurant_users (relación usuario-restaurante-rol)
-- =============================================================================
alter table public.restaurant_users enable row level security;
grant select on public.restaurant_users to authenticated;
grant insert, update, delete on public.restaurant_users to authenticated;

-- Un usuario ve sus propias membresías; el admin ve las de su restaurante.
create policy restaurant_users_select on public.restaurant_users
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_restaurant_admin(restaurant_id)
    or public.is_superadmin()
  );

-- El admin del restaurante (o el superadmin) gestiona su equipo.
create policy restaurant_users_write_admin on public.restaurant_users
  for all to authenticated
  using (public.is_restaurant_admin(restaurant_id) or public.is_superadmin())
  with check (public.is_restaurant_admin(restaurant_id) or public.is_superadmin());

-- =============================================================================
-- categories
-- =============================================================================
alter table public.categories enable row level security;
grant select on public.categories to anon, authenticated;
grant insert, update, delete on public.categories to authenticated;

-- Lectura pública: categorías activas de restaurantes activos.
create policy categories_select_public on public.categories
  for select to anon, authenticated
  using (
    is_active = true
    and exists (
      select 1 from public.restaurants r
      where r.id = restaurant_id and r.is_active = true
    )
  );

-- El staff ve todas las categorías de su restaurante (activas o no).
create policy categories_select_staff on public.categories
  for select to authenticated
  using (public.is_restaurant_staff(restaurant_id) or public.is_superadmin());

-- Solo el admin del restaurante (o superadmin) edita el catálogo.
create policy categories_write_admin on public.categories
  for all to authenticated
  using (public.is_restaurant_admin(restaurant_id) or public.is_superadmin())
  with check (public.is_restaurant_admin(restaurant_id) or public.is_superadmin());

-- =============================================================================
-- products
-- =============================================================================
alter table public.products enable row level security;
grant select on public.products to anon, authenticated;
grant insert, update, delete on public.products to authenticated;

-- Lectura pública: solo productos disponibles de restaurantes activos.
create policy products_select_public on public.products
  for select to anon, authenticated
  using (
    is_available = true
    and exists (
      select 1 from public.restaurants r
      where r.id = restaurant_id and r.is_active = true
    )
  );

-- El staff ve todos los productos de su restaurante (disponibles o no).
create policy products_select_staff on public.products
  for select to authenticated
  using (public.is_restaurant_staff(restaurant_id) or public.is_superadmin());

create policy products_write_admin on public.products
  for all to authenticated
  using (public.is_restaurant_admin(restaurant_id) or public.is_superadmin())
  with check (public.is_restaurant_admin(restaurant_id) or public.is_superadmin());

-- =============================================================================
-- tables
-- =============================================================================
alter table public.tables enable row level security;
grant select on public.tables to authenticated;
grant insert, update, delete on public.tables to authenticated;

create policy tables_select_staff on public.tables
  for select to authenticated
  using (public.is_restaurant_staff(restaurant_id) or public.is_superadmin());

create policy tables_write_admin on public.tables
  for all to authenticated
  using (public.is_restaurant_admin(restaurant_id) or public.is_superadmin())
  with check (public.is_restaurant_admin(restaurant_id) or public.is_superadmin());

-- =============================================================================
-- nfc_tags
-- =============================================================================
alter table public.nfc_tags enable row level security;
grant select on public.nfc_tags to authenticated;
grant insert, update, delete on public.nfc_tags to authenticated;

create policy nfc_tags_select_staff on public.nfc_tags
  for select to authenticated
  using (public.is_restaurant_staff(restaurant_id) or public.is_superadmin());

create policy nfc_tags_write_admin on public.nfc_tags
  for all to authenticated
  using (public.is_restaurant_admin(restaurant_id) or public.is_superadmin())
  with check (public.is_restaurant_admin(restaurant_id) or public.is_superadmin());

-- =============================================================================
-- sessions  (sin escritura directa: se crean por función SECURITY DEFINER en B4)
-- =============================================================================
alter table public.sessions enable row level security;
grant select on public.sessions to authenticated;

create policy sessions_select_staff on public.sessions
  for select to authenticated
  using (public.is_restaurant_staff(restaurant_id) or public.is_superadmin());

-- =============================================================================
-- orders  (sin escritura directa: se crean/actualizan por función en B3)
-- =============================================================================
alter table public.orders enable row level security;
grant select on public.orders to authenticated;

create policy orders_select_staff on public.orders
  for select to authenticated
  using (public.is_restaurant_staff(restaurant_id) or public.is_superadmin());

-- =============================================================================
-- order_items  (sin escritura directa: se crean por función en B3)
-- =============================================================================
alter table public.order_items enable row level security;
grant select on public.order_items to authenticated;

create policy order_items_select_staff on public.order_items
  for select to authenticated
  using (public.is_restaurant_staff(restaurant_id) or public.is_superadmin());

-- #############################################################################
-- # Origen: supabase/migrations/20260917130000_b3_functions.sql
-- #############################################################################

-- =============================================================================
-- Fase B3 — Lógica de negocio segura (funciones RPC)
-- Carta Digital · el cliente nunca escribe directo; opera a través de funciones
-- SECURITY DEFINER que validan todo del lado del servidor.
--
-- Códigos de error (para que el frontend pueda distinguir cada caso):
--   P0001 sesión inválida        P0006 cantidad inválida
--   P0002 sesión expirada        P0007 producto inexistente/no disponible
--   P0003 restaurante inactivo   P0008 pedido inexistente
--   P0004 pedidos deshabilitados P0009 sin permiso para cambiar estado
--   P0005 pedido sin productos
-- =============================================================================

-- -----------------------------------------------------------------------------
-- create_order — crea un pedido a partir de una sesión + lista de productos.
-- p_items: jsonb array de { "product_id": uuid, "quantity": int }.
-- El precio y el total SIEMPRE se calculan desde la base; se ignora cualquier
-- precio que venga del cliente.
-- -----------------------------------------------------------------------------
create or replace function public.create_order(
  p_session_token uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session    public.sessions;
  v_restaurant public.restaurants;
  v_item       jsonb;
  v_product    public.products;
  v_product_id uuid;
  v_quantity   integer;
  v_order_id   uuid;
  v_line_total numeric(10,2);
  v_total      numeric(10,2) := 0;
  v_count      integer := 0;
begin
  -- 1. Sesión válida y no expirada
  select * into v_session from public.sessions s where s.token = p_session_token;
  if not found then
    raise exception 'Sesión inválida.' using errcode = 'P0001';
  end if;
  if v_session.expires_at <= now() then
    raise exception 'La sesión expiró. Escaneá la mesa nuevamente.' using errcode = 'P0002';
  end if;

  -- 2. Restaurante activo y con pedidos habilitados
  select * into v_restaurant from public.restaurants r where r.id = v_session.restaurant_id;
  if not found or v_restaurant.is_active = false then
    raise exception 'El restaurante no está disponible.' using errcode = 'P0003';
  end if;
  if v_restaurant.orders_enabled = false then
    raise exception 'Los pedidos desde la mesa están deshabilitados.' using errcode = 'P0004';
  end if;

  -- 3. Debe haber al menos un producto
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido no tiene productos.' using errcode = 'P0005';
  end if;

  -- 4. Cabecera del pedido (total provisorio 0, se completa al final)
  insert into public.orders (restaurant_id, table_id, session_id, status, total)
  values (v_session.restaurant_id, v_session.table_id, v_session.id, 'pendiente', 0)
  returning id into v_order_id;

  -- 5. Cada renglón: validar producto y calcular precio desde la base
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_quantity   := (v_item->>'quantity')::integer;

    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Cantidad inválida para un producto.' using errcode = 'P0006';
    end if;

    -- El producto debe ser de ESTE restaurante y estar disponible
    select * into v_product from public.products p
    where p.id = v_product_id
      and p.restaurant_id = v_session.restaurant_id
      and p.is_available = true;
    if not found then
      raise exception 'Un producto no existe o no está disponible.' using errcode = 'P0007';
    end if;

    v_line_total := v_product.price * v_quantity;
    v_total := v_total + v_line_total;

    insert into public.order_items
      (restaurant_id, order_id, product_id, product_name, unit_price, quantity, line_total)
    values
      (v_session.restaurant_id, v_order_id, v_product.id, v_product.name,
       v_product.price, v_quantity, v_line_total);

    v_count := v_count + 1;
  end loop;

  -- 6. Total real calculado por el servidor
  update public.orders set total = v_total where id = v_order_id;

  return jsonb_build_object(
    'order_id',   v_order_id,
    'status',     'pendiente',
    'total',      v_total,
    'item_count', v_count
  );
end;
$$;

grant execute on function public.create_order(uuid, jsonb) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- set_order_status — cambia el estado de un pedido. Solo staff (admin/cocina)
-- de ese restaurante, o superadmin. El cliente no puede llamarla.
-- -----------------------------------------------------------------------------
create or replace function public.set_order_status(
  p_order_id uuid,
  p_status   public.order_status
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders;
begin
  select * into v_order from public.orders o where o.id = p_order_id;
  if not found then
    raise exception 'El pedido no existe.' using errcode = 'P0008';
  end if;

  if not (public.is_restaurant_staff(v_order.restaurant_id) or public.is_superadmin()) then
    raise exception 'No tenés permiso para cambiar el estado de este pedido.' using errcode = 'P0009';
  end if;

  update public.orders set status = p_status where id = p_order_id;

  return jsonb_build_object('order_id', p_order_id, 'status', p_status);
end;
$$;

-- Solo usuarios logueados pueden intentar cambiar estados (el rol se valida adentro).
grant execute on function public.set_order_status(uuid, public.order_status) to authenticated;

-- #############################################################################
-- # Origen: supabase/migrations/20260917140000_b4_nfc_sessions.sql
-- #############################################################################

-- =============================================================================
-- Fase B4 — Sesiones temporales y NFC
-- Carta Digital · resolver el tag NFC/QR y abrir una sesión con expiración;
-- reasignar un tag a otra mesa sin tocar el chip físico.
--
-- Códigos de error:
--   P0101 tag inexistente / código inválido
--   P0102 tag desactivado
--   P0103 tag sin mesa asignada
--   P0104 restaurante inactivo
--   P0105 sin permiso para reasignar (no es admin del restaurante)
--   P0106 mesa destino no pertenece al restaurante del tag
-- =============================================================================

-- Duración de la sesión configurable por restaurante (minutos). Por defecto 2 horas.
alter table public.restaurants
  add column session_ttl_minutes integer not null default 120
  check (session_ttl_minutes > 0);

-- -----------------------------------------------------------------------------
-- resolve_nfc_tag — resuelve el código escaneado y abre una sesión temporal.
-- La usa el cliente (rol anon). Devuelve el token de sesión + datos para la UI.
-- -----------------------------------------------------------------------------
create or replace function public.resolve_nfc_tag(p_tag_uid text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tag        public.nfc_tags;
  v_restaurant public.restaurants;
  v_table      public.tables;
  v_session_id uuid;
  v_token      uuid;
  v_expires    timestamptz;
begin
  select * into v_tag from public.nfc_tags t where t.tag_uid = p_tag_uid;
  if not found then
    raise exception 'El código escaneado no es válido.' using errcode = 'P0101';
  end if;
  if v_tag.is_active = false then
    raise exception 'Este código está desactivado.' using errcode = 'P0102';
  end if;
  if v_tag.table_id is null then
    raise exception 'Este código no está asignado a ninguna mesa.' using errcode = 'P0103';
  end if;

  select * into v_restaurant from public.restaurants r where r.id = v_tag.restaurant_id;
  if not found or v_restaurant.is_active = false then
    raise exception 'El restaurante no está disponible.' using errcode = 'P0104';
  end if;

  select * into v_table from public.tables tb where tb.id = v_tag.table_id;

  v_expires := now() + make_interval(mins => v_restaurant.session_ttl_minutes);

  insert into public.sessions (restaurant_id, table_id, nfc_tag_id, expires_at)
  values (v_tag.restaurant_id, v_tag.table_id, v_tag.id, v_expires)
  returning id, token into v_session_id, v_token;

  return jsonb_build_object(
    'session_token', v_token,
    'expires_at',    v_expires,
    'restaurant',    jsonb_build_object('id', v_restaurant.id, 'name', v_restaurant.name, 'slug', v_restaurant.slug),
    'table',         jsonb_build_object('id', v_table.id, 'label', v_table.label)
  );
end;
$$;

grant execute on function public.resolve_nfc_tag(text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- reassign_nfc_tag — reasigna un tag a otra mesa del mismo restaurante.
-- Solo el admin de ese restaurante (o superadmin).
-- -----------------------------------------------------------------------------
create or replace function public.reassign_nfc_tag(p_tag_id uuid, p_table_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tag   public.nfc_tags;
  v_table public.tables;
begin
  select * into v_tag from public.nfc_tags t where t.id = p_tag_id;
  if not found then
    raise exception 'El tag no existe.' using errcode = 'P0101';
  end if;

  if not (public.is_restaurant_admin(v_tag.restaurant_id) or public.is_superadmin()) then
    raise exception 'No tenés permiso para reasignar este tag.' using errcode = 'P0105';
  end if;

  select * into v_table from public.tables tb
    where tb.id = p_table_id and tb.restaurant_id = v_tag.restaurant_id;
  if not found then
    raise exception 'La mesa destino no pertenece a este restaurante.' using errcode = 'P0106';
  end if;

  update public.nfc_tags set table_id = p_table_id where id = p_tag_id;

  return jsonb_build_object('tag_id', p_tag_id, 'table_id', p_table_id, 'table_label', v_table.label);
end;
$$;

grant execute on function public.reassign_nfc_tag(uuid, uuid) to authenticated;

-- #############################################################################
-- # Origen: supabase/migrations/20260917150000_b5_realtime.sql
-- #############################################################################

-- =============================================================================
-- Fase B5 — Realtime (tiempo real)
-- Carta Digital · activa la transmisión de cambios en orders y order_items.
--
-- La segmentación por restaurante NO se programa aquí: Realtime (Postgres
-- Changes) respeta las políticas RLS de la Fase B2, así que cada cliente
-- suscripto solo recibe los cambios de las filas que su rol puede ver.
--
-- REPLICA IDENTITY FULL: hace que los eventos de UPDATE/DELETE incluyan la fila
-- completa (necesario para que RLS pueda evaluarlos y para que el frontend
-- reciba todas las columnas del cambio).
-- =============================================================================

alter table public.orders      replica identity full;
alter table public.order_items replica identity full;

-- Agregar las tablas a la publicación de Realtime de Supabase (idempotente).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'order_items'
  ) then
    alter publication supabase_realtime add table public.order_items;
  end if;
end $$;
