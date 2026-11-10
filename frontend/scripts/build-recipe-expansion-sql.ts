import { createHash } from 'node:crypto'
import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createJiti } from 'jiti'
import type { Recipe } from '../src/features/recipes/domain/Recipe.ts'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const outputDirectory = resolve(root, 'backend/supabase/seeds')
const jiti = createJiti(import.meta.url)
const { expandedRecipes } = await jiti.import<{ expandedRecipes: Recipe[] }>('../src/mocks/expandedRecipes.ts')
const { inferIngredientCategory } = await jiti.import<{ inferIngredientCategory(name: string): string | undefined }>('../src/features/admin/domain/ingredientCategory.ts')

const namespace = Buffer.from('f7d5b8c1a6e34a60a1c4f5913027d8af', 'hex')
function stableUuid(value: string): string {
  const digest = createHash('sha1').update(Buffer.concat([namespace, Buffer.from(value)])).digest()
  digest[6] = (digest[6]! & 0x0f) | 0x50
  digest[8] = (digest[8]! & 0x3f) | 0x80
  const hex = digest.subarray(0, 16).toString('hex')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}
function sql(value: string): string { return `'${value.replace(/'/g, "''")}'` }
function sqlNullable(value: string | undefined): string { return value === undefined ? 'null' : sql(value) }
function normalize(value: string): string {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().replace(/\s+/g, ' ').toLocaleLowerCase('es')
}
function jsonb(value: unknown): string { return `${sql(JSON.stringify(value))}::jsonb` }
function values(rows: string[][]): string { return rows.map((row) => `  (${row.join(', ')})`).join(',\n') }

const manualCategories: Record<string, string> = {
  agua: 'Almacén', canela: 'Almacén', ricota: 'Lácteos', 'semillas de chia': 'Almacén', frutillas: 'Frutas y verduras',
  lechuga: 'Frutas y verduras', polenta: 'Granos y legumbres', zucchini: 'Frutas y verduras',
  'porotos blancos cocidos': 'Granos y legumbres', 'cacao amargo sin azucar': 'Almacén', naranja: 'Frutas y verduras',
  azucar: 'Almacén', 'polvo de hornear': 'Almacén', cebolla: 'Frutas y verduras',
}
const baseUnits = {
  g: { name: 'Gramo', dimension: 'mass' },
  ml: { name: 'Mililitro', dimension: 'volume' },
  u: { name: 'Unidad', dimension: 'count' },
} as const
const shifts: Record<string, string> = { Desayuno: 'breakfast', Almuerzo: 'lunch', Merienda: 'snack', Cena: 'dinner' }
const tagKeys: Record<string, string> = {
  'Sin TACC': 'gluten-free', Vegetariana: 'vegetarian', Vegana: 'vegan', 'Sin lactosa': 'lactose-free', 'Sin frutos secos': 'nut-free',
}

function ingredientCategory(name: string, explicit: string | undefined): string {
  const category = explicit ?? inferIngredientCategory(name) ?? manualCategories[normalize(name)]
  if (!category) throw new Error(`Falta categoría explícita para ingrediente: ${name}`)
  return category
}

if (expandedRecipes.length !== 20) throw new Error(`Se esperaban 20 recetas y se recibieron ${expandedRecipes.length}.`)
if (new Set(expandedRecipes.map((recipe) => recipe.id)).size !== expandedRecipes.length) throw new Error('Hay ids repetidos en el lote de recetas.')
if (new Set(expandedRecipes.map((recipe) => normalize(recipe.name))).size !== expandedRecipes.length) throw new Error('Hay títulos normalizados repetidos en el lote de recetas.')

const categories = new Map<string, { id: string; name: string; normalized: string }>()
const ingredientMap = new Map<string, { name: string; normalized: string; category: string; unit: keyof typeof baseUnits }>()
const requiredUnits = new Set<keyof typeof baseUnits>()
for (const recipe of expandedRecipes) {
  if (!recipe.id || !recipe.image || recipe.image !== `/assets/recipes/${recipe.id}.webp` || !recipe.imageAlt?.trim()) {
    throw new Error(`ID o referencia de imagen inválida: ${recipe.id}`)
  }
  if (!recipe.ingredients.length || !recipe.steps.length || recipe.stepMeta && recipe.stepMeta.length > recipe.steps.length) {
    throw new Error(`Receta incompleta: ${recipe.id}`)
  }
  if (new Set(recipe.mealShifts ?? []).size !== (recipe.mealShifts?.length ?? 0)
    || !(recipe.mealShifts?.length ? recipe.mealShifts : [recipe.category]).every((shift) => shifts[shift])) {
    throw new Error(`Turnos de comida inválidos: ${recipe.id}`)
  }
  for (const label of recipe.dietaryTags ?? []) if (!tagKeys[label]) throw new Error(`Etiqueta dietaria no reconocida: ${label}`)
  for (const item of recipe.ingredients) {
    const unit = item.unit as keyof typeof baseUnits
    if (!Object.hasOwn(baseUnits, unit)) throw new Error(`Unidad sin definición explícita: ${item.unit} (${item.name})`)
    requiredUnits.add(unit)
    const normalized = normalize(item.name)
    const category = ingredientCategory(item.name, item.category)
    const previous = ingredientMap.get(normalized)
    if (previous && (previous.category !== category || previous.unit !== unit)) {
      throw new Error(`Mapeo inconsistente para ingrediente ${item.name}: categoría/unidad distintas.`)
    }
    ingredientMap.set(normalized, { name: previous?.name ?? item.name, normalized, category, unit })
    categories.set(normalize(category), { id: stableUuid(`recipe-expansion-v4:category:${normalize(category)}`), name: category, normalized: normalize(category) })
  }
  for (const [index, step] of recipe.steps.entries()) {
    if (!step.trim() || step.length > 5000) throw new Error(`Instrucción fuera de rango: ${recipe.id}, paso ${index + 1}`)
    const meta = recipe.stepMeta?.[index]
    if (meta && (meta.durationMinutes ?? meta.minutes ?? 0) > 1440) throw new Error(`Duración de paso fuera de rango: ${recipe.id}, paso ${index + 1}`)
    for (const ref of meta?.stepIngredients ?? []) {
      if (!recipe.ingredients.some((line) => normalize(line.name) === normalize(ref.name) && line.unit === ref.unit)) {
        throw new Error(`Ingrediente de paso sin línea general equivalente: ${recipe.id}, ${ref.name}/${ref.unit}`)
      }
    }
  }
}

const unitRows = [...requiredUnits].sort().map((abbr) => {
  const unit = baseUnits[abbr]
  return [sql(stableUuid(`recipe-expansion-v4:unit:${abbr}`)), sql(abbr), sql(unit.name), sql(normalize(unit.name)), sql(unit.dimension)]
})
const categoryRows = [...categories.values()].sort((a, b) => a.normalized.localeCompare(b.normalized, 'es')).map((category) => [
  sql(category.id), sql(`recipe-expansion-v4:category:${category.normalized}`), sql(category.name), sql(category.normalized),
])
const ingredientRows = [...ingredientMap.values()].sort((a, b) => a.normalized.localeCompare(b.normalized, 'es')).map((ingredient) => [
  sql(stableUuid(`recipe-expansion-v4:ingredient:${ingredient.normalized}`)), sql(`recipe-expansion-v4:ingredient:${ingredient.normalized}`),
  sql(ingredient.name), sql(ingredient.normalized), sql(ingredient.category), sql(ingredient.unit),
])
const recipeRows = expandedRecipes.map((recipe) => [
  sql(stableUuid(`recipe-expansion-v4:recipe:${recipe.id}`)), sql(recipe.id), sql(recipe.name), sql('CocinAPP'), sql(recipe.description),
  sql(recipe.category), String(recipe.minutes), String(recipe.portions), sql(recipe.difficulty === 'Fácil' ? 'easy' : recipe.difficulty === 'Intermedia' ? 'intermediate' : 'advanced'),
  sql(recipe.symbol), sql(recipe.color), String(recipe.featured ?? false), sqlNullable(recipe.crossContaminationNote), sql(recipe.image!), sql(recipe.imageAlt!),
  jsonb(recipe.ingredients), jsonb(recipe.steps), jsonb(recipe.stepMeta ?? []), jsonb(recipe.mealShifts?.length ? recipe.mealShifts : [recipe.category]),
  jsonb((recipe.dietaryTags ?? []).map((tag) => tagKeys[tag])),
])

const sourceSql = `-- Generated from frontend/src/mocks/expandedRecipes.ts. Do not edit by hand.
-- Additive only: preserves unrelated rows and user edits; refuses mismatches.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local timezone = 'UTC';

create temp table rx_recipe_source (
  id uuid primary key, source_id text not null unique, title text not null, author text not null, description text not null,
  category_label text not null, total_minutes integer not null, portions integer not null, difficulty text not null,
  symbol text not null, color text not null, featured boolean not null, cross_note text, image_path text not null, image_alt text not null,
  ingredients jsonb not null, steps jsonb not null, step_meta jsonb not null, shifts jsonb not null, dietary_keys jsonb not null
) on commit drop;
insert into rx_recipe_source values
${values(recipeRows)};

lock table public.categorias,public.unidades,public.ingredientes,public.etiquetas_dieteticas,public.recetas,
  public.ingredientes_receta,public.pasos_receta,public.ingredientes_paso_receta,public.turnos_comida_receta,
  public.etiquetas_dieteticas_receta,public.registro_auditoria in share row exclusive mode;

create temp table rx_needed_categories(id uuid not null, legacy_id text not null, name text not null, normalized_name text primary key) on commit drop;
insert into rx_needed_categories values
${values(categoryRows)};
create temp table rx_needed_units(id uuid not null, abbreviation text primary key, name text not null, normalized_name text not null, dimension text not null) on commit drop;
insert into rx_needed_units values
${values(unitRows)};
create temp table rx_needed_ingredients(id uuid not null, legacy_id text not null, name text not null, normalized_name text primary key, category_name text not null, base_abbreviation text not null) on commit drop;
insert into rx_needed_ingredients values
${values(ingredientRows)};
create temp table rx_tag_input(tag_key text primary key, label text not null) on commit drop;
insert into rx_tag_input values
${values(Object.entries(tagKeys).map(([label, key]) => [sql(key), sql(label)]))};

create temp table rx_category_map on commit drop as
select n.normalized_name, n.name, n.legacy_id, coalesce(c.id,n.id) id, c.id is null as needs_insert
from rx_needed_categories n left join public.categorias c
  on c.normalized_name=n.normalized_name and not c.is_deleted;
create temp table rx_unit_map on commit drop as
select n.abbreviation, n.name, n.normalized_name, n.dimension, coalesce(u.id,n.id) id, u.id is null as needs_insert
from rx_needed_units n left join public.unidades u on lower(u.abbreviation)=lower(n.abbreviation);
create temp table rx_ingredient_map on commit drop as
select n.normalized_name,n.name,n.legacy_id,n.category_name,n.base_abbreviation,
  coalesce(i.id,n.id) id,i.id is null as needs_insert,coalesce(existing_category.active and not existing_category.is_deleted,true) category_active
from rx_needed_ingredients n
left join public.ingredientes i on i.normalized_name=n.normalized_name
left join public.categorias existing_category on existing_category.id=i.category_id;

do $$
declare problems text;
begin
  if to_regclass('public.recetas') is null or to_regclass('public.ingredientes_receta') is null
    or to_regclass('public.pasos_receta') is null or to_regclass('public.ingredientes_paso_receta') is null
    or to_regclass('public.turnos_comida_receta') is null or to_regclass('public.etiquetas_dieteticas_receta') is null
    or to_regclass('public.estado_escritura_receta_admin') is null then
    raise exception 'Falta el esquema relacional final, los renombres españoles o el estado de escritura de recetas. No se modificó nada.';
  end if;
  if (select count(*) from rx_recipe_source) <> 20 then raise exception 'El lote debe contener exactamente 20 recetas.'; end if;

  select string_agg(problem, E'\n') into problems from (
    select 'Categoría ausente/ambigua/inactiva: '||n.name problem from rx_needed_categories n
      where (select count(*) from public.categorias c where c.normalized_name=n.normalized_name and not c.is_deleted and c.active) > 1
        or exists(select 1 from public.categorias c where c.normalized_name=n.normalized_name and not c.is_deleted and not c.active)
        or exists(select 1 from public.categorias c where c.id=n.id and (c.normalized_name is distinct from n.normalized_name or c.is_deleted))
        or exists(select 1 from public.categorias c where c.legacy_id=n.legacy_id and (c.normalized_name is distinct from n.normalized_name or c.is_deleted))
    union all
    select 'Unidad ausente/ambigua/inactiva o con dimensión distinta: '||n.abbreviation from rx_needed_units n
      where (select count(*) from public.unidades u where lower(u.abbreviation)=lower(n.abbreviation)) > 1
        or exists(select 1 from public.unidades u where lower(u.abbreviation)=lower(n.abbreviation) and (not u.active or u.is_deleted or u.dimension<>n.dimension or u.base_unit_id is not null))
        or exists(select 1 from public.unidades u where u.id=n.id and lower(u.abbreviation)<>lower(n.abbreviation))
        or exists(select 1 from public.unidades u where u.legacy_id='recipe-expansion-v4:unit:'||n.abbreviation and lower(u.abbreviation)<>lower(n.abbreviation))
        or exists(select 1 from public.unidades u where u.normalized_name=n.normalized_name and not u.is_deleted and lower(u.abbreviation)<>lower(n.abbreviation))
    union all
    select 'Ingrediente duplicado/inactivo/ID en conflicto: '||n.name from rx_needed_ingredients n
      where (select count(*) from public.ingredientes i where i.normalized_name=n.normalized_name) > 1
        or exists(select 1 from public.ingredientes i where i.normalized_name=n.normalized_name and (not i.active or i.is_deleted))
        or exists(select 1 from public.ingredientes i where i.id=n.id and i.normalized_name is distinct from n.normalized_name)
        or exists(select 1 from public.ingredientes i where i.legacy_id=n.legacy_id and i.normalized_name is distinct from n.normalized_name)
        or exists(select 1 from public.ingredientes i join public.categorias c on c.id=i.category_id
          where i.normalized_name=n.normalized_name and (not c.active or c.is_deleted
            or c.normalized_name<>(select normalized_name from rx_needed_categories where name=n.category_name)))
    union all
    select 'Categoría de ingrediente inexistente/inactiva: '||n.name from rx_needed_ingredients n
      where not exists(select 1 from rx_category_map c where c.normalized_name=(select normalized_name from rx_needed_categories where name=n.category_name) and c.id is not null)
    union all
    select 'Unidad base faltante: '||n.base_abbreviation from rx_needed_ingredients n
      where not exists(select 1 from rx_unit_map u where u.abbreviation=n.base_abbreviation)
    union all
    select 'Dimensión/unidad base incompatible: '||n.name from rx_needed_ingredients n
      join rx_unit_map expected on expected.abbreviation=n.base_abbreviation
      left join public.ingredientes i on i.normalized_name=n.normalized_name
      left join public.unidades base on base.id=i.base_unit_id
      where i.id is not null and (base.id is null or base.dimension<>expected.dimension or base.base_unit_id is not null)
    union all
    select 'Etiqueta dietaria ausente/inactiva: '||tag.label from rx_tag_input tag
      where not exists(select 1 from public.etiquetas_dieteticas d where d.tag_key=tag.tag_key and d.active)
    union all
    select 'Colisión de id/legacy_id/título: '||r.title from rx_recipe_source r
      where exists(select 1 from public.recetas x where x.id=r.id and (x.legacy_id is distinct from r.source_id or x.recipe_source<>'official' or x.owner_user_id is not null))
        or exists(select 1 from public.recetas x where x.legacy_id=r.source_id and x.id<>r.id)
        or exists(select 1 from public.recetas x where x.id<>r.id and x.recipe_source='official' and x.owner_user_id is null and not x.is_deleted
          and lower(regexp_replace(regexp_replace(normalize(trim(x.title),NFD),U&'[\\0300-\\036f]','','g'),'\\s+',' ','g'))
            = lower(regexp_replace(regexp_replace(normalize(trim(r.title),NFD),U&'[\\0300-\\036f]','','g'),'\\s+',' ','g')))
  ) issues;
  if problems is not null then raise exception 'Preflight bloqueado; corregir referencias/colisiones antes de importar:%', E'\n'||problems; end if;
end;
$$;

create temp table rx_categories_to_insert on commit drop as
select c.* from rx_category_map c where c.needs_insert
  and exists(select 1 from rx_needed_ingredients i where i.category_name=c.name
    and not exists(select 1 from public.ingredientes known where known.normalized_name=i.normalized_name));
create temp table rx_units_to_insert on commit drop as select * from rx_unit_map where needs_insert;
create temp table rx_ingredients_to_insert on commit drop as select * from rx_ingredient_map where needs_insert;

-- Add only catalog references that are genuinely missing. Never reactivate or overwrite a row.
insert into public.categorias(id,legacy_id,name,normalized_name,active,is_deleted,version)
select id,legacy_id,name,normalized_name,true,false,1 from rx_categories_to_insert;
insert into public.unidades(id,legacy_id,name,normalized_name,abbreviation,dimension,base_unit_id,equivalence_multiplier,active,is_deleted,version)
select id,'recipe-expansion-v4:unit:'||abbreviation,name,normalized_name,abbreviation,dimension,null,null,true,false,1
from rx_units_to_insert;
insert into public.ingredientes(id,legacy_id,name,normalized_name,category_id,base_unit_id,active,is_deleted,version)
select m.id,m.legacy_id,m.name,m.normalized_name,c.id,u.id,true,false,1
from rx_ingredients_to_insert m join rx_category_map c on c.normalized_name=(select normalized_name from rx_needed_categories where name=m.category_name)
join rx_unit_map u on u.abbreviation=m.base_abbreviation;

create temp table rx_expected_ingredients on commit drop as
select r.id recipe_id, line.n::integer position, m.id ingredient_id, (line.value->>'quantity')::numeric quantity,
  u.id unit_id, coalesce(line.value->>'note','') note, line.value->>'name' source_name, line.value->>'unit' source_unit
from rx_recipe_source r cross join lateral jsonb_array_elements(r.ingredients) with ordinality line(value,n)
join rx_ingredient_map m on m.normalized_name=lower(regexp_replace(regexp_replace(normalize(trim(line.value->>'name'),NFD),U&'[\\0300-\\036f]','','g'),'\\s+',' ','g'))
join rx_unit_map u on lower(u.abbreviation)=lower(line.value->>'unit');
do $$
begin
  if exists(select 1 from rx_expected_ingredients e join rx_ingredient_map m on m.id=e.ingredient_id
    join rx_unit_map recipe_unit on recipe_unit.id=e.unit_id
    where (m.needs_insert and recipe_unit.id<>(select id from rx_unit_map where abbreviation=m.base_abbreviation))
      or (not m.needs_insert and exists(select 1 from public.ingredientes i join public.unidades ingredient_base on ingredient_base.id=i.base_unit_id
        where i.id=m.id and recipe_unit.id<>ingredient_base.id))) then
    raise exception 'Unidad de receta incompatible con la unidad base del ingrediente. Se revierte la transacción.';
  end if;
end;
$$;
create temp table rx_expected_steps on commit drop as
select r.id recipe_id, step.n::integer position, step.value #>> '{}' instruction,
  coalesce((meta.value->>'durationMinutes')::integer,(meta.value->>'minutes')::integer) duration_minutes,
  nullif(meta.value->>'temperature','') temperature,nullif(meta.value->>'tip','') tip,nullif(meta.value->>'warning','') warning,
  coalesce(array(select jsonb_array_elements_text(coalesce(meta.value->'utensils','[]'::jsonb))),'{}') utensils,
  nullif(meta.value->>'specialInstructions','') special_instructions,coalesce(meta.value->'stepIngredients','[]'::jsonb) step_ingredients
from rx_recipe_source r cross join lateral jsonb_array_elements(r.steps) with ordinality step(value,n)
left join lateral (select r.step_meta->(step.n::integer-1) value) meta on true;
create temp table rx_expected_step_links on commit drop as
select s.recipe_id,s.position step_position,ri.position ingredient_position,(item.value->>'quantity')::numeric quantity_override
from rx_expected_steps s cross join lateral jsonb_array_elements(s.step_ingredients) item(value)
join rx_expected_ingredients ri on ri.recipe_id=s.recipe_id
  and lower(regexp_replace(regexp_replace(normalize(trim(item.value->>'name'),NFD),U&'[\\0300-\\036f]','','g'),'\\s+',' ','g'))
      = lower(regexp_replace(regexp_replace(normalize(trim(ri.source_name),NFD),U&'[\\0300-\\036f]','','g'),'\\s+',' ','g'))
  and lower(item.value->>'unit')=lower(ri.source_unit);
create temp table rx_expected_shifts on commit drop as
select distinct r.id recipe_id,case shift.value #>> '{}' when 'Desayuno' then 'breakfast' when 'Almuerzo' then 'lunch' when 'Merienda' then 'snack' when 'Cena' then 'dinner' end meal_shift
from rx_recipe_source r cross join lateral jsonb_array_elements(r.shifts) shift(value);
create temp table rx_expected_tags on commit drop as
select distinct r.id recipe_id,tag.value #>> '{}' tag_key
from rx_recipe_source r cross join lateral jsonb_array_elements(r.dietary_keys) tag(value);

create temp table rx_recipes_to_insert on commit drop as
select r.* from rx_recipe_source r where not exists(select 1 from public.recetas x where x.id=r.id);

do $$
declare problems text;
begin
  select string_agg(problem,E'\n') into problems from (
    select 'Ingrediente/unidad no resuelta o incompatible: '||r.title||' / '||(line.value->>'name') problem
    from rx_recipe_source r cross join lateral jsonb_array_elements(r.ingredients) with ordinality line(value,ordinality)
    where (select count(*) from rx_expected_ingredients i where i.recipe_id=r.id and i.position=line.ordinality::integer)<>1
    union all
    select 'Etiqueta dietaria sin destino activo: '||r.title||' / '||(tag.value #>> '{}') from rx_recipe_source r
      cross join lateral jsonb_array_elements(r.dietary_keys) tag(value)
      where not exists(select 1 from rx_expected_tags t join public.etiquetas_dieteticas d on d.tag_key=t.tag_key and d.active where t.recipe_id=r.id and t.tag_key=tag.value #>> '{}')
    union all
    select 'Metadato de paso sin ingrediente inequívoco: '||r.title||' / paso '||s.position from rx_expected_steps s
      join rx_recipe_source r on r.id=s.recipe_id
      where jsonb_array_length(s.step_ingredients)<>(select count(*) from rx_expected_step_links l where l.recipe_id=s.recipe_id and l.step_position=s.position)
  ) unresolved;
  if problems is not null then raise exception 'Preflight bloqueado; faltan asociaciones:%', E'\n'||problems; end if;

  -- Exact rows are skipped on rerun. Any same-ID/legacy-ID row with different data fails closed.
  if exists(
    select 1 from rx_recipe_source e join public.recetas r on r.id=e.id or r.legacy_id=e.source_id
    where r.id is distinct from e.id or r.legacy_id is distinct from e.source_id or r.recipe_source<>'official' or r.owner_user_id is not null
      or r.title is distinct from e.title or r.author is distinct from e.author or r.description is distinct from e.description
      or r.category_label is distinct from e.category_label or r.total_minutes is distinct from e.total_minutes or r.portions is distinct from e.portions
      or r.difficulty is distinct from e.difficulty or r.calories_per_portion is not null or r.preparation_minutes is not null or r.cooking_minutes is not null
      or r.publication_status is distinct from 'published' or not r.active or r.is_deleted or r.featured is distinct from e.featured
      or r.symbol is distinct from e.symbol or r.color is distinct from e.color or r.cross_contamination_note is distinct from e.cross_note
      or r.image_path is distinct from e.image_path or r.image_alt is distinct from e.image_alt or r.version is distinct from 1
  ) then raise exception 'La receta existente coincide por id/legacy_id pero no con este seed. Se aborta sin sobrescribirla.'; end if;

  if exists(
    (select e.recipe_id,e.position,e.ingredient_id,e.quantity,e.unit_id,e.note from rx_expected_ingredients e
      join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
    except
    (select a.recipe_id,a.position,a.ingredient_id,a.quantity,a.unit_id,a.note from public.ingredientes_receta a join rx_recipe_source r on r.id=a.recipe_id)
  ) or exists(
    (select a.recipe_id,a.position,a.ingredient_id,a.quantity,a.unit_id,a.note from public.ingredientes_receta a join rx_recipe_source r on r.id=a.recipe_id)
    except
    (select e.recipe_id,e.position,e.ingredient_id,e.quantity,e.unit_id,e.note from rx_expected_ingredients e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
  ) then raise exception 'Las líneas de ingredientes de una receta existente difieren del seed. No se sobrescribe.'; end if;
  if exists(
    (select e.recipe_id,e.position,e.instruction,e.duration_minutes,e.temperature,e.tip,e.warning,e.utensils,e.special_instructions from rx_expected_steps e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
    except
    (select a.recipe_id,a.position,a.instruction,a.duration_minutes,a.temperature,a.tip,a.warning,a.utensils,a.special_instructions from public.pasos_receta a join rx_recipe_source r on r.id=a.recipe_id)
  ) or exists(
    (select a.recipe_id,a.position,a.instruction,a.duration_minutes,a.temperature,a.tip,a.warning,a.utensils,a.special_instructions from public.pasos_receta a join rx_recipe_source r on r.id=a.recipe_id)
    except
    (select e.recipe_id,e.position,e.instruction,e.duration_minutes,e.temperature,e.tip,e.warning,e.utensils,e.special_instructions from rx_expected_steps e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
  ) then raise exception 'Los pasos de una receta existente difieren del seed. No se sobrescribe.'; end if;
  if exists(
    (select e.recipe_id,e.step_position,e.ingredient_position,e.quantity_override from rx_expected_step_links e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
    except
    (select s.recipe_id,s.position,ri.position,link.quantity_override from public.ingredientes_paso_receta link join public.pasos_receta s on s.id=link.step_id join public.ingredientes_receta ri on ri.id=link.recipe_ingredient_id join rx_recipe_source r on r.id=s.recipe_id)
  ) or exists(
    (select s.recipe_id,s.position,ri.position,link.quantity_override from public.ingredientes_paso_receta link join public.pasos_receta s on s.id=link.step_id join public.ingredientes_receta ri on ri.id=link.recipe_ingredient_id join rx_recipe_source r on r.id=s.recipe_id)
    except
    (select e.recipe_id,e.step_position,e.ingredient_position,e.quantity_override from rx_expected_step_links e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
  ) then raise exception 'Las referencias de ingredientes por paso difieren del seed. No se sobrescribe.'; end if;
  if exists(
    (select e.recipe_id,e.meal_shift from rx_expected_shifts e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
    except
    (select a.recipe_id,a.meal_shift from public.turnos_comida_receta a join rx_recipe_source r on r.id=a.recipe_id)
  ) or exists(
    (select a.recipe_id,a.meal_shift from public.turnos_comida_receta a join rx_recipe_source r on r.id=a.recipe_id)
    except
    (select e.recipe_id,e.meal_shift from rx_expected_shifts e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
  ) then raise exception 'Los turnos de comida de una receta existente difieren del seed. No se sobrescribe.'; end if;
  if exists(
    (select e.recipe_id,d.id from rx_expected_tags e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id join public.etiquetas_dieteticas d on d.tag_key=e.tag_key)
    except
    (select a.recipe_id,a.dietary_tag_id from public.etiquetas_dieteticas_receta a join rx_recipe_source r on r.id=a.recipe_id)
  ) or exists(
    (select a.recipe_id,a.dietary_tag_id from public.etiquetas_dieteticas_receta a join rx_recipe_source r on r.id=a.recipe_id)
    except
    (select e.recipe_id,d.id from rx_expected_tags e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id join public.etiquetas_dieteticas d on d.tag_key=e.tag_key)
  ) then raise exception 'Las etiquetas de una receta existente difieren del seed. No se sobrescribe.'; end if;
end;
$$;

-- Insert recipes not already present. Their deterministic IDs and legacy slugs keep routes stable.
insert into public.recetas(id,legacy_id,owner_user_id,recipe_source,title,author,description,category_label,total_minutes,preparation_minutes,cooking_minutes,
  portions,difficulty,calories_per_portion,publication_status,active,is_deleted,featured,symbol,color,cross_contamination_note,image_path,image_alt,version)
select r.id,r.source_id,null,'official',r.title,r.author,r.description,r.category_label,r.total_minutes,null,null,r.portions,r.difficulty,null,
  'published',true,false,r.featured,r.symbol,r.color,r.cross_note,r.image_path,r.image_alt,1
from rx_recipes_to_insert r;
insert into public.ingredientes_receta(id,recipe_id,ingredient_id,quantity,unit_id,note,position)
select md5('recipe-expansion-v4:recipe-line:'||e.recipe_id::text||':'||e.position)::uuid,e.recipe_id,e.ingredient_id,e.quantity,e.unit_id,e.note,e.position
from rx_expected_ingredients e join rx_recipes_to_insert r on r.id=e.recipe_id;
insert into public.pasos_receta(id,recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions)
select md5('recipe-expansion-v4:recipe-step:'||e.recipe_id::text||':'||e.position)::uuid,e.recipe_id,e.position,e.instruction,e.duration_minutes,e.temperature,e.tip,e.warning,e.utensils,e.special_instructions
from rx_expected_steps e join rx_recipes_to_insert r on r.id=e.recipe_id;
insert into public.ingredientes_paso_receta(step_id,recipe_ingredient_id,quantity_override)
select md5('recipe-expansion-v4:recipe-step:'||l.recipe_id::text||':'||l.step_position)::uuid,
  md5('recipe-expansion-v4:recipe-line:'||l.recipe_id::text||':'||l.ingredient_position)::uuid,l.quantity_override
from rx_expected_step_links l join rx_recipes_to_insert r on r.id=l.recipe_id;
insert into public.turnos_comida_receta(recipe_id,meal_shift)
select e.recipe_id,e.meal_shift from rx_expected_shifts e join rx_recipes_to_insert r on r.id=e.recipe_id;
insert into public.etiquetas_dieteticas_receta(recipe_id,dietary_tag_id)
select e.recipe_id,d.id from rx_expected_tags e join public.etiquetas_dieteticas d on d.tag_key=e.tag_key
join rx_recipes_to_insert r on r.id=e.recipe_id;

-- Record the operator-driven catalog additions; actor_user_id is NULL for SQL Editor execution.
insert into public.registro_auditoria(actor_user_id,action,details)
select null::uuid,'catalog.category_saved',jsonb_build_object('entity_id',c.id,'version',1,'source','recipe-expansion-v4') from rx_categories_to_insert c
union all
select null::uuid,'catalog.unit_saved',jsonb_build_object('entity_id',u.id,'version',1,'source','recipe-expansion-v4') from rx_units_to_insert u
union all
select null::uuid,'catalog.ingredient_saved',jsonb_build_object('entity_id',i.id,'version',1,'source','recipe-expansion-v4') from rx_ingredients_to_insert i
union all
select null::uuid,'catalog.recipe_saved',jsonb_build_object('entity_id',r.id,'version',1,'source','recipe-expansion-v4') from rx_recipes_to_insert r;

do $$
begin
  if exists(select 1 from rx_recipe_source r where not exists(select 1 from public.recetas x where x.id=r.id and x.legacy_id=r.source_id)) then
    raise exception 'Validación final falló: faltan recetas del lote.';
  end if;
  if exists(
    (select recipe_id,position,ingredient_id,quantity,unit_id,note from rx_expected_ingredients)
    except
    (select recipe_id,position,ingredient_id,quantity,unit_id,note from public.ingredientes_receta where recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan ingredientes de receta.'; end if;
  if exists(
    (select recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions from rx_expected_steps)
    except
    (select recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions from public.pasos_receta where recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan pasos o metadatos.'; end if;
  if exists(
    (select recipe_id,step_position,ingredient_position,quantity_override from rx_expected_step_links)
    except
    (select s.recipe_id,s.position,ri.position,l.quantity_override from public.ingredientes_paso_receta l
      join public.pasos_receta s on s.id=l.step_id join public.ingredientes_receta ri on ri.id=l.recipe_ingredient_id
      where s.recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan referencias de ingrediente por paso.'; end if;
  if exists(
    (select recipe_id,meal_shift from rx_expected_shifts)
    except
    (select recipe_id,meal_shift from public.turnos_comida_receta where recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan turnos de comida.'; end if;
  if exists(
    (select e.recipe_id,d.id from rx_expected_tags e join public.etiquetas_dieteticas d on d.tag_key=e.tag_key)
    except
    (select recipe_id,dietary_tag_id from public.etiquetas_dieteticas_receta where recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan etiquetas dietarias.'; end if;
end;
$$;

select 'PASS: preflight, referencias y contenido de las 20 recetas verificados' as validation;
select 'recipes_inserted' as result,count(*) from rx_recipes_to_insert
union all select 'ingredients_inserted',count(*) from rx_ingredients_to_insert
union all select 'categories_inserted',count(*) from rx_categories_to_insert
union all select 'units_inserted',count(*) from rx_units_to_insert;
`

for (const [filename, terminator] of [['recipe_expansion_v4.sql', 'commit'], ['recipe_expansion_v4_rehearsal.sql', 'rollback']] as const) {
  const target = resolve(outputDirectory, filename)
  await mkdir(dirname(target), { recursive: true })
  await writeFile(target, `${sourceSql}\n${terminator};\n`, 'utf8')
}
console.log(`Generated apply and rehearsal SQL for ${expandedRecipes.length} recipes in ${outputDirectory}`)
