// S5-004: versioned application config for the S0-015 public form
// surface (docs/preliminary-form-contract.md Sections 10/11/15).
//
// income_ranges, income_modes and the consent notice are deliberately
// NOT database tables. None of the three appear in docs/core-schema.md's
// entity inventory (unlike `form_sessions`/`tracking_links`/`publications`,
// which do), and the contract itself describes them as versioned,
// rarely-changing, non-personal, "controlled configuration, not
// alphabetical sorting" (Section 10) whose codes "MUST remain stable
// after production use" and whose changes require "a versioned
// configuration change and impact review" -- a code review + deploy,
// not a runtime database UPDATE. This was flagged as an open decision
// in `campaigns_public_slug_s5_004.sql`'s own header and confirmed with
// the product owner on 2026-08-07 before this route was built (see
// registro-de-patrones.md). Revisit only if the product owner later
// asks for these to be editable without a deploy.
//
// Values below are transcribed verbatim from the contract's own
// catalogs (Section 10 income-range table, Section 11 income-mode
// table) and its Section 15 conceptual response example -- not
// invented here.

export interface PublicCatalogEntry {
  readonly code: string;
  readonly label: string;
  readonly order: number;
}

export const PUBLIC_FORM_VERSION = "lead_capture_v1";

// Section 10. Order is controlled configuration (ascending declared
// income), not alphabetical -- per the contract's own rule.
export const PUBLIC_INCOME_RANGES: readonly PublicCatalogEntry[] = [
  {
    code: "below_1000000",
    label: "Menos de $1.000.000",
    order: 10,
  },
  {
    code: "from_1000000_to_1499999",
    label: "$1.000.000 a $1.499.999",
    order: 20,
  },
  {
    code: "from_1500000_to_1999999",
    label: "$1.500.000 a $1.999.999",
    order: 30,
  },
  {
    code: "from_2000000_to_2499999",
    label: "$2.000.000 a $2.499.999",
    order: 40,
  },
  {
    code: "from_2500000_to_2999999",
    label: "$2.500.000 a $2.999.999",
    order: 50,
  },
  {
    code: "from_3000000_to_3999999",
    label: "$3.000.000 a $3.999.999",
    order: 60,
  },
  {
    code: "from_4000000_or_more",
    label: "$4.000.000 o más",
    order: 70,
  },
];

// Section 11.
export const PUBLIC_INCOME_MODES: readonly PublicCatalogEntry[] = [
  { code: "individual", label: "Renta individual", order: 10 },
  { code: "combined", label: "Renta complementada", order: 20 },
  {
    code: "could_combine",
    label: "Podría complementar renta",
    order: 30,
  },
  { code: "guidance", label: "Necesito orientación", order: 40 },
];

export interface PublicConsentNotice {
  readonly notice_version: string;
  readonly notice_text: string;
}

// Section 15. `contact_data_v1_draft` is explicitly a non-production
// placeholder ("MUST NOT be used as a production legal notice" --
// production activation requires an approved notice version and exact
// approved text, still an open decision per Section 33).
export const PUBLIC_CONSENT_NOTICE: PublicConsentNotice = {
  notice_version: "contact_data_v1_draft",
  notice_text:
    "Texto preliminar sujeto a validación jurídica antes de producción.",
};
