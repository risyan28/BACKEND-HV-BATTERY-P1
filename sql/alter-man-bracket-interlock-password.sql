-- Simple setup for TB_R_MAN_BRACKET_INTERLOCK
-- Using DESTINATION column to store password
-- FID=1 → ASSY with password
-- FID=2 → CKD with password (12345678)

-- Ensure FID=1 exists
IF NOT EXISTS (
    SELECT 1
    FROM [dbo].[TB_R_MAN_BRACKET_INTERLOCK]
    WHERE [FID] = 1
)
BEGIN
    INSERT INTO [dbo].[TB_R_MAN_BRACKET_INTERLOCK] (
        [FID],
        [DESTINATION],
        [FUPDATE]
    ) VALUES (
        1,
        '12345678',
        GETDATE()
    )
    PRINT 'FID=1 created with password in DESTINATION'
END
GO

-- Ensure FID=2 exists with password
IF NOT EXISTS (
    SELECT 1
    FROM [dbo].[TB_R_MAN_BRACKET_INTERLOCK]
    WHERE [FID] = 2
)
BEGIN
    INSERT INTO [dbo].[TB_R_MAN_BRACKET_INTERLOCK] (
        [FID],
        [DESTINATION],
        [FUPDATE]
    ) VALUES (
        2,
        '12345678',
        GETDATE()
    )
    PRINT 'FID=2 created with password in DESTINATION'
END
ELSE
BEGIN
    UPDATE [dbo].[TB_R_MAN_BRACKET_INTERLOCK]
    SET [DESTINATION] = '12345678',
        [FUPDATE] = GETDATE()
    WHERE [FID] = 2
    
    PRINT 'FID=2 updated with password'
END
GO

-- Verify
PRINT '--- Final Table State ---'
SELECT [FID], [DESTINATION], [FUPDATE]
FROM [dbo].[TB_R_MAN_BRACKET_INTERLOCK]
ORDER BY [FID]
GO

PRINT '✓ Setup complete'




