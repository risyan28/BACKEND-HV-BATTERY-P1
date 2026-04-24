-- Add FVALUE column to TB_R_MAN_BRACKET
-- FVALUE = 0 : scanned / in progress
-- FVALUE = 1 : process completed
IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[TB_R_MAN_BRACKET]')
      AND name = 'FVALUE'
)
BEGIN
    ALTER TABLE [dbo].[TB_R_MAN_BRACKET]
    ADD [FVALUE] INT NOT NULL DEFAULT 0

    PRINT 'Column FVALUE added to TB_R_MAN_BRACKET.'
END
ELSE
BEGIN
    PRINT 'Column FVALUE already exists.'
END
