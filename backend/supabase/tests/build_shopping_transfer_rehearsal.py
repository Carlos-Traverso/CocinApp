"""Build rollback-only transfer rehearsal and isolated local install."""
from pathlib import Path
root=Path(__file__).resolve().parent.parent
schema=(root/'migrations/202610300002_add_relational_domain_tables.sql').read_text(encoding='utf-8').rsplit('commit;',1)[0]
rpcs=''.join((root/'migrations'/name).read_text(encoding='utf-8').replace('begin;','',1).rsplit('commit;',1)[0] for name in (
'202610300003_personal_write_rpcs.sql','202610300004_planning_write_rpcs.sql','202610300005_shopping_write_rpcs.sql','202610300006_shopping_transfer_rpcs.sql'))
stage=(root/'tests/shopping_transfer_rpcs.stage.sql').read_text(encoding='utf-8')
(root/'tests/shopping_transfer_rehearsal.sql').write_text('-- Run COMPLETE as postgres. Keep final ROLLBACK.\n'+schema.replace('begin;',"begin;\nset local lock_timeout='5s';\nset local statement_timeout='120s';",1)+rpcs+stage+'\nrollback;\n',encoding='utf-8')
(root/'tests/fixtures/shopping_transfer_concurrency_install.sql').write_text('-- LOCAL ISOLATED DATABASE ONLY. Not a Supabase deployment script.\n'+schema+rpcs+'\ncommit;\n',encoding='utf-8')
