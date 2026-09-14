# Carta Digital

Sistema de gestión de atención al cliente para restaurantes y bares. El cliente
escanea un tag NFC (o QR) en la mesa, ve el menú digital y realiza pedidos que
llegan en tiempo real a la cocina y a la administración del local.

## Estructura del monorepo

```
.
├── backend/     # Base de datos + lógica de servidor (Supabase / PostgreSQL)
└── frontend/    # Aplicación web (Angular + Tailwind, PWA)
```

- **`backend/`** — a cargo de la Parte 1 (base de datos, RLS, funciones RPC,
  Realtime). Ver [`backend/README.md`](backend/README.md).
- **`frontend/`** — a cargo de la Parte 2 (Angular). Consume las funciones RPC
  documentadas por el backend.

## Roles del sistema

| Rol          | Alcance         | Cómo entra                                   |
|--------------|-----------------|----------------------------------------------|
| `superadmin` | Global          | Cuenta (Supabase Auth)                       |
| `admin`      | Por restaurante | Cuenta (Supabase Auth)                       |
| `kitchen`    | Por restaurante | Cuenta (Supabase Auth)                       |
| cliente      | Por sesión/mesa | Sin cuenta — sesión temporal creada vía NFC  |

## Estado

Proyecto en desarrollo. El backend se construye primero (Fases B0–B7) y el
frontend asume que el backend ya existe con datos de prueba y funciones RPC
documentadas (Fases F0–F10).
