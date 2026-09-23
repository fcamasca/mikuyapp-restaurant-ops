import assert from "node:assert/strict";
import test from "node:test";
import { createCashierService } from "../src/services/cashierService.ts";

// E1-T18: cashierService.fail() es el único punto de mapeo de errores de
// conflicto para todas las RPC de caja (rpc_abrir_sesion_caja,
// rpc_solicitar_descuento_pedido, rpc_registrar_cobro_pedido, etc.). Antes de
// este correctivo no existía ninguna prueba que cubriera ese mapeo; estas
// pruebas verifican que PT409 (código vigente) y 40001/23505 (compatibilidad
// temporal) se traducen igual a `kind: 'conflict'`, y que un código no
// relacionado no lo hace.

const context = {
  profile: { id: "u1", local_id: "l1", rol_id: 4, nombre: "Caja", activo: true },
  role: { id: 4, codigo: "CAJA", activo: true },
  local: { id: "l1", nombre: "Local", activo: true },
};

const clientWithRpcError = (code) => ({
  async rpc() {
    return { data: null, error: { code } };
  },
});

for (const code of ["PT409", "40001", "23505"]) {
  test(`E1-T18 cashierService traduce ${code} como conflict`, async () => {
    const service = createCashierService(clientWithRpcError(code));
    const result = await service.getActiveSession(context, "caja-1");
    assert.equal(result.ok, false);
    assert.equal(result.error.kind, "conflict");
  });
}

test("E1-T18 cashierService no trata un error ajeno como conflict", async () => {
  const service = createCashierService(clientWithRpcError("22023"));
  const result = await service.getActiveSession(context, "caja-1");
  assert.equal(result.ok, false);
  assert.equal(result.error.kind, "operation-error");
});
