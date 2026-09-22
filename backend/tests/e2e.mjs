// =============================================================================
// Prueba end-to-end contra el backend REAL de Supabase (Fase B6).
// Simula el recorrido completo sin ninguna interfaz gráfica, hablándole a la
// base por internet igual que lo hará la app.
//
// Cómo correrla (desde la carpeta backend/):
//   1. Completar backend/.env con SUPABASE_URL, SUPABASE_ANON_KEY y COCINA_PASSWORD.
//   2. npm install        (una sola vez, instala @supabase/supabase-js)
//   3. npm run test:e2e
// =============================================================================
import { createClient } from '@supabase/supabase-js';

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const COCINA_EMAIL = 'cocina@barlindo.test';
const COCINA_PASSWORD = process.env.COCINA_PASSWORD;

const faltan = [];
if (!URL) faltan.push('SUPABASE_URL');
if (!ANON) faltan.push('SUPABASE_ANON_KEY');
if (!COCINA_PASSWORD) faltan.push('COCINA_PASSWORD');
if (faltan.length) {
  console.error('Faltan variables en backend/.env: ' + faltan.join(', '));
  process.exit(1);
}

const fail = (m) => { console.error('\n❌ FALLO: ' + m); process.exit(1); };
const ok = (m) => console.log('✅ ' + m);

// IDs del seed "Bar Lindo"
const COCA = 'b0000000-0000-0000-0000-000000000301';      // 1500, disponible
const MILANESA = 'b0000000-0000-0000-0000-000000000308';  // 8500, disponible

const anon = createClient(URL, ANON, { auth: { persistSession: false } });

console.log('\n— Prueba end-to-end contra el backend real —\n');

// 1. Cliente escanea la Mesa 1 -> abre sesión
const { data: ses, error: e1 } = await anon.rpc('resolve_nfc_tag', { p_tag_uid: 'bar-lindo-mesa-1' });
if (e1) fail('resolve_nfc_tag devolvió error: ' + e1.message);
if (!ses?.session_token) fail('resolve_nfc_tag no devolvió session_token');
ok(`Escaneo OK: ${ses.restaurant.name} / ${ses.table.label} (sesión abierta).`);

// 2. Hace un pedido real: 2 Coca (1500) + 1 Milanesa (8500) = 11500
const { data: ord, error: e2 } = await anon.rpc('create_order', {
  p_session_token: ses.session_token,
  p_items: [
    { product_id: COCA, quantity: 2 },
    { product_id: MILANESA, quantity: 1 }
  ]
});
if (e2) fail('create_order devolvió error: ' + e2.message);
if (Number(ord.total) !== 11500) fail(`total esperado 11500, backend devolvió ${ord.total}`);
ok(`Pedido creado: total $${ord.total} calculado por el servidor (order_id ${ord.order_id}).`);

// 3. El cliente anónimo NO puede cambiar el estado
const { error: e3 } = await anon.rpc('set_order_status', { p_order_id: ord.order_id, p_status: 'en_proceso' });
if (!e3) fail('el cliente anónimo pudo cambiar el estado (no debería)');
ok(`Cliente anónimo bloqueado al cambiar estado (${e3.code || 'rechazado'}).`);

// 4. La cocina se loguea y sí puede cambiar el estado
const cocina = createClient(URL, ANON, { auth: { persistSession: false } });
const { error: eLogin } = await cocina.auth.signInWithPassword({ email: COCINA_EMAIL, password: COCINA_PASSWORD });
if (eLogin) fail('no se pudo loguear la cocina: ' + eLogin.message + ' (¿email confirmado y contraseña correcta?)');
ok('Cocina logueada correctamente.');

const { data: st, error: e4 } = await cocina.rpc('set_order_status', { p_order_id: ord.order_id, p_status: 'en_proceso' });
if (e4) fail('la cocina no pudo cambiar el estado: ' + e4.message);
if (st.status !== 'en_proceso') fail(`estado esperado en_proceso, quedó ${st.status}`);
ok(`Cocina cambió el pedido a "${st.status}".`);

// 5. La cocina ve el pedido en su restaurante (lectura con RLS)
const { data: pedidos, error: e5 } = await cocina.from('orders').select('id,status,total').eq('id', ord.order_id);
if (e5) fail('la cocina no pudo leer el pedido: ' + e5.message);
if (!pedidos?.length) fail('la cocina no ve su propio pedido (RLS mal configurado)');
ok('Cocina ve su pedido vía lectura directa (RLS correcto).');

await cocina.auth.signOut();
console.log('\n🎉 Prueba end-to-end completa: el backend real funciona de punta a punta.\n');
