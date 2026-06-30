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
- [x] Flujo de listado de gastos
- [x] Flujo de resumen por período

---

## Fase 1.5 — Funcionalidades adicionales

### Nuevas tools
- [x] `eliminar_gasto` — eliminar un gasto por ID o el último registrado (`workflows/sub-eliminar-gasto.json`)
- [x] `editar_gasto` — modificar monto, categoría o descripción de un gasto existente (`workflows/sub-editar-gasto.json`)
- [x] `presupuestos` — definir límite mensual por categoría y consultar estado
  - Implementado como dos tools: `definir_presupuesto` (`workflows/sub-definir-presupuesto.json`) y `consultar_presupuestos` (`workflows/sub-consultar-presupuestos.json`)
  - Tabla `presupuestos` agregada a `sql/schema.sql` (UNIQUE phone_number+categoria para upsert) — **pendiente: correr el SQL en Supabase**
  - El aviso al superar/acercarse al límite (≥80%) está integrado dentro de `registrar_gasto` (nodo Check Presupuesto + Code), automático tras cada registro
- [x] `buscar_gastos` — filtrar gastos por categoría, descripción o rango de fechas (`workflows/sub-buscar-gastos.json`)
- [x] `comparar_periodos` — comparar gasto total o por categoría entre dos períodos (`workflows/sub-comparar-periodos.json`)

### Mejoras al agente
- [x] Soporte para múltiples gastos en un mensaje ("gasté 500 en comida, 1200 en nafta y 300 en café")
  - El agente los parsea todos, muestra resumen conjunto y registra uno por uno tras confirmación
  - Implementado vía system prompt (regla 11), sin sub-workflow nuevo: reusa `registrar_gasto` por cada gasto

---

## Fase 2 — WhatsApp

- [ ] Reemplazar Chat Trigger por WhatsApp Trigger
- [ ] Reemplazar número hardcodeado con `{{ $('WhatsApp Trigger').item.json.from }}`
  - Nota: en sub-workflows, `$json.phone_number` viene del trigger, no del sessionId. Ya está diseñado así.
- [ ] Configurar Meta API / webhook
- [ ] Soporte para notas de voz — transcripción con Whisper para registrar gastos por voz

---

## Fase 3 — Deploy

- [ ] Dockerizar (n8n ya corre en el VPS con Docker + Caddy)
- [ ] Configurar variables de entorno en producción

---

## Backlog

- [ ] Tool `resumen_por_categoria` — gráfico de torta por categoría
