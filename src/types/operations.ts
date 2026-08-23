export type RoleCode =
  (typeof import('../data/operationalCodes').ROLE_CODES)[number]

export type TableStatusCode =
  (typeof import('../data/operationalCodes').TABLE_STATUS_CODES)[number]

export type OrderStatusCode =
  (typeof import('../data/operationalCodes').ORDER_STATUS_CODES)[number]

export type PaymentMethodCode =
  (typeof import('../data/operationalCodes').PAYMENT_METHOD_CODES)[number]

export interface RoleDefinition {
  readonly code: RoleCode
  readonly name: string
  readonly futureResponsibility: string
}

export interface OperationalFlowStep {
  readonly step: number
  readonly actor: RoleCode
  readonly description: string
  readonly resultingOrderStatus?: OrderStatusCode
  readonly resultingTableStatus?: TableStatusCode
}
