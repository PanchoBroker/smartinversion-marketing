# Trazabilidad de Requisitos - Fase 6 (Medición y Aprendizaje)

## 1. Contexto y Dependencias
- **Fase:** 6 (Medición y Aprendizaje).
- **Dependencia Crítica:** Fase 1 (Fundación Segura) - CERRADA.
- **Paralelismo Seguro:** Autorizado por Plan Maestro §7 ("Las fases 5 y 6 pueden desarrollarse en paralelo después de F1").
- **Objetivo:** Implementar la ingesta de métricas, cálculo de embudos, registro de hipótesis y generación de informes de cierre sin interferir con la lógica transaccional de F3 (Campañas) o F4 (Producción).

## 2. Requisitos Funcionales (FR) a Implementar
Basado en *Especificación Funcional v1.0*, Sección 13:

### 2.1 Métricas (MET)
| ID | Requisito | Prioridad | Componente Técnico |
|---|---|---|---|
| FR-MET-001 | Registrar métricas por campaña, pieza, publicación, plataforma y periodo. | MUST | Tabla `metric_values`, API `/metrics/import` |
| FR-MET-002 | Distinguir tráfico orgánico, pagado y combinado. | MUST | Columna `traffic_type` en `metric_values` |
| FR-MET-003 | Conservar numerador, denominador, fórmula y fuente de cada métrica. | MUST | Tabla `metric_definitions`, `metric_snapshots` (raw) |
| FR-MET-004 | Registrar ventanas de medición: 24h, 72h, 7d y cierre. | MUST | Job `measurement-window`, vistas de dashboard |
| FR-MET-005 | Calcular conversión, prefiltro, costos y tasas posteriores. | MUST | Funciones SQL / Vistas derivadas |
| FR-MET-006 | Permitir importación manual (CSV) y futura integración automática. | MUST | Endpoint `/metrics/import`, validación de esquema |
| FR-MET-007 | Detectar ausencia, duplicación o inconsistencia de datos. | MUST | Validación en API, alertas en dashboard |
| FR-MET-008 | Mostrar vistas ejecutiva, contenido, embudo, producción y aprendizaje. | MUST | Rutas UI `/analytics/*` |
| FR-MET-009 | No comparar directamente campañas con objetivos distintos sin advertencia. | MUST | Lógica de presentación en UI |

### 2.2 Aprendizaje (LRN)
| ID | Requisito | Prioridad | Componente Técnico |
|---|---|---|---|
| FR-LRN-001 | Registrar hipótesis con variable, resultado esperado, métrica y periodo. | MUST | Tabla `hypotheses` (ya existe en F3, se usa aquí) |
| FR-LRN-002 | Clasificar resultado: validado, rechazado, inconcluso, inválido o pendiente. | MUST | Estado en `hypotheses`, UI de cierre |
| FR-LRN-003 | Separar observación, evidencia, interpretación, incertidumbre y decisión. | MUST | Tabla `learning_records` |
| FR-LRN-004 | Crear informe de cierre de campaña. | MUST | Generación de PDF/Exportable, ruta `/learning/reports` |
| FR-LRN-005 | Permitir promover aprendizajes a reglas reutilizables. | SHOULD | UI de administración de conocimientos |
| FR-LRN-006 | Mantener historial sin eliminar resultados negativos. | MUST | Política de solo-append en `learning_records` |

## 3. Modelo de Datos (Esquema F6)
Basado en *Especificacion Técnica v1.0*, Sección 8.6:
1. **`metric_snapshots`**: Payload original crudo, inmutable. Proveedor, ventana, fecha de importación.
2. **`metric_values`**: Métrica normalizada. FK a `campaigns`, `publications`, `metric_definitions`. Valor numérico, unidad, tipo de tráfico.
3. **`learning_records`**: Registro estructurado del aprendizaje. FK a `hypotheses`. Campos: observación, evidencia_numérica, interpretación_textual, decisión_accion.
4. **`campaign_reports`**: Archivos de cierre generados. FK a `campaigns`.

*Nota: Verificar en `main` si las tablas `hypotheses` y `metric_definitions` ya fueron creadas por F3 antes de escribir migraciones.*

## 4. Reglas de Negocio (BR) Aplicables
- **BR-016:** La métrica principal es lead prefiltrado entregado.
- **BR-017:** Tráfico orgánico y pagado se conservan separados.
- **BR-018:** Una promoción para visualizaciones no equivale a campaña de leads.
- **BR-024:** No se borran resultados negativos del aprendizaje.

## 5. Criterios de Aceptación (AC) para Gate G6
- [ ] AC-010: Las métricas separan orgánico y pagado en todas las vistas.
- [ ] AC-011: Cada porcentaje en el dashboard permite consultar su numerador y denominador.
- [ ] AC-012: El informe de cierre separa claramente observación de interpretación.
- [ ] Importación de CSV valida columnas y tipos antes de confirmar.
- [ ] Ventanas de medición (24h/72h/7d) se calculan automáticamente al cerrar el periodo.

## 6. Backlog Técnico Propuesto (Sprint F6)
1. **S6-001:** Verificación de esquema existente (`hypotheses`, `metric_definitions`) y creación de `metric_snapshots`, `metric_values`, `learning_records`.
2. **S6-002:** API de importación de métricas (`POST /api/v1/metrics/import`) con validación de esquema.
3. **S6-003:** Jobs programados para cálculo de ventanas de medición (`measurement-window`).
4. **S6-004:** Vistas SQL para cálculo de embudo (Conversión, Prefiltro, CPL).
5. **S6-005:** UI de Dashboard Analítico (`/analytics`) con filtros por campaña y ventana.
6. **S6-006:** UI de Registro de Aprendizaje (`/learning`) y generación de informe de cierre.