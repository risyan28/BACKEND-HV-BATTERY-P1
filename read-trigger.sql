-- Read existing trigger definition
SELECT 
  OBJECT_NAME(tr.object_id) AS TriggerName,
  OBJECT_DEFINITION(tr.object_id) AS TriggerDefinition,
  tr.create_date,
  tr.modify_date
FROM sys.triggers tr
WHERE tr.name = 'TR_PLAN_DETAIL_SYNC_TARGET_PROD'
  AND OBJECT_NAME(tr.parent_object_id) = 'TB_H_PROD_PLAN_DETAIL';
