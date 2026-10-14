# Backend Runtime Update Notes

- Bundle mode: slim
- Selected from: explicit --slim
- Created at: 2026-09-28T05:02:23.665Z
- Changed files: 21

## Changed Files
- prisma/schema.prisma
- prisma/seed.ts
- sql/backup-trigger-20260710.sql
- sql/create-scan-trigger.sql
- sql/fix-final-judge-wipe.sql
- sql/fix-rfid-complete.sql
- sql/fix-rfid-reset-leak.sql
- sql/fix-rfid-timing-trigger.sql
- src/app.ts
- src/controllers/manBracket.controller.ts
- src/controllers/rfid.controller.ts
- src/controllers/sequence.controller.ts
- src/index.ts
- src/routes/manBracket.routes.ts
- src/routes/rfid.routes.ts
- src/services/manBracket.service.ts
- src/services/traceability.service.ts
- src/utils/strategyStore.ts
- src/ws/SCAN_MAN_BRACKET/TB_R_SCAN_MAN_BRACKET.ws.ts
- src/ws/SEQUENCE_BATTERY/TB_R_SEQUENCE_BATTERY.ws.ts
- src/ws/setup.ts

## Deployment
- This bundle is overlay-only. Extract on top of an existing backend-runtime folder.
- Restart PM2 or the Windows service after extract.
- If Prisma schema changed, run the migration command before starting the service.
- If deploy fails, restore the previous runtime backup and check logs.
