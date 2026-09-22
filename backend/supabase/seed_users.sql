-- =============================================================================
-- Seed de USUARIOS de prueba (Fase B6) — asignación de roles
--
-- Los usuarios de Supabase Auth NO se crean con SQL: se crean primero desde el
-- panel (Authentication > Users > Add user > Create new user), con estos emails
-- y marcando "Auto Confirm User":
--
--     superadmin@barlindo.test   -> superadmin (global)
--     admin@barlindo.test        -> admin de Bar Lindo
--     cocina@barlindo.test       -> cocina de Bar Lindo
--
-- Al crearlos, el trigger handle_new_user (Fase B2) les crea el perfil en
-- public.users automáticamente. Después de crearlos, ejecutar este script en el
-- SQL Editor para conectarlos con sus roles. Es idempotente.
-- =============================================================================

-- Superadmin global
update public.users
   set is_superadmin = true
 where email = 'superadmin@barlindo.test';

-- Admin de Bar Lindo
insert into public.restaurant_users (restaurant_id, user_id, role)
select 'b0000000-0000-0000-0000-000000000001', u.id, 'admin'
from auth.users u
where u.email = 'admin@barlindo.test'
on conflict (restaurant_id, user_id) do nothing;

-- Cocina de Bar Lindo
insert into public.restaurant_users (restaurant_id, user_id, role)
select 'b0000000-0000-0000-0000-000000000001', u.id, 'kitchen'
from auth.users u
where u.email = 'cocina@barlindo.test'
on conflict (restaurant_id, user_id) do nothing;
