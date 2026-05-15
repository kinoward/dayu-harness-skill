import assert from 'node:assert/strict'
import { execSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const fixtureRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const output = execSync('node ./src/index.js', { cwd: fixtureRoot }).toString().trim()
assert.equal(output, 'Hello, world!')

console.log('ok')
