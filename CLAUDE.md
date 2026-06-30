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
     ├── Tool: resumen_periodo                → sub-workflow
     ├── Tool: eliminar_gasto                 → sub-workflow
     ├── Tool: editar_gasto                   → sub-workflow
     ├── Tool: buscar_gastos                  → sub-workflow
     ├── Tool: comparar_periodos              → sub-workflow
     ├── Tool: definir_presupuesto            → sub-workflow
     └── Tool: consultar_presupuestos         → sub-workflow
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

CREATE TABLE IF NOT EXISTS presupuestos (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) NOT NULL REFERENCES usuarios(phone_number),
    categoria VARCHAR(50) NOT NULL,
    monto_limite DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (phone_number, categoria)
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
- **Logic**: INSERT into `gastos`, return the new `id`. Then checks the category's budget for the current month (`Postgres: Check Presupuesto`) and a Code node appends an automatic warning to the output if the category is near (≥80%) or over its limit.
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

### `eliminar_gasto`
- **Input**: `phone_number`, `gasto_id` (number)
- **Logic**: DELETE from `gastos` WHERE id AND phone_number match, RETURNING deleted row.
- **When called**: After showing the user their expenses (via `listar_gastos`) and getting explicit confirmation of which ID to delete.

### `editar_gasto`
- **Input**: `phone_number`, `gasto_id` (number), `nuevo_monto` (string), `nueva_categoria` (string), `nueva_descripcion` (string)
- **Logic**: UPDATE `gastos` using CASE WHEN to only change non-empty fields. RETURNING updated row.
- **When called**: After showing expenses with IDs, user specifies which field(s) to change. Pass empty string `''` for fields that don't change.

### `buscar_gastos`
- **Input**: `phone_number`, `categoria` (string), `descripcion` (string), `fecha_desde` (string, YYYY-MM-DD), `fecha_hasta` (string, YYYY-MM-DD)
- **Logic**: Dynamic WHERE clause built from non-empty filters. ILIKE for descripcion. LIMIT 20.
- **When called**: When user wants to find specific expenses by category, description keyword, or date range. Pass empty string for unused filters.

### `comparar_periodos`
- **Input**: `phone_number`, `periodo1` (string), `periodo2` (string)
- **Logic**: UNION ALL query comparing totals by category for two periods. Valid periods: `hoy`, `ayer`, `semana`, `semana_pasada`, `mes`, `mes_pasado`.
- **When called**: When user wants to compare spending between two time periods.

### `definir_presupuesto`
- **Input**: `phone_number`, `categoria` (string), `monto_limite` (number)
- **Logic**: `INSERT INTO presupuestos ... ON CONFLICT (phone_number, categoria) DO UPDATE SET monto_limite = EXCLUDED.monto_limite`. Creates or updates the monthly limit for a category.
- **When called**: When the user wants to set or change how much they can spend per month in a category.

### `consultar_presupuestos`
- **Input**: `phone_number`
- **Logic**: SELECT each budget for the user with the amount spent in the current month (correlated subquery on `gastos`), formatted in a Code node with % used, remaining, and a near/over marker. Returns a friendly message if no budgets are defined.
- **When called**: When the user asks about their budgets or how much they have left.
- **Note**: The proactive over/near-limit warning at registration time is handled inside `registrar_gasto`, not here.

## Agent behavior rules (system prompt)

These rules must be in the AI Agent's system prompt:

1. Always call `verificar_o_registrar_usuario` before any expense operation if the user hasn't been confirmed yet in this session.
2. When the user mentions an expense, extract `monto`, `categoria`, and `descripcion` from the message. If `monto` or `categoria` are missing, ask. Never ask for `descripcion` — if not mentioned, pass empty string.
3. Always show a confirmation summary and wait for explicit "sí" before calling `registrar_gasto`.
4. Never invent categories — use only the predefined list.
5. Respond always in Spanish, concise and friendly.
6. For `listar_gastos`, show expenses with their IDs so the user can reference them for edit/delete.
7. For `eliminar_gasto`, first show expenses via `listar_gastos`, confirm which ID to delete, then call the tool.
8. For `editar_gasto`, first show expenses via `listar_gastos`, ask what to change, pass only changed fields (empty string for unchanged).
9. For `buscar_gastos`, filter by category, description (partial match), and/or date range (YYYY-MM-DD). Pass empty string for unused filters.
10. For `comparar_periodos`, valid periods: hoy, ayer, semana, semana_pasada, mes, mes_pasado.
11. If the user mentions multiple expenses in one message ("gasté 500 en comida, 1200 en nafta y 300 en café"), extract them all, show a single numbered summary, and ask for one confirmation. After "sí", call `registrar_gasto` once per expense (one tool call each). If any expense is missing `monto` or `categoria`, ask only for that before confirming. At the end, confirm how many were registered and the total.
12. For `definir_presupuesto`, set/update a monthly budget per category ("poné un presupuesto de 50000 en Comida").
13. For `consultar_presupuestos`, show budget status (spent this month vs limit per category). `registrar_gasto` already appends an automatic warning when a category is near (≥80%) or over its limit — no extra tool call is needed for that warning.

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
| `workflows/main-workflow.json` | Main entry point: Chat Trigger → AI Agent + 10 tools |
| `workflows/sub-verificar-usuario.json` | Check/register user by phone number |
| `workflows/sub-registrar-gasto.json` | INSERT expense with optional descripcion |
| `workflows/sub-listar-gastos.json` | SELECT last N expenses with category subtotals |
| `workflows/sub-resumen-periodo.json` | Totals by category for hoy/semana/mes |
| `workflows/sub-eliminar-gasto.json` | DELETE expense by ID |
| `workflows/sub-editar-gasto.json` | UPDATE expense fields selectively |
| `workflows/sub-buscar-gastos.json` | Search expenses with dynamic filters |
| `workflows/sub-comparar-periodos.json` | Compare spending between two periods |
| `workflows/sub-definir-presupuesto.json` | Upsert monthly budget limit per category |
| `workflows/sub-consultar-presupuestos.json` | List budgets with current-month spending + status |

**After importing `main-workflow.json`:**
1. Re-link credential `OpenAi Model - Aesthetic` on the OpenAI Chat Model node.
2. In the AI Agent system prompt, replace `+5491112345678` with the real phone number.
3. The 8 tool nodes have empty workflow references — link each to its sub-workflow once they are created.

**When migrating to WhatsApp:** replace the hardcoded phone number in the system prompt with `{{ $('WhatsApp Trigger').item.json.from }}` and swap the Chat Trigger for the WhatsApp trigger node.

## n8n credentials

| Credential name in n8n | ID | Used by |
|---|---|---|
| `OpenAi Model - Aesthetic` | `9vxsodMdLd5pKDr8` | OpenAI Chat Model node |
| `Postgres - Personal Assistant` | `TyHuDs86VO4FrazA` | PostgreSQL nodes in sub-workflows |

## n8n workflow IDs (live instance)

| Workflow | ID |
|---|---|
| Main | `Yv3di4yVfG7DpgCJ` |
| Verificar Usuario | `qR5bTnFu5XBxPcTw` |
| Registrar Gasto | `EQIw3VEM4YH7p5Ag` |
| Listar Gastos | `sZ1vimeJWihfq4AW` |
| Resumen Periodo | `DnvMBIxiWBTkeh3P` |
| Eliminar Gasto | `UJvwXUI3Irgmie8O` |
| Editar Gasto | `CZpwqBbYF22al0Lb` |
| Buscar Gastos | `kUXaX660MVpUeUHq` |
| Comparar Periodos | `JZ12Df0n5C3h76aX` |
| Definir Presupuesto | `IukLwefYgco2zJCJ` |
| Consultar Presupuestos | `WkLWNk8CJQNFxKCO` |

n8n URL: `https://ferrarioasociados-n8n.site`
MCP clientId: `aHR0cHM6Ly9mZXJyYXJpb2Fzb2NpYWRvcy1uOG4uc2l0ZQ==`

## n8n version

Running **n8n 2.9.4** self-hosted. All AI Agent consolidation (Tools Agent as default), Simple Memory rename, and Call n8n Workflow Tool v2.0 input schema are already in place at this version.

If input parameters from the agent are not arriving in sub-workflows, ensure the sub-workflow defines its **Workflow Input Schema** in the Execute Sub-workflow Trigger node — the Call n8n Workflow Tool node pulls field definitions from there.

## Key patterns

- **Optional string fields in tools**: Use `$fromAI(...) ?? ''` in the Call n8n Workflow Tool to prevent null schema errors. Handle empty/null in sub-workflow SQL with `NULLIF(NULLIF('{{ $json.field }}', ''), 'null')`.
- **Optional UPDATE fields**: Use `CASE WHEN '{{ $json.field }}' IN ('', 'null') THEN original ELSE new_value END` pattern (see `sub-editar-gasto.json`).
- **Dynamic queries**: Build SQL in Code nodes when WHERE clause varies (see `sub-buscar-gastos.json`, `sub-comparar-periodos.json`).
- **Budget warning at registration**: `registrar_gasto` runs a `Check Presupuesto` query (always-output-data, so it emits a row even with no budget) → a Code node appends the over/near-limit warning. Reference the trigger explicitly (`$('Execute Sub-workflow Trigger')`) in the check query since the node's direct input is the INSERT result, not the trigger.
- **SERIAL sequence desync**: Inserting rows with an explicit `id` (e.g. manual rows in Supabase) does NOT advance the SERIAL sequence, causing later `duplicate key ... gastos_pkey` errors. Never specify `id` on manual inserts. To fix: `SELECT setval(pg_get_serial_sequence('gastos','id'), (SELECT MAX(id) FROM gastos));`

## Roadmap

See `PLAN.md` for detailed task checklist. Current status:
- **Phase 1** (core): Complete
- **Phase 1.5** (additional tools): Complete
- **Phase 2**: Migrate to WhatsApp (Meta API) — replace hardcoded `phone_number` with trigger data, add voice notes with Whisper
- **Phase 3**: Deploy via Docker + Caddy on existing VPS
