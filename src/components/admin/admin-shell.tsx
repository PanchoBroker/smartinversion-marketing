"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

// Interfaz admin (2026-08-12): shell de navegación compartido para las
// 5 pantallas orquestadoras (Campañas, Leads, QA, Publicaciones,
// Asignación de roles) confirmadas con el usuario -- ver conversación de
// alcance. Envuelve TODO lo que ya vive bajo /app (incluyendo
// /app y /app/security, ya existentes) vía src/app/app/layout.tsx, así
// que la navegación aparece en toda la app privada sin duplicar el
// layout en cada pantalla nueva.
//
// Client component (usePathname para resaltar el link activo). El
// gate de autenticación real vive en el layout.tsx server component que
// envuelve a este shell, no aquí -- este componente solo dibuja la
// navegación, nunca decide quién puede verla.

interface NavItem {
  href: string;
  label: string;
  // Pantallas todavía no construidas (placeholder) se marcan para dar
  // contexto visual honesto -- no se ocultan, per la conversación de
  // alcance: el usuario quiere ver el sistema completo desde el día uno,
  // aunque cada módulo se llene de forma incremental.
  soon?: boolean;
}

const PRIMARY_NAV: NavItem[] = [
  { href: "/app", label: "Inicio" },
  { href: "/app/campaigns", label: "Campañas" },
  { href: "/app/leads", label: "Leads" },
  { href: "/app/qa", label: "QA" },
  { href: "/app/publications", label: "Publicaciones" },
];

const SECONDARY_NAV: NavItem[] = [
  { href: "/analytics", label: "Analítica" },
  { href: "/learning", label: "Aprendizaje" },
  { href: "/app/role-assignments", label: "Asignación de roles" },
  { href: "/app/security", label: "Seguridad" },
];

function NavSection({
  title,
  items,
  pathname,
}: {
  title: string;
  items: NavItem[];
  pathname: string;
}) {
  return (
    <div>
      <p className="px-3 text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
        {title}
      </p>
      <nav className="mt-2 flex flex-col gap-1">
        {items.map((item) => {
          const isActive =
            item.href === "/app"
              ? pathname === "/app"
              : pathname === item.href || pathname.startsWith(`${item.href}/`);

          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "rounded-lg px-3 py-2 text-sm font-medium transition",
                isActive
                  ? "bg-slate-800 text-amber-400"
                  : "text-slate-300 hover:bg-slate-900 hover:text-slate-100",
              )}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>
    </div>
  );
}

export function AdminShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto flex max-w-7xl">
        <aside className="sticky top-0 hidden h-screen w-64 shrink-0 flex-col gap-8 border-r border-slate-800 bg-slate-950 px-4 py-8 lg:flex">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
              Smartinversión
            </p>
            <p className="mt-1 text-lg font-semibold text-slate-100">
              Marketing Content
            </p>
          </div>

          <NavSection
            title="Orquestación"
            items={PRIMARY_NAV}
            pathname={pathname}
          />

          <NavSection
            title="Consulta y gobierno"
            items={SECONDARY_NAV}
            pathname={pathname}
          />
        </aside>

        <main className="min-w-0 flex-1 px-6 py-8 lg:px-10">{children}</main>
      </div>
    </div>
  );
}
