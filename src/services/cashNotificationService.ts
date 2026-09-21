import type { SupabaseClient } from "@supabase/supabase-js";
import type { ValidatedProfileContext } from "./profileContext";

export interface CashNotification {
  id: string;
  type: "APERTURA" | "CIERRE";
  priority: "INFORMATIVA" | "ALERTA";
  createdAt: string;
  readAt: string | null;
  cashboxCode: string;
  cashboxName: string;
  actorName: string;
  initialAmount: number | null;
  expectedCash: number | null;
  countedCash: number | null;
  difference: number | null;
  reason: string | null;
}

export interface CashNotificationSnapshot {
  unreadCount: number;
  notifications: readonly CashNotification[];
}

export type CashNotificationResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: { message: string } };

type Client = Pick<SupabaseClient, "rpc">;

function mapNotification(row: Record<string, unknown>): CashNotification {
  const nullableNumber = (value: unknown) => value == null ? null : Number(value);
  return {
    id: String(row.id),
    type: row.tipo as CashNotification["type"],
    priority: row.prioridad as CashNotification["priority"],
    createdAt: String(row.creado_en),
    readAt: row.leida_en == null ? null : String(row.leida_en),
    cashboxCode: String(row.caja_codigo),
    cashboxName: String(row.caja_nombre),
    actorName: String(row.actor_nombre),
    initialAmount: nullableNumber(row.monto_inicial),
    expectedCash: nullableNumber(row.efectivo_esperado),
    countedCash: nullableNumber(row.efectivo_contado),
    difference: nullableNumber(row.diferencia),
    reason: row.motivo == null ? null : String(row.motivo),
  };
}

export function createCashNotificationService(client: Client) {
  return {
    async getNotifications(context: ValidatedProfileContext): Promise<CashNotificationResult<CashNotificationSnapshot>> {
      if (context.role.codigo !== "ADMINISTRADOR") {
        return { ok: false, error: { message: "No autorizado." } };
      }
      try {
        const result = await client.rpc("rpc_obtener_notificaciones_caja");
        if (result.error) {
          return { ok: false, error: { message: "No pudimos cargar las notificaciones." } };
        }
        const data = (result.data ?? {}) as Record<string, unknown>;
        const rows = Array.isArray(data.notificaciones)
          ? data.notificaciones as Record<string, unknown>[]
          : [];
        return {
          ok: true,
          data: {
            unreadCount: Number(data.no_leidas ?? 0),
            notifications: rows.map(mapNotification),
          },
        };
      } catch {
        return { ok: false, error: { message: "No pudimos cargar las notificaciones." } };
      }
    },
    async markAsRead(context: ValidatedProfileContext, notificationId: string): Promise<CashNotificationResult<{ id: string; readAt: string }>> {
      if (context.role.codigo !== "ADMINISTRADOR") {
        return { ok: false, error: { message: "No autorizado." } };
      }
      try {
        const result = await client.rpc("rpc_marcar_notificacion_caja_leida", {
          p_notificacion_id: notificationId,
        });
        if (result.error) {
          return { ok: false, error: { message: "No pudimos marcar la notificación como leída." } };
        }
        const data = result.data as Record<string, unknown>;
        return { ok: true, data: { id: String(data.id), readAt: String(data.leida_en) } };
      } catch {
        return { ok: false, error: { message: "No pudimos marcar la notificación como leída." } };
      }
    },
  };
}
