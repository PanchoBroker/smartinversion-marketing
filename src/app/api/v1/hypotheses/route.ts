import {
  createCreateHandler,
  createListHandler,
} from "@/lib/api/resource-routes";

export const dynamic = "force-dynamic";

// S3-007: hypotheses has no S1-007 machine (S3-002) and no version
// resolution to compute (unlike campaign_briefs/content_versions), so the
// plain generic factory (userClient + RLS, campaign_manager insert
// policy) is sufficient, mirroring /claims, /sources, /evidence.

const config = {
  table: "hypotheses",
  listAction: "hypothesis.read",
  createAction: "hypothesis.write",
  requiredFields: ["campaign_id", "statement", "variable", "expected_result"],
  optionalFields: [
    "metric_definition_id",
    "measurement_period_starts_at",
    "measurement_period_ends_at",
    "status",
    "result_summary",
  ],
} as const;

export const GET = createListHandler(config);
export const POST = createCreateHandler(config);
