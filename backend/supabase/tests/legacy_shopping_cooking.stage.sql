-- Runs the production converter block against isolated, non-empty fixtures.
-- Requires migrated schema through rename 009. All synthetic rows roll back.
begin;
set local timezone='UTC';
-- Isolate test-only source documents; the outer test transaction restores them.
delete from public.datos_personales where data_key in ('shopping','cooking_progress');
insert into auth.users(id,email,raw_user_meta_data)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','legacy-converter-test@example.invalid','{}');
insert into public.estado_cuenta(user_id,active) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
insert into public.categorias(id,name,normalized_name) values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','LegacyTest','legacytest');
insert into public.unidades(id,name,abbreviation,dimension) values('dddddddd-dddd-4ddd-8ddd-dddddddddddd','Legacy test unit','ltu','count');
insert into public.recetas(id,legacy_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
values('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','legacy-recipe-test','official','Legacy recipe test',10,2,'easy','published');
insert into public.pasos_receta(recipe_id,position,instruction,duration_minutes)
values('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',1,'Test step',1);
insert into public.articulos_despensa(id,user_id,name,category,quantity,unit,minimum,source_shopping_ids)
values('ffffffff-ffff-4fff-8fff-ffffffffffff','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Already transferred','LegacyTest',1,'ltu',0,array['legacy-transferred']);
insert into public.datos_personales(user_id,data_key,value,updated_at) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','shopping',jsonb_build_array(
   jsonb_build_object('id','legacy-active','name','Active item','category','LegacyTest','quantity',2,'unit','ltu','note','','checked',true,'sources',jsonb_build_array('manual')),
   jsonb_build_object('id','legacy-transferred','name','Already transferred','category','LegacyTest','quantity',1,'unit','ltu','note','','checked',true,'transferredToPantry',true,'transferredAt','2026-11-01T00:00:00Z','sources',jsonb_build_array('manual'))),now()),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','cooking_progress',jsonb_build_array(jsonb_build_object(
   'recipeId','legacy-recipe-test','stepIndex',0,'completed',jsonb_build_array(0),'portions',2,
   'startedAt','2026-11-01T12:00:00Z','timer',jsonb_build_object('stepIndex',0,'remainingMs',30000,'deadlineAt',extract(epoch from clock_timestamp()+interval '30 seconds')*1000))),now());
create function pg_temp.convert_legacy() returns void language plpgsql as $fn$
declare expected_count bigint; d record; item jsonb; link jsonb; raw_id text; source_name text;
  list_uuid uuid; item_uuid uuid; recipe_uuid uuid; plan_uuid uuid; ing_uuid uuid; unit_uuid uuid;
  session_uuid uuid; started timestamptz; snapshot jsonb; recipe_row record; idx integer; step_count integer;
  deadline bigint; remaining bigint; tstate text; completed boolean; ingredient_rows jsonb; step_rows jsonb;
  expected_items bigint := 0; inserted_items bigint := 0; transferred_items bigint := 0;
  expected_sessions bigint := 0; inserted_sessions bigint := 0;
begin
  if exists(select 1 from public.listas_compras) or exists(select 1 from public.sesiones_cocina where finished_at is null)
     or exists(select 1 from public.pasos_sesion_cocina p join public.sesiones_cocina s on s.id=p.session_id where s.finished_at is null) then
    raise exception 'Destino de compras/cocina no vacío; se rechaza sobrescribirlo.';
  end if;
  if exists(select 1 from public.datos_personales where data_key in ('shopping','cooking_progress')
      and (jsonb_typeof(value) is distinct from 'array')) then
    raise exception 'Documento shopping/cooking_progress debe ser arreglo JSON.';
  end if;
  if exists(select 1 from public.datos_personales legacy_source where legacy_source.data_key in ('shopping','cooking_progress')
      and not exists(select 1 from auth.users u where u.id=legacy_source.user_id)) then
    raise exception 'Documento legacy sin cuenta Auth.';
  end if;

  for d in select user_id,value,updated_at from public.datos_personales where data_key='shopping' order by user_id loop
    list_uuid := md5('cocinapp:legacy-shopping-list:'||d.user_id::text)::uuid;
    insert into public.listas_compras(id,owner_user_id,created_at,updated_at)
      values(list_uuid,d.user_id,d.updated_at,d.updated_at);
    for item in select value from jsonb_array_elements(d.value) loop
      expected_items := expected_items+1;
      if jsonb_typeof(item) is distinct from 'object' or jsonb_typeof(item->'id') is distinct from 'string'
        or length(item->>'id')=0 or jsonb_typeof(item->'name') is distinct from 'string'
        or length(trim(item->>'name')) not between 1 and 70 or jsonb_typeof(item->'quantity') is distinct from 'number'
        or jsonb_typeof(item->'unit') is distinct from 'string' or jsonb_typeof(item->'category') is distinct from 'string'
        or jsonb_typeof(item->'note') is distinct from 'string' or length(item->>'note')>200
        or jsonb_typeof(item->'checked') is distinct from 'boolean' or jsonb_typeof(item->'sources') is distinct from 'array'
        or jsonb_array_length(item->'sources')=0 then
        raise exception 'Artículo de compra legacy malformado (cuenta %, índice %).',d.user_id,expected_items;
      end if;
      if (item ? 'transferredToPantry' and jsonb_typeof(item->'transferredToPantry') not in ('boolean','null'))
        or (item ? 'transferredAt' and jsonb_typeof(item->'transferredAt') not in ('string','null')) then
        raise exception 'Metadatos de transferencia legacy malformados (cuenta %).',d.user_id;
      end if;
      raw_id:=item->>'id';
      if exists(select 1 from jsonb_array_elements(d.value) e where e->>'id'=raw_id group by e->>'id' having count(*)>1) then
        raise exception 'Identificador legacy de compra duplicado (cuenta %).',d.user_id;
      end if;
      if (item->>'quantity')::numeric<=0 or (item->>'quantity')::numeric>1000000
        or (item->>'quantity')::numeric<>round((item->>'quantity')::numeric,4) then
        raise exception 'Cantidad fuera de rango o precisión SQL no representable (cuenta %).',d.user_id;
      end if;
      select id into unit_uuid from public.unidades where abbreviation=item->>'unit' and active and not is_deleted;
      if unit_uuid is null then raise exception 'Unidad legacy ausente o inactiva (cuenta %).',d.user_id; end if;
      if not exists(select 1 from public.categorias where name=item->>'category' and active and not is_deleted) then
        raise exception 'Categoría legacy no coincide exactamente con catálogo (cuenta %).',d.user_id;
      end if;
      ing_uuid:=null;
      if item ? 'ingredientId' and jsonb_typeof(item->'ingredientId')='string' and item->>'ingredientId'<>'' then
        select id into ing_uuid from public.ingredientes where (legacy_id=item->>'ingredientId' or id::text=item->>'ingredientId') and active and not is_deleted;
        if ing_uuid is null then raise exception 'Referencia de ingrediente sin resolver (cuenta %).',d.user_id; end if;
      elsif item ? 'ingredientId' and jsonb_typeof(item->'ingredientId') not in ('null','string') then
        raise exception 'Referencia ingredientId malformada (cuenta %).',d.user_id;
      end if;
      -- `readShoppingItems` filters transferred items; sourceShoppingIds is the durable
      -- duplicate guard. Preserve those source rows unchanged and never recreate stock.
      if coalesce(item->>'transferredToPantry','false')='true'
        or exists(select 1 from public.articulos_despensa p where d.user_id=p.user_id and raw_id=any(p.source_shopping_ids)) then
        transferred_items:=transferred_items+1;
        continue;
      end if;
      if not (item->>'checked')::boolean then null; end if;
      item_uuid:=md5('cocinapp:legacy-shopping-item:'||d.user_id::text||':'||raw_id)::uuid;
      source_name:=item->'sources'->>0;
      if source_name not in ('manual','recipe','plan','favorites','pantry') then raise exception 'Origen de compra inválido (cuenta %).',d.user_id; end if;
      insert into public.articulos_compra(id,list_id,ingredient_id,name_snapshot,category_snapshot,quantity,unit_id,note,checked,source,created_at,updated_at)
        values(item_uuid,list_uuid,ing_uuid,item->>'name',item->>'category',(item->>'quantity')::numeric,unit_uuid,item->>'note',(item->>'checked')::boolean,source_name,d.updated_at,d.updated_at);
      -- Retain every source. Recipe/plan refs are inserted only when explicitly linked
      -- and uniquely resolvable to the current relational catalog/plan.
      for link in select value from jsonb_array_elements(item->'sources') loop
        source_name:=link #>> '{}';
        if source_name not in ('manual','recipe','plan','favorites','pantry') then raise exception 'Origen de compra inválido (cuenta %).',d.user_id; end if;
        recipe_uuid:=null; plan_uuid:=null;
        if source_name='recipe' then
          if (select count(*) from jsonb_array_elements(coalesce(item->'sourceLinks','[]'::jsonb)) l(value) where l.value->>'source'='recipe')=0 then
            raise exception 'Origen recipe sin enlaces conservables (cuenta %).',d.user_id;
          end if;
          for link in select value from jsonb_array_elements(coalesce(item->'sourceLinks','[]'::jsonb)) where value->>'source'='recipe' loop
            if nullif(link->>'recipe_id','') is null then raise exception 'Enlace recipe sin ID (cuenta %).',d.user_id; end if;
            select count(*) into expected_count from public.recetas where (legacy_id=link->>'recipe_id' or id::text=link->>'recipe_id')
              and (owner_user_id is null or owner_user_id=d.user_id) and active and not is_deleted;
            if expected_count<>1 then raise exception 'Enlace recipe ambiguo o sin resolver (cuenta %).',d.user_id; end if;
            select id into recipe_uuid from public.recetas where (legacy_id=link->>'recipe_id' or id::text=link->>'recipe_id')
              and (owner_user_id is null or owner_user_id=d.user_id) and active and not is_deleted;
            insert into public.origenes_articulo_compra(shopping_item_id,source,recipe_id)
              values(item_uuid,source_name,recipe_uuid) on conflict do nothing;
          end loop;
        elsif source_name='plan' then
          if (select count(*) from jsonb_array_elements(coalesce(item->'sourceLinks','[]'::jsonb)) l(value) where l.value->>'source'='plan')=0 then
            raise exception 'Origen plan sin enlaces conservables (cuenta %).',d.user_id;
          end if;
          for link in select value from jsonb_array_elements(coalesce(item->'sourceLinks','[]'::jsonb)) where value->>'source'='plan' loop
            if nullif(link->>'plan_id','') is null then raise exception 'Enlace plan sin ID (cuenta %).',d.user_id; end if;
            select count(*) into expected_count from public.planes_comida where owner_user_id=d.user_id and id::text=link->>'plan_id';
            if expected_count<>1 then raise exception 'Enlace plan no resuelto (cuenta %).',d.user_id; end if;
            select id into plan_uuid from public.planes_comida where owner_user_id=d.user_id and id::text=link->>'plan_id';
            insert into public.origenes_articulo_compra(shopping_item_id,source,plan_id)
              values(item_uuid,source_name,plan_uuid) on conflict do nothing;
          end loop;
          continue;
        end if;
        if source_name<>'recipe' then
          insert into public.origenes_articulo_compra(shopping_item_id,source,recipe_id,plan_id)
            values(item_uuid,source_name,recipe_uuid,plan_uuid) on conflict do nothing;
        end if;
      end loop;
      inserted_items:=inserted_items+1;
    end loop;
  end loop;

  for d in select user_id,value,updated_at from public.datos_personales where data_key='cooking_progress' order by user_id loop
    for item in select value from jsonb_array_elements(d.value) loop
      expected_sessions:=expected_sessions+1;
      if jsonb_typeof(item) is distinct from 'object' or jsonb_typeof(item->'recipeId') is distinct from 'string'
        or jsonb_typeof(item->'stepIndex') is distinct from 'number' or jsonb_typeof(item->'completed') is distinct from 'array'
        or jsonb_typeof(item->'portions') is distinct from 'number' or jsonb_typeof(item->'startedAt') is distinct from 'string'
        or (item->>'portions')::numeric<>trunc((item->>'portions')::numeric) or (item->>'portions')::integer not between 1 and 20 then
        raise exception 'Sesión de cocina malformada (cuenta %).',d.user_id;
      end if;
      select * into recipe_row from public.recetas where legacy_id=item->>'recipeId'
        and (owner_user_id is null or owner_user_id=d.user_id) and active and not is_deleted;
      if not found then raise exception 'Receta de sesión inexistente o ajena (cuenta %).',d.user_id; end if;
      if (item->>'stepIndex')::numeric<>trunc((item->>'stepIndex')::numeric) or (item->>'stepIndex')::integer<0
        or not exists(select 1 from public.pasos_receta where recipe_id=recipe_row.id and position=(item->>'stepIndex')::integer+1) then
        raise exception 'Paso activo fuera de la receta migrada (cuenta %).',d.user_id;
      end if;
      if exists(select 1 from jsonb_array_elements(item->'completed') c(value) where jsonb_typeof(c.value) is distinct from 'number'
        or (c.value #>> '{}')::numeric<>trunc((c.value #>> '{}')::numeric) or (c.value #>> '{}')::integer<0
        or not exists(select 1 from public.pasos_receta s where s.recipe_id=recipe_row.id and s.position=(c.value #>> '{}')::integer+1)) then
        raise exception 'Paso completado inválido (cuenta %).',d.user_id;
      end if;
      started:=(item->>'startedAt')::timestamptz;
      select coalesce(jsonb_agg(jsonb_build_object('ingredientId',i.id,'name',i.name,'quantity',ri.quantity,'unit',u.abbreviation,
        'unitId',u.id,'unitRootId',root.id,'unitDimension',u.dimension,'unitFactor',coalesce(u.equivalence_multiplier,1),'category',c.name)
        order by ri.position),'[]'::jsonb) into ingredient_rows
        from public.ingredientes_receta ri join public.ingredientes i on i.id=ri.ingredient_id
        join public.unidades u on u.id=ri.unit_id join public.unidades root on root.id=coalesce(u.base_unit_id,u.id)
        join public.categorias c on c.id=i.category_id where ri.recipe_id=recipe_row.id;
      select coalesce(jsonb_agg(jsonb_build_object('instruction',s.instruction,'durationMinutes',coalesce(s.duration_minutes,0),
        'temperature',s.temperature,'tip',s.tip,'warning',s.warning,'utensils',to_jsonb(s.utensils),
        'specialInstructions',s.special_instructions,'stepIngredients',coalesce(si.ingredients,'[]'::jsonb)) order by s.position),'[]'::jsonb)
        into step_rows from public.pasos_receta s left join lateral (
          select jsonb_agg(jsonb_build_object('ingredientId',i.id,'name',i.name,'quantity',coalesce(x.quantity_override,ri.quantity),
            'unit',u.abbreviation,'unitId',u.id,'unitRootId',root.id,'unitDimension',u.dimension,
            'unitFactor',coalesce(u.equivalence_multiplier,1),'category',c.name) order by ri.position) ingredients
          from public.ingredientes_paso_receta x join public.ingredientes_receta ri on ri.id=x.recipe_ingredient_id
          join public.ingredientes i on i.id=ri.ingredient_id join public.unidades u on u.id=ri.unit_id
          join public.unidades root on root.id=coalesce(u.base_unit_id,u.id) join public.categorias c on c.id=i.category_id
          where x.step_id=s.id
        ) si on true where s.recipe_id=recipe_row.id;
      snapshot:=jsonb_build_object('id',recipe_row.id::text,'name',recipe_row.title,'description',recipe_row.description,
        'category',recipe_row.category_label,'minutes',recipe_row.total_minutes,'portions',recipe_row.portions,
        'difficulty',case recipe_row.difficulty when 'intermediate' then 'Intermedia' when 'advanced' then 'Avanzada' else 'Fácil' end,
        'symbol',recipe_row.symbol,'color',recipe_row.color,'image',recipe_row.image_path,'imageAlt',recipe_row.image_alt,
        'crossContaminationNote',recipe_row.cross_contamination_note,'legacyRecipeId',item->>'recipeId','snapshotOrigin','migration_catalog',
        'ingredients',ingredient_rows,'steps',step_rows);
      session_uuid:=md5('cocinapp:legacy-cooking-session:'||d.user_id::text||':'||(item->>'recipeId')||':'||started::text)::uuid;
      insert into public.sesiones_cocina(id,owner_user_id,recipe_id,recipe_snapshot,recipe_version,portions,requested_portions,current_step,client_idempotency_key,started_at)
        values(session_uuid,d.user_id,recipe_row.id,snapshot,recipe_row.version::integer,(item->>'portions')::integer,(item->>'portions')::integer,
          (item->>'stepIndex')::integer,session_uuid,started);
      select count(*)::integer into step_count from public.pasos_receta where recipe_id=recipe_row.id;
      for idx in 0..step_count-1 loop
        completed:=exists(select 1 from jsonb_array_elements(item->'completed') c(value) where (c.value #>> '{}')::integer=idx);
        remaining:=null; deadline:=null; tstate:=case when completed then 'finished' else 'idle' end;
        if item ? 'timer' then
          if jsonb_typeof(item->'timer') is distinct from 'object'
            or jsonb_typeof(item->'timer'->'stepIndex') is distinct from 'number'
            or (item->'timer'->>'stepIndex')::integer<>(item->>'stepIndex')::integer then
            raise exception 'Temporizador asociado a otro paso o malformado (cuenta %).',d.user_id;
          end if;
          if jsonb_typeof(item->'timer'->'remainingMs') is distinct from 'number'
            or (item->'timer'->>'remainingMs')::numeric<0 or (item->'timer'->>'remainingMs')::numeric<>trunc((item->'timer'->>'remainingMs')::numeric) then
            raise exception 'Temporizador inválido (cuenta %).',d.user_id;
          end if;
          remaining:=(item->'timer'->>'remainingMs')::bigint;
          if item->'timer' ? 'deadlineAt' then
            deadline:=(item->'timer'->>'deadlineAt')::numeric::bigint;
            remaining:=greatest(0,deadline-(extract(epoch from clock_timestamp())*1000)::bigint);
            tstate:=case when remaining=0 then 'finished' else 'running' end;
          else tstate:='paused'; end if;
        end if;
        insert into public.pasos_sesion_cocina(session_id,step_position,completed_at,remaining_ms,timer_deadline_at,timer_state)
          values(session_uuid,idx+1,case when completed then started else null end,
            case when idx=(item->>'stepIndex')::integer then remaining else null end,
            case when idx=(item->>'stepIndex')::integer and deadline is not null and tstate='running' then to_timestamp(deadline::numeric/1000) else null end,
            case when idx=(item->>'stepIndex')::integer then tstate else case when completed then 'finished' else 'idle' end end);
      end loop;
      inserted_sessions:=inserted_sessions+1;
    end loop;
  end loop;
  if expected_items<>inserted_items+transferred_items then raise exception 'Reconciliación de compras fallida.'; end if;
  if inserted_sessions<>expected_sessions then raise exception 'Reconciliación de sesiones activas fallida.'; end if;
  raise notice 'Reconciliación: compras activas %, compras transferidas conservadas en origen/despensa %, sesiones activas %.',inserted_items,transferred_items,inserted_sessions;
exception when others then
  -- Avoid echoing raw JSON values (which may contain user-authored data) in SQL errors.
  raise exception 'Conversión compras/cocina cancelada; datos inválidos, destino ocupado o referencias no migradas. SQLSTATE %: %.',sqlstate,sqlerrm;
end;
$fn$;
select pg_temp.convert_legacy();
do $$
declare l uuid; s public.sesiones_cocina; session_json jsonb; stock_result jsonb;
begin
 select id into l from public.listas_compras where owner_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 if l is null or (select count(*) from public.articulos_compra where list_id=l)<>1
   or not (select checked from public.articulos_compra where list_id=l) then raise exception 'Active/checked shopping mapping failed'; end if;
 if exists(select 1 from public.articulos_compra where name_snapshot='Already transferred') then raise exception 'Transferred item was reactivated'; end if;
 if (select quantity from public.articulos_despensa where id='ffffffff-ffff-4fff-8fff-ffffffffffff')<>1
   or (select source_shopping_ids from public.articulos_despensa where id='ffffffff-ffff-4fff-8fff-ffffffffffff')<>array['legacy-transferred'] then raise exception 'Pantry stock/provenance changed'; end if;
 select * into s from public.sesiones_cocina where owner_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 if s.id is null or s.finished_at is not null or s.portions<>2 or s.current_step<>0
   or s.recipe_snapshot->>'snapshotOrigin'<>'migration_catalog' then raise exception 'Active cooking session mapping failed'; end if;
 if not exists(select 1 from public.pasos_sesion_cocina where session_id=s.id and step_position=1
   and completed_at is not null and timer_state='running' and remaining_ms between 29000 and 30000 and timer_deadline_at is not null) then raise exception 'Cooking progress/timer mapping failed'; end if;
 perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
 session_json:=public.get_my_cooking_session(s.id);
 stock_result:=public.check_my_cooking_stock(null,null,s.id);
 if session_json->>'id'<>s.id::text or jsonb_typeof(session_json->'steps')<>'array' or stock_result->'ingredients'<>'[]'::jsonb or stock_result->>'sessionId'<>s.id::text then
   raise exception 'Migrated cooking session is not readable/checkable through RPCs'; end if;
 perform public.update_my_cooking_session(s.id,1,'timer_pause',0,null);
 perform public.finish_my_cooking_session(s.id,2,false);
 if not exists(select 1 from public.eventos_cocina where session_id=s.id and not deduct_stock)
   or (select quantity from public.articulos_despensa where id='ffffffff-ffff-4fff-8fff-ffffffffffff')<>1 then
   raise exception 'Finish without stock discount changed pantry or omitted event'; end if;
end $$;
-- Re-run is rejected while relational destination has rows; source stays intact.
do $$ begin
  begin perform pg_temp.convert_legacy(); raise exception 'non-empty replay unexpectedly passed';
  exception when others then if sqlerrm='non-empty replay unexpectedly passed' then raise; end if; end;
end $$;
-- Remove only synthetic relational rows, then prove malformed legacy JSON aborts atomically.
delete from public.listas_compras where owner_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
delete from public.eventos_cocina where owner_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
delete from public.sesiones_cocina where owner_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
update public.datos_personales set value=value||jsonb_build_array(jsonb_build_object('id','bad','name','','quantity','bad'))
 where user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and data_key='shopping';
do $$ begin
  begin perform pg_temp.convert_legacy(); raise exception 'malformed input unexpectedly passed';
  exception when others then if sqlerrm='malformed input unexpectedly passed' then raise; end if; end;
end $$;
do $$ begin
 if (select count(*) from public.listas_compras where owner_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')<>0
   or (select count(*) from public.sesiones_cocina where owner_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')<>0 then
   raise exception 'Malformed conversion left partial destination rows';
 end if;
end $$;
rollback;
select 'PASS: production converter mapped active rows and rejected malformed input; all fixtures rolled back' as result;
