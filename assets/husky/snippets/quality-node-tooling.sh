# lint-staged runner for Node.js projects.
if command -v npx &> /dev/null && [ -f ".lintstagedrc.json" ]; then
    npx --no-install lint-staged
fi
