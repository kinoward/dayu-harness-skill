import type { ZodError } from "zod";

export function formatZodIssues(error: ZodError): string[] {
  return error.issues.map((issue) => {
    const path = issue.path.length > 0 ? issue.path.join(".") : "<root>";
    return `${path}: ${issue.message}`;
  });
}

export function formatZodError(error: ZodError): string {
  return formatZodIssues(error).join("\n");
}
