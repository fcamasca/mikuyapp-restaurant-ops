begin;
create function pg_temp.ok(v boolean,m text)returns void language plpgsql as $$begin if not coalesce(v,false) then raise exception '%',m;end if;end$$;

select pg_temp.ok(not has_table_privilege('authenticated','public.auditoria_caja','INSERT,UPDATE,DELETE'),'auditoría sin escritura cliente');
select pg_temp.ok((select confdeltype='r' from pg_constraint where conname='fk_auditoria_caja_cobro'),'FK cobro RESTRICT');
select pg_temp.ok((select count(*)=1 from pg_indexes where schemaname='public' and tablename='auditoria_caja' and indexname='uq_auditoria_caja_cobro'),'un evento por cobro');
select pg_temp.ok((select pg_get_functiondef('public.rpc_registrar_cobro_pedido(bigint,uuid,text,jsonb,uuid)'::regprocedure) ~ 'insert into public.auditoria_caja'),'auditoría dentro de RPC atómica');

-- El delta acepta explícitamente auditorías PAGO históricas sin fabricar cabecera.
select pg_temp.ok((select pg_get_constraintdef(oid) ~* 'cobro_id IS NULL.*medios IS NULL' from pg_constraint where conname='ck_auditoria_caja_medios'),'auditoría legacy representable');

select 'PASS DELTA E1-T11 auditoría por cobro, inmutable y legacy compatible';
rollback;
