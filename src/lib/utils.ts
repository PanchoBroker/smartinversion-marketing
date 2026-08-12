import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

// Interfaz admin (2026-08-12): estándar shadcn/ui `cn()` -- combina
// clsx (condicionales) con tailwind-merge (resuelve conflictos de
// utilidades Tailwind, ej. "px-2 px-4" -> "px-4"). Usado por todos los
// componentes en src/components/ui/*.
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
