import {
  EnvironmentGuardError,
  maskProjectRef,
  readLocalLinkedProjectRef,
  validateEnvironmentConfiguration,
} from './environmentGuard.mjs'

try {
  const linkedRef = await readLocalLinkedProjectRef()
  const result = validateEnvironmentConfiguration(process.env, linkedRef)
  console.log(
    `Environment guard OK: context=${result.context} state=${result.state} logical=${result.logicalEnvironment} ref=${maskProjectRef(result.effectiveRef)}`,
  )
} catch (error) {
  if (error instanceof EnvironmentGuardError) {
    console.error(`Environment guard rejected [${error.code}]: ${error.message}`)
    process.exitCode = 1
  } else {
    console.error('Environment guard failed: no se pudo validar la configuración.')
    process.exitCode = 1
  }
}
