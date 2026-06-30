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
- [x] Flujo de registro de usuario nuevo
- [x] Flujo de registro de gasto con confirmación
- [ ] Flujo de listado de gastos
- [ ] Flujo de resumen por período

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
