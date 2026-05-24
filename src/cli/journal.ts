import { existsSync, mkdirSync, openSync, readFileSync, writeFileSync, fsyncSync, closeSync, unlinkSync } from "node:fs";
import { dirname, join } from "node:path";
import { createHash, randomUUID } from "node:crypto";

import { writeFileAtomically } from "./filesystem.js";
import { resolveInsideRoot } from "./paths.js";

const DAYU_DIR = ".dayu";
const JOURNAL_FILE = ".dayu/journal.jsonl";
const LOCK_FILE = ".dayu/apply.lock";
const MANAGED_PATHS_FILE = ".dayu/managed-paths.json";

export interface JournalEntry {
  id: string;
  command: string;
  phase: "begin" | "preimage" | "write" | "commit" | "rollback";
  path?: string;
  timestamp: string;
  checksum?: string | null;
  existed?: boolean;
  contentBase64?: string | null;
  detail?: Record<string, unknown>;
}

export interface ApplyLock {
  release(): void;
}

export interface ManagedPathsRecord {
  managedPaths: string[];
  updatedAt: string;
}

export function acquireApplyLock(targetRoot: string): ApplyLock {
  const lockPath = resolveInsideRoot(targetRoot, LOCK_FILE);
  mkdirSync(dirname(lockPath), { recursive: true });

  let fd: number;
  try {
    fd = openSync(lockPath, "wx");
  } catch (error) {
    if (!isStaleLock(lockPath)) {
      throw error;
    }
    unlinkSync(lockPath);
    fd = openSync(lockPath, "wx");
  }
  writeFileSync(fd, `${process.pid}\n${new Date().toISOString()}\n`);
  fsyncSync(fd);

  return {
    release() {
      closeSync(fd);
      if (existsSync(lockPath)) {
        unlinkSync(lockPath);
      }
    }
  };
}

export function recoverInterruptedTransactions(targetRoot: string): string[] {
  const journalFilePath = resolveInsideRoot(targetRoot, JOURNAL_FILE);
  if (!existsSync(journalFilePath)) {
    return [];
  }

  const transactions = new Map<
    string,
    { committed: boolean; rolledBack: boolean; preimages: Map<string, JournalEntry>; writtenChecksums: Map<string, string | null> }
  >();
  for (const line of readFileSync(journalFilePath, "utf8").split(/\r?\n/)) {
    if (!line.trim()) {
      continue;
    }
    const entry = JSON.parse(line) as JournalEntry;
    const transaction =
      transactions.get(entry.id) ?? {
        committed: false,
        rolledBack: false,
        preimages: new Map<string, JournalEntry>(),
        writtenChecksums: new Map<string, string | null>()
      };
    if (entry.phase === "commit") {
      transaction.committed = true;
    }
    if (entry.phase === "rollback" && !entry.path) {
      transaction.rolledBack = true;
    }
    if (entry.phase === "preimage" && entry.path) {
      transaction.preimages.set(entry.path, entry);
    }
    if (entry.phase === "write" && entry.path) {
      transaction.writtenChecksums.set(entry.path, entry.checksum ?? null);
    }
    transactions.set(entry.id, transaction);
  }

  const recovered: string[] = [];
  for (const [transactionId, transaction] of transactions) {
    if (transaction.committed || transaction.rolledBack || transaction.preimages.size === 0) {
      continue;
    }
    recovered.push(
      ...rollbackPaths(targetRoot, transactionId, transaction.preimages, {
        expectedCurrentChecksums: transaction.writtenChecksums,
        skipPathsWithoutExpectedChecksum: true
      })
    );
  }

  return [...new Set(recovered)].sort();
}

export function appendJournalEntry(targetRoot: string, entry: Omit<JournalEntry, "timestamp">): void {
  const journalPath = resolveInsideRoot(targetRoot, JOURNAL_FILE);
  mkdirSync(dirname(journalPath), { recursive: true });
  const fd = openSync(journalPath, "a");
  try {
    writeFileSync(fd, `${JSON.stringify({ ...entry, timestamp: new Date().toISOString() })}\n`);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
}

export function capturePreimage(targetRoot: string, relativePath: string): Pick<JournalEntry, "checksum" | "existed" | "contentBase64"> {
  const targetPath = resolveInsideRoot(targetRoot, relativePath);
  if (!existsSync(targetPath)) {
    return {
      checksum: null,
      existed: false,
      contentBase64: null
    };
  }

  const content = readFileSync(targetPath);
  return {
    checksum: hashBuffer(content),
    existed: true,
    contentBase64: content.toString("base64")
  };
}

export function rollbackPaths(
  targetRoot: string,
  transactionId: string,
  preimages: ReadonlyMap<string, JournalEntry>,
  options: { expectedCurrentChecksums?: ReadonlyMap<string, string | null>; skipPathsWithoutExpectedChecksum?: boolean } = {}
): string[] {
  const rolledBack: string[] = [];

  for (const [relativePath, preimage] of [...preimages.entries()].reverse()) {
    const targetPath = resolveInsideRoot(targetRoot, relativePath);
    if (options.expectedCurrentChecksums?.has(relativePath)) {
      const expectedChecksum = options.expectedCurrentChecksums.get(relativePath) ?? null;
      if (currentChecksum(targetPath) !== expectedChecksum) {
        continue;
      }
    } else if (options.skipPathsWithoutExpectedChecksum) {
      continue;
    }

    if (preimage.existed && preimage.contentBase64) {
      mkdirSync(dirname(targetPath), { recursive: true });
      writeFileAtomically(targetPath, Buffer.from(preimage.contentBase64, "base64"));
    } else if (existsSync(targetPath)) {
      unlinkSync(targetPath);
    }
    rolledBack.push(relativePath);
    appendJournalEntry(targetRoot, {
      id: transactionId,
      command: "apply",
      phase: "rollback",
      path: relativePath,
      checksum: preimage.checksum,
      existed: preimage.existed,
      contentBase64: null
    });
  }

  appendJournalEntry(targetRoot, {
    id: transactionId,
    command: "apply",
    phase: "rollback",
    detail: {
      completed: true,
      paths: rolledBack
    }
  });

  return rolledBack;
}

export function createTransactionId(): string {
  return randomUUID();
}

export function readManagedPaths(targetRoot: string): string[] {
  const managedPathsPath = resolveInsideRoot(targetRoot, MANAGED_PATHS_FILE);
  if (!existsSync(managedPathsPath)) {
    return [];
  }

  const parsed = JSON.parse(readFileSync(managedPathsPath, "utf8")) as Partial<ManagedPathsRecord>;
  return Array.isArray(parsed.managedPaths) ? parsed.managedPaths.filter((item): item is string => typeof item === "string") : [];
}

export function writeManagedPaths(targetRoot: string, managedPaths: readonly string[]): void {
  const managedPathsPath = resolveInsideRoot(targetRoot, MANAGED_PATHS_FILE);
  mkdirSync(dirname(managedPathsPath), { recursive: true });
  const body: ManagedPathsRecord = {
    managedPaths: [...new Set(managedPaths)].sort(),
    updatedAt: new Date().toISOString()
  };
  writeFileAtomically(managedPathsPath, `${JSON.stringify(body, null, 2)}\n`);
}

export function journalPath(): string {
  return JOURNAL_FILE;
}

export function managedPathsFile(): string {
  return MANAGED_PATHS_FILE;
}

function hashBuffer(content: Buffer): string {
  return createHash("sha256").update(content).digest("hex");
}

function currentChecksum(path: string): string | null {
  if (!existsSync(path)) {
    return null;
  }

  return hashBuffer(readFileSync(path));
}

function isStaleLock(lockPath: string): boolean {
  if (!existsSync(lockPath)) {
    return true;
  }

  const pidLine = readFileSync(lockPath, "utf8").split(/\r?\n/)[0];
  const pid = Number(pidLine);
  if (!Number.isInteger(pid) || pid <= 0) {
    return true;
  }

  try {
    process.kill(pid, 0);
    return false;
  } catch {
    return true;
  }
}
