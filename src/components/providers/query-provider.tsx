"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";

// Interfaz admin (2026-08-12): capa de consulta con invalidación
// explícita post-mutación, per Especificacion Tecnica Sección 12.3
// ("El estado remoto se obtendrá mediante una capa de consulta con
// invalidación explícita después de mutaciones"). QueryClient se crea
// una vez por sesión de navegador vía useState (no module-scope) --
// patrón estándar de TanStack Query con Next.js App Router, evita
// compartir estado entre requests SSR distintos.
export function QueryProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 30_000,
            retry: 1,
          },
        },
      }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  );
}
