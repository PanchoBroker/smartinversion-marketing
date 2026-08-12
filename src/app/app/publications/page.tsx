import { PublicationsScreen } from "@/components/admin/publications/publications-screen";

// Publications admin screen (2026-08-12): thin server wrapper, same
// criterio que /app/leads y /app/qa -- el gate de autenticación real vive
// en src/app/app/layout.tsx, no se duplica aquí. Reemplaza el placeholder
// honesto de PR #149.
export default function PublicationsPage() {
  return <PublicationsScreen />;
}
