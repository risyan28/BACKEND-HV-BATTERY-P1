-- Rename FLAG column to FVALUE for TB_R_MAN_BRACKET
IF EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[TB_R_MAN_BRACKET]')
      AND name = 'FLAG'
) AND NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[TB_R_MAN_BRACKET]')
      AND name = 'FVALUE'
)
BEGIN
    EXEC sp_rename 'dbo.TB_R_MAN_BRACKET.FLAG', 'FVALUE', 'COLUMN'
    PRINT 'Column FLAG renamed to FVALUE.'
END

IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[dbo].[TB_R_MAN_BRACKET]')
      AND name = 'FVALUE'
)
BEGIN
    ALTER TABLE [dbo].[TB_R_MAN_BRACKET]
    ADD [FVALUE] INT NOT NULL CONSTRAINT DF_TB_R_MAN_BRACKET_FVALUE DEFAULT 0

    PRINT 'Column FVALUE added to TB_R_MAN_BRACKET.'
END
ELSE
BEGIN
    PRINT 'Column FVALUE already exists.'
END
