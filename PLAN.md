# Plan de desarrollo

## Fase 1 — Core del agente (n8n)

### Main workflow
- [x] Definir arquitectura y stack
- [x] Escribir CLAUDE.md con specs completas
- [x] Crear `workflows/main-workflow.json` e importar en n8n
- [x] Configurar credencial OpenAI en el nodo OpenAI Chat Model
- [x] Reemplazar número de teléfono hardcodeado en el system prompt

### Base de datos (Supabase)
- [x] Crear tabla `usuarios`  ← correr `sql/schema.sql` en Supabase → SQL Editor
- [x] Crear tabla `gastos`    ← ídem (mismo archivo)

### Sub-workflows (tools)
- [x] `verificar_o_registrar_usuario` — importar `workflows/sub-verificar-usuario.json`, linkear credencial Postgres, linkear en main workflow
- [x] `registrar_gasto` — INSERT en tabla gastos (`workflows/sub-registrar-gasto.json`)
- [x] `listar_gastos` — SELECT últimos N gastos con subtotal por categoría (`workflows/sub-listar-gastos.json`)
- [x] `resumen_periodo` — totales por hoy / semana / mes (`workflows/sub-resumen-periodo.json`)

### Pruebas end-to-end
- [ ] Flujo de registro de usuario nuevo  ← EN CURSO — ver bug abajo
- [ ] Flujo de registro de gasto con confirmación
- [ ] Flujo de listado de gastos
- [ ] Flujo de resumen por período

#### Bug activo — registro de usuario nuevo
**Error:** `Received tool input did not match expected schema ✖ Expected string, received object → at input`

**Diagnóstico:** El AI Agent llama a `verificar_o_registrar_usuario` y pasa `nombre` o `apellido`
como objeto en lugar de string. Ocurre cuando el usuario proporciona nombre y apellido
luego de que el agente se los solicita.

**Causa probable:** El `$fromAI()` en el nodo "Tool: Verificar Usuario" del main workflow
genera un schema donde `nombre` y `apellido` son opcionales. Cuando el LLM los incluye,
n8n puede estar envolviendo el valor en un objeto en lugar de pasarlo como string plano.

**Fixes ya aplicados (pendiente de verificar si resuelven):**
- IF node del sub-workflow: cambiado operador de `notEquals ""` a `isNotEmpty`
- System prompt: regla 2 actualizada para que el agente extraiga nombre/apellido por separado

**Próximo paso a investigar:**
- Revisar el nodo "Tool: Verificar Usuario" en el main workflow → pestaña Output de una
  ejecución fallida para ver exactamente qué objeto está pasando el LLM
- Posible fix: cambiar `$fromAI('nombre', ..., 'string')` por un schema más estricto
  o usar un solo campo `nombre_completo` y splitear en el sub-workflow

---

## Fase 2 — WhatsApp

- [ ] Reemplazar Chat Trigger por WhatsApp Trigger
- [ ] Reemplazar número hardcodeado con `{{ $('WhatsApp Trigger').item.json.from }}`
  - Nota: en sub-workflows, `$json.phone_number` viene del trigger, no del sessionId. Ya está diseñado así.
- [ ] Configurar Meta API / webhook

---

## Fase 3 — Deploy

- [ ] Dockerizar (n8n ya corre en el VPS con Docker + Caddy)
- [ ] Configurar variables de entorno en producción

---

## Backlog

- [ ] Tool `resumen_por_categoria` — gráfico de torta por categoría
- [ ] Tool `comparar_meses` — comparar gasto entre dos meses
