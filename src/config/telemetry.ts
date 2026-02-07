// src/config/telemetry.ts
import { NodeSDK } from '@opentelemetry/sdk-node'
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'
import { loggers } from '../utils/logger'

/**
 * ✅ Initialize OpenTelemetry instrumentation
 *
 * Features:
 * - Automatic instrumentation for HTTP, Express, Prisma, Redis
 * - OTLP export to Jaeger/Zipkin/Tempo
 * - Service name and environment tagging
 * - Graceful degradation if disabled
 *
 * Environment Variables:
 * - OTEL_ENABLED: Enable/disable OpenTelemetry (default: false)
 * - OTEL_SERVICE_NAME: Service name for tracing (default: hv-battery-backend)
 * - OTEL_EXPORTER_OTLP_ENDPOINT: Exporter endpoint (default: http://localhost:4318)
 */

let sdk: NodeSDK | null = null

export function initializeOpenTelemetry(): void {
  const isEnabled = process.env.OTEL_ENABLED === 'true'

  if (!isEnabled) {
    loggers.server.info('OpenTelemetry is disabled')
    return
  }

  try {
    const serviceName = process.env.OTEL_SERVICE_NAME || 'hv-battery-backend'
    const endpoint =
      process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318'

    // ✅ Set service name via environment variable (OpenTelemetry standard)
    process.env.OTEL_SERVICE_NAME = serviceName

    // Configure trace exporter
    const traceExporter = new OTLPTraceExporter({
      url: `${endpoint}/v1/traces`,
    })

    // Initialize SDK (service name auto-detected from OTEL_SERVICE_NAME env var)
    sdk = new NodeSDK({
      traceExporter,
      instrumentations: [
        getNodeAutoInstrumentations({
          // ✅ Automatically instrument common libraries
          '@opentelemetry/instrumentation-http': {},
          '@opentelemetry/instrumentation-express': {},
          '@opentelemetry/instrumentation-dns': { enabled: false }, // Too noisy
          '@opentelemetry/instrumentation-fs': { enabled: false }, // Too noisy
        }),
      ],
    })

    sdk.start()

    loggers.server.info(
      { serviceName, endpoint },
      'OpenTelemetry initialized successfully',
    )

    // Graceful shutdown
    process.on('SIGTERM', () => {
      sdk
        ?.shutdown()
        .then(() => loggers.server.info('OpenTelemetry shut down successfully'))
        .catch((error) =>
          loggers.server.error({ error }, 'Error shutting down OpenTelemetry'),
        )
    })
  } catch (error) {
    loggers.server.error({ error }, 'Failed to initialize OpenTelemetry')
  }
}

/**
 * ✅ Shutdown OpenTelemetry SDK
 */
export async function shutdownOpenTelemetry(): Promise<void> {
  if (sdk) {
    await sdk.shutdown()
    loggers.server.info('OpenTelemetry shut down')
  }
}
