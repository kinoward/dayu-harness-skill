#!/usr/bin/env node

function parseArgv(argv) {
  const [name = 'world'] = argv
  return name
}

const name = parseArgv(process.argv.slice(2))

console.log(`Hello, ${name}!`)

