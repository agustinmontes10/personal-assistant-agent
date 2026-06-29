# Plan de desarrollo

## Fase 1 — Core del agente (n8n)

### Main workflow
- [x] Definir arquitectura y stack
- [x] Escribir CLAUDE.md con specs completas
- [x] Crear `workflows/main-workflow.json` e importar en n8n
- [ ] Configurar credencial OpenAI en el nodo OpenAI Chat Model
- [ ] Reemplazar número de teléfono hardcodeado en el system prompt

### Base de datos (Supabase)
- [ ] Crear tabla `usuarios`  ← correr `sql/schema.sql` en Supabase → SQL Editor
- [ ] Crear tabla `gastos`    ← ídem (mismo archivo)

### Sub-workflows (tools)
- [ ] `verificar_o_registrar_usuario` — importar `workflows/sub-verificar-usuario.json`, linkear credencial Postgres, linkear en main workflow
- [ ] `registrar_gasto` — INSERT en tabla gastos
- [ ] `listar_gastos` — SELECT últimos N gastos con subtotal por categoría
- [ ] `resumen_periodo` — totales por hoy / semana / mes

### Pruebas end-to-end
- [ ] Flujo de registro de usuario nuevo
- [ ] Flujo de registro de gasto con confirmación
- [ ] Flujo de listado de gastos
- [ ] Flujo de resumen por período

---

## Fase 2 — WhatsApp

- [ ] Reemplazar Chat Trigger por WhatsApp Trigger
- [ ] Reemplazar número hardcodeado con `{{ $('WhatsApp Trigger').item.json.from }}`
- [ ] Configurar Meta API / webhook

---

## Fase 3 — Deploy

- [ ] Dockerizar (n8n ya corre en el VPS con Docker + Caddy)
- [ ] Configurar variables de entorno en producción

---

## Backlog

- [ ] Tool `resumen_por_categoria` — gráfico de torta por categoría
- [ ] Tool `comparar_meses` — comparar gasto entre dos meses
