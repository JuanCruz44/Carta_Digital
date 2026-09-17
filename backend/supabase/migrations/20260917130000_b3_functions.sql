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
