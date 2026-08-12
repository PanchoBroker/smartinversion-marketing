import { CampaignsScreen } from "@/components/admin/campaigns/campaigns-screen";

// Campaigns admin screen (2026-08-12): thin server wrapper, mismo criterio
// que /app/publications, /app/leads y /app/qa -- el gate de autenticación
// real vive en src/app/app/layout.tsx, no se duplica aquí. Reemplaza el
// placeholder honesto que existía hasta este objetivo (última de las 5
// pantallas de Bloque B9).
export default function CampaignsPage() {
  return <CampaignsScreen />;
}
