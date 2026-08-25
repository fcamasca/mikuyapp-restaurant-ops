import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createAuthenticationController } from '../src/services/authSession.ts'

function createClient({ session = null, signInResult, signOutResult } = {}) {
  let listener
  let unsubscribed = false

  const client = {
    auth: {
      getSession: async () => ({ data: { session }, error: null }),
      onAuthStateChange(callback) {
        listener = callback
        return {
          data: {
            subscription: {
              unsubscribe() {
                unsubscribed = true
              },
            },
          },
        }
      },
      signInWithPassword: async () => signInResult ?? {
        data: { session: { user: { id: 'fake-user' } } },
        error: null,
      },
      signOut: async () => signOutResult ?? { error: null },
    },
  }

  return {
    client,
    emit(event, nextSession) {
      listener?.(event, nextSession)
    },
    get unsubscribed() {
      return unsubscribed
    },
  }
}

test('restaura una sesión existente durante la carga inicial', async () => {
  const session = { user: { id: 'fake-user' } }
  const fixture = createClient({ session })
  const controller = createAuthenticationController(fixture.client)

  assert.equal(controller.getSnapshot().status, 'loading')
  await controller.initialize()

  assert.equal(controller.getSnapshot().status, 'authenticated')
  assert.equal(controller.getSnapshot().session, session)
})

test('representa una sesión ausente después de la restauración inicial', async () => {
  const fixture = createClient()
  const controller = createAuthenticationController(fixture.client)

  await controller.initialize()

  assert.equal(controller.getSnapshot().status, 'unauthenticated')
  assert.equal(controller.getSnapshot().session, null)
})

test('actualiza el estado cuando Supabase notifica un cambio de sesión', async () => {
  const fixture = createClient()
  const controller = createAuthenticationController(fixture.client)
  await controller.initialize()

  fixture.emit('SIGNED_IN', { user: { id: 'fake-user' } })

  assert.equal(controller.getSnapshot().status, 'authenticated')
  fixture.emit('SIGNED_OUT', null)
  assert.equal(controller.getSnapshot().status, 'unauthenticated')
})

test('muestra un mensaje seguro ante credenciales inválidas', async () => {
  const fixture = createClient({
    signInResult: {
      data: { session: null },
      error: { code: 'invalid_credentials', status: 400 },
    },
  })
  const controller = createAuthenticationController(fixture.client)
  await controller.initialize()

  const result = await controller.signIn('test@example.invalid', 'fake-password')

  assert.equal(result.ok, false)
  assert.equal(controller.getSnapshot().status, 'error')
  assert.equal(controller.getSnapshot().message, 'El correo o la contraseña no son correctos.')
  assert.doesNotMatch(controller.getSnapshot().message, /fake-password|example\.invalid/)
})

test('informa cuando el inicio de sesión está en curso', async () => {
  let finishSignIn
  const pendingSignIn = new Promise((resolve) => {
    finishSignIn = resolve
  })
  const fixture = createClient()
  fixture.client.auth.signInWithPassword = () => pendingSignIn
  const controller = createAuthenticationController(fixture.client)
  await controller.initialize()

  const result = controller.signIn('test@example.invalid', 'fake-password')
  assert.equal(controller.getSnapshot().operation, 'signing-in')

  finishSignIn({ data: { session: { user: { id: 'fake-user' } } }, error: null })
  assert.equal((await result).ok, true)
  assert.equal(controller.getSnapshot().operation, 'idle')
})

test('cierra sesión y limpia el estado autenticado', async () => {
  const fixture = createClient({ session: { user: { id: 'fake-user' } } })
  const controller = createAuthenticationController(fixture.client)
  await controller.initialize()

  const result = await controller.signOut()

  assert.equal(result.ok, true)
  assert.equal(controller.getSnapshot().status, 'unauthenticated')
  assert.equal(controller.getSnapshot().session, null)
})

test('cancela la suscripción y omite eventos después del desmontaje', async () => {
  const fixture = createClient()
  const controller = createAuthenticationController(fixture.client)
  await controller.initialize()

  controller.dispose()
  fixture.emit('SIGNED_IN', { user: { id: 'fake-user' } })

  assert.equal(fixture.unsubscribed, true)
  assert.equal(controller.getSnapshot().status, 'unauthenticated')
})

test('presenta un error recuperable si falla la conexión inicial', async () => {
  const fixture = createClient()
  fixture.client.auth.getSession = async () => {
    throw new Error('internal network detail')
  }
  const controller = createAuthenticationController(fixture.client)

  await controller.initialize()

  assert.equal(controller.getSnapshot().status, 'error')
  assert.match(controller.getSnapshot().message, /Verifica tu conexión/)
  assert.doesNotMatch(controller.getSnapshot().message, /internal network detail/)
})
