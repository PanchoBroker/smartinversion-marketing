import { RoleAssignmentsScreen } from "@/components/admin/role-assignments/role-assignments-screen";

// Role-assignments admin screen (2026-08-12): thin server wrapper --
// the real authentication gate for everything under /app already lives
// in src/app/app/layout.tsx (single source of truth for the 5
// orchestration screens, per its own header comment). This page does not
// duplicate that gate the way the pre-existing /app and /app/security
// pages do (their duplication predates the layout and was kept on
// purpose as defense in depth) -- every new screen built under this
// layout relies on it alone, same as the campaigns/leads/qa/publications
// placeholders it replaces here.
export default function RoleAssignmentsPage() {
  return <RoleAssignmentsScreen />;
}
