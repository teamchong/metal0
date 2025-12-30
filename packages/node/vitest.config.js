import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    testTimeout: 30000,
    include: ['test/**/*.spec.js', 'test/**/*.test.js'],
    exclude: [
      'test/basic.test.js',
      'test/compat.test.js',
      'test/params.test.js',
      'test/distinct.test.js',
      'test/types.test.js',
      'test/timestamp.test.js',
    ], // Node.js native test runner files
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['src/**/*.js'],
    },
  },
});
