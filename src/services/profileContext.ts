import type { Session, SupabaseClient } from '@supabase/supabase-js'
import type { RoleCode } from '../types/operations'

export type ProfileContextStatus = 'idle' | 'loading' | 'valid' | 'invalid' | 'error'

export interface AuthenticatedProfile {
  readonly id: string
  readonly local_id: string
  readonly rol_id: number
  readonly nombre: string
  readonly activo: boolean
}

export interface AuthenticatedRole {
  readonly id: number
  readonly codigo: RoleCode
  readonly activo: boolean
}

export interface AuthenticatedLocal {
  readonly id: string
  readonly activo: boolean
}

export interface ValidatedProfileContext {
  readonly profile: AuthenticatedProfile
  readonly role: AuthenticatedRole
  readonly local: AuthenticatedLocal
}

export interface ProfileContextState {
  readonly status: ProfileContextStatus
  readonly context: ValidatedProfileContext | null
  readonly message: string | null
}

export interface ProfileContextController {
  readonly getSnapshot: () => ProfileContextState
  readonly subscribe: (listener: () => void) => () => void
  readonly load: (session: Session | null) => Promise<void>
  readonly retry: () => Promise<void>
  readonly clear: () => void
}

interface RelatedRole {
  readonly id: number
  readonly codigo: string
  readonly activo: boolean
}

interface RelatedLocal {
  readonly id: string
  readonly activo: boolean
}

interface ProfileRow {
  readonly id: string
  readonly local_id: string
  readonly rol_id: number
  readonly nombre: string
  readonly activo: boolean
  readonly rol: RelatedRole | readonly RelatedRole[] | null
  readonly local: RelatedLocal | readonly RelatedLocal[] | null
}

type ProfileClient = Pick<SupabaseClient, 'from'>

const allowedRoleCodes = new Set<string>([
  'ADMINISTRADOR',
  'MOZO',
  'COCINA',
  'CAJA',
])

const profileColumns =
  'id,local_id,rol_id,nombre,activo,rol:rol_id(id,codigo,activo),local:local_id(id,activo)'

const invalidContextMessage = 'Tu acceso no está habilitado. Comunícate con el administrador.'
const connectionErrorMessage = 'No pudimos verificar tu acceso. Revisa tu conexión e intenta nuevamente.'

const emptyState: ProfileContextState = {
  status: 'idle',
  context: null,
  message: null,
}

function singleRelation<T>(relation: T | readonly T[] | null): T | null {
  if (!relation) {
    return null
  }
  if (Array.isArray(relation)) {
    return relation.length === 1 ? relation[0] as T : null
  }
  return relation as T
}

function validateProfile(row: ProfileRow | null, userId: string): ValidatedProfileContext | null {
  if (!row || row.id !== userId || !row.activo) {
    return null
  }

  const role = singleRelation(row.rol)
  const local = singleRelation(row.local)

  if (
    !role
    || !role.activo
    || role.id !== row.rol_id
    || !allowedRoleCodes.has(role.codigo)
    || !local
    || !local.activo
    || local.id !== row.local_id
  ) {
    return null
  }

  return {
    profile: {
      id: row.id,
      local_id: row.local_id,
      rol_id: row.rol_id,
      nombre: row.nombre,
      activo: row.activo,
    },
    role: {
      id: role.id,
      codigo: role.codigo as RoleCode,
      activo: role.activo,
    },
    local: {
      id: local.id,
      activo: local.activo,
    },
  }
}

export function createProfileContextController(client: ProfileClient): ProfileContextController {
  let state = emptyState
  let currentSession: Session | null = null
  let generation = 0
  const listeners = new Set<() => void>()

  function publish(nextState: ProfileContextState): void {
    state = nextState
    for (const listener of listeners) {
      listener()
    }
  }

  async function load(session: Session | null): Promise<void> {
    currentSession = session
    const requestGeneration = ++generation

    if (!session) {
      publish(emptyState)
      return
    }

    publish({ status: 'loading', context: null, message: null })

    try {
      const { data, error } = await client
        .from('perfil_usuario')
        .select(profileColumns)
        .eq('id', session.user.id)
        .maybeSingle()

      if (requestGeneration !== generation) {
        return
      }

      if (error) {
        if (error.code === 'PGRST116') {
          publish({ status: 'invalid', context: null, message: invalidContextMessage })
          return
        }

        publish({ status: 'error', context: null, message: connectionErrorMessage })
        return
      }

      const context = validateProfile(data as unknown as ProfileRow | null, session.user.id)
      if (!context) {
        publish({ status: 'invalid', context: null, message: invalidContextMessage })
        return
      }

      publish({ status: 'valid', context, message: null })
    } catch {
      if (requestGeneration === generation) {
        publish({ status: 'error', context: null, message: connectionErrorMessage })
      }
    }
  }

  return {
    getSnapshot: () => state,

    subscribe(listener) {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },

    load,

    async retry() {
      await load(currentSession)
    },

    clear() {
      currentSession = null
      generation += 1
      publish(emptyState)
    },
  }
}
