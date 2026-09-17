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
