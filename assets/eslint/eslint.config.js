// ESLint flat config (v9+)
// 安装: npm install -D eslint @eslint/js
// 使用: npx eslint .

import js from '@eslint/js';

export default [
  js.configs.recommended,
  {
    rules: {
      'no-unused-vars': 'warn',
      'no-undef': 'error',
      'no-console': 'warn',
    },
  },
  {
    ignores: ['dist/**', 'node_modules/**', '.git/**'],
  },
];
