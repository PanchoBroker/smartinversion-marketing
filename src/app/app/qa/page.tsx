// Interfaz admin (2026-08-12): placeholder honesto -- el backend de
// este módulo ya está en producción (ver PRs de esta misma jornada),
// la pantalla se construye en su propia iteración siguiente. No se
// oculta del menú (el usuario quiere visibilidad del sistema completo
// desde el día uno), pero tampoco se simula contenido que no existe.
export default function QaPage() {
  return (
    <section className="mx-auto max-w-3xl rounded-2xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
      <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
        Próximamente
      </p>
      <h1 className="mt-4 text-2xl font-semibold text-slate-100">
        QA
      </h1>
      <p className="mt-4 text-sm leading-6 text-slate-400">
        El backend de este módulo ya está desplegado y validado. Esta
        pantalla se construye en la siguiente iteración de la interfaz.
      </p>
    </section>
  );
}
