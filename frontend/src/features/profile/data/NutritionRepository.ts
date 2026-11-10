import type { ActivityLevel, Goal, NutritionConfig } from '../domain/profile'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'
import { isRelationalAdminEnabled, isRelationalProfilesEnabled, isSupabaseConfigured, supabase } from '../../../shared/data/supabaseClient'

export type NutritionConfigRow = Record<string, unknown>
export type NutritionConfigInput = Omit<NutritionConfig, 'configVersion'>

const activityLevels: ActivityLevel[] = ['sedentary', 'light', 'moderate', 'active', 'very-active']
const goals: Goal[] = ['lose', 'maintain', 'gain', 'gain-muscle']

function numericMap<T extends string>(value: unknown, keys: T[], label: string): Record<T, number> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`Configuración nutricional inválida: ${label}.`)
  const row = value as Record<string, unknown>
  if (keys.some((key) => typeof row[key] !== 'number' || !Number.isFinite(row[key])) || Object.keys(row).length !== keys.length) throw new Error(`Configuración nutricional inválida: ${label}.`)
  return Object.fromEntries(keys.map((key) => [key, row[key]])) as Record<T, number>
}

export function mapNutritionConfig(value: unknown): NutritionConfig | null {
  if (value === null || value === undefined) return null
  if (Array.isArray(value)) {
    if (value.length === 0) return null
    if (value.length !== 1) throw new Error('El servidor devolvió una configuración nutricional inválida.')
  }
  const row = Array.isArray(value) ? value[0] : value
  if (!row || typeof row !== 'object') throw new Error('El servidor devolvió una configuración nutricional inválida.')
  const config = row as NutritionConfigRow
  const configFields = ['config_version', 'activity_factors', 'goal_adjustments', 'source_note', 'effective_at']
  if (configFields.every((field) => Object.hasOwn(config, field) && config[field] === null)) return null
  const configVersion = Number(config.config_version)
  const effectiveAt = config.effective_at
  const sourceNote = config.source_note
  if (!Number.isSafeInteger(configVersion) || configVersion < 1 || typeof effectiveAt !== 'string' || !Number.isFinite(Date.parse(effectiveAt)) || typeof sourceNote !== 'string') throw new Error('El servidor devolvió una configuración nutricional inválida.')
  const factorNumbers = numericMap(config.activity_factors, activityLevels, 'factores')
  if (activityLevels.some((key) => factorNumbers[key] <= 0 || factorNumbers[key] > 10 || Math.round(factorNumbers[key] * 1e6) !== factorNumbers[key] * 1e6)) throw new Error('Configuración nutricional inválida: factores.')
  const rawGoals = config.goal_adjustments
  if (!rawGoals || typeof rawGoals !== 'object' || Array.isArray(rawGoals)) throw new Error('Configuración nutricional inválida: objetivos.')
  const goalRow = rawGoals as Record<string, unknown>
  if (Object.keys(goalRow).length !== goals.length) throw new Error('Configuración nutricional inválida: objetivos.')
  const goalAdjustments = Object.fromEntries(goals.map((goal) => {
    const bounds = goalRow[goal]
    if (!bounds || typeof bounds !== 'object' || Array.isArray(bounds)) throw new Error('Configuración nutricional inválida: objetivos.')
    const item = bounds as Record<string, unknown>
    if (Object.keys(item).length !== 2 || typeof item.minimum !== 'number' || typeof item.maximum !== 'number' || !Number.isInteger(item.minimum) || !Number.isInteger(item.maximum) || item.minimum < -10000 || item.minimum > 10000 || item.maximum < -10000 || item.maximum > 10000 || item.minimum > item.maximum) throw new Error('Configuración nutricional inválida: objetivos.')
    return [goal, { minimum: item.minimum, maximum: item.maximum }]
  })) as NutritionConfig['goalAdjustments']
  return { configVersion, activityFactors: factorNumbers, goalAdjustments, sourceNote, effectiveAt }
}

interface NutritionDependencies {
  configured: boolean
  relationalProfiles: boolean
  relationalAdmin: boolean
  getCurrent(session: PersonalDataSession): Promise<unknown>
  list(session: PersonalDataSession): Promise<unknown>
  publish(config: NutritionConfigInput, expectedVersion: number, session: PersonalDataSession): Promise<unknown>
}

export function createNutritionRepository(dependencies: NutritionDependencies = {
  configured: isSupabaseConfigured,
  relationalProfiles: isRelationalProfilesEnabled,
  relationalAdmin: isRelationalAdminEnabled,
  async getCurrent(session) {
    assertPersonalDataSessionCurrent(session)
    const { data: { user }, error: userError } = await supabase!.auth.getUser()
    if (userError) throw userError
    if (!user) throw new Error('Iniciá sesión para consultar la configuración nutricional.')
    assertPersonalDataOwner(session, user.id)
    const { data, error } = await supabase!.rpc('get_current_nutrition_config')
    if (error) throw error
    assertPersonalDataSessionCurrent(session)
    return data
  },
  async list(session) {
    assertPersonalDataSessionCurrent(session)
    const { data, error } = await supabase!.rpc('admin_list_nutrition_configs')
    if (error) throw error
    assertPersonalDataSessionCurrent(session)
    return data
  },
  async publish(config, expectedVersion, session) {
    assertPersonalDataSessionCurrent(session)
    const { data, error } = await supabase!.rpc('admin_publish_nutrition_config', {
      p_config: { activity_factors: config.activityFactors, goal_adjustments: config.goalAdjustments, source_note: config.sourceNote, effective_at: config.effectiveAt },
      p_expected_latest_version: expectedVersion,
    })
    if (error) throw error
    assertPersonalDataSessionCurrent(session)
    return data
  },
}) {
  return {
    async getCurrent() {
      if (!dependencies.configured || !dependencies.relationalProfiles) return null
      const session = capturePersonalDataSession()
      const result = mapNutritionConfig(await dependencies.getCurrent(session))
      assertPersonalDataSessionCurrent(session)
      return result
    },
    async list() {
      if (!dependencies.configured || !dependencies.relationalAdmin) throw new Error('La administración relacional no está disponible.')
      const session = capturePersonalDataSession()
      const rows = await dependencies.list(session)
      assertPersonalDataSessionCurrent(session)
      if (!Array.isArray(rows)) throw new Error('El servidor devolvió versiones nutricionales inválidas.')
      return rows.map(mapNutritionConfig).filter((item): item is NutritionConfig => item !== null)
    },
    async publish(config: NutritionConfigInput, expectedVersion: number) {
      if (!dependencies.configured || !dependencies.relationalAdmin) throw new Error('La administración relacional no está disponible.')
      const session = capturePersonalDataSession()
      const result = mapNutritionConfig(await dependencies.publish(config, expectedVersion, session))
      assertPersonalDataSessionCurrent(session)
      if (!result) throw new Error('El servidor no devolvió la versión publicada.')
      return result
    },
  }
}

export const nutritionRepository = createNutritionRepository()
