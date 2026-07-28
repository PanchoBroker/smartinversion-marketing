import { headers } from "next/headers";
import {
  CORRELATION_HEADER,
  resolveCorrelationId,
} from "./correlation";

export async function currentCorrelationId(): Promise<string> {
  const headerList = await headers();

  return resolveCorrelationId(
    headerList.get(CORRELATION_HEADER),
  );
}