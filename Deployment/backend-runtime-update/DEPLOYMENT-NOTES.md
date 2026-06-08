# Backend Runtime Update Notes

- Bundle mode: slim
- Selected from: code-only update
- Created at: 2026-05-29T07:31:09.861Z
- Changed files: 5

## Changed Files
- docs/WTG-DB-GUIDE.md
- sql/test.sql
- src/services/manBracket.service.ts
- src/services/sequence.service.ts
- src/utils/active-days-converter.ts

## Deployment
- This bundle is overlay-only. Extract on top of an existing backend-runtime folder.
- Restart PM2 or the Windows service after extract.
- If Prisma schema changed, run the migration command before starting the service.
- If deploy fails, restore the previous runtime backup and check logs.
