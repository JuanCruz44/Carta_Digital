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
