// vitest.config.ts
import { defineConfig } from 'vitest/config'
import path from 'path'

export default defineConfig({
  test: {
    // Test environment
    environment: 'node',

    // Global setup/teardown
    globals: true,

    // Coverage configuration
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'dist/',
        'build/',
        '**/*.config.{js,ts}',
        '**/*.d.ts',
        '**/types/',
        'test/',
        'backend-runtime/',
      ],
      thresholds: {
        lines: 70,
        functions: 70,
        branches: 70,
        statements: 70,
      },
    },

    // Test file patterns
    include: ['**/*.{test,spec}.{js,ts}'],
    exclude: ['node_modules', 'dist', 'build', 'backend-runtime'],

    // Timeout settings
    testTimeout: 10000,
    hookTimeout: 10000,

    // Parallel/sequential execution
    pool: 'threads',
    maxConcurrency: 5,

    // Mock configuration
    mockReset: true,
    clearMocks: true,
    restoreMocks: true,
  },

  // Path resolution (match tsconfig paths)
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
