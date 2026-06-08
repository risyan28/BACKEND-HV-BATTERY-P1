 -- Insert statements for trigger here
	UPDATE A
 SET 
     A.REG_VALUE =
     (
         '{' +
         '"command": "signIn",' +
         '"productId": "' + I.BARCODE + '",' +
         '"sequenceNumber": "' + I.BARCODE + '",' +
         '"stationId": "1_4",' +
         '"prCodes": ["' + CASE WHEN UPPER(LTRIM(RTRIM(I.DESTINATION))) = 'SERVICE PART' THEN 'S/P' ELSE I.DESTINATION END + '"]' +
         '}'
     ),
     A.WRITE_FLAG = 0,
     A.TR_TIME = GETDATE()
 FROM DB_TMMIN1_KRW_ATLAS_COPCO.dbo.TB_R_WRITE_DEVICE_AIS A
 CROSS JOIN (
     SELECT TOP 1 BARCODE, DESTINATION 
     FROM INSERTED
     ORDER BY FID DESC
 )  I
 WHERE 
     A.DEV_NAME = 'AVANTGUARD-HV-BATTERY'
     AND A.PROTOCOL = 'Avantguard'
     AND A.GROUP_NAME = '1_4';