'use client';

export default function LearningDashboard() {
  return (
    <div className="p-6 space-y-8">
      <header>
        <h1 className="text-3xl font-bold tracking-tight">Registro de Aprendizaje (F6)</h1>
        <p className="text-muted-foreground mt-2">
          Hipótesis, evidencias e interpretación • Ciclo de mejora continua
        </p>
      </header>

      {/* Formulario de Nuevo Registro */}
      <section className="border rounded-xl p-6 bg-card shadow-sm">
        <h2 className="font-semibold mb-4">Nuevo Registro de Aprendizaje</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium mb-1">Campaña (ID)</label>
            <input 
              type="text" 
              placeholder="MC-REG-001" 
              className="w-full border rounded-md px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">Hipótesis</label>
            <input 
              type="text" 
              placeholder="H1: Alternativas regionales generan atención" 
              className="w-full border rounded-md px-3 py-2 text-sm"
            />
          </div>
          <div className="md:col-span-2">
            <label className="block text-sm font-medium mb-1">Observación (Hechos)</label>
            <textarea 
              rows={3}
              placeholder="¿Qué ocurrió exactamente?" 
              className="w-full border rounded-md px-3 py-2 text-sm"
            />
          </div>
          <div className="md:col-span-2">
            <label className="block text-sm font-medium mb-1">Evidencia (Cifras/Fuentes)</label>
            <textarea 
              rows={2}
              placeholder="Datos duros que respaldan la observación" 
              className="w-full border rounded-md px-3 py-2 text-sm"
            />
          </div>
          <div className="md:col-span-2">
            <label className="block text-sm font-medium mb-1">Interpretación</label>
            <textarea 
              rows={2}
              placeholder="¿Qué podría explicar estos resultados?" 
              className="w-full border rounded-md px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">Estado</label>
            <select className="w-full border rounded-md px-3 py-2 text-sm">
              <option value="pending">Pendiente</option>
              <option value="validated">Validada Provisionalmente</option>
              <option value="rejected">Rechazada Provisionalmente</option>
              <option value="inconclusive">Inconclusa</option>
              <option value="invalidated">Invalidada Metodológicamente</option>
            </select>
          </div>
          <div className="flex items-end">
            <button className="bg-primary text-primary-foreground px-4 py-2 rounded-md text-sm font-medium hover:bg-primary/90 transition-colors w-full">
              Guardar Registro
            </button>
          </div>
        </div>
      </section>

      {/* Tabla de Registros Existentes */}
      <section className="border rounded-xl overflow-hidden">
        <div className="bg-muted/50 px-6 py-4 border-b">
          <h2 className="font-semibold">Historial de Aprendizajes</h2>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left">
            <thead className="bg-muted/30 text-xs uppercase font-medium text-muted-foreground">
              <tr>
                <th className="px-6 py-3">Campaña</th>
                <th className="px-6 py-3">Hipótesis</th>
                <th className="px-6 py-3">Estado</th>
                <th className="px-6 py-3">Fecha</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              <tr>
                <td colSpan={4} className="px-6 py-8 text-center text-muted-foreground">
                  No hay registros aún. Completa el formulario superior para iniciar.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}