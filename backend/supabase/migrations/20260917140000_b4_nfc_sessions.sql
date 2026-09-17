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
