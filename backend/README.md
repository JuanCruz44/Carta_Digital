# Backend — Carta Digital (Supabase / PostgreSQL)

Base de datos, seguridad (RLS), lógica de negocio (funciones RPC) y Realtime del
sistema de carta digital. El esquema se maneja con **migraciones versionadas**
en `supabase/migrations/`; el dashboard de Supabase no es la fuente de verdad.

## Requisitos

- [Node.js](https://nodejs.org/) (para usar el CLI vía `npx`, ya instalado).
- Una cuenta y un proyecto en [Supabase](https://supabase.com/).
- **Opcional**: [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  para levantar Postgres local con `supabase start`. Sin Docker, se trabaja
  directo contra el proyecto remoto con `supabase db push` (ver más abajo).

> El CLI de Supabase se usa con `npx supabase <comando>` (no requiere instalación
> global). La primera vez descarga el binario.

## Puesta en marcha desde cero

### 1. Crear el proyecto en Supabase

1. En [app.supabase.com](https://app.supabase.com/) crear un proyecto nuevo
   (elegir región cercana y guardar la contraseña de la base de datos).
2. En **Project Settings > API** copiar `Project URL`, la `anon key` y la
   `service_role key`.
3. Copiar `.env.example` a `.env` y completar los valores.

```bash
cp backend/.env.example backend/.env
```

### 2. Vincular el repo con el proyecto remoto

Desde la carpeta `backend/`:

```bash
npx supabase login            # abre el navegador para autenticar el CLI
npx supabase link --project-ref TU_PROJECT_REF
```

### 3. Aplicar las migraciones al proyecto remoto

```bash
npx supabase db push
```

Esto crea todas las tablas, tipos, funciones, políticas RLS y Realtime en el
proyecto remoto, en el orden de los archivos de `supabase/migrations/`.

### 4. Cargar los datos de prueba ("Bar Lindo")

`db push` crea la estructura pero no carga datos. Para el seed, abrir el
**SQL Editor** de Supabase, pegar el contenido de `supabase/seed.sql` y
ejecutarlo. Es idempotente (se puede correr varias veces).

### 5. Crear los usuarios de prueba

1. En **Authentication > Users > Add user > Create new user**, crear (con
   "Auto Confirm User" activado):
   - `superadmin@barlindo.test`, `admin@barlindo.test`, `cocina@barlindo.test`.
2. Conectar los roles: pegar y ejecutar `supabase/seed_users.sql` en el SQL Editor.

### 6. Prueba end-to-end contra el backend real

Verifica el recorrido completo (escaneo → sesión → pedido → cambio de estado)
como lo haría la app, respetando RLS y permisos.

```bash
cd backend
# completar SUPABASE_URL, SUPABASE_ANON_KEY y COCINA_PASSWORD en backend/.env
npm install          # instala @supabase/supabase-js (una sola vez)
npm run test:e2e
```

### 7. (Opcional) Entorno local con Docker

Si más adelante instalás Docker Desktop y querés probar cambios en local antes
de tocar el remoto:

```bash
npx supabase start            # levanta Postgres + servicios en local
npx supabase db reset         # aplica todas las migraciones + seed en local
```

## Estructura

```
backend/
├── docs/
│   ├── conventions.md    # convenciones de nombres, tipos, timestamps (B0)
│   ├── er-diagram.md     # diagrama ER final (Mermaid)
│   ├── api-rpc.md        # manual de consumo para el frontend (funciones + RLS)
│   └── schema.sql        # export consolidado de todo el esquema (solo lectura)
├── supabase/
│   ├── migrations/       # migraciones SQL versionadas (fuente de verdad)
│   ├── seed.sql          # datos de prueba "Bar Lindo" (Fase B6)
│   └── seed_users.sql    # asignación de roles a los usuarios de prueba
├── tests/
│   └── e2e.mjs           # prueba end-to-end contra el backend real
├── .env.example
├── package.json
└── README.md
```

## Migraciones

| Archivo                              | Fase | Contenido                              |
|--------------------------------------|------|----------------------------------------|
| `20260911120000_b1_core_schema.sql`  | B1   | Tablas, tipos enum, FKs, triggers      |
| `20260917120000_b2_rls.sql`          | B2   | RLS, roles y funciones ayudantes       |
| `20260917130000_b3_functions.sql`    | B3   | RPC: crear pedido, cambiar estado      |
| `20260917140000_b4_nfc_sessions.sql` | B4   | Resolver NFC, sesiones, reasignar tag  |
| `20260917150000_b5_realtime.sql`     | B5   | Realtime en orders y order_items       |

El `docs/schema.sql` es una vista consolidada de estas migraciones; la fuente de
verdad son los archivos de `supabase/migrations/`.

## Crear una migración nueva

```bash
npx supabase migration new nombre_descriptivo
```

Se edita el archivo generado en `supabase/migrations/` y se aplica con
`npx supabase db push`. **Nunca** se edita una migración ya aplicada.

## Roles y seguridad

- Usuarios con cuenta (`superadmin`, `admin`, `kitchen`) → **Supabase Auth**.
- Cliente de mesa → **sin cuenta**, sesión temporal creada al resolver el NFC.
- El aislamiento entre restaurantes se garantiza con FKs compuestas
  `(restaurant_id, id)` + Row Level Security (Fase B2).
- El total de los pedidos y los cambios de estado se validan **en el servidor**
  (funciones RPC, Fase B3); nunca se confía en datos enviados por el cliente.

## Para el frontend

El manual de consumo del backend (funciones RPC, qué reciben y devuelven, lectura
de datos con RLS, Realtime y datos de prueba) está en
[`docs/api-rpc.md`](docs/api-rpc.md).
