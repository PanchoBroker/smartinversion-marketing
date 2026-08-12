import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

// Interfaz admin (2026-08-12): componente shadcn/ui estándar (fuente
// idiomática, no una variante propia), adaptado a la paleta slate/amber
// que ya usa el proyecto (src/app/app/page.tsx, src/app/app/security/
// page.tsx) en vez del tema zinc/blue por defecto de shadcn -- consistencia
// visual con lo que ya existe, no un tema nuevo.
const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 rounded-lg text-sm font-semibold transition focus:outline-none focus:ring-2 focus:ring-amber-300 focus:ring-offset-2 focus:ring-offset-slate-900 disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default:
          "bg-amber-400 text-slate-950 hover:bg-amber-300",
        outline:
          "border border-slate-700 text-slate-200 hover:border-amber-400 hover:text-amber-400",
        ghost:
          "text-slate-300 hover:bg-slate-800 hover:text-slate-100",
        destructive:
          "bg-red-500/10 text-red-400 border border-red-500/30 hover:bg-red-500/20",
      },
      size: {
        default: "px-4 py-3",
        sm: "px-3 py-2 text-xs",
        icon: "h-9 w-9 p-0",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return (
      <Comp
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    );
  },
);
Button.displayName = "Button";

export { Button, buttonVariants };
