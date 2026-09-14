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

Esto crea todas las tablas, tipos, funciones y (a partir de B2) las políticas
RLS en el proyecto remoto, en el orden de los archivos de `supabase/migrations/`.

### 4. (Opcional) Entorno local con Docker

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
│   └── er-diagram.md     # diagrama ER (Mermaid)
├── supabase/
│   ├── migrations/       # migraciones SQL versionadas
│   └── seed.sql          # datos de prueba (Fase B6)
├── .env.example
└── README.md
```

## Migraciones

| Archivo                              | Fase | Contenido                          |
|--------------------------------------|------|------------------------------------|
| `20260911120000_b1_core_schema.sql`  | B1   | Tablas, tipos enum, FKs, triggers  |

_(Se irán agregando: B2 RLS, B3 funciones RPC, B4 NFC/sesiones, B5 Realtime.)_

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
