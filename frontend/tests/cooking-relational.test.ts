import assert from 'node:assert/strict'
import test from 'node:test'
import { createSupabaseCookingRepository } from '../src/features/cooking/data/supabaseCookingRepository'
import { createSession } from '../src/features/cooking/domain/cooking'
import type { Recipe } from '../src/features/recipes/domain/Recipe'

const recipe:Recipe={id:'legacy-soup',name:'Sopa',description:'',category:'Cena',minutes:10,portions:2,difficulty:'Fácil',ingredients:[{name:'Agua',quantity:1,unit:'l'}],steps:['Hervir','Servir'],symbol:'🍲',color:'green'}
function harness(handler:(name:string,args:Record<string,unknown>)=>unknown,assertSession:()=>void=()=>{}){
  const calls:Array<[string,Record<string,unknown>]> = []
  const client={auth:{getUser:async()=>({data:{user:{id:'user-1'}},error:null})},rpc:async(name:string,args:Record<string,unknown>)=>{calls.push([name,args]);try{return {data:await handler(name,args),error:null}}catch(error){return {data:null,error}}}}
  const repo=createSupabaseCookingRepository({getClient:()=>client as never,captureSession:()=>({token:'supabase-user:user-1',localRevision:0,supabaseRevision:0}),assertSession,assertOwner:()=>{}})
  return {repo,calls}
}
function row(id:string,version=1):Record<string,unknown>{return {id,recipe_id:'recipe-uuid',recipe_snapshot:{id:'recipe-uuid',name:'Sopa congelada',description:'',category:'Cena',minutes:10,portions:2,difficulty:'Fácil',ingredients:recipe.ingredients,steps:[{instruction:'Hervir'},{instruction:'Servir'}],symbol:'🍲',color:'green'},portions:2,current_step:0,version,started_at:'2026-01-01T00:00:00Z',steps:[{step_position:1,completed_at:null,remaining_ms:0,timer_state:'idle',timer_deadline_at:null},{step_position:2,completed_at:null,remaining_ms:0,timer_state:'idle',timer_deadline_at:null}]}}
test('starts with stable UUID, reopens immutable snapshot, and sends expected versions',async()=>{
  let saved:Record<string,unknown>|null=null,version=1
  const {repo,calls}=harness((name,args)=>{if(name==='get_my_open_cooking_session')return saved;if(name==='get_my_cooking_session'){if(!saved)throw Object.assign(new Error('missing'),{code:'P0002'});return saved}if(name==='get_my_recipe_detail')return {recipe:{id:'recipe-uuid'}};if(name==='start_my_cooking_session'){assert.equal(args.p_session_id,'stable-session-id');saved=row('stable-session-id');return saved}if(name==='update_my_cooking_session'){assert.equal(args.p_expected_version,version);version++;saved={...saved!,version};return {version}};throw new Error(name)})
  const initial={...createSession(recipe,new Date('2026-01-01T00:00:00Z')),recipeSnapshot:recipe};Object.defineProperty(globalThis,'crypto',{configurable:true,value:{randomUUID:()=> 'stable-session-id'}})
  await repo.saveSession(initial)
  const opened=await repo.getSession(recipe.id)
  assert.equal(opened?.recipeSnapshot?.name,'Sopa congelada')
  assert.equal(opened?.relationalId,'stable-session-id')
  assert.equal(calls.filter(([name])=>name==='start_my_cooking_session').length,1)
  await repo.saveSession({...opened!,stepIndex:1,completed:[0]},opened!)
  assert.equal(calls.find(([name])=>name==='update_my_cooking_session')?.[1].p_expected_version,1)
  assert.deepEqual(calls.filter(([name])=>name==='update_my_cooking_session').map(([,args])=>args.p_action),['move','complete'])
})
test('surfaces version conflicts and retries finish without repeating local stock writes',async()=>{
  const stale=Object.assign(createSession(recipe),{relationalId:'session-a',version:2,recipeSnapshot:recipe})
  const {repo,calls}=harness((name)=>{if(name==='update_my_cooking_session')throw Object.assign(new Error('stale'),{code:'40001'});if(name==='finish_my_cooking_session')return {id:'event-1',cooked_at:'2026-01-01T00:00:00Z',portions:2};throw new Error(name)})
  await assert.rejects(()=>repo.saveSession({...stale,stepIndex:1},stale),/Recargá la cocina/)
  const first=await repo.finalize(recipe,stale,true),retry=await repo.finalize(recipe,stale,true)
  assert.equal(first.history[0]?.id,'event-1');assert.equal(retry.history[0]?.id,'event-1')
  const finishes=calls.filter(([name])=>name==='finish_my_cooking_session')
  assert.equal(finishes.length,2)
  assert.deepEqual(finishes.map(([,args])=>[args.p_session_id,args.p_expected_version,args.p_deduct_stock]),[['session-a',2,true],['session-a',2,true]])
  assert.equal(calls.some(([name])=>name.includes('pantry')||name.includes('stock_write')),false)
})
test('maps historical snapshot independent of current recipe catalog',async()=>{
  const {repo}=harness(name=>name==='get_my_cooking_history'?[{id:'event-a',session_id:'session-a',recipe_id:'recipe-uuid',recipe_snapshot:row('s').recipe_snapshot,cooked_at:'2026-02-01T12:00:00Z',portions:3,deduct_stock:false}]:[])
  const history=await repo.getHistory()
  assert.equal(history[0]?.recipeSnapshot?.name,'Sopa congelada')
  assert.equal(history[0]?.portions,3)
})
test('discards an out of order RPC response after the account session changes',async()=>{
  let finish!: (value:unknown)=>void
  let current=true
  const {repo}=harness(()=>new Promise((resolve)=>{finish=resolve}),()=>{if(!current)throw new Error('session changed')})
  const pending=repo.getHistory()
  await new Promise((resolve)=>setImmediate(resolve))
  current=false
  finish([])
  await assert.rejects(()=>pending,/session changed/)
})
