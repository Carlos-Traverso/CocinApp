import type { Recipe } from '../../recipes/domain/Recipe'
import type { IngredientDeficit } from '../../recipes/domain/recipeRules'
import { supabase } from '../../../shared/data/supabaseClient'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession } from '../../../shared/data/personalDataSession'
import type { CookingRepository } from './CookingRepository'
import type { CookingSession, PreparationEvent } from '../domain/cooking'
import { getRecipeById } from '../../recipes/data/availableRecipes'
import { supabaseRecipeRepository } from '../../recipes/data/SupabaseRecipeRepository'

type Client = NonNullable<typeof supabase>
type SessionRow = { id: string; recipe_id: string; recipe_snapshot: Record<string, unknown>; portions: number; current_step: number; version: number; started_at:string; steps: Array<{step_position:number;completed_at:string|null;remaining_ms:number;timer_state:string;timer_deadline_at:string|null}> }
export function recipeFromSnapshot(value: unknown, legacyId?: string): Recipe {
  if (!value || typeof value !== 'object') throw new Error('La receta guardada no tiene un formato válido.')
  const row = value as Record<string, unknown>
  if (typeof row.id !== 'string' || typeof row.name !== 'string' || !Array.isArray(row.ingredients) || !Array.isArray(row.steps)) throw new Error('La receta guardada no tiene un formato válido.')
  const steps = row.steps as Array<Record<string, unknown>>
  return { id: legacyId ?? row.id, name: row.name, description: String(row.description ?? ''), category: String(row.category ?? ''), minutes: Number(row.minutes ?? 0), portions: Number(row.portions ?? 1), difficulty: (row.difficulty === 'Intermedia' || row.difficulty === 'Avanzada' ? row.difficulty : 'Fácil'), ingredients: (row.ingredients as Array<Record<string, unknown>>).map((i) => ({ name:String(i.name),quantity:Number(i.quantity),unit:String(i.unit),category:String(i.category ?? '') })), steps: steps.map((s) => String(s.instruction ?? '')), stepMeta: steps.map((s) => ({ durationMinutes:Number(s.durationMinutes ?? 0),temperature:typeof s.temperature==='string'?s.temperature:undefined,tip:typeof s.tip==='string'?s.tip:undefined,warning:typeof s.warning==='string'?s.warning:undefined,utensils:Array.isArray(s.utensils)?s.utensils as string[]:[],specialInstructions:typeof s.specialInstructions==='string'?s.specialInstructions:undefined,stepIngredients:Array.isArray(s.stepIngredients)?(s.stepIngredients as Array<Record<string,unknown>>).map(i=>({name:String(i.name),quantity:Number(i.quantity),unit:String(i.unit)})):[] })), symbol:String(row.symbol ?? '🍽️'), color:(['green','gold','pink','blue'].includes(String(row.color))?row.color:'green') as Recipe['color'], image:typeof row.image==='string'?row.image:undefined,imageAlt:typeof row.imageAlt==='string'?row.imageAlt:undefined,crossContaminationNote:typeof row.crossContaminationNote==='string'?row.crossContaminationNote:undefined }
}
function fromRow(row: SessionRow, recipeId: string): CookingSession {
  const recipe = recipeFromSnapshot(row.recipe_snapshot, recipeId)
  const current = row.steps.find((s) => s.step_position === row.current_step + 1)
  const deadline = current?.timer_state === 'running' && current.timer_deadline_at ? Date.parse(current.timer_deadline_at) : undefined
  return { recipeId, relationalId:row.id, version:Number(row.version),recipeSnapshot:recipe,stepIndex:Number(row.current_step),completed:row.steps.filter(s=>s.completed_at!==null).map(s=>s.step_position-1),portions:Number(row.portions),startedAt:row.started_at,timer:current && current.timer_state!=='idle'?{stepIndex:row.current_step,remainingMs:Number(current.remaining_ms),...(deadline?{deadlineAt:deadline}:{})}:undefined }
}
function conflict(error: unknown): boolean { return !!error && typeof error==='object' && (error as {code?:string}).code==='40001' }
function idFor(recipeId:string,owner:string,ids:Map<string,string>):string {
  const cacheKey=`${owner}:${recipeId}`
  const stored=ids.get(cacheKey); if(stored)return stored
  const key=`cocinapp.cooking-session.v1:${owner}:${recipeId}`
  try { const saved=sessionStorage.getItem(key); if(saved){ids.set(cacheKey,saved);return saved} } catch {}
  const id=crypto.randomUUID(); ids.set(cacheKey,id); try{sessionStorage.setItem(key,id)}catch{}; return id
}
export function createSupabaseCookingRepository(deps:{getClient:()=>Client; assertSession:typeof assertPersonalDataSessionCurrent; assertOwner:typeof assertPersonalDataOwner; captureSession:typeof capturePersonalDataSession}):CookingRepository {
  const client=deps.getClient
  const pendingIds = new Map<string,string>()
  async function rpc<T>(name:string,args:Record<string,unknown>,session:ReturnType<typeof capturePersonalDataSession>):Promise<T>{
    let userId:string|null=null
    deps.assertSession(session)
    const auth=await client().auth.getUser(); if(auth.error)throw auth.error; userId=auth.data.user?.id??null
    deps.assertSession(session)
    if(!userId)throw new Error('Iniciá sesión para cocinar.')
    deps.assertOwner(session,userId)
    const {data,error}=await client().rpc(name,args); if(error){if(conflict(error)){const stale=new Error('La sesión cambió en otro dispositivo. Recargá la cocina para continuar.');Object.assign(stale,{code:'40001'});throw stale}throw error}
    deps.assertSession(session)
    deps.assertOwner(session,userId); return data as T
  }
  async function resolve(recipe:Recipe,session:ReturnType<typeof capturePersonalDataSession>):Promise<string>{
    if (recipe.relationalId) return recipe.relationalId
    const data=await rpc<{recipe?:{id?:string}}>('get_my_recipe_detail',{p_legacy_id:recipe.id},session)
    if(typeof data?.recipe?.id!=='string')throw new Error('La receta todavía no está disponible en el catálogo relacional.')
    return data.recipe.id
  }
  async function open(recipeId:string,relId:string,s:ReturnType<typeof capturePersonalDataSession>):Promise<CookingSession>{return fromRow(await rpc<SessionRow>('get_my_cooking_session',{p_session_id:relId},s),recipeId)}
  async function ensure(recipe:Recipe,s:ReturnType<typeof capturePersonalDataSession>,portions=recipe.portions):Promise<CookingSession>{
    const relId=idFor(recipe.id,s.token??'anonymous',pendingIds)
    try{return await open(recipe.id,relId,s)}catch(error){if((error as {code?:string})?.code!=='P0002')throw error}
    const relationalRecipeId=await resolve(recipe,s)
    const started = await rpc<{ finished_at?: string | null }>('start_my_cooking_session',{p_session_id:relId,p_recipe_id:relationalRecipeId,p_portions:portions},s)
    if (started?.finished_at) {
      pendingIds.delete(`${s.token??'anonymous'}:${recipe.id}`)
      try { sessionStorage.removeItem(`cocinapp.cooking-session.v1:${s.token??'anonymous'}:${recipe.id}`) } catch {}
      return ensure(recipe, s, portions)
    }
    return open(recipe.id,relId,s)
  }
  return {
    async getSession(recipeId) {
      const s = deps.captureSession()
      let result = await rpc<SessionRow | null>('get_my_open_cooking_session', { p_legacy_recipe_id: recipeId }, s)
      if (!result && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(recipeId)) {
        const recipe = await supabaseRecipeRepository.getById(recipeId, true)
        deps.assertSession(s)
        if (recipe?.relationalId) result = await rpc<SessionRow | null>('get_my_open_cooking_session', { p_recipe_id: recipe.relationalId }, s)
      }
      return result ? fromRow(result, recipeId) : null
    },
    async saveSession(next,previous){const s=deps.captureSession(); let current=next.relationalId?next:undefined
      if(!current){const recipe=next.recipeSnapshot??getRecipeById(next.recipeId,true);if(!recipe)throw new Error('Recargá la receta antes de guardar el progreso.');current=await ensure(recipe,s,next.portions)}
      if(!current.version||!current.relationalId)throw new Error('Recargá la cocina antes de continuar.')
      const base=previous ?? (current===next?undefined:current)
      if(!base)return
      if(!base.relationalId || !base.version)throw new Error('Recargá la cocina antes de continuar.')
      const actions:Array<[string,number|null,number|null]> = []
      if(next.portions!==base.portions)actions.push(['portions',null,next.portions])
      if(next.stepIndex!==base.stepIndex)actions.push(['move',next.stepIndex,null])
      for(const step of new Set([...base.completed,...next.completed])) if(base.completed.includes(step)!==next.completed.includes(step)) actions.push([next.completed.includes(step)?'complete':'uncomplete',step,null])
      const bt=base.timer,nt=next.timer
      if(JSON.stringify(bt)!==JSON.stringify(nt) && next.stepIndex===base.stepIndex){
        if(!nt && bt)actions.push(['timer_reset',next.stepIndex,null])
        else if(nt?.deadlineAt)actions.push([bt?'timer_resume':'timer_start',nt.stepIndex,null])
        else if(bt?.deadlineAt)actions.push(['timer_pause',next.stepIndex,null])
      }
      let version=base.version
      let committed=false
      try {
        for(const [action,step,portions] of actions){const row=await rpc<{version:number}>('update_my_cooking_session',{p_session_id:base.relationalId,p_expected_version:version,p_action:action,...(step===null?{}:{p_step:step}),...(portions===null?{}:{p_portions:portions})},s);committed=true;version=Number(row.version)}
      } catch(error) {
        if(committed)throw new Error('Parte del progreso pudo guardarse. Recargá la cocina para sincronizar antes de continuar.')
        throw error
      }
      const refreshed=await open(next.recipeId,base.relationalId,s)
      Object.assign(next,refreshed)
    },
    async getHistory(){const s=deps.captureSession(),items:PreparationEvent[]=[];let before:string|null=null,beforeId:string|null=null
      do{const page:Record<string,unknown>[]=await rpc<Record<string,unknown>[]>('get_my_cooking_history',{p_limit:100,p_before:before,p_before_id:beforeId},s);for(const e of page){const recipe=recipeFromSnapshot(e.recipe_snapshot);items.push({id:String(e.id),recipeId:recipe.id,cookedAt:String(e.cooked_at),portions:Number(e.portions),sessionStartedAt:String(e.session_id),recipeSnapshot:recipe,deductStock:Boolean(e.deduct_stock)})}if(page.length<100)break;const tail:Record<string,unknown>=page[page.length-1]!;before=String(tail.cooked_at);beforeId=String(tail.id)}while(items.length<10000);return items},
    async removeHistoryEntry(eventId){await rpc('hide_my_cooking_history_entry',{p_event_id:eventId},deps.captureSession())},
    async clearHistory(){await rpc('clear_my_cooking_history',{},deps.captureSession())},
    async checkStock(recipe,portions,cookingSession){const s=deps.captureSession();const result=await rpc<{ingredients?:Array<Record<string,unknown>>}>('check_my_cooking_stock',cookingSession?.relationalId?{p_session_id:cookingSession.relationalId}:{p_recipe_id:await resolve(recipe,s),p_portions:portions},s);return (result.ingredients??[]).map((i)=>({ingredient:{name:String(i.name),quantity:Number(i.required),unit:String(i.unit)},required:Number(i.required),available:Number(i.available),missing:Number(i.missing)})) as IngredientDeficit[]},
    async finalize(_recipe,session,discount){if(!session.relationalId||!session.version)throw new Error('Recargá la cocina antes de finalizar.');const s=deps.captureSession();const event=await rpc<Record<string,unknown>>('finish_my_cooking_session',{p_session_id:session.relationalId,p_expected_version:session.version,p_deduct_stock:discount},s);pendingIds.delete(`${s.token??'anonymous'}:${session.recipeId}`);try{sessionStorage.removeItem(`cocinapp.cooking-session.v1:${s.token??'anonymous'}:${session.recipeId}`)}catch{};return {history:[{id:String(event.id),recipeId:session.recipeId,cookedAt:String(event.cooked_at),portions:Number(event.portions),sessionStartedAt:session.startedAt,recipeSnapshot:session.recipeSnapshot,deductStock:discount}],exhaustedIngredients:[]}}
  }
}
export const supabaseCookingRepository=createSupabaseCookingRepository({getClient:()=>{if(!supabase)throw new Error('Falta configurar la conexión de Supabase.');return supabase},assertSession:assertPersonalDataSessionCurrent,assertOwner:assertPersonalDataOwner,captureSession:capturePersonalDataSession})
