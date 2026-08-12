import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AdminShell } from "@/components/admin/admin-shell";

export const dynamic = "force-dynamic";

// Interfaz admin (2026-08-12): layout compartido para todo lo que vive
// bajo /app -- envuelve la página existente (/app, /app/security) y las
// 5 pantallas orquestadoras nuevas (Campañas, Leads, QA, Publicaciones,
// Asignación de roles) con una única navegación y un único gate de
// autenticación server-side, mismo patrón exacto que ya usaban
// src/app/app/page.tsx y src/app/app/security/page.tsx (ambas siguen
// haciendo su propia verificación también -- defensa en profundidad, no
// se tocó ese código existente). El límite real de autorización sigue
// siendo la capa de API (authorizePrivateRoute + RLS/RPC); este gate
// solo evita renderizar la navegación completa a una sesión inválida.
export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    redirect("/login?reason=invalid_session");
  }

  return <AdminShell>{children}</AdminShell>;
}
