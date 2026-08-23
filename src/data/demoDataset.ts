import type {
  DemoCategory,
  DemoDataset,
  DemoLocal,
  DemoProduct,
  DemoTable,
} from '../types/demoDataset'
import { ROLES } from './operationalRules'

export const DEMO_LOCAL = {
  code: 'MIKUY-DEMO',
  name: 'MikuyApp Demo',
  active: true,
} as const satisfies DemoLocal

export const DEMO_TABLES = [
  { code: 'M01', localCode: 'MIKUY-DEMO', name: 'Mesa 1', status: 'LIBRE', active: true },
  { code: 'M02', localCode: 'MIKUY-DEMO', name: 'Mesa 2', status: 'LIBRE', active: true },
  { code: 'M03', localCode: 'MIKUY-DEMO', name: 'Mesa 3', status: 'LIBRE', active: true },
  { code: 'M04', localCode: 'MIKUY-DEMO', name: 'Mesa 4', status: 'LIBRE', active: true },
  { code: 'M05', localCode: 'MIKUY-DEMO', name: 'Mesa 5', status: 'LIBRE', active: true },
  { code: 'M06', localCode: 'MIKUY-DEMO', name: 'Mesa 6', status: 'LIBRE', active: true },
] as const satisfies readonly DemoTable[]

export const DEMO_CATEGORIES = [
  { code: 'CEVICHES', localCode: 'MIKUY-DEMO', name: 'Ceviches', order: 1, active: true },
  { code: 'CHICHARRONES', localCode: 'MIKUY-DEMO', name: 'Chicharrones', order: 2, active: true },
  { code: 'ARROCES', localCode: 'MIKUY-DEMO', name: 'Arroces', order: 3, active: true },
  { code: 'COMBOS', localCode: 'MIKUY-DEMO', name: 'Combos', order: 4, active: true },
  { code: 'BEBIDAS', localCode: 'MIKUY-DEMO', name: 'Bebidas', order: 5, active: true },
] as const satisfies readonly DemoCategory[]

export const DEMO_PRODUCTS = [
  { code: 'CEVICHE_CLASICO', categoryCode: 'CEVICHES', name: 'Ceviche clásico', price: 30.00, active: true },
  { code: 'CEVICHE_MIXTO', categoryCode: 'CEVICHES', name: 'Ceviche mixto', price: 38.00, active: true },
  { code: 'CHICHARRON_PESCADO', categoryCode: 'CHICHARRONES', name: 'Chicharrón de pescado', price: 28.00, active: true },
  { code: 'CHICHARRON_MIXTO', categoryCode: 'CHICHARRONES', name: 'Chicharrón mixto', price: 35.00, active: true },
  { code: 'ARROZ_MARISCOS', categoryCode: 'ARROCES', name: 'Arroz con mariscos', price: 34.00, active: true },
  { code: 'CHAUFA_MARISCOS', categoryCode: 'ARROCES', name: 'Chaufa de mariscos', price: 32.00, active: true },
  { code: 'COMBO_CEVICHE_CHICHARRON', categoryCode: 'COMBOS', name: 'Combo ceviche y chicharrón', price: 42.00, active: true },
  { code: 'COMBO_FAMILIAR', categoryCode: 'COMBOS', name: 'Combo familiar', price: 75.00, active: true },
  { code: 'CHICHA_MORADA', categoryCode: 'BEBIDAS', name: 'Chicha morada', price: 8.00, active: true },
  { code: 'GASEOSA_PERSONAL', categoryCode: 'BEBIDAS', name: 'Gaseosa personal', price: 5.00, active: true },
] as const satisfies readonly DemoProduct[]

export const DEMO_DATASET = {
  roles: ROLES,
  local: DEMO_LOCAL,
  tables: DEMO_TABLES,
  categories: DEMO_CATEGORIES,
  products: DEMO_PRODUCTS,
} as const satisfies DemoDataset
