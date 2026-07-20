import {
  APP_ENVIRONMENT,
  APP_RELEASE,
  APP_VERSION,
  SERVICE_NAME,
} from "./runtime";
import { sanitizeLogContext } from "./sanitize";

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface LogInput {
  event: string;
  correlationId: string;
  context?: Record<string, unknown>;
}

function emit(level: LogLevel, input: LogInput): void {
  const record = {
    timestamp: new Date().toISOString(),
    level,
    event: input.event,
    service: SERVICE_NAME,
    environment: APP_ENVIRONMENT,
    version: APP_VERSION,
    release: APP_RELEASE,
    correlation_id: input.correlationId,
    context: sanitizeLogContext(input.context ?? {}),
  };

  switch (level) {
    case "error":
      console.error(record);
      break;
    case "warn":
      console.warn(record);
      break;
    case "debug":
      console.debug(record);
      break;
    default:
      console.info(record);
  }
}

export function logDebug(input: LogInput): void {
  emit("debug", input);
}

export function logInfo(input: LogInput): void {
  emit("info", input);
}

export function logWarn(input: LogInput): void {
  emit("warn", input);
}

export function logError(input: LogInput): void {
  emit("error", input);
}