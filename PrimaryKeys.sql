SELECT
    t.TABLE_SCHEMA [schema],
    t.TABLE_NAME [table],
    cc.COLUMN_NAME [column],
    c.DATA_TYPE [dataType]    
FROM
	INFORMATION_SCHEMA.TABLE_CONSTRAINTS t,
	INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE cc,
	INFORMATION_SCHEMA.COLUMNS c
WHERE
	cc.CONSTRAINT_NAME = t.CONSTRAINT_NAME
	AND c.TABLE_NAME = t.TABLE_NAME
	AND cc.COLUMN_NAME = c.COLUMN_NAME
	AND t.CONSTRAINT_TYPE = 'PRIMARY KEY'