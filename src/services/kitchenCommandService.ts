import type { SupabaseClient } from '@supabase/supabase-js'
import type { KitchenCancellation, KitchenCommand } from './kitchenRealtimeService.ts'

/**
 * E7-D12 — Comandas de cocina.
 * La aplicación registra solicitudes de impresión; no certifica la salida física del papel.
 * Imprimir nunca modifica detalle, pedido ni mesa.
 */

export type CommandPrintAction = 'Imprimir' | 'Reimprimir'

/** Una sola primera solicitud por comanda; las posteriores son reimpresiones. */
export function commandPrintAction(command: Pick<KitchenCommand, 'impresiones'>): CommandPrintAction {
  return command.impresiones > 0 ? 'Reimprimir' : 'Imprimir'
}

/** Etiqueta de copia: la primera solicitud es el original; cada reimpresión es COPIA n. */
export function commandCopyLabel(impresiones: number): string | null {
  return impresiones > 1 ? `COPIA ${impresiones - 1}` : null
}

export interface CommandDocumentLine {
  readonly detalle_id: number
  readonly producto_codigo: string
  readonly producto_nombre: string
  readonly cantidad: number
  readonly observacion: string | null
  readonly cancelado: boolean
}

export interface CommandDocument {
  readonly title: string
  readonly copyLabel: string | null
  readonly mesa: string
  readonly pedidoId: number
  readonly enviadoEn: string
  readonly mozo: string
  readonly lines: readonly CommandDocumentLine[]
}

/** Documento a imprimir: líneas históricas inmutables, marcando las canceladas después del envío. */
export function buildCommandDocument(
  command: KitchenCommand,
  cancellations: readonly Pick<KitchenCancellation, 'detalle_id'>[],
  impresiones: number,
): CommandDocument {
  const cancelled = new Set(cancellations.map((item) => item.detalle_id))
  return {
    title: `COMANDA #${command.numero}`,
    copyLabel: commandCopyLabel(impresiones),
    mesa: `${command.mesa_codigo} · ${command.mesa_nombre}`,
    pedidoId: command.pedido_id,
    enviadoEn: command.enviado_en,
    mozo: command.creado_por_nombre,
    lines: command.lineas.map((line) => ({ ...line, cancelado: cancelled.has(line.detalle_id) })),
  }
}

export type CommandPrintResult =
  | { readonly ok: true; readonly impresiones: number }
  | { readonly ok: false; readonly error: { readonly kind: 'operation-error' | 'concurrent-conflict'; readonly message: string } }

type CommandClient = Pick<SupabaseClient, 'rpc'>

export function createKitchenCommandService(client: CommandClient) {
  return {
    /** Registra la solicitud antes de invocar window.print(). */
    async registerPrint(commandId: number, reprint: boolean): Promise<CommandPrintResult> {
      try {
        const result = await client.rpc('rpc_registrar_impresion_comanda', { p_comanda_id: commandId, p_reimpresion: reprint })
        if (result.error?.code === 'PT409') {
          return {
            ok: false,
            error: {
              kind: 'concurrent-conflict',
              message: reprint
                ? 'No pudimos reimprimir esta comanda. Se cargó la versión más reciente.'
                : 'Esta comanda ya fue impresa desde otro dispositivo. Usa Reimprimir si necesitas otra copia.',
            },
          }
        }
        if (result.error) {
          return { ok: false, error: { kind: 'operation-error', message: 'No pudimos registrar la impresión. Intenta nuevamente.' } }
        }
        const row = (result.data as Array<{ impresiones: number }> | null)?.[0]
        if (!row) return { ok: false, error: { kind: 'operation-error', message: 'No pudimos registrar la impresión. Intenta nuevamente.' } }
        return { ok: true, impresiones: Number(row.impresiones) }
      } catch {
        return { ok: false, error: { kind: 'operation-error', message: 'No pudimos registrar la impresión. Revisa tu conexión.' } }
      }
    },
  }
}
