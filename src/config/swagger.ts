// src/config/swagger.ts
import swaggerJsdoc from 'swagger-jsdoc'
import swaggerUi from 'swagger-ui-express'
import { Express } from 'express'

/**
 * Swagger/OpenAPI Documentation Configuration
 *
 * Access: http://localhost:4001/api-docs
 */

const options: swaggerJsdoc.Options = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'HV Battery Production API',
      version: process.env.npm_package_version || '1.0.0',
      description:
        'API documentation for HV Battery Production Information System',
      contact: {
        name: 'API Support',
        email: 'support@example.com',
      },
    },
    servers: [
      {
        url: process.env.API_URL || 'http://localhost:4001',
        description:
          process.env.NODE_ENV === 'production'
            ? 'Production Server'
            : 'Development Server',
      },
    ],
    components: {
      schemas: {
        Error: {
          type: 'object',
          properties: {
            success: {
              type: 'boolean',
              example: false,
            },
            error: {
              type: 'string',
              example: 'Error message',
            },
            message: {
              type: 'string',
              example: 'Detailed error description',
            },
          },
        },
        ValidationError: {
          type: 'object',
          properties: {
            success: {
              type: 'boolean',
              example: false,
            },
            error: {
              type: 'string',
              example: 'Validation Error',
            },
            details: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  field: {
                    type: 'string',
                    example: 'FTYPE_BATTERY',
                  },
                  message: {
                    type: 'string',
                    example: 'FTYPE_BATTERY is required',
                  },
                },
              },
            },
          },
        },
        Sequence: {
          type: 'object',
          properties: {
            FID: { type: 'integer' },
            FID_ADJUST: { type: 'integer', nullable: true },
            FSEQ_NO: { type: 'integer', nullable: true },
            FTYPE_BATTERY: { type: 'string' },
            FMODEL_BATTERY: { type: 'string' },
            FSEQ_DATE: { type: 'string', format: 'date' },
            FSTATUS: {
              type: 'integer',
              enum: [0, 1, 2, 3],
              description: '0=QUEUE, 1=PRINTED, 2=COMPLETE, 3=PARKED',
            },
            FBARCODE: { type: 'string', nullable: true },
            FTIME_RECEIVED: {
              type: 'string',
              format: 'date-time',
              nullable: true,
            },
            FTIME_PRINTED: {
              type: 'string',
              format: 'date-time',
              nullable: true,
            },
            FTIME_COMPLETED: {
              type: 'string',
              format: 'date-time',
              nullable: true,
            },
          },
        },
      },
    },
    tags: [
      {
        name: 'Health',
        description: 'Health check and system monitoring endpoints',
      },
      {
        name: 'Sequences',
        description: 'Battery production sequence management',
      },
      {
        name: 'Traceability',
        description: 'Product traceability and history tracking',
      },
      {
        name: 'Print History',
        description: 'Print history management',
      },
    ],
  },
  apis: [
    './src/routes/*.ts', // Path to route files with JSDoc comments
    './src/controllers/*.ts', // Path to controller files
  ],
}

const swaggerSpec = swaggerJsdoc(options)

/**
 * Setup Swagger UI documentation
 */
export function setupSwagger(app: Express) {
  // Swagger UI
  app.use(
    '/api-docs',
    swaggerUi.serve,
    swaggerUi.setup(swaggerSpec, {
      customCss: '.swagger-ui .topbar { display: none }',
      customSiteTitle: 'HV Battery API Docs',
    }),
  )

  // JSON spec endpoint
  app.get('/api-docs.json', (req, res) => {
    res.setHeader('Content-Type', 'application/json')
    res.send(swaggerSpec)
  })
}
