import packageMetadata from "../../../package.json";

export const SERVICE_NAME = "smartinversion-marketing";

export const APP_VERSION =
  process.env.APP_VERSION?.trim() ||
  packageMetadata.version ||
  "unknown";

export const APP_RELEASE =
  process.env.APP_RELEASE?.trim() ||
  process.env.CF_PAGES_COMMIT_SHA?.trim() ||
  process.env.VERCEL_GIT_COMMIT_SHA?.trim() ||
  "unversioned";

export const APP_ENVIRONMENT =
  process.env.NEXTJS_ENV?.trim() ||
  process.env.NODE_ENV?.trim() ||
  "unknown";