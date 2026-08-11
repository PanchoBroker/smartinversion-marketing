import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  cancelTotpEnrollment,
  enrollTotpFactor,
  verifyTotpEnrollment,
} from "./actions";

export const dynamic = "force-dynamic";

interface SecurityPageProps {
  searchParams: Promise<{
    error?: string;
    success?: string;
  }>;
}

function resolveMessage(error?: string, success?: string) {
  if (error === "invalid_code") {
    return {
      tone: "error" as const,
      text: "El código ingresado no es válido o ya expiró.",
    };
  }

  if (error === "enroll_failed" || error === "service_unavailable") {
    return {
      tone: "error" as const,
      text: "No fue posible iniciar la inscripción de MFA. Intenta nuevamente.",
    };
  }

  if (success === "enrolled") {
    return {
      tone: "success" as const,
      text: "MFA quedó habilitado para esta cuenta.",
    };
  }

  return null;
}

// G0-R05 (2026-08-10): self-service TOTP enrollment/status for the
// current profile. Reachable by any authenticated profile -- MFA is
// gated per-action, not per-role (docs/access-control-matrix.md Section
// 6, src/lib/auth/authorization.ts MFA_REQUIRED_ACTIONS), so this page
// does not try to guess in advance which profiles "need" it; any profile
// that later attempts an MFA-required action without a verified factor
// will simply be denied with "mfa_required" at that point and can return
// here.
export default async function SecurityPage({
  searchParams,
}: SecurityPageProps) {
  const { error, success } = await searchParams;
  const message = resolveMessage(error, success);

  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?reason=invalid_session");
  }

  const { data: factorsData } = await supabase.auth.mfa.listFactors();
  // `factorsData.totp` is typed verified-only (supabase-js); an
  // unverified, in-progress factor only shows up in `.all`.
  const verifiedFactor = factorsData?.totp?.[0];
  const unverifiedFactor = factorsData?.all?.find(
    (factor) => factor.factor_type === "totp" && factor.status === "unverified",
  );

  let enrollment: {
    factorId: string;
    qrCodeSvg: string;
    secret: string;
  } | null = null;

  if (!verifiedFactor) {
    if (unverifiedFactor) {
      // A prior enrollment attempt was left unfinished. Cancel it and
      // start a fresh one -- Supabase does not return the QR code again
      // for an existing unverified factor, so resuming is not possible.
      await supabase.auth.mfa.unenroll({
        factorId: unverifiedFactor.id,
      });
    }

    const result = await enrollTotpFactor();

    if (result.ok) {
      enrollment = result;
    }
  }

  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-2xl rounded-2xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
          Smartinversion
        </p>

        <h1 className="mt-4 text-3xl font-semibold">
          Verificación en dos pasos (MFA)
        </h1>

        <p className="mt-3 text-sm leading-6 text-slate-400">
          Requerida para acceder a leads y a funciones
          administrativas (docs/access-control-matrix.md,
          Sección 6).
        </p>

        {message ? (
          <div
            className={`mt-6 rounded-lg border p-4 text-sm ${
              message.tone === "error"
                ? "border-red-900 bg-red-950 text-red-200"
                : "border-emerald-900 bg-emerald-950 text-emerald-200"
            }`}
            role="status"
          >
            {message.text}
          </div>
        ) : null}

        {verifiedFactor ? (
          <div className="mt-8 rounded-xl bg-slate-950 p-5 text-sm">
            <p className="text-emerald-400">
              MFA habilitado.
            </p>
            <p className="mt-2 text-slate-400">
              Esta cuenta ya tiene un factor TOTP verificado.
              Deshabilitarlo requiere una operación
              administrativa protegida, no está disponible
              desde esta pantalla.
            </p>
          </div>
        ) : enrollment ? (
          <div className="mt-8 space-y-6">
            <div className="rounded-xl bg-white p-4">
              {/* Supabase returns a trusted, server-generated SVG QR
                  code from auth.mfa.enroll(); not user-controlled
                  input. */}
              <div
                dangerouslySetInnerHTML={{
                  __html: enrollment.qrCodeSvg,
                }}
              />
            </div>

            <div className="rounded-lg border border-slate-700 bg-slate-950 p-4 text-xs text-slate-400">
              <p>
                Si no puedes escanear el código, ingresa
                este secreto manualmente en tu aplicación
                autenticadora:
              </p>
              <p className="mt-2 break-all font-mono text-slate-200">
                {enrollment.secret}
              </p>
            </div>

            <form
              action={verifyTotpEnrollment}
              className="space-y-5"
            >
              <input
                name="factorId"
                type="hidden"
                value={enrollment.factorId}
              />

              <div>
                <label
                  className="mb-2 block text-sm font-medium text-slate-200"
                  htmlFor="code"
                >
                  Código de verificación
                </label>

                <input
                  autoComplete="one-time-code"
                  className="w-full rounded-lg border border-slate-700 bg-slate-950 px-4 py-3 text-center text-lg tracking-[0.4em] text-slate-100 outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20"
                  id="code"
                  inputMode="numeric"
                  maxLength={16}
                  name="code"
                  required
                  type="text"
                />
              </div>

              <button
                className="w-full rounded-lg bg-amber-500 px-4 py-3 font-semibold text-slate-950 transition hover:bg-amber-400 focus:outline-none focus:ring-2 focus:ring-amber-300 focus:ring-offset-2 focus:ring-offset-slate-900"
                type="submit"
              >
                Activar MFA
              </button>
            </form>

            <form action={cancelTotpEnrollment}>
              <input
                name="factorId"
                type="hidden"
                value={enrollment.factorId}
              />

              <button
                className="w-full rounded-lg border border-slate-700 px-4 py-3 text-sm font-semibold text-slate-200 transition hover:border-amber-400 hover:text-amber-400"
                type="submit"
              >
                Cancelar
              </button>
            </form>
          </div>
        ) : (
          <div className="mt-8 rounded-xl bg-slate-950 p-5 text-sm text-slate-400">
            No fue posible iniciar la inscripción de MFA en
            este momento. Intenta recargar esta página.
          </div>
        )}
      </section>
    </main>
  );
}
