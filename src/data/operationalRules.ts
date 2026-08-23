import type {
  OperationalFlowStep,
  RoleDefinition,
} from '../types/operations'

export const ROLES = [
  {
    code: 'ADMINISTRADOR',
    name: 'Administrador',
    futureResponsibility: 'Configuración y consultas globales.',
  },
  {
    code: 'MOZO',
    name: 'Mozo',
    futureResponsibility: 'Mesas, registro y entrega de pedidos.',
  },
  {
    code: 'COCINA',
    name: 'Cocina',
    futureResponsibility: 'Recepción y preparación.',
  },
  {
    code: 'CAJA',
    name: 'Caja',
    futureResponsibility: 'Cobro y cierre.',
  },
] as const satisfies readonly RoleDefinition[]

export const MAIN_OPERATIONAL_FLOW = [
  {
    step: 1,
    actor: 'MOZO',
    description: 'Abre la mesa y el pedido, agrega productos y observaciones.',
    resultingOrderStatus: 'ABIERTO',
    resultingTableStatus: 'OCUPADA',
  },
  {
    step: 2,
    actor: 'MOZO',
    description: 'Envía el pedido.',
    resultingOrderStatus: 'ENVIADO',
  },
  {
    step: 3,
    actor: 'COCINA',
    description: 'Recibe el pedido.',
    resultingOrderStatus: 'RECIBIDO_COCINA',
  },
  {
    step: 4,
    actor: 'COCINA',
    description: 'Inicia la preparación.',
    resultingOrderStatus: 'EN_PREPARACION',
  },
  {
    step: 5,
    actor: 'COCINA',
    description: 'Marca el pedido como listo.',
    resultingOrderStatus: 'LISTO',
    resultingTableStatus: 'PEDIDO_LISTO',
  },
  {
    step: 6,
    actor: 'MOZO',
    description: 'Entrega el pedido.',
    resultingOrderStatus: 'ENTREGADO',
    resultingTableStatus: 'PENDIENTE_PAGO',
  },
  {
    step: 7,
    actor: 'CAJA',
    description: 'Registra el pago.',
  },
  {
    step: 8,
    actor: 'CAJA',
    description: 'Deja el pedido pagado y la mesa libre.',
    resultingOrderStatus: 'PAGADO',
    resultingTableStatus: 'LIBRE',
  },
] as const satisfies readonly OperationalFlowStep[]
