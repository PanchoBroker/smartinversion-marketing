import { LeadsScreen } from "@/components/admin/leads/leads-screen";

// Leads admin screen (2026-08-12): thin server wrapper, same criterio que
// /app/role-assignments -- el gate de autenticación real vive en
// src/app/app/layout.tsx, no se duplica aquí.
export default function LeadsPage() {
  return <LeadsScreen />;
}
