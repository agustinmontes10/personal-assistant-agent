# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Personal expenses assistant agent built in **n8n** (self-hosted). Users interact via Chat Trigger (migrating to WhatsApp in a future phase). The agent understands natural language, extracts expense data, confirms with the user before saving, and persists to PostgreSQL on Supabase. Multi-tenant: each user is identified by phone number.

## Stack

| Component | Technology |
|---|---|
| Orchestration | n8n self-hosted |
| AI Agent | n8n AI Agent node (Tools Agent, default since v1.82.0) |
| LLM | gpt-4o-mini via OpenAI credentials |
| Memory | Simple Memory node (formerly "Window Buffer Memory") |
| Database | PostgreSQL on Supabase (direct connection, no API) |
| Entry point (v1) | Chat Trigger node |
| Entry point (v2) | WhatsApp trigger (future) |

## Architecture

### Main workflow

```
[Chat Trigger]
     ↓
[AI Agent]  ←── Simple Memory (sessionId from Chat Trigger)
     ├── Tool: verificar_o_registrar_usuario  → sub-workflow
     ├── Tool: registrar_gasto                → sub-workflow
     ├── Tool: listar_gastos                  → sub-workflow
     └── Tool: resumen_periodo               → sub-workflow
```

Each tool is a **Call n8n Workflow Tool** node pointing to a dedicated sub-workflow. This keeps the main workflow clean and makes each operation independently testable and debuggable (each sub-workflow has its own execution logs in n8n).

### Sub-workflows

Each sub-workflow uses **Execute Sub-workflow Trigger** as its entry point and receives parameters from the agent via the tool's input schema. The sub-workflow must define its **Workflow Input Schema** so the Call n8n Workflow Tool node can pull in the fields automatically.

Sub-workflows return plain text that the agent formats for the user.

### Tool descriptions (critical for LLM behavior)

Each tool's description in the Call n8n Workflow Tool node must be precise — the LLM uses it to decide when to call each tool. Write them in imperative form describing *when* to use the tool, not what it does internally.

### Memory / session

- Use **Simple Memory** node (not the legacy Window Buffer Memory).
- Set `Session ID` to "Connected Chat Trigger Node" so it auto-reads from the trigger.
- Connect the same Simple Memory node to both the Chat Trigger and the AI Agent.

> **Known issue**: The `sessionId` from the Chat Trigger does **not** pass automatically to sub-workflow tools. Always send `phone_number` as an explicit parameter in each tool call so sub-workflows can identify the user without relying on sessionId injection.

## Multi-tenancy

Users are identified by `phone_number` (string). In v1, this value is hardcoded directly in the Chat Trigger node (easy to replace with a dynamic value when migrating to WhatsApp).

On first contact, the agent detects the user is not registered and calls `verificar_o_registrar_usuario`, which asks for name and last name before proceeding.

## Database schema (PostgreSQL on Supabase)

```sql
CREATE TABLE IF NOT EXISTS usuarios (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS gastos (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) NOT NULL REFERENCES usuarios(phone_number),
    monto DECIMAL(10, 2) NOT NULL,
    categoria VARCHAR(50) NOT NULL,
    descripcion TEXT,
    fecha TIMESTAMP DEFAULT NOW()
);
```

Valid categories: `Comida`, `Transporte`, `Servicios`, `Salud`, `Entretenimiento`, `Ropa`, `Tecnología`, `Otros`

## Tool specifications

### `verificar_o_registrar_usuario`
- **Input**: `phone_number` (string)
- **Logic**: SELECT from `usuarios`. If found → return user data. If not found → return a flag so the agent asks for name + last name, then INSERT.
- **When called**: At the start of every conversation when the user is unknown, or whenever the agent needs to confirm who the user is.

### `registrar_gasto`
- **Input**: `phone_number`, `monto` (number), `categoria` (string), `descripcion` (string)
- **Logic**: INSERT into `gastos`, return the new `id`.
- **When called**: Only after explicit user confirmation ("sí" or equivalent). Never on first mention of an expense.

### `listar_gastos`
- **Input**: `phone_number`, `cantidad` (number, default 5)
- **Logic**: SELECT last N rows ordered by `fecha DESC`, return formatted list + subtotal per category.
- **Output format**: Each row on its own line, then a summary by category at the bottom.

### `resumen_periodo`
- **Input**: `phone_number`, `periodo` (string: `"hoy"` | `"semana"` | `"mes"`)
- **Logic**:
  - `hoy` → WHERE fecha::date = CURRENT_DATE
  - `semana` → WHERE fecha >= NOW() - INTERVAL '7 days' (rolling 7 days, not Mon–Sun)
  - `mes` → WHERE DATE_TRUNC('month', fecha) = DATE_TRUNC('month', NOW())
- **Output format**: Total spent + breakdown by category.

## Agent behavior rules (system prompt)

These rules must be in the AI Agent's system prompt:

1. Always call `verificar_o_registrar_usuario` before any expense operation if the user hasn't been confirmed yet in this session.
2. When the user mentions an expense, extract `monto`, `categoria`, and `descripcion` from the message. If any field is missing or ambiguous, ask for it before proceeding.
3. Always show a confirmation summary and wait for explicit "sí" before calling `registrar_gasto`.
4. Never invent categories — use only the predefined list.
5. Respond always in Spanish, concise and friendly.

## Confirmation flow

```
User: "gasté 800 en el colectivo"
Agent: [calls preparación mentally, shows summary]
       "Te confirmo:
        • Monto: $800
        • Categoría: Transporte
        • Descripción: Colectivo
        ¿Lo registro? (sí/no)"
User: "sí"
Agent: [calls registrar_gasto] "✓ Gasto registrado."
```

The confirmation state is maintained via Simple Memory — the agent remembers the pending expense in the conversation window.

## Workflows directory

All n8n workflow JSONs live in `workflows/`. Import them via **Settings → Import from file** (or `Ctrl+Shift+I` in the editor).

| File | Description |
|---|---|
| `workflows/main-workflow.json` | Main entry point: Chat Trigger → AI Agent + 4 tools |

**After importing `main-workflow.json`:**
1. Re-link credential `OpenAi Model - Aesthetic` on the OpenAI Chat Model node.
2. In the AI Agent system prompt, replace `+5491112345678` with the real phone number.
3. The 4 tool nodes have empty workflow references — link each to its sub-workflow once they are created.

**When migrating to WhatsApp:** replace the hardcoded phone number in the system prompt with `{{ $('WhatsApp Trigger').item.json.from }}` and swap the Chat Trigger for the WhatsApp trigger node.

## n8n credentials

| Credential name in n8n | Used by |
|---|---|
| `OpenAi Model - Aesthetic` | OpenAI Chat Model node |
| `Postgres - Personal Assistant` | PostgreSQL nodes in sub-workflows |

## n8n version

Running **n8n 2.9.4** self-hosted. All AI Agent consolidation (Tools Agent as default), Simple Memory rename, and Call n8n Workflow Tool v2.0 input schema are already in place at this version.

If input parameters from the agent are not arriving in sub-workflows, ensure the sub-workflow defines its **Workflow Input Schema** in the Execute Sub-workflow Trigger node — the Call n8n Workflow Tool node pulls field definitions from there.

## Roadmap

1. Add `ver_gastos_del_mes`, `resumen_por_categoria`, `comparar_meses` tools
2. Migrate trigger from Chat to WhatsApp (Meta API) — replace hardcoded `phone_number` with trigger data
3. Deploy via Docker + Caddy on existing VPS (n8n already running there)
