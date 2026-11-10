WITH included_tables AS (
  SELECT n.nspname AS schema_name, c.relname AS table_name, c.oid AS table_oid,
         c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced,
         c.relkind = 'p' AS partitioned
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE (n.nspname = 'public' AND c.relkind IN ('r','p'))
     OR (n.nspname = 'auth' AND c.relname = 'users' AND c.relkind IN ('r','p'))
), table_data AS (
  SELECT t.schema_name, t.table_name, t.table_oid, t.rls_enabled, t.rls_forced, t.partitioned,
    (SELECT jsonb_agg(jsonb_build_object(
      'name', a.attname, 'type', format_type(a.atttypid,a.atttypmod),
      'nullable', NOT a.attnotnull,
      'default', pg_get_expr(d.adbin,d.adrelid),
      'identity', nullif(a.attidentity,''), 'generated', nullif(a.attgenerated,''),
      'primary_key', EXISTS (SELECT 1 FROM pg_constraint pk WHERE pk.conrelid=t.table_oid AND pk.contype='p' AND a.attnum=ANY(pk.conkey)),
      'unique', EXISTS (SELECT 1 FROM pg_constraint uq WHERE uq.conrelid=t.table_oid AND uq.contype='u' AND a.attnum=ANY(uq.conkey))
    ) ORDER BY a.attnum)
     FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
     WHERE a.attrelid=t.table_oid AND a.attnum>0 AND NOT a.attisdropped
       AND (t.schema_name <> 'auth' OR a.attname='id')) AS columns,
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'name', con.conname,
      'type', CASE con.contype WHEN 'p' THEN 'primary_key' WHEN 'u' THEN 'unique' WHEN 'c' THEN 'check' END,
      'columns', (SELECT jsonb_agg(a.attname ORDER BY k.ord) FROM unnest(con.conkey) WITH ORDINALITY k(attnum,ord) JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=k.attnum),
      'definition', pg_get_constraintdef(con.oid), 'validated', con.convalidated
    ) ORDER BY con.conname),'[]'::jsonb)
     FROM pg_constraint con WHERE con.conrelid=t.table_oid AND con.contype IN ('p','u','c')
       AND (t.schema_name <> 'auth' OR con.contype='p')) AS constraints,
    (SELECT coalesce(jsonb_agg(jsonb_build_object('name',ic.relname,'unique',ix.indisunique,'primary',ix.indisprimary,'definition',pg_get_indexdef(ix.indexrelid),'predicate',pg_get_expr(ix.indpred,ix.indrelid)) ORDER BY ic.relname),'[]'::jsonb)
     FROM pg_index ix JOIN pg_class ic ON ic.oid=ix.indexrelid
     WHERE ix.indrelid=t.table_oid AND ix.indisunique AND NOT ix.indisprimary) AS unique_indexes
  FROM included_tables t
), fk_data AS (
 SELECT jsonb_agg(jsonb_build_object(
   'name', con.conname, 'source_schema', sn.nspname, 'source_table', sc.relname,
   'source_columns', (SELECT jsonb_agg(a.attname ORDER BY k.ord) FROM unnest(con.conkey) WITH ORDINALITY k(attnum,ord) JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=k.attnum),
   'target_schema', tn.nspname, 'target_table', tc.relname,
   'target_columns', (SELECT jsonb_agg(a.attname ORDER BY k.ord) FROM unnest(con.confkey) WITH ORDINALITY k(attnum,ord) JOIN pg_attribute a ON a.attrelid=con.confrelid AND a.attnum=k.attnum),
   'on_delete', CASE con.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT' WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END,
   'validated',con.convalidated
 ) ORDER BY sn.nspname,sc.relname,con.conname) AS data
 FROM pg_constraint con JOIN pg_class sc ON sc.oid=con.conrelid JOIN pg_namespace sn ON sn.oid=sc.relnamespace
 JOIN pg_class tc ON tc.oid=con.confrelid JOIN pg_namespace tn ON tn.oid=tc.relnamespace
 WHERE con.contype='f' AND con.conrelid IN (SELECT table_oid FROM included_tables)
)
SELECT jsonb_pretty(jsonb_build_object(
 'schema','public', 'generated_from','PostgreSQL catalogs after local migrations through 202611010012; no remote connection',
 'tables',(SELECT jsonb_agg(jsonb_build_object('schema',schema_name,'name',table_name,'external',CASE WHEN schema_name='auth' THEN 'stub' END,'rls_enabled',rls_enabled,'rls_forced',rls_forced,'partitioned',partitioned,'columns',columns,'constraints',constraints,'unique_indexes',unique_indexes) ORDER BY schema_name,table_name) FROM table_data),
 'foreign_keys',(SELECT coalesce(data,'[]'::jsonb) FROM fk_data),
 'counts',jsonb_build_object('public_tables',(SELECT count(*) FROM table_data WHERE schema_name='public'),'tables_including_auth_stub',(SELECT count(*) FROM table_data),'columns',(SELECT sum(jsonb_array_length(columns)) FROM table_data),'foreign_keys',(SELECT count(*) FROM pg_constraint con WHERE con.contype='f' AND con.conrelid IN(SELECT table_oid FROM included_tables)),'constraints_pk_unique_check',(SELECT count(*) FROM pg_constraint con WHERE con.contype IN ('p','u','c') AND con.conrelid IN(SELECT table_oid FROM included_tables) AND (con.conrelid <> 'auth.users'::regclass OR con.contype='p')))
));
