export interface CliIssue {
  code: string;
  message: string;
  path?: string;
}

export class CliError extends Error {
  readonly code: string;
  readonly issues: readonly CliIssue[];

  constructor(code: string, message: string, issues: readonly CliIssue[] = []) {
    super(message);
    this.name = "CliError";
    this.code = code;
    this.issues = issues.length > 0 ? issues : [{ code, message }];
  }
}

export function isCliError(error: unknown): error is CliError {
  return error instanceof CliError;
}
