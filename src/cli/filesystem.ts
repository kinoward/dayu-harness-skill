import { existsSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";

export function writeFileAtomically(path: string, content: string | NodeJS.ArrayBufferView): void {
  const tempPath = join(dirname(path), `.${randomUUID()}.tmp`);

  try {
    writeFileSync(tempPath, content);
    renameSync(tempPath, path);
  } catch (error) {
    if (existsSync(tempPath)) {
      unlinkSync(tempPath);
    }
    throw error;
  }
}
