export const ROLE_CODES = [
  'ADMINISTRADOR',
  'MOZO',
  'COCINA',
  'CAJA',
] as const

export const TABLE_STATUS_CODES = [
  'LIBRE',
  'OCUPADA',
  'PEDIDO_LISTO',
  'PENDIENTE_PAGO',
] as const

export const ORDER_STATUS_CODES = [
  'ABIERTO',
  'ENVIADO',
  'RECIBIDO_COCINA',
  'EN_PREPARACION',
  'LISTO',
  'ENTREGADO',
  'PAGADO',
  'ANULADO',
] as const

export const PAYMENT_METHOD_CODES = [
  'EFECTIVO',
  'YAPE',
  'PLIN',
  'TARJETA',
] as const
