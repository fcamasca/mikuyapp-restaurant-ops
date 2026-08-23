import type { RoleDefinition, TableStatusCode } from './operations'

export interface DemoLocal {
  readonly code: string
  readonly name: string
  readonly active: boolean
}

export interface DemoTable {
  readonly code: string
  readonly localCode: string
  readonly name: string
  readonly status: TableStatusCode
  readonly active: boolean
}

export interface DemoCategory {
  readonly code: string
  readonly localCode: string
  readonly name: string
  readonly order: number
  readonly active: boolean
}

export interface DemoProduct {
  readonly code: string
  readonly categoryCode: string
  readonly name: string
  readonly price: number
  readonly active: boolean
}

export interface DemoDataset {
  readonly roles: readonly RoleDefinition[]
  readonly local: DemoLocal
  readonly tables: readonly DemoTable[]
  readonly categories: readonly DemoCategory[]
  readonly products: readonly DemoProduct[]
}
