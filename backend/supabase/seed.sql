-- =============================================================================
-- Seed de datos de prueba (Fase B6) — Restaurante ficticio "Bar Lindo"
--
-- Es idempotente: usa IDs fijos + ON CONFLICT DO NOTHING, así que se puede
-- correr varias veces sin duplicar datos.
--
-- Cómo aplicarlo al proyecto remoto: pegar este contenido en el SQL Editor de
-- Supabase y ejecutarlo (el SQL Editor corre como administrador y omite RLS).
-- Los USUARIOS de prueba (superadmin/admin/cocina) NO están acá: se crean desde
-- Authentication > Users y se conectan con sus roles en un paso aparte.
-- =============================================================================

-- Restaurante --------------------------------------------------------------
insert into public.restaurants (id, name, slug, is_active, orders_enabled, session_ttl_minutes)
values ('b0000000-0000-0000-0000-000000000001', 'Bar Lindo', 'bar-lindo', true, true, 120)
on conflict (id) do nothing;

-- Mesas (5) ----------------------------------------------------------------
insert into public.tables (id, restaurant_id, label) values
  ('b0000000-0000-0000-0000-000000000101', 'b0000000-0000-0000-0000-000000000001', 'Mesa 1'),
  ('b0000000-0000-0000-0000-000000000102', 'b0000000-0000-0000-0000-000000000001', 'Mesa 2'),
  ('b0000000-0000-0000-0000-000000000103', 'b0000000-0000-0000-0000-000000000001', 'Mesa 3'),
  ('b0000000-0000-0000-0000-000000000104', 'b0000000-0000-0000-0000-000000000001', 'Mesa 4'),
  ('b0000000-0000-0000-0000-000000000105', 'b0000000-0000-0000-0000-000000000001', 'Mesa 5')
on conflict (id) do nothing;

-- Categorías (4) -----------------------------------------------------------
insert into public.categories (id, restaurant_id, name, sort_order) values
  ('b0000000-0000-0000-0000-000000000201', 'b0000000-0000-0000-0000-000000000001', 'Bebidas', 1),
  ('b0000000-0000-0000-0000-000000000202', 'b0000000-0000-0000-0000-000000000001', 'Entradas', 2),
  ('b0000000-0000-0000-0000-000000000203', 'b0000000-0000-0000-0000-000000000001', 'Platos principales', 3),
  ('b0000000-0000-0000-0000-000000000204', 'b0000000-0000-0000-0000-000000000001', 'Postres', 4)
on conflict (id) do nothing;

-- Productos (11) -----------------------------------------------------------
-- Nota: "Rabas" y "Cerveza artesanal" quedan como NO disponibles para probar
-- que no aparecen en el menú del cliente.
insert into public.products
  (id, restaurant_id, category_id, name, description, price, is_available, sort_order)
values
  -- Bebidas
  ('b0000000-0000-0000-0000-000000000301', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000201', 'Coca-Cola 500ml', 'Gaseosa línea Coca-Cola', 1500.00, true, 1),
  ('b0000000-0000-0000-0000-000000000302', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000201', 'Agua mineral 500ml', 'Con o sin gas', 1000.00, true, 2),
  ('b0000000-0000-0000-0000-000000000303', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000201', 'Limonada', 'Con menta y jengibre', 1800.00, true, 3),
  ('b0000000-0000-0000-0000-000000000304', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000201', 'Cerveza artesanal', 'Pinta rubia', 2500.00, false, 4),
  -- Entradas
  ('b0000000-0000-0000-0000-000000000305', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000202', 'Papas fritas', 'Porción para compartir', 3000.00, true, 1),
  ('b0000000-0000-0000-0000-000000000306', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000202', 'Rabas', 'A la provenzal', 5500.00, false, 2),
  ('b0000000-0000-0000-0000-000000000307', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000202', 'Empanadas (x3)', 'Carne, pollo o jamón y queso', 3600.00, true, 3),
  -- Platos principales
  ('b0000000-0000-0000-0000-000000000308', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000203', 'Milanesa napolitana', 'Con guarnición', 8500.00, true, 1),
  ('b0000000-0000-0000-0000-000000000309', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000203', 'Hamburguesa completa', 'Con papas', 7000.00, true, 2),
  ('b0000000-0000-0000-0000-00000000030a', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000203', 'Pizza muzzarella', '8 porciones', 6500.00, true, 3),
  -- Postres
  ('b0000000-0000-0000-0000-00000000030b', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000204', 'Flan casero', 'Con dulce de leche y crema', 2800.00, true, 1)
on conflict (id) do nothing;

-- Tags NFC (uno por mesa) --------------------------------------------------
insert into public.nfc_tags (id, tag_uid, restaurant_id, table_id, is_active) values
  ('b0000000-0000-0000-0000-000000000401', 'bar-lindo-mesa-1', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000101', true),
  ('b0000000-0000-0000-0000-000000000402', 'bar-lindo-mesa-2', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000102', true),
  ('b0000000-0000-0000-0000-000000000403', 'bar-lindo-mesa-3', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000103', true),
  ('b0000000-0000-0000-0000-000000000404', 'bar-lindo-mesa-4', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000104', true),
  ('b0000000-0000-0000-0000-000000000405', 'bar-lindo-mesa-5', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000105', true)
on conflict (id) do nothing;
