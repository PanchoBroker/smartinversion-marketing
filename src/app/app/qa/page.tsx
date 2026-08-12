import { QaScreen } from "@/components/admin/qa/qa-screen";

// QA admin screen (2026-08-12): thin server wrapper, mismo criterio que
// /app/role-assignments y /app/leads -- el gate de autenticación real
// vive en src/app/app/layout.tsx, no se duplica aquí.
export default function QaPage() {
  return <QaScreen />;
}
