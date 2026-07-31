--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: apagar_folha_mes(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apagar_folha_mes(p_run_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_run payroll_runs%rowtype;
  v_status_folha text;
  v_status_ir text;
begin
  select * into v_run from payroll_runs where id = p_run_id;
  if v_run is null then raise exception 'Folha não encontrada'; end if;

  select status into v_status_folha from financial_transactions where id = v_run.financial_transaction_folha_id;
  select status into v_status_ir from financial_transactions where id = v_run.financial_transaction_ir_id;

  if v_status_folha = 'baixado' or v_status_ir = 'baixado' then
    raise exception 'Não é possível apagar: uma das contas já foi baixada (dinheiro já foi movimentado).';
  end if;

  delete from financial_transactions where id in (v_run.financial_transaction_folha_id, v_run.financial_transaction_ir_id);
  delete from payroll_runs where id = p_run_id; -- payroll_items apaga em cascata
end;
$$;


--
-- Name: aplicar_investimento(uuid, text, numeric, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.aplicar_investimento(p_conta_id uuid, p_produto_id text, p_valor numeric, p_data_vencimento date) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
declare
  v_produto record;
  v_aplicacao_id uuid;
begin
  select * into v_produto from banco_alegre_produtos_captacao where id = p_produto_id;

  if v_produto is null then
    raise exception 'Produto de captação não encontrado';
  end if;

  if p_valor < v_produto.valor_minimo_aplicacao then
    raise exception 'Valor abaixo do mínimo exigido (%). Mínimo: R$ %', v_produto.nome, v_produto.valor_minimo_aplicacao;
  end if;

  if p_valor > (select saldo from banco_alegre_contas where id = p_conta_id) then
    raise exception 'Saldo insuficiente na conta para essa aplicação';
  end if;

  insert into banco_alegre_aplicacoes (
    conta_id, produto_id, valor_aplicado, taxa_juros_pct_am, data_vencimento,
    isento_ir, aliquota_ir_pct, garantia_fgc
  ) values (
    p_conta_id, p_produto_id, p_valor, v_produto.taxa_juros_pct_am, p_data_vencimento,
    v_produto.isento_ir, v_produto.aliquota_ir_pct, v_produto.garantia_fgc
  )
  returning id into v_aplicacao_id;

  update banco_alegre_contas set saldo = saldo - p_valor, updated_at = now() where id = p_conta_id;

  insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao, referencia_id)
  values (p_conta_id, 'Aplicacao', -p_valor, 'Aplicação em ' || v_produto.nome, v_aplicacao_id);

  return v_aplicacao_id;
end;
$_$;


--
-- Name: aplicar_juros_cheque_especial(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.aplicar_juros_cheque_especial() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  conta record;
  v_dentro_limite numeric;
  v_excedente numeric;
  v_juros_total numeric;
  v_count int := 0;
begin
  for conta in
    select * from banco_alegre_contas where saldo < 0
  loop
    if abs(conta.saldo) <= conta.limite_cheque_especial then
      v_dentro_limite := abs(conta.saldo);
      v_excedente := 0;
    else
      v_dentro_limite := conta.limite_cheque_especial;
      v_excedente := abs(conta.saldo) - conta.limite_cheque_especial;
    end if;

    v_juros_total := round(
      v_dentro_limite * coalesce(conta.taxa_cheque_especial_pct_am, 0) / 100 +
      v_excedente * coalesce(conta.taxa_mora_excedente_pct_am, 0) / 100,
      2
    );

    if v_juros_total > 0 then
      update banco_alegre_contas
      set saldo = saldo - v_juros_total, updated_at = now()
      where id = conta.id;

      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (conta.id, 'Juros_Cheque_Especial', -v_juros_total, 'Juros mensais sobre saldo negativo');

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;


--
-- Name: atacarejo_apagar_folha_mes(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_apagar_folha_mes(p_run_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_run atacarejo_payroll_runs%rowtype;
  v_status_folha text;
  v_status_ir text;
begin
  select * into v_run from atacarejo_payroll_runs where id = p_run_id;
  if v_run is null then raise exception 'Folha não encontrada'; end if;

  select status into v_status_folha from atacarejo_financial_transactions where id = v_run.financial_transaction_folha_id;
  select status into v_status_ir from atacarejo_financial_transactions where id = v_run.financial_transaction_ir_id;

  if v_status_folha = 'baixado' or v_status_ir = 'baixado' then
    raise exception 'Não é possível apagar: uma das contas já foi baixada (dinheiro já foi movimentado).';
  end if;

  delete from atacarejo_financial_transactions where id in (v_run.financial_transaction_folha_id, v_run.financial_transaction_ir_id);
  delete from atacarejo_payroll_runs where id = p_run_id;
end;
$$;


--
-- Name: atacarejo_check_coupon(text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_check_coupon(p_code text, p_order_total numeric) RETURNS TABLE(valid boolean, message text, discount_amount numeric, discount_type text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
declare
  v_coupon atacarejo_coupons%rowtype;
  v_discount numeric;
begin
  select * into v_coupon from atacarejo_coupons where upper(code) = upper(p_code) and active = true;

  if not found then
    return query select false, 'Cupom inválido.', 0::numeric, ''::text;
    return;
  end if;

  if v_coupon.valid_until is not null and v_coupon.valid_until < now() then
    return query select false, 'Cupom expirado.', 0::numeric, ''::text;
    return;
  end if;

  if v_coupon.max_uses is not null and v_coupon.used_count >= v_coupon.max_uses then
    return query select false, 'Cupom esgotado.', 0::numeric, ''::text;
    return;
  end if;

  if p_order_total < v_coupon.min_order_value then
    return query select false,
      ('Pedido mínimo de R$ ' || to_char(v_coupon.min_order_value, 'FM999990.00') || ' para usar este cupom.'),
      0::numeric, ''::text;
    return;
  end if;

  if v_coupon.discount_type = 'percentage' then
    v_discount := p_order_total * (v_coupon.discount_value / 100);
  else
    v_discount := v_coupon.discount_value;
  end if;

  v_discount := least(v_discount, p_order_total);

  return query select true, 'Cupom aplicado!', v_discount, v_coupon.discount_type;
end;
$_$;


--
-- Name: atacarejo_create_delivery_record(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_create_delivery_record() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  insert into atacarejo_deliveries (order_id, status) values (new.id, 'aguardando_separacao')
  on conflict (order_id) do nothing;
  return new;
end;
$$;


--
-- Name: atacarejo_credit_governo_on_tax_payment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_credit_governo_on_tax_payment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_governo_conta_id uuid;
begin
  if new.category = 'IMPOSTOS SOBRE VENDAS' and new.status = 'baixado' and (old.status is distinct from 'baixado') then
    select ba.id into v_governo_conta_id
    from banco_alegre_contas ba
    join banco_alegre_clientes bc on bc.id = ba.cliente_id
    where bc.nome = 'Governo';

    if v_governo_conta_id is not null then
      insert into governo_extrato (empresa, tipo, valor, descricao, referencia_transacao_id, data)
      values ('Atacarejo', 'Imposto sobre Vendas', new.amount, new.description, new.id, current_date);

      update banco_alegre_contas set saldo = saldo + new.amount, updated_at = now() where id = v_governo_conta_id;

      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_governo_conta_id, 'Recebimento_Imposto', new.amount, 'Imposto recebido de Atacarejo: ' || new.description);
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: atacarejo_decrement_stock(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_decrement_stock(p_product_id uuid, p_quantity integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  if p_quantity <= 0 then
    raise exception 'Quantidade inválida';
  end if;
  update atacarejo_products
  set stock = greatest(stock - p_quantity, 0), updated_at = now()
  where id = p_product_id;
end;
$$;


--
-- Name: atacarejo_generate_receivable_on_delivery(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_generate_receivable_on_delivery() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_order record;
  v_modo_comissao boolean;
  v_custo_produtos numeric;
  v_valor_receita numeric;
begin
  if new.status = 'entregue' and (old.status is distinct from 'entregue') then
    select * into v_order from atacarejo_orders where id = new.order_id;

    if found and not exists (
      select 1 from atacarejo_financial_transactions
      where order_id = v_order.id and category = 'RECEITA DE VENDA'
    ) then
      select coalesce(enabled, false) into v_modo_comissao from atacarejo_module_settings where id = 'modo_comissao';

      if v_modo_comissao then
        select coalesce(sum(oi.quantity * p.cost_price), 0) into v_custo_produtos
        from atacarejo_order_items oi
        join atacarejo_products p on p.id = oi.product_id
        where oi.order_id = v_order.id;

        v_valor_receita := v_order.total - v_custo_produtos;
      else
        v_valor_receita := v_order.total;
      end if;

      insert into atacarejo_financial_transactions
        (type, description, category, amount, due_date, status, order_id, origin)
      values
        ('entrada',
         'Venda - Pedido #' || v_order.order_number || case when v_modo_comissao then ' (comissão)' else '' end,
         'RECEITA DE VENDA',
         v_valor_receita, current_date, 'pendente', v_order.id, 'pedido_entregue');
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: atacarejo_gerar_conta_imposto_governo(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_gerar_conta_imposto_governo(p_order_ids uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_total numeric := 0;
  v_categoria_existe boolean;
  v_transaction_id uuid;
  v_count int;
begin
  select count(*), coalesce(sum(tax_amount), 0) into v_count, v_total
  from atacarejo_order_tax_view
  where order_id = any(p_order_ids) and tax_settled = false;

  if v_count = 0 then
    raise exception 'Nenhum pedido válido selecionado (já podem estar quitados, ou não entregues).';
  end if;

  select exists(select 1 from atacarejo_chart_of_accounts where upper(name) = 'IMPOSTOS SOBRE VENDAS') into v_categoria_existe;
  if not v_categoria_existe then
    insert into atacarejo_chart_of_accounts (name, type, classification, active)
    values ('IMPOSTOS SOBRE VENDAS', 'despesa', 'variavel', true);
  end if;

  insert into atacarejo_financial_transactions (type, description, category, amount, due_date, status, origin)
  values ('saida', 'Imposto sobre vendas — ' || v_count || ' pedido(s) entregue(s)',
          'IMPOSTOS SOBRE VENDAS', v_total, current_date, 'pendente', 'imposto_governo')
  returning id into v_transaction_id;

  update atacarejo_orders
  set tax_settled = true, tax_settlement_id = v_transaction_id
  where id = any(p_order_ids) and tax_settled = false;

  return v_transaction_id;
end;
$$;


--
-- Name: atacarejo_gerar_folha_pagamento(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_gerar_folha_pagamento(p_forcar boolean DEFAULT false) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_mes text := to_char(current_date, 'YYYY-MM');
  v_ja_existe boolean;
  v_faturamento_mes numeric;
  v_categoria_folha_existe boolean;
  v_categoria_ir_existe boolean;
  v_run_id uuid;
  v_transacao_folha_id uuid;
  v_transacao_ir_id uuid;
  v_total_folha numeric := 0;
  v_total_ir numeric := 0;
  e record;
  v_bruto numeric;
  v_ir numeric;
  v_liquido numeric;
begin
  select exists(select 1 from atacarejo_payroll_runs where mes = v_mes) into v_ja_existe;
  if v_ja_existe and not p_forcar then
    raise exception 'FOLHA_JA_GERADA';
  end if;

  select coalesce(sum(amount), 0) into v_faturamento_mes
  from atacarejo_financial_transactions
  where type = 'entrada' and category = 'RECEITA DE VENDA'
    and due_date >= date_trunc('month', current_date)
    and due_date < date_trunc('month', current_date) + interval '1 month';

  select exists(select 1 from atacarejo_chart_of_accounts where upper(name) = 'FOLHA DE PAGAMENTO') into v_categoria_folha_existe;
  if not v_categoria_folha_existe then
    insert into atacarejo_chart_of_accounts (name, type, classification, active) values ('FOLHA DE PAGAMENTO', 'despesa', 'fixo', true);
  end if;

  select exists(select 1 from atacarejo_chart_of_accounts where upper(name) = 'IR SOBRE FOLHA DE PAGAMENTO') into v_categoria_ir_existe;
  if not v_categoria_ir_existe then
    insert into atacarejo_chart_of_accounts (name, type, classification, active) values ('IR SOBRE FOLHA DE PAGAMENTO', 'despesa', 'fixo', true);
  end if;

  create temporary table temp_folha_ataca (employee_id uuid, bruto numeric, ir numeric, liquido numeric) on commit drop;

  for e in select * from atacarejo_employees where status = 'ativo' loop
    if e.salario_tipo = 'fixo' then
      v_bruto := coalesce(e.valor_salario, 0) + coalesce(e.acrescimos, 0);
    else
      v_bruto := (v_faturamento_mes * coalesce(e.pct_salario_faturamento, 0) / 100) + coalesce(e.acrescimos, 0);
    end if;
    v_ir := round(v_bruto * coalesce(e.pct_ir, 0) / 100, 2);
    v_liquido := v_bruto - v_ir;

    insert into temp_folha_ataca values (e.id, v_bruto, v_ir, v_liquido);
    v_total_folha := v_total_folha + v_liquido;
    v_total_ir := v_total_ir + v_ir;
  end loop;

  insert into atacarejo_financial_transactions (type, description, category, amount, due_date, status, origin)
  values ('saida', 'Folha de pagamento — ' || v_mes, 'FOLHA DE PAGAMENTO', v_total_folha, current_date, 'pendente', 'folha_pagamento')
  returning id into v_transacao_folha_id;

  insert into atacarejo_financial_transactions (type, description, category, amount, due_date, status, origin)
  values ('saida', 'IR sobre folha de pagamento — ' || v_mes, 'IR SOBRE FOLHA DE PAGAMENTO', v_total_ir, current_date, 'pendente', 'folha_pagamento')
  returning id into v_transacao_ir_id;

  insert into atacarejo_payroll_runs (mes, financial_transaction_folha_id, financial_transaction_ir_id, total_folha, total_ir)
  values (v_mes || '#' || gen_random_uuid()::text, v_transacao_folha_id, v_transacao_ir_id, v_total_folha, v_total_ir)
  returning id into v_run_id;

  if not p_forcar then
    update atacarejo_payroll_runs set mes = v_mes where id = v_run_id;
  end if;

  insert into atacarejo_payroll_items (payroll_run_id, employee_id, valor_bruto, valor_ir, valor_liquido)
  select v_run_id, employee_id, bruto, ir, liquido from temp_folha_ataca;

  return v_transacao_folha_id;
end;
$$;


--
-- Name: atacarejo_increment_coupon_usage(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_increment_coupon_usage(p_code text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  update atacarejo_coupons set used_count = used_count + 1 where upper(code) = upper(p_code);
end;
$$;


--
-- Name: atacarejo_juridico_gerar_conta_a_pagar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_juridico_gerar_conta_a_pagar() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_categoria_existe boolean;
  v_nova_conta_id uuid;
begin
  select exists(select 1 from atacarejo_chart_of_accounts where upper(name) = 'IMPOSTOS E TAXAS') into v_categoria_existe;
  if not v_categoria_existe then
    insert into atacarejo_chart_of_accounts (name, type, classification, active)
    values ('IMPOSTOS E TAXAS', 'despesa', 'variavel', true);
  end if;

  insert into atacarejo_financial_transactions (type, description, category, amount, due_date, status, origin)
  values ('saida', new.nome || ' (' || new.competencia || ')', 'IMPOSTOS E TAXAS',
          coalesce(new.valor_estimado, 0), new.vencimento, 'pendente', 'obrigacao_fiscal')
  returning id into v_nova_conta_id;

  update atacarejo_juridico_obrigacoes_fiscais set contas_pagar_id = v_nova_conta_id where id = new.id;
  return new;
end;
$$;


--
-- Name: atacarejo_launch_purchase_invoice(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_launch_purchase_invoice(invoice_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  item record;
  v_status text;
  v_current_stock int;
  v_current_cost numeric;
  v_new_stock int;
  v_new_cost numeric;
  v_total numeric := 0;
begin
  select status into v_status from atacarejo_purchase_invoices where id = invoice_id;
  if v_status is null then raise exception 'Nota de compra não encontrada'; end if;
  if v_status = 'Lançada' then raise exception 'Essa nota já foi lançada anteriormente'; end if;

  for item in select * from atacarejo_purchase_invoice_items where purchase_invoice_id = invoice_id loop
    select stock, cost_price into v_current_stock, v_current_cost from atacarejo_products where id = item.product_id;
    v_new_stock := coalesce(v_current_stock, 0) + item.quantity;

    if v_new_stock > 0 then
      v_new_cost := ((coalesce(v_current_stock, 0) * coalesce(v_current_cost, 0)) + (item.quantity * item.unit_cost)) / v_new_stock;
    else
      v_new_cost := item.unit_cost;
    end if;

    update atacarejo_products
    set stock = v_new_stock, cost_price = round(v_new_cost, 2),
        tax_pct = coalesce(item.tax_pct, tax_pct), updated_at = now()
    where id = item.product_id;

    v_total := v_total + item.subtotal;
  end loop;

  update atacarejo_purchase_invoices
  set status = 'Lançada', total_value = v_total, launched_at = now(), updated_at = now()
  where id = invoice_id;
end;
$$;


--
-- Name: atacarejo_processar_baixa_folha_ir(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_processar_baixa_folha_ir() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_empresa_conta_id uuid;
  v_governo_conta_id uuid;
  v_run atacarejo_payroll_runs%rowtype;
  item record;
begin
  if new.status <> 'baixado' or old.status = 'baixado' then
    return new;
  end if;

  select ba.id into v_empresa_conta_id
  from banco_alegre_contas ba join banco_alegre_clientes bc on bc.id = ba.cliente_id
  where bc.nome = 'Atacarejo';

  if new.category = 'FOLHA DE PAGAMENTO' then
    select * into v_run from atacarejo_payroll_runs where financial_transaction_folha_id = new.id;

    if v_empresa_conta_id is not null and v_run is not null then
      update banco_alegre_contas set saldo = saldo + new.amount, updated_at = now() where id = v_empresa_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_empresa_conta_id, 'Transferencia_Do_Caixa', new.amount, 'Transferência do Caixa — Folha de pagamento — ' || v_run.mes);

      update banco_alegre_contas set saldo = saldo - new.amount, updated_at = now() where id = v_empresa_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_empresa_conta_id, 'Pagamento_Folha', -new.amount, 'Folha de pagamento — ' || v_run.mes);

      for item in select pi.*, e.name as employee_name from atacarejo_payroll_items pi
        join atacarejo_employees e on e.id = pi.employee_id
        where pi.payroll_run_id = v_run.id
      loop
        if not exists (select 1 from atacarejo_employees where id = item.employee_id and banco_alegre_cliente_id is not null) then
          declare
            v_novo_cliente_id uuid;
            v_nova_conta_id uuid;
          begin
            insert into banco_alegre_clientes (nome, tipo) values (item.employee_name, 'PF') returning id into v_novo_cliente_id;
            insert into banco_alegre_contas (cliente_id, saldo) values (v_novo_cliente_id, 0) returning id into v_nova_conta_id;
            update atacarejo_employees set banco_alegre_cliente_id = v_novo_cliente_id where id = item.employee_id;
          end;
        end if;

        declare
          v_func_cliente_id uuid;
          v_func_conta_id uuid;
        begin
          select banco_alegre_cliente_id into v_func_cliente_id from atacarejo_employees where id = item.employee_id;
          select id into v_func_conta_id from banco_alegre_contas where cliente_id = v_func_cliente_id;

          update banco_alegre_contas set saldo = saldo + item.valor_liquido, updated_at = now() where id = v_func_conta_id;
          insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
          values (v_func_conta_id, 'Recebimento_Salario', item.valor_liquido, 'Salário — Atacarejo — ' || v_run.mes);
        end;
      end loop;
    end if;
  end if;

  if new.category = 'IR SOBRE FOLHA DE PAGAMENTO' then
    select ba.id into v_governo_conta_id
    from banco_alegre_contas ba join banco_alegre_clientes bc on bc.id = ba.cliente_id
    where bc.nome = 'Governo';

    if v_empresa_conta_id is not null then
      update banco_alegre_contas set saldo = saldo + new.amount, updated_at = now() where id = v_empresa_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_empresa_conta_id, 'Transferencia_Do_Caixa', new.amount, 'Transferência do Caixa — ' || new.description);

      update banco_alegre_contas set saldo = saldo - new.amount, updated_at = now() where id = v_empresa_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_empresa_conta_id, 'Recolhimento_IR_Folha', -new.amount, new.description);
    end if;

    if v_governo_conta_id is not null then
      update banco_alegre_contas set saldo = saldo + new.amount, updated_at = now() where id = v_governo_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_governo_conta_id, 'Recebimento_Imposto', new.amount, 'IR sobre folha — Atacarejo — ' || new.description);
      insert into governo_extrato (empresa, tipo, valor, descricao, referencia_transacao_id, data)
      values ('Atacarejo', 'IR sobre Folha de Pagamento', new.amount, new.description, new.id, current_date);
    end if;
  end if;

  return new;
end;
$$;


--
-- Name: atacarejo_sync_order_status_with_delivery(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_sync_order_status_with_delivery() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  if new.status = 'entregue' then
    update atacarejo_orders set status = 'entregue' where id = new.order_id;
    if new.data_entrega is null then
      update atacarejo_deliveries set data_entrega = current_date where id = new.id;
    end if;
  elsif new.status = 'problema' then
    update atacarejo_orders set status = 'pendente' where id = new.order_id;
  end if;
  return new;
end;
$$;


--
-- Name: atacarejo_transferir_banco_para_caixa(uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_transferir_banco_para_caixa(p_conta_id uuid, p_valor numeric, p_descricao text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_categoria_existe boolean;
begin
  if p_valor <= 0 then
    raise exception 'O valor da transferencia precisa ser maior que zero';
  end if;

  select exists(select 1 from atacarejo_chart_of_accounts where upper(name) = 'TRANSFERENCIA BANCARIA') into v_categoria_existe;
  if not v_categoria_existe then
    insert into atacarejo_chart_of_accounts (name, type, classification, active)
    values ('TRANSFERENCIA BANCARIA', 'receita', 'variavel', true);
  end if;

  update banco_alegre_contas set saldo = saldo - p_valor, updated_at = now() where id = p_conta_id;

  insert into atacarejo_financial_transactions (type, description, category, amount, due_date, payment_date, status, origin)
  values ('entrada', coalesce(p_descricao, 'Transferencia do Banco Alegre para o Caixa'),
          'TRANSFERENCIA BANCARIA', p_valor, current_date, current_date, 'baixado', 'transferencia_banco');

  insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
  values (p_conta_id, 'Transferencia_Para_Caixa', -p_valor, coalesce(p_descricao, 'Transferencia para o Caixa'));
end;
$$;


--
-- Name: atacarejo_transferir_caixa_para_banco(uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atacarejo_transferir_caixa_para_banco(p_conta_id uuid, p_valor numeric, p_descricao text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_categoria_existe boolean;
begin
  if p_valor <= 0 then
    raise exception 'O valor da transferencia precisa ser maior que zero';
  end if;

  select exists(select 1 from atacarejo_chart_of_accounts where upper(name) = 'TRANSFERENCIA BANCARIA') into v_categoria_existe;
  if not v_categoria_existe then
    insert into atacarejo_chart_of_accounts (name, type, classification, active)
    values ('TRANSFERENCIA BANCARIA', 'despesa', 'variavel', true);
  end if;

  insert into atacarejo_financial_transactions (type, description, category, amount, due_date, payment_date, status, origin)
  values ('saida', coalesce(p_descricao, 'Transferencia do Caixa para o Banco Alegre'),
          'TRANSFERENCIA BANCARIA', p_valor, current_date, current_date, 'baixado', 'transferencia_banco');

  update banco_alegre_contas set saldo = saldo + p_valor, updated_at = now() where id = p_conta_id;

  insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
  values (p_conta_id, 'Transferencia_Do_Caixa', p_valor, coalesce(p_descricao, 'Transferencia do Caixa'));
end;
$$;


--
-- Name: check_coupon(text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_coupon(p_code text, p_order_total numeric) RETURNS TABLE(valid boolean, message text, discount_amount numeric, discount_type text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
declare
  v_coupon coupons%rowtype;
  v_discount numeric;
begin
  select * into v_coupon from coupons where upper(code) = upper(p_code) and active = true;

  if not found then
    return query select false, 'Cupom inválido.', 0::numeric, ''::text;
    return;
  end if;

  if v_coupon.valid_until is not null and v_coupon.valid_until < now() then
    return query select false, 'Cupom expirado.', 0::numeric, ''::text;
    return;
  end if;

  if v_coupon.max_uses is not null and v_coupon.used_count >= v_coupon.max_uses then
    return query select false, 'Cupom esgotado.', 0::numeric, ''::text;
    return;
  end if;

  if p_order_total < v_coupon.min_order_value then
    return query select false,
      ('Pedido mínimo de R$ ' || to_char(v_coupon.min_order_value, 'FM999990.00') || ' para usar este cupom.'),
      0::numeric, ''::text;
    return;
  end if;

  if v_coupon.discount_type = 'percentage' then
    v_discount := p_order_total * (v_coupon.discount_value / 100);
  else
    v_discount := v_coupon.discount_value;
  end if;

  v_discount := least(v_discount, p_order_total);

  return query select true, 'Cupom aplicado!', v_discount, v_coupon.discount_type;
end;
$_$;


--
-- Name: contratar_emprestimo(uuid, numeric, numeric, integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.contratar_emprestimo(p_conta_id uuid, p_valor_principal numeric, p_taxa_pct_am numeric, p_num_parcelas integer, p_data_primeira_parcela date) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_emprestimo_id uuid;
  v_taxa_mensal numeric := p_taxa_pct_am / 100;
  v_valor_parcela numeric;
  v_saldo_devedor numeric := p_valor_principal;
  v_juros numeric;
  v_amortizacao numeric;
  v_data date;
  i int;
begin
  if v_taxa_mensal = 0 then
    v_valor_parcela := round(p_valor_principal / p_num_parcelas, 2);
  else
    v_valor_parcela := round(
      p_valor_principal * v_taxa_mensal / (1 - power(1 + v_taxa_mensal, -p_num_parcelas)), 2
    );
  end if;

  insert into banco_alegre_emprestimos (
    conta_id, valor_principal, taxa_juros_pct_am, num_parcelas, valor_parcela, data_primeira_parcela
  ) values (
    p_conta_id, p_valor_principal, p_taxa_pct_am, p_num_parcelas, v_valor_parcela, p_data_primeira_parcela
  )
  returning id into v_emprestimo_id;

  v_data := p_data_primeira_parcela;

  for i in 1..p_num_parcelas loop
    v_juros := round(v_saldo_devedor * v_taxa_mensal, 2);
    v_amortizacao := round(v_valor_parcela - v_juros, 2);
    v_saldo_devedor := round(v_saldo_devedor - v_amortizacao, 2);

    if i = p_num_parcelas then
      v_amortizacao := v_amortizacao + v_saldo_devedor;
      v_saldo_devedor := 0;
    end if;

    insert into banco_alegre_emprestimo_parcelas (
      emprestimo_id, numero_parcela, data_vencimento, valor_parcela,
      valor_juros, valor_amortizacao, saldo_devedor_apos
    ) values (
      v_emprestimo_id, i, v_data, v_valor_parcela, v_juros, v_amortizacao, greatest(v_saldo_devedor, 0)
    );

    v_data := v_data + interval '1 month';
  end loop;

  update banco_alegre_contas
  set saldo = saldo + p_valor_principal, updated_at = now()
  where id = p_conta_id;

  insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao, referencia_id)
  values (p_conta_id, 'Emprestimo_Liberado', p_valor_principal, 'Emprestimo liberado', v_emprestimo_id);

  return v_emprestimo_id;
end;
$$;


--
-- Name: create_delivery_record(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_delivery_record() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into deliveries (order_id, status) values (new.id, 'aguardando_separacao')
  on conflict (order_id) do nothing;
  return new;
end;
$$;


--
-- Name: credit_governo_on_tax_payment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.credit_governo_on_tax_payment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_governo_conta_id uuid;
begin
  if new.category = 'IMPOSTOS SOBRE VENDAS' and new.status = 'baixado' and (old.status is distinct from 'baixado') then
    select ba.id into v_governo_conta_id
    from banco_alegre_contas ba
    join banco_alegre_clientes bc on bc.id = ba.cliente_id
    where bc.nome = 'Governo';

    if v_governo_conta_id is not null then
      insert into governo_extrato (empresa, tipo, valor, descricao, referencia_transacao_id, data)
      values ('Minha Loja', 'Imposto sobre Vendas', new.amount, new.description, new.id, current_date);

      update banco_alegre_contas set saldo = saldo + new.amount, updated_at = now() where id = v_governo_conta_id;

      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_governo_conta_id, 'Recebimento_Imposto', new.amount, 'Imposto recebido de Minha Loja: ' || new.description);
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: decrement_stock(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decrement_stock(p_product_id uuid, p_quantity integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  if p_quantity <= 0 then
    raise exception 'Quantidade inválida';
  end if;
  update products
  set stock = greatest(stock - p_quantity, 0), updated_at = now()
  where id = p_product_id;
end;
$$;


--
-- Name: generate_receivable_on_delivery(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_receivable_on_delivery() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_order record;
  v_modo_comissao boolean;
  v_custo_produtos numeric;
  v_valor_receita numeric;
begin
  if new.status = 'entregue' and (old.status is distinct from 'entregue') then
    select * into v_order from orders where id = new.order_id;

    if found and not exists (
      select 1 from financial_transactions
      where order_id = v_order.id and category = 'RECEITA DE VENDA'
    ) then
      select coalesce(enabled, false) into v_modo_comissao from module_settings where id = 'modo_comissao';

      if v_modo_comissao then
        select coalesce(sum(oi.quantity * p.cost_price), 0) into v_custo_produtos
        from order_items oi
        join products p on p.id = oi.product_id
        where oi.order_id = v_order.id;

        v_valor_receita := v_order.total - v_custo_produtos;
      else
        v_valor_receita := v_order.total;
      end if;

      insert into financial_transactions
        (type, description, category, amount, due_date, status, order_id, origin)
      values
        ('entrada',
         'Venda - Pedido #' || v_order.order_number || case when v_modo_comissao then ' (comissão)' else '' end,
         'RECEITA DE VENDA',
         v_valor_receita, current_date, 'pendente', v_order.id, 'pedido_entregue');
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: gerar_conta_imposto_governo(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gerar_conta_imposto_governo(p_order_ids uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_total numeric := 0;
  v_categoria_existe boolean;
  v_transaction_id uuid;
  v_count int;
begin
  select count(*), coalesce(sum(tax_amount), 0) into v_count, v_total
  from order_tax_view
  where order_id = any(p_order_ids) and tax_settled = false;

  if v_count = 0 then
    raise exception 'Nenhum pedido válido selecionado (já podem estar quitados, ou não entregues).';
  end if;

  select exists(select 1 from chart_of_accounts where upper(name) = 'IMPOSTOS SOBRE VENDAS') into v_categoria_existe;
  if not v_categoria_existe then
    insert into chart_of_accounts (name, type, classification, active)
    values ('IMPOSTOS SOBRE VENDAS', 'despesa', 'variavel', true);
  end if;

  insert into financial_transactions (type, description, category, amount, due_date, status, origin)
  values ('saida', 'Imposto sobre vendas — ' || v_count || ' pedido(s) entregue(s)',
          'IMPOSTOS SOBRE VENDAS', v_total, current_date, 'pendente', 'imposto_governo')
  returning id into v_transaction_id;

  update orders
  set tax_settled = true, tax_settlement_id = v_transaction_id
  where id = any(p_order_ids) and tax_settled = false;

  return v_transaction_id;
end;
$$;


--
-- Name: gerar_folha_pagamento(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gerar_folha_pagamento(p_forcar boolean DEFAULT false) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_mes text := to_char(current_date, 'YYYY-MM');
  v_ja_existe boolean;
  v_faturamento_mes numeric;
  v_categoria_folha_existe boolean;
  v_categoria_ir_existe boolean;
  v_run_id uuid;
  v_transacao_folha_id uuid;
  v_transacao_ir_id uuid;
  v_total_folha numeric := 0;
  v_total_ir numeric := 0;
  e record;
  v_bruto numeric;
  v_ir numeric;
  v_liquido numeric;
begin
  select exists(select 1 from payroll_runs where mes = v_mes) into v_ja_existe;
  if v_ja_existe and not p_forcar then
    raise exception 'FOLHA_JA_GERADA';
  end if;

  select coalesce(sum(amount), 0) into v_faturamento_mes
  from financial_transactions
  where type = 'entrada' and category = 'RECEITA DE VENDA'
    and due_date >= date_trunc('month', current_date)
    and due_date < date_trunc('month', current_date) + interval '1 month';

  select exists(select 1 from chart_of_accounts where upper(name) = 'FOLHA DE PAGAMENTO') into v_categoria_folha_existe;
  if not v_categoria_folha_existe then
    insert into chart_of_accounts (name, type, classification, active) values ('FOLHA DE PAGAMENTO', 'despesa', 'fixo', true);
  end if;

  select exists(select 1 from chart_of_accounts where upper(name) = 'IR SOBRE FOLHA DE PAGAMENTO') into v_categoria_ir_existe;
  if not v_categoria_ir_existe then
    insert into chart_of_accounts (name, type, classification, active) values ('IR SOBRE FOLHA DE PAGAMENTO', 'despesa', 'fixo', true);
  end if;

  -- Calcula tudo primeiro (sem gravar), pra saber o total antes de criar as contas a pagar
  create temporary table temp_folha (employee_id uuid, bruto numeric, ir numeric, liquido numeric) on commit drop;

  for e in select * from employees where status = 'ativo' loop
    if e.salario_tipo = 'fixo' then
      v_bruto := coalesce(e.valor_salario, 0) + coalesce(e.acrescimos, 0);
    else
      v_bruto := (v_faturamento_mes * coalesce(e.pct_salario_faturamento, 0) / 100) + coalesce(e.acrescimos, 0);
    end if;
    v_ir := round(v_bruto * coalesce(e.pct_ir, 0) / 100, 2);
    v_liquido := v_bruto - v_ir;

    insert into temp_folha values (e.id, v_bruto, v_ir, v_liquido);
    v_total_folha := v_total_folha + v_liquido;
    v_total_ir := v_total_ir + v_ir;
  end loop;

  insert into financial_transactions (type, description, category, amount, due_date, status, origin)
  values ('saida', 'Folha de pagamento — ' || v_mes, 'FOLHA DE PAGAMENTO', v_total_folha, current_date, 'pendente', 'folha_pagamento')
  returning id into v_transacao_folha_id;

  insert into financial_transactions (type, description, category, amount, due_date, status, origin)
  values ('saida', 'IR sobre folha de pagamento — ' || v_mes, 'IR SOBRE FOLHA DE PAGAMENTO', v_total_ir, current_date, 'pendente', 'folha_pagamento')
  returning id into v_transacao_ir_id;

  insert into payroll_runs (mes, financial_transaction_folha_id, financial_transaction_ir_id, total_folha, total_ir)
  values (v_mes || '#' || gen_random_uuid()::text, v_transacao_folha_id, v_transacao_ir_id, v_total_folha, v_total_ir)
  returning id into v_run_id;

  -- Corrige o "mes" pra ficar limpo quando não é forçado (não duplicado);
  -- quando forçado, mantém um sufixo pra não colidir com a unique constraint
  if not p_forcar then
    update payroll_runs set mes = v_mes where id = v_run_id;
  end if;

  insert into payroll_items (payroll_run_id, employee_id, valor_bruto, valor_ir, valor_liquido)
  select v_run_id, employee_id, bruto, ir, liquido from temp_folha;

  return v_transacao_folha_id;
end;
$$;


--
-- Name: governo_registrar_desembolso(uuid, numeric, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.governo_registrar_desembolso(p_pasta_id uuid, p_valor numeric, p_descricao text, p_data date DEFAULT CURRENT_DATE) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
declare
  v_pasta governo_pastas_view%rowtype;
  v_governo_conta_id uuid;
  v_desembolso_id uuid;
begin
  select * into v_pasta from governo_pastas_view where id = p_pasta_id;

  if v_pasta is null then
    raise exception 'Pasta não encontrada';
  end if;

  if p_valor > v_pasta.a_realizar then
    raise exception 'Valor (%) maior que o saldo disponível na pasta "%": R$ %',
      p_valor, v_pasta.nome, v_pasta.a_realizar;
  end if;

  insert into governo_desembolsos (pasta_id, data, descricao, valor)
  values (p_pasta_id, p_data, p_descricao, p_valor)
  returning id into v_desembolso_id;

  select ba.id into v_governo_conta_id
  from banco_alegre_contas ba
  join banco_alegre_clientes bc on bc.id = ba.cliente_id
  where bc.nome = 'Governo';

  if v_governo_conta_id is not null then
    update banco_alegre_contas set saldo = saldo - p_valor, updated_at = now() where id = v_governo_conta_id;

    insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
    values (v_governo_conta_id, 'Desembolso_Publico', -p_valor, v_pasta.nome || ': ' || p_descricao);
  end if;

  -- NOVO: também lança no Extrato do Governo, como débito
  insert into governo_extrato (empresa, tipo, valor, descricao, referencia_transacao_id, data)
  values ('Governo', 'Desembolso — ' || v_pasta.nome, -p_valor, p_descricao, v_desembolso_id, p_data);

  return v_desembolso_id;
end;
$_$;


--
-- Name: handle_new_auth_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_auth_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into system_users (id, email, role)
  values (
    new.id,
    new.email,
    case when (select count(*) from system_users) = 0 then 'administrador' else 'operador' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;


--
-- Name: increment_coupon_usage(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_coupon_usage(p_code text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  update coupons set used_count = used_count + 1 where upper(code) = upper(p_code);
end;
$$;


--
-- Name: juridico_gerar_conta_a_pagar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.juridico_gerar_conta_a_pagar() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_categoria_existe boolean;
  v_nova_conta_id uuid;
begin
  -- Confere se a categoria "IMPOSTOS E TAXAS" já existe no Plano de Contas
  select exists(
    select 1 from chart_of_accounts where upper(name) = 'IMPOSTOS E TAXAS'
  ) into v_categoria_existe;

  -- Se não existir, cria automaticamente (Despesa, Variável, ativa)
  if not v_categoria_existe then
    insert into chart_of_accounts (name, type, classification, active)
    values ('IMPOSTOS E TAXAS', 'despesa', 'variavel', true);
  end if;

  insert into financial_transactions (
    type, description, category, amount, due_date, status, origin
  ) values (
    'saida',
    new.nome || ' (' || new.competencia || ')',
    'IMPOSTOS E TAXAS',
    coalesce(new.valor_estimado, 0),
    new.vencimento,
    'pendente',
    'obrigacao_fiscal'
  )
  returning id into v_nova_conta_id;

  update juridico_obrigacoes_fiscais
  set contas_pagar_id = v_nova_conta_id
  where id = new.id;

  return new;
end;
$$;


--
-- Name: juridico_marcar_obrigacoes_atrasadas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.juridico_marcar_obrigacoes_atrasadas() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  update juridico_obrigacoes_fiscais
  set status = 'Atrasado', updated_at = now()
  where status = 'Pendente' and vencimento < current_date;
end;
$$;


--
-- Name: launch_purchase_invoice(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.launch_purchase_invoice(invoice_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  item record;
  v_status text;
  v_current_stock int;
  v_current_cost numeric;
  v_new_stock int;
  v_new_cost numeric;
  v_total numeric := 0;
begin
  select status into v_status from purchase_invoices where id = invoice_id;

  if v_status is null then
    raise exception 'Nota de compra não encontrada';
  end if;

  if v_status = 'Lançada' then
    raise exception 'Essa nota já foi lançada anteriormente — não é possível lançar de novo';
  end if;

  for item in select * from purchase_invoice_items where purchase_invoice_id = invoice_id loop
    select stock, cost_price into v_current_stock, v_current_cost
    from products where id = item.product_id;

    v_new_stock := coalesce(v_current_stock, 0) + item.quantity;

    -- Custo médio ponderado: mistura o estoque antigo (e seu custo) com a compra nova
    if v_new_stock > 0 then
      v_new_cost := ((coalesce(v_current_stock, 0) * coalesce(v_current_cost, 0)) + (item.quantity * item.unit_cost)) / v_new_stock;
    else
      v_new_cost := item.unit_cost;
    end if;

    update products
    set
      stock = v_new_stock,
      cost_price = round(v_new_cost, 2),
      tax_pct = coalesce(item.tax_pct, tax_pct),
      updated_at = now()
    where id = item.product_id;

    v_total := v_total + item.subtotal;
  end loop;

  update purchase_invoices
  set status = 'Lançada', total_value = v_total, launched_at = now(), updated_at = now()
  where id = invoice_id;
end;
$$;


--
-- Name: processar_baixa_folha_ir(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.processar_baixa_folha_ir() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_empresa_conta_id uuid;
  v_governo_conta_id uuid;
  v_run payroll_runs%rowtype;
  item record;
begin
  if new.status <> 'baixado' or old.status = 'baixado' then
    return new;
  end if;

  select ba.id into v_empresa_conta_id
  from banco_alegre_contas ba join banco_alegre_clientes bc on bc.id = ba.cliente_id
  where bc.nome = 'Minha Loja';

  if new.category = 'FOLHA DE PAGAMENTO' then
    select * into v_run from payroll_runs where financial_transaction_folha_id = new.id;

    if v_empresa_conta_id is not null and v_run is not null then
      -- Etapa 1: o Caixa transfere o valor pro Banco
      update banco_alegre_contas set saldo = saldo + new.amount, updated_at = now() where id = v_empresa_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_empresa_conta_id, 'Transferencia_Do_Caixa', new.amount, 'Transferência do Caixa — Folha de pagamento — ' || v_run.mes);

      -- Etapa 2: o Banco debita e distribui (pagamento sai da empresa)
      update banco_alegre_contas set saldo = saldo - new.amount, updated_at = now() where id = v_empresa_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_empresa_conta_id, 'Pagamento_Folha', -new.amount, 'Folha de pagamento — ' || v_run.mes);

      for item in select pi.*, e.name as employee_name from payroll_items pi
        join employees e on e.id = pi.employee_id
        where pi.payroll_run_id = v_run.id
      loop
        if not exists (select 1 from employees where id = item.employee_id and banco_alegre_cliente_id is not null) then
          declare
            v_novo_cliente_id uuid;
            v_nova_conta_id uuid;
          begin
            insert into banco_alegre_clientes (nome, tipo) values (item.employee_name, 'PF') returning id into v_novo_cliente_id;
            insert into banco_alegre_contas (cliente_id, saldo) values (v_novo_cliente_id, 0) returning id into v_nova_conta_id;
            update employees set banco_alegre_cliente_id = v_novo_cliente_id where id = item.employee_id;
          end;
        end if;

        declare
          v_func_cliente_id uuid;
          v_func_conta_id uuid;
        begin
          select banco_alegre_cliente_id into v_func_cliente_id from employees where id = item.employee_id;
          select id into v_func_conta_id from banco_alegre_contas where cliente_id = v_func_cliente_id;

          update banco_alegre_contas set saldo = saldo + item.valor_liquido, updated_at = now() where id = v_func_conta_id;
          insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
          values (v_func_conta_id, 'Recebimento_Salario', item.valor_liquido, 'Salário — Minha Loja — ' || v_run.mes);
        end;
      end loop;
    end if;
  end if;

  if new.category = 'IR SOBRE FOLHA DE PAGAMENTO' then
    select ba.id into v_governo_conta_id
    from banco_alegre_contas ba join banco_alegre_clientes bc on bc.id = ba.cliente_id
    where bc.nome = 'Governo';

    if v_empresa_conta_id is not null then
      -- Etapa 1: o Caixa transfere o valor pro Banco
      update banco_alegre_contas set saldo = saldo + new.amount, updated_at = now() where id = v_empresa_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_empresa_conta_id, 'Transferencia_Do_Caixa', new.amount, 'Transferência do Caixa — ' || new.description);

      -- Etapa 2: o Banco debita e recolhe pro Governo
      update banco_alegre_contas set saldo = saldo - new.amount, updated_at = now() where id = v_empresa_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_empresa_conta_id, 'Recolhimento_IR_Folha', -new.amount, new.description);
    end if;

    if v_governo_conta_id is not null then
      update banco_alegre_contas set saldo = saldo + new.amount, updated_at = now() where id = v_governo_conta_id;
      insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
      values (v_governo_conta_id, 'Recebimento_Imposto', new.amount, 'IR sobre folha — Minha Loja — ' || new.description);
      insert into governo_extrato (empresa, tipo, valor, descricao, referencia_transacao_id, data)
      values ('Minha Loja', 'IR sobre Folha de Pagamento', new.amount, new.description, new.id, current_date);
    end if;
  end if;

  return new;
end;
$$;


--
-- Name: processar_cobrancas_vencidas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.processar_cobrancas_vencidas() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  parcela record;
  v_count int := 0;
begin
  for parcela in
    select p.*, e.conta_id
    from banco_alegre_emprestimo_parcelas p
    join banco_alegre_emprestimos e on e.id = p.emprestimo_id
    where p.status = 'Pendente' and p.data_vencimento <= current_date
  loop
    update banco_alegre_contas
    set saldo = saldo - parcela.valor_parcela, updated_at = now()
    where id = parcela.conta_id;

    update banco_alegre_emprestimo_parcelas
    set status = 'Paga', data_pagamento = current_date
    where id = parcela.id;

    insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao, referencia_id)
    values (parcela.conta_id, 'Pagamento_Parcela', -parcela.valor_parcela,
            'Parcela ' || parcela.numero_parcela || ' debitada automaticamente', parcela.id);

    v_count := v_count + 1;
  end loop;

  update banco_alegre_emprestimos e
  set status = 'Quitado'
  where status = 'Ativo'
    and not exists (
      select 1 from banco_alegre_emprestimo_parcelas p
      where p.emprestimo_id = e.id and p.status = 'Pendente'
    );

  return v_count;
end;
$$;


--
-- Name: resgatar_aplicacao(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resgatar_aplicacao(p_aplicacao_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
declare
  v_aplicacao record;
  v_meses_completos int;
  v_taxa_mensal numeric;
  v_valor_bruto numeric;
  v_rendimento_bruto numeric;
  v_ir numeric;
  v_valor_liquido numeric;
begin
  select * into v_aplicacao from banco_alegre_aplicacoes where id = p_aplicacao_id;

  if v_aplicacao is null then
    raise exception 'Aplicação não encontrada';
  end if;

  if v_aplicacao.status = 'Resgatada' then
    raise exception 'Essa aplicação já foi resgatada';
  end if;

  -- Meses completos entre a aplicação e hoje (capitalização mensal)
  v_meses_completos := greatest(
    (extract(year from age(current_date, v_aplicacao.data_aplicacao)) * 12 +
     extract(month from age(current_date, v_aplicacao.data_aplicacao)))::int,
    0
  );

  v_taxa_mensal := v_aplicacao.taxa_juros_pct_am / 100;
  v_valor_bruto := round(v_aplicacao.valor_aplicado * power(1 + v_taxa_mensal, v_meses_completos), 2);
  v_rendimento_bruto := v_valor_bruto - v_aplicacao.valor_aplicado;

  if v_aplicacao.isento_ir then
    v_ir := 0;
  else
    v_ir := round(v_rendimento_bruto * v_aplicacao.aliquota_ir_pct / 100, 2);
  end if;

  v_valor_liquido := v_valor_bruto - v_ir;

  update banco_alegre_aplicacoes
  set
    status = 'Resgatada',
    valor_resgate = v_valor_liquido,
    valor_rendimento_bruto = v_rendimento_bruto,
    valor_ir_pago = v_ir,
    data_resgate = current_date
  where id = p_aplicacao_id;

  update banco_alegre_contas
  set saldo = saldo + v_valor_liquido, updated_at = now()
  where id = v_aplicacao.conta_id;

  insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao, referencia_id)
  values (
    v_aplicacao.conta_id, 'Resgate', v_valor_liquido,
    'Resgate de aplicação (rendimento bruto: R$ ' || v_rendimento_bruto || ', IR: R$ ' || v_ir || ')',
    p_aplicacao_id
  );
end;
$_$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: sync_atacarejo_customer_address(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_atacarejo_customer_address() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  new.address := nullif(trim(both ', ' from
    concat_ws(', ',
      nullif(trim(concat_ws(' ', new.street, new.street_number)), ''),
      nullif(new.complement, ''),
      nullif(new.neighborhood, ''),
      nullif(new.city, ''),
      nullif(new.state, ''),
      nullif(new.zip_code, '')
    )
  ), '');
  return new;
end;
$$;


--
-- Name: sync_customer_address(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_customer_address() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  new.address := nullif(trim(both ', ' from
    concat_ws(', ',
      nullif(trim(concat_ws(' ', new.street, new.street_number)), ''),
      nullif(new.complement, ''),
      nullif(new.neighborhood, ''),
      nullif(new.city, ''),
      nullif(new.state, ''),
      nullif(new.zip_code, '')
    )
  ), '');
  return new;
end;
$$;


--
-- Name: sync_order_status_with_delivery(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_order_status_with_delivery() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  if new.status = 'entregue' then
    update orders set status = 'entregue' where id = new.order_id;
    if new.data_entrega is null then
      update deliveries set data_entrega = current_date where id = new.id;
    end if;
  elsif new.status = 'problema' then
    update orders set status = 'pendente' where id = new.order_id;
  end if;
  return new;
end;
$$;


--
-- Name: transferir_banco_para_caixa(uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.transferir_banco_para_caixa(p_conta_id uuid, p_valor numeric, p_descricao text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_categoria_existe boolean;
begin
  if p_valor <= 0 then
    raise exception 'O valor da transferencia precisa ser maior que zero';
  end if;

  select exists(select 1 from chart_of_accounts where upper(name) = 'TRANSFERENCIA BANCARIA') into v_categoria_existe;
  if not v_categoria_existe then
    insert into chart_of_accounts (name, type, classification, active)
    values ('TRANSFERENCIA BANCARIA', 'receita', 'variavel', true);
  end if;

  update banco_alegre_contas set saldo = saldo - p_valor, updated_at = now() where id = p_conta_id;

  insert into financial_transactions (type, description, category, amount, due_date, payment_date, status, origin)
  values ('entrada', coalesce(p_descricao, 'Transferencia do Banco Alegre para o Caixa'),
          'TRANSFERENCIA BANCARIA', p_valor, current_date, current_date, 'baixado', 'transferencia_banco');

  insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
  values (p_conta_id, 'Transferencia_Para_Caixa', -p_valor, coalesce(p_descricao, 'Transferencia para o Caixa'));
end;
$$;


--
-- Name: transferir_caixa_para_banco(uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.transferir_caixa_para_banco(p_conta_id uuid, p_valor numeric, p_descricao text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_categoria_existe boolean;
begin
  if p_valor <= 0 then
    raise exception 'O valor da transferencia precisa ser maior que zero';
  end if;

  select exists(select 1 from chart_of_accounts where upper(name) = 'TRANSFERENCIA BANCARIA') into v_categoria_existe;
  if not v_categoria_existe then
    insert into chart_of_accounts (name, type, classification, active)
    values ('TRANSFERENCIA BANCARIA', 'despesa', 'variavel', true);
  end if;

  insert into financial_transactions (type, description, category, amount, due_date, payment_date, status, origin)
  values ('saida', coalesce(p_descricao, 'Transferencia do Caixa para o Banco Alegre'),
          'TRANSFERENCIA BANCARIA', p_valor, current_date, current_date, 'baixado', 'transferencia_banco');

  update banco_alegre_contas set saldo = saldo + p_valor, updated_at = now() where id = p_conta_id;

  insert into banco_alegre_transacoes (conta_id, tipo, valor, descricao)
  values (p_conta_id, 'Transferencia_Do_Caixa', p_valor, coalesce(p_descricao, 'Transferencia do Caixa'));
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: atacarejo_chart_of_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_chart_of_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    type text NOT NULL,
    classification text DEFAULT 'variavel'::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    CONSTRAINT atacarejo_chart_of_accounts_classification_check CHECK ((classification = ANY (ARRAY['fixo'::text, 'variavel'::text]))),
    CONSTRAINT atacarejo_chart_of_accounts_type_check CHECK ((type = ANY (ARRAY['receita'::text, 'despesa'::text])))
);


--
-- Name: atacarejo_coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_coupons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    discount_type text NOT NULL,
    discount_value numeric(10,2) NOT NULL,
    min_order_value numeric(10,2) DEFAULT 0,
    max_uses integer,
    used_count integer DEFAULT 0 NOT NULL,
    valid_until date,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_coupons_discount_type_check CHECK ((discount_type = ANY (ARRAY['percentage'::text, 'fixed'::text])))
);


--
-- Name: atacarejo_customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    source text,
    stage text DEFAULT 'lead'::text NOT NULL,
    street text,
    street_number text,
    complement text,
    neighborhood text,
    city text,
    state text,
    zip_code text,
    address text,
    reference_point text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_order_number_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.atacarejo_order_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: atacarejo_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_number integer DEFAULT nextval('public.atacarejo_order_number_seq'::regclass) NOT NULL,
    customer_id uuid,
    status text DEFAULT 'pendente'::text NOT NULL,
    payment_method text NOT NULL,
    delivery_payment_option text,
    shipping_cost numeric(10,2) DEFAULT 0 NOT NULL,
    subtotal numeric(12,2) DEFAULT 0 NOT NULL,
    total numeric(12,2) DEFAULT 0 NOT NULL,
    notes text,
    coupon_code text,
    discount_amount numeric(10,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tax_settled boolean DEFAULT false NOT NULL,
    tax_settlement_id uuid,
    delivery_payment_options text[]
);


--
-- Name: atacarejo_customer_profile_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.atacarejo_customer_profile_view AS
 SELECT c.id AS customer_id,
    count(o.id) AS total_pedidos,
    COALESCE(sum(o.total), (0)::numeric) AS total_gasto,
        CASE
            WHEN (count(o.id) > 0) THEN round((COALESCE(sum(o.total), (0)::numeric) / (count(o.id))::numeric), 2)
            ELSE (0)::numeric
        END AS ticket_medio,
    max(o.created_at) AS ultima_compra,
    min(o.created_at) AS primeira_compra
   FROM (public.atacarejo_customers c
     LEFT JOIN public.atacarejo_orders o ON ((o.customer_id = c.id)))
  GROUP BY c.id;


--
-- Name: atacarejo_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_deliveries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    status text DEFAULT 'aguardando_separacao'::text NOT NULL,
    carrier text,
    tracking_code text,
    estimated_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    data_entrega date
);


--
-- Name: atacarejo_delivery_payment_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_delivery_payment_options (
    id text NOT NULL,
    label text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_employees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    role text,
    department text,
    email text,
    phone text,
    admission_date date,
    status text DEFAULT 'ativo'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    system_role text DEFAULT 'Operador'::text,
    salario_tipo text DEFAULT 'fixo'::text NOT NULL,
    valor_salario numeric(12,2) DEFAULT 0 NOT NULL,
    pct_salario_faturamento numeric(6,3) DEFAULT 0 NOT NULL,
    acrescimos numeric(12,2) DEFAULT 0 NOT NULL,
    pct_ir numeric(6,3) DEFAULT 0 NOT NULL,
    banco_alegre_cliente_id uuid,
    CONSTRAINT atacarejo_employees_salario_tipo_check CHECK ((salario_tipo = ANY (ARRAY['fixo'::text, 'faturamento'::text])))
);


--
-- Name: atacarejo_financial_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_financial_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    type text NOT NULL,
    description text NOT NULL,
    category text,
    amount numeric(12,2) NOT NULL,
    due_date date NOT NULL,
    payment_date date,
    status text DEFAULT 'pendente'::text NOT NULL,
    origin text DEFAULT 'manual'::text,
    settlement_group_id uuid,
    order_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_financial_transactions_status_check CHECK ((status = ANY (ARRAY['pendente'::text, 'baixado'::text]))),
    CONSTRAINT atacarejo_financial_transactions_type_check CHECK ((type = ANY (ARRAY['entrada'::text, 'saida'::text])))
);


--
-- Name: atacarejo_interactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_interactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    type text NOT NULL,
    description text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_juridico_anexos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_juridico_anexos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    titulo text NOT NULL,
    categoria text DEFAULT 'Outro'::text NOT NULL,
    registro_relacionado text,
    descricao text,
    data_documento date,
    arquivo_url text NOT NULL,
    arquivo_nome text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_juridico_anexos_categoria_check CHECK ((categoria = ANY (ARRAY['Contratos'::text, 'Obrigações Fiscais'::text, 'LGPD'::text, 'Reclamações'::text, 'Documentos'::text, 'Outro'::text])))
);


--
-- Name: atacarejo_juridico_contratos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_juridico_contratos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo_contrato text NOT NULL,
    titulo text NOT NULL,
    parte_nome text NOT NULL,
    parte_documento text,
    data_inicio date NOT NULL,
    data_fim date,
    valor numeric(12,2),
    status text DEFAULT 'Vigente'::text NOT NULL,
    arquivo_url text,
    observacoes text,
    funcionario_id uuid,
    fornecedor_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_juridico_contratos_status_check CHECK ((status = ANY (ARRAY['Vigente'::text, 'Encerrado'::text, 'Renovação Pendente'::text, 'Cancelado'::text]))),
    CONSTRAINT atacarejo_juridico_contratos_tipo_contrato_check CHECK ((tipo_contrato = ANY (ARRAY['fornecedor'::text, 'cliente'::text, 'funcionario'::text, 'outro'::text])))
);


--
-- Name: atacarejo_juridico_documentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_juridico_documentos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    tipo text NOT NULL,
    numero_documento text,
    orgao_emissor text,
    data_emissao date,
    data_validade date,
    arquivo_url text,
    observacoes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_juridico_documentos_tipo_check CHECK ((tipo = ANY (ARRAY['Cadastro'::text, 'Licença'::text, 'Certidão'::text, 'Outro'::text])))
);


--
-- Name: atacarejo_juridico_lgpd_politica; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_juridico_lgpd_politica (
    id text DEFAULT 'atual'::text NOT NULL,
    texto text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_juridico_lgpd_solicitacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_juridico_lgpd_solicitacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_nome text NOT NULL,
    cliente_contato text NOT NULL,
    tipo_solicitacao text NOT NULL,
    data_solicitacao date DEFAULT CURRENT_DATE NOT NULL,
    prazo_resposta date DEFAULT (CURRENT_DATE + '15 days'::interval) NOT NULL,
    status text DEFAULT 'Recebida'::text NOT NULL,
    resposta text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_juridico_lgpd_solicitacoes_status_check CHECK ((status = ANY (ARRAY['Recebida'::text, 'Em Andamento'::text, 'Concluída'::text, 'Negada'::text]))),
    CONSTRAINT atacarejo_juridico_lgpd_solicitacoes_tipo_solicitacao_check CHECK ((tipo_solicitacao = ANY (ARRAY['Acesso aos Dados'::text, 'Correção'::text, 'Exclusão'::text, 'Portabilidade'::text, 'Revogação de Consentimento'::text])))
);


--
-- Name: atacarejo_juridico_obrigacoes_fiscais; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_juridico_obrigacoes_fiscais (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    tipo text NOT NULL,
    competencia text NOT NULL,
    vencimento date NOT NULL,
    valor_estimado numeric(12,2),
    status text DEFAULT 'Pendente'::text NOT NULL,
    contas_pagar_id uuid,
    observacoes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_juridico_obrigacoes_fiscais_status_check CHECK ((status = ANY (ARRAY['Pendente'::text, 'Pago'::text, 'Atrasado'::text]))),
    CONSTRAINT atacarejo_juridico_obrigacoes_fiscais_tipo_check CHECK ((tipo = ANY (ARRAY['Imposto'::text, 'Taxa'::text, 'Declaração'::text, 'Contribuição'::text])))
);


--
-- Name: atacarejo_juridico_reclamacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_juridico_reclamacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_nome text NOT NULL,
    cliente_contato text,
    canal text NOT NULL,
    numero_protocolo text,
    descricao text NOT NULL,
    data_reclamacao date DEFAULT CURRENT_DATE NOT NULL,
    prazo_resposta date,
    status text DEFAULT 'Aberta'::text NOT NULL,
    pedido_id uuid,
    sac_chamado_id uuid,
    resposta_empresa text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_juridico_reclamacoes_canal_check CHECK ((canal = ANY (ARRAY['Procon'::text, 'Reclame Aqui'::text, 'Judicial'::text, 'Outro'::text]))),
    CONSTRAINT atacarejo_juridico_reclamacoes_status_check CHECK ((status = ANY (ARRAY['Aberta'::text, 'Em Análise'::text, 'Respondida'::text, 'Resolvida'::text, 'Escalada'::text])))
);


--
-- Name: atacarejo_module_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_module_settings (
    id text NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_order_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    product_id uuid,
    product_name text NOT NULL,
    unit_price numeric(12,2) NOT NULL,
    quantity integer NOT NULL,
    CONSTRAINT atacarejo_order_items_quantity_check CHECK ((quantity > 0))
);


--
-- Name: atacarejo_order_tax_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.atacarejo_order_tax_view AS
SELECT
    NULL::uuid AS order_id,
    NULL::integer AS order_number,
    NULL::timestamp with time zone AS created_at,
    NULL::uuid AS customer_id,
    NULL::text AS payment_method,
    NULL::text AS delivery_payment_option,
    NULL::numeric(12,2) AS order_total,
    NULL::boolean AS tax_settled,
    NULL::uuid AS tax_settlement_id,
    NULL::numeric AS tax_amount,
    NULL::numeric AS valor_comissao;


--
-- Name: atacarejo_payment_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_payment_settings (
    id text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_payroll_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_payroll_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payroll_run_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    valor_bruto numeric(12,2) NOT NULL,
    valor_ir numeric(12,2) NOT NULL,
    valor_liquido numeric(12,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_payroll_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_payroll_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    mes text NOT NULL,
    financial_transaction_folha_id uuid,
    financial_transaction_ir_id uuid,
    total_folha numeric(14,2) DEFAULT 0 NOT NULL,
    total_ir numeric(14,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    description text,
    category text,
    brand text,
    active boolean DEFAULT true NOT NULL,
    image_url text,
    image_urls text[],
    cost_price numeric(12,2) DEFAULT 0,
    expense_commercialization_pct numeric(6,2) DEFAULT 0,
    expense_discount_pct numeric(6,2) DEFAULT 0,
    expense_marketing_pct numeric(6,2) DEFAULT 0,
    expense_fixed_pct numeric(6,2) DEFAULT 0,
    tax_pct numeric(6,2) DEFAULT 0,
    profit_pct numeric(6,2) DEFAULT 0,
    price numeric(12,2) DEFAULT 0,
    promotional_price numeric(12,2),
    discount_percent numeric(5,2),
    sku text,
    barcode text,
    stock integer DEFAULT 0 NOT NULL,
    weight_kg numeric(8,3),
    height_cm numeric(8,2),
    width_cm numeric(8,2),
    depth_cm numeric(8,2),
    product_type text DEFAULT 'produto'::text,
    fiscal_origin text DEFAULT 'nacional'::text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_purchase_invoice_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_purchase_invoice_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    purchase_invoice_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_cost numeric(12,2) NOT NULL,
    tax_pct numeric(6,2),
    subtotal numeric(12,2) GENERATED ALWAYS AS (((quantity)::numeric * unit_cost)) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_purchase_invoice_items_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT atacarejo_purchase_invoice_items_unit_cost_check CHECK ((unit_cost >= (0)::numeric))
);


--
-- Name: atacarejo_purchase_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_purchase_invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_id uuid,
    invoice_number text,
    issue_date date DEFAULT CURRENT_DATE NOT NULL,
    status text DEFAULT 'Rascunho'::text NOT NULL,
    total_value numeric(12,2) DEFAULT 0 NOT NULL,
    notes text,
    launched_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_purchase_invoices_status_check CHECK ((status = ANY (ARRAY['Rascunho'::text, 'Lançada'::text, 'Cancelada'::text])))
);


--
-- Name: atacarejo_shipping_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_shipping_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cep_start text NOT NULL,
    cep_end text NOT NULL,
    mode text NOT NULL,
    price numeric(10,2),
    min_purchase_value numeric(10,2),
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atacarejo_shipping_rules_mode_check CHECK ((mode = ANY (ARRAY['preco_fixo'::text, 'gratis_sempre'::text, 'gratis_a_partir_de'::text])))
);


--
-- Name: atacarejo_suppliers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    document text,
    phone text,
    email text,
    address text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_support_tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.atacarejo_support_tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_name text NOT NULL,
    customer_phone text,
    subject text NOT NULL,
    description text NOT NULL,
    priority text DEFAULT 'media'::text NOT NULL,
    status text DEFAULT 'aberto'::text NOT NULL,
    response text,
    order_id uuid,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: banco_alegre_aplicacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banco_alegre_aplicacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conta_id uuid NOT NULL,
    produto_id text NOT NULL,
    valor_aplicado numeric(14,2) NOT NULL,
    taxa_juros_pct_am numeric(6,3) NOT NULL,
    data_aplicacao date DEFAULT CURRENT_DATE NOT NULL,
    data_vencimento date,
    status text DEFAULT 'Ativa'::text NOT NULL,
    valor_resgate numeric(14,2),
    data_resgate date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    isento_ir boolean DEFAULT false NOT NULL,
    aliquota_ir_pct numeric(5,2) DEFAULT 0 NOT NULL,
    garantia_fgc boolean DEFAULT true NOT NULL,
    valor_rendimento_bruto numeric(14,2),
    valor_ir_pago numeric(14,2),
    CONSTRAINT banco_alegre_aplicacoes_status_check CHECK ((status = ANY (ARRAY['Ativa'::text, 'Resgatada'::text]))),
    CONSTRAINT banco_alegre_aplicacoes_valor_aplicado_check CHECK ((valor_aplicado > (0)::numeric))
);


--
-- Name: banco_alegre_clientes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banco_alegre_clientes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    documento text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tipo text DEFAULT 'PJ'::text NOT NULL,
    CONSTRAINT banco_alegre_clientes_tipo_check CHECK ((tipo = ANY (ARRAY['PJ'::text, 'PF'::text])))
);


--
-- Name: banco_alegre_contas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banco_alegre_contas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_id uuid NOT NULL,
    saldo numeric(14,2) DEFAULT 0 NOT NULL,
    cheque_especial_contratado boolean DEFAULT false NOT NULL,
    limite_cheque_especial numeric(14,2) DEFAULT 0 NOT NULL,
    taxa_cheque_especial_pct_am numeric(6,3),
    taxa_mora_excedente_pct_am numeric(6,3),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: banco_alegre_emprestimo_parcelas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banco_alegre_emprestimo_parcelas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    emprestimo_id uuid NOT NULL,
    numero_parcela integer NOT NULL,
    data_vencimento date NOT NULL,
    valor_parcela numeric(14,2) NOT NULL,
    valor_juros numeric(14,2) NOT NULL,
    valor_amortizacao numeric(14,2) NOT NULL,
    saldo_devedor_apos numeric(14,2) NOT NULL,
    status text DEFAULT 'Pendente'::text NOT NULL,
    data_pagamento date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT banco_alegre_emprestimo_parcelas_status_check CHECK ((status = ANY (ARRAY['Pendente'::text, 'Paga'::text])))
);


--
-- Name: banco_alegre_emprestimos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banco_alegre_emprestimos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conta_id uuid NOT NULL,
    valor_principal numeric(14,2) NOT NULL,
    taxa_juros_pct_am numeric(6,3) NOT NULL,
    num_parcelas integer NOT NULL,
    valor_parcela numeric(14,2) NOT NULL,
    data_contratacao date DEFAULT CURRENT_DATE NOT NULL,
    data_primeira_parcela date NOT NULL,
    status text DEFAULT 'Ativo'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT banco_alegre_emprestimos_num_parcelas_check CHECK ((num_parcelas > 0)),
    CONSTRAINT banco_alegre_emprestimos_status_check CHECK ((status = ANY (ARRAY['Ativo'::text, 'Quitado'::text]))),
    CONSTRAINT banco_alegre_emprestimos_valor_principal_check CHECK ((valor_principal > (0)::numeric))
);


--
-- Name: banco_alegre_managers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banco_alegre_managers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_user_id uuid,
    name text NOT NULL,
    email text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: banco_alegre_parametros_credito; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banco_alegre_parametros_credito (
    id text NOT NULL,
    nome text NOT NULL,
    taxa_juros_pct_am numeric(6,3) NOT NULL,
    taxa_mora_excedente_pct_am numeric(6,3),
    prazo_maximo_meses integer,
    ativo boolean DEFAULT true NOT NULL,
    descricao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: banco_alegre_produtos_captacao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banco_alegre_produtos_captacao (
    id text NOT NULL,
    nome text NOT NULL,
    taxa_juros_pct_am numeric(6,3) NOT NULL,
    prazo_minimo_meses integer DEFAULT 1 NOT NULL,
    liquidez_diaria boolean DEFAULT false NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    descricao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    valor_minimo_aplicacao numeric(14,2) DEFAULT 0 NOT NULL,
    isento_ir boolean DEFAULT false NOT NULL,
    aliquota_ir_pct numeric(5,2) DEFAULT 15.00 NOT NULL,
    garantia_fgc boolean DEFAULT true NOT NULL
);


--
-- Name: banco_alegre_transacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banco_alegre_transacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conta_id uuid NOT NULL,
    tipo text NOT NULL,
    valor numeric(14,2) NOT NULL,
    descricao text,
    referencia_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT banco_alegre_transacoes_tipo_check CHECK ((tipo = ANY (ARRAY['Emprestimo_Liberado'::text, 'Pagamento_Parcela'::text, 'Transferencia_Para_Caixa'::text, 'Transferencia_Do_Caixa'::text, 'Aplicacao'::text, 'Resgate'::text, 'Juros_Cheque_Especial'::text, 'Recebimento_Imposto'::text, 'Desembolso_Publico'::text, 'Pagamento_Folha'::text, 'Recebimento_Salario'::text, 'Recolhimento_IR_Folha'::text])))
);


--
-- Name: chart_of_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chart_of_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    type text DEFAULT 'despesa'::text NOT NULL,
    classification text DEFAULT 'variavel'::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coupons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    discount_type text DEFAULT 'percentage'::text NOT NULL,
    discount_value numeric(10,2) NOT NULL,
    min_order_value numeric(10,2) DEFAULT 0 NOT NULL,
    max_uses integer,
    used_count integer DEFAULT 0 NOT NULL,
    valid_until timestamp with time zone,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: juridico_lgpd_solicitacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.juridico_lgpd_solicitacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_nome text NOT NULL,
    cliente_contato text NOT NULL,
    tipo_solicitacao text NOT NULL,
    data_solicitacao date DEFAULT CURRENT_DATE NOT NULL,
    prazo_resposta date DEFAULT (CURRENT_DATE + '15 days'::interval) NOT NULL,
    status text DEFAULT 'Recebida'::text NOT NULL,
    resposta text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT juridico_lgpd_solicitacoes_status_check CHECK ((status = ANY (ARRAY['Recebida'::text, 'Em Andamento'::text, 'Concluída'::text, 'Negada'::text]))),
    CONSTRAINT juridico_lgpd_solicitacoes_tipo_solicitacao_check CHECK ((tipo_solicitacao = ANY (ARRAY['Acesso aos Dados'::text, 'Correção'::text, 'Exclusão'::text, 'Portabilidade'::text, 'Revogação de Consentimento'::text])))
);


--
-- Name: crm_lgpd_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.crm_lgpd_view AS
 SELECT cliente_nome,
    cliente_contato,
    tipo_solicitacao,
    status,
    prazo_resposta,
    ((prazo_resposta < CURRENT_DATE) AND (status <> 'Concluída'::text)) AS prazo_estourado
   FROM public.juridico_lgpd_solicitacoes
  WHERE (status <> 'Concluída'::text);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    address text,
    stage text DEFAULT 'lead'::text NOT NULL,
    source text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    reference_point text,
    street text,
    street_number text,
    complement text,
    neighborhood text,
    city text,
    state text,
    zip_code text
);


--
-- Name: order_number_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.order_number_seq
    START WITH 1000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid,
    status text DEFAULT 'pendente'::text NOT NULL,
    payment_method text DEFAULT 'cod'::text NOT NULL,
    shipping_cost numeric(10,2) DEFAULT 0 NOT NULL,
    subtotal numeric(10,2) DEFAULT 0 NOT NULL,
    total numeric(10,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    order_number integer DEFAULT nextval('public.order_number_seq'::regclass) NOT NULL,
    coupon_code text,
    discount_amount numeric(10,2) DEFAULT 0 NOT NULL,
    delivery_payment_option text,
    tax_settled boolean DEFAULT false NOT NULL,
    tax_settlement_id uuid,
    delivery_payment_options text[]
);


--
-- Name: customer_profile_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.customer_profile_view AS
 SELECT c.id AS customer_id,
    count(o.id) AS total_pedidos,
    COALESCE(sum(o.total), (0)::numeric) AS total_gasto,
        CASE
            WHEN (count(o.id) > 0) THEN round((COALESCE(sum(o.total), (0)::numeric) / (count(o.id))::numeric), 2)
            ELSE (0)::numeric
        END AS ticket_medio,
    max(o.created_at) AS ultima_compra,
    min(o.created_at) AS primeira_compra
   FROM (public.customers c
     LEFT JOIN public.orders o ON ((o.customer_id = c.id)))
  GROUP BY c.id;


--
-- Name: deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deliveries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    status text DEFAULT 'aguardando_separacao'::text NOT NULL,
    carrier text,
    tracking_code text,
    estimated_date date,
    delivered_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    data_entrega date
);


--
-- Name: delivery_payment_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_payment_options (
    id text NOT NULL,
    label text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    role text,
    department text,
    email text,
    phone text,
    admission_date date,
    status text DEFAULT 'ativo'::text NOT NULL,
    salary numeric(10,2),
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    salario_tipo text DEFAULT 'fixo'::text NOT NULL,
    valor_salario numeric(12,2) DEFAULT 0 NOT NULL,
    pct_salario_faturamento numeric(6,3) DEFAULT 0 NOT NULL,
    acrescimos numeric(12,2) DEFAULT 0 NOT NULL,
    pct_ir numeric(6,3) DEFAULT 0 NOT NULL,
    banco_alegre_cliente_id uuid,
    CONSTRAINT employees_salario_tipo_check CHECK ((salario_tipo = ANY (ARRAY['fixo'::text, 'faturamento'::text])))
);


--
-- Name: expense_category_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expense_category_types (
    category text NOT NULL,
    cost_type text DEFAULT 'variavel'::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: financial_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.financial_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    type text NOT NULL,
    description text NOT NULL,
    category text,
    amount numeric(10,2) NOT NULL,
    due_date date NOT NULL,
    payment_date date,
    status text DEFAULT 'pendente'::text NOT NULL,
    order_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    origin text DEFAULT 'manual'::text,
    settlement_group_id uuid
);


--
-- Name: governo_desembolsos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governo_desembolsos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pasta_id uuid NOT NULL,
    data date DEFAULT CURRENT_DATE NOT NULL,
    descricao text NOT NULL,
    valor numeric(14,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT governo_desembolsos_valor_check CHECK ((valor > (0)::numeric))
);


--
-- Name: governo_extrato; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governo_extrato (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa text NOT NULL,
    tipo text NOT NULL,
    valor numeric(14,2) NOT NULL,
    descricao text,
    referencia_transacao_id uuid,
    data date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: governo_managers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governo_managers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_user_id uuid,
    name text NOT NULL,
    email text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: governo_pastas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governo_pastas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    orcamento numeric(14,2) DEFAULT 0 NOT NULL,
    ativa boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: governo_pastas_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.governo_pastas_view AS
SELECT
    NULL::uuid AS id,
    NULL::text AS nome,
    NULL::numeric(14,2) AS orcamento,
    NULL::boolean AS ativa,
    NULL::numeric AS realizado,
    NULL::numeric AS a_realizar;


--
-- Name: interactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.interactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid,
    type text DEFAULT 'outro'::text NOT NULL,
    description text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: juridico_anexos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.juridico_anexos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    titulo text NOT NULL,
    categoria text DEFAULT 'Outro'::text NOT NULL,
    registro_relacionado text,
    descricao text,
    data_documento date,
    arquivo_url text NOT NULL,
    arquivo_nome text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT juridico_anexos_categoria_check CHECK ((categoria = ANY (ARRAY['Contratos'::text, 'Obrigações Fiscais'::text, 'LGPD'::text, 'Reclamações'::text, 'Documentos'::text, 'Outro'::text])))
);


--
-- Name: juridico_contratos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.juridico_contratos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo_contrato text NOT NULL,
    titulo text NOT NULL,
    parte_nome text NOT NULL,
    parte_documento text,
    data_inicio date NOT NULL,
    data_fim date,
    valor numeric(12,2),
    status text DEFAULT 'Vigente'::text NOT NULL,
    arquivo_url text,
    observacoes text,
    funcionario_id uuid,
    fornecedor_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT juridico_contratos_status_check CHECK ((status = ANY (ARRAY['Vigente'::text, 'Encerrado'::text, 'Renovação Pendente'::text, 'Cancelado'::text]))),
    CONSTRAINT juridico_contratos_tipo_contrato_check CHECK ((tipo_contrato = ANY (ARRAY['fornecedor'::text, 'cliente'::text, 'funcionario'::text, 'outro'::text])))
);


--
-- Name: juridico_documentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.juridico_documentos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    tipo text NOT NULL,
    numero_documento text,
    orgao_emissor text,
    data_emissao date,
    data_validade date,
    arquivo_url text,
    observacoes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT juridico_documentos_tipo_check CHECK ((tipo = ANY (ARRAY['Cadastro'::text, 'Licença'::text, 'Certidão'::text, 'Outro'::text])))
);


--
-- Name: juridico_lgpd_politica; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.juridico_lgpd_politica (
    id text DEFAULT 'atual'::text NOT NULL,
    texto text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: juridico_obrigacoes_fiscais; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.juridico_obrigacoes_fiscais (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    tipo text NOT NULL,
    competencia text NOT NULL,
    vencimento date NOT NULL,
    valor_estimado numeric(12,2),
    status text DEFAULT 'Pendente'::text NOT NULL,
    contas_pagar_id uuid,
    observacoes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT juridico_obrigacoes_fiscais_status_check CHECK ((status = ANY (ARRAY['Pendente'::text, 'Pago'::text, 'Atrasado'::text]))),
    CONSTRAINT juridico_obrigacoes_fiscais_tipo_check CHECK ((tipo = ANY (ARRAY['Imposto'::text, 'Taxa'::text, 'Declaração'::text, 'Contribuição'::text])))
);


--
-- Name: juridico_reclamacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.juridico_reclamacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_nome text NOT NULL,
    cliente_contato text,
    canal text NOT NULL,
    numero_protocolo text,
    descricao text NOT NULL,
    data_reclamacao date DEFAULT CURRENT_DATE NOT NULL,
    prazo_resposta date,
    status text DEFAULT 'Aberta'::text NOT NULL,
    pedido_id uuid,
    sac_chamado_id uuid,
    resposta_empresa text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT juridico_reclamacoes_canal_check CHECK ((canal = ANY (ARRAY['Procon'::text, 'Reclame Aqui'::text, 'Judicial'::text, 'Outro'::text]))),
    CONSTRAINT juridico_reclamacoes_status_check CHECK ((status = ANY (ARRAY['Aberta'::text, 'Em Análise'::text, 'Respondida'::text, 'Resolvida'::text, 'Escalada'::text])))
);


--
-- Name: module_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.module_settings (
    id text NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid,
    product_id uuid,
    product_name text NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    quantity integer DEFAULT 1 NOT NULL
);


--
-- Name: order_tax_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.order_tax_view AS
SELECT
    NULL::uuid AS order_id,
    NULL::integer AS order_number,
    NULL::timestamp with time zone AS created_at,
    NULL::uuid AS customer_id,
    NULL::text AS payment_method,
    NULL::text AS delivery_payment_option,
    NULL::numeric(10,2) AS order_total,
    NULL::boolean AS tax_settled,
    NULL::uuid AS tax_settlement_id,
    NULL::numeric AS tax_amount,
    NULL::numeric AS valor_comissao;


--
-- Name: painel_documentos_vencendo_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.painel_documentos_vencendo_view AS
 SELECT nome,
    tipo,
    data_validade,
    (data_validade - CURRENT_DATE) AS dias_restantes
   FROM public.juridico_documentos
  WHERE ((data_validade IS NOT NULL) AND (data_validade <= (CURRENT_DATE + '30 days'::interval)))
  ORDER BY data_validade;


--
-- Name: payment_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_settings (
    id text NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payroll_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payroll_run_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    valor_bruto numeric(12,2) NOT NULL,
    valor_ir numeric(12,2) NOT NULL,
    valor_liquido numeric(12,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payroll_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    mes text NOT NULL,
    financial_transaction_folha_id uuid,
    financial_transaction_ir_id uuid,
    total_folha numeric(14,2) DEFAULT 0 NOT NULL,
    total_ir numeric(14,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    description text,
    price numeric(10,2) DEFAULT 0 NOT NULL,
    category text,
    image_url text,
    stock integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    cost_price numeric(10,2) DEFAULT 0,
    promotional_price numeric(10,2),
    sku text,
    barcode text,
    weight_kg numeric(8,3),
    height_cm numeric(8,2),
    width_cm numeric(8,2),
    depth_cm numeric(8,2),
    product_type text DEFAULT 'produto'::text,
    fiscal_origin text DEFAULT 'nacional'::text,
    brand text,
    discount_percent numeric(5,2),
    image_urls text[] DEFAULT '{}'::text[],
    expense_commercialization_pct numeric(5,2) DEFAULT 0,
    expense_discount_pct numeric(5,2) DEFAULT 0,
    expense_marketing_pct numeric(5,2) DEFAULT 0,
    expense_fixed_pct numeric(5,2) DEFAULT 0,
    tax_pct numeric(5,2) DEFAULT 0,
    profit_pct numeric(5,2) DEFAULT 0
);


--
-- Name: purchase_invoice_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_invoice_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    purchase_invoice_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_cost numeric(12,2) NOT NULL,
    tax_pct numeric(6,2),
    subtotal numeric(12,2) GENERATED ALWAYS AS (((quantity)::numeric * unit_cost)) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT purchase_invoice_items_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT purchase_invoice_items_unit_cost_check CHECK ((unit_cost >= (0)::numeric))
);


--
-- Name: purchase_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_id uuid,
    invoice_number text,
    issue_date date DEFAULT CURRENT_DATE NOT NULL,
    status text DEFAULT 'Rascunho'::text NOT NULL,
    total_value numeric(12,2) DEFAULT 0 NOT NULL,
    notes text,
    launched_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT purchase_invoices_status_check CHECK ((status = ANY (ARRAY['Rascunho'::text, 'Lançada'::text, 'Cancelada'::text])))
);


--
-- Name: rh_contratos_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.rh_contratos_view AS
 SELECT e.id AS funcionario_id,
    e.name AS funcionario_nome,
    e.department AS departamento,
    c.id AS contrato_id,
    c.status AS status_contrato,
    c.data_inicio,
    c.data_fim,
        CASE
            WHEN ((c.data_fim IS NOT NULL) AND (c.data_fim <= (CURRENT_DATE + '30 days'::interval))) THEN true
            ELSE false
        END AS vencendo_em_30_dias
   FROM (public.employees e
     LEFT JOIN public.juridico_contratos c ON (((c.funcionario_id = e.id) AND (c.tipo_contrato = 'funcionario'::text))));


--
-- Name: support_tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.support_tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid,
    customer_name text NOT NULL,
    customer_phone text,
    order_id uuid,
    subject text NOT NULL,
    description text NOT NULL,
    priority text DEFAULT 'media'::text NOT NULL,
    status text DEFAULT 'aberto'::text NOT NULL,
    response text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone
);


--
-- Name: sac_reclamacoes_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.sac_reclamacoes_view AS
 SELECT st.id AS chamado_id,
    st.subject AS chamado_assunto,
    st.status AS chamado_status,
    r.id AS reclamacao_id,
    r.canal,
    r.status AS status_reclamacao,
    r.prazo_resposta,
    r.data_reclamacao
   FROM (public.support_tickets st
     JOIN public.juridico_reclamacoes r ON ((r.sac_chamado_id = st.id)));


--
-- Name: shipping_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shipping_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cep_start text NOT NULL,
    cep_end text NOT NULL,
    mode text NOT NULL,
    price numeric(10,2),
    min_purchase_value numeric(10,2),
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shipping_rules_mode_check CHECK ((mode = ANY (ARRAY['preco_fixo'::text, 'gratis_sempre'::text, 'gratis_a_partir_de'::text])))
);


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    document text,
    phone text,
    email text,
    address text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: system_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_users (
    id uuid NOT NULL,
    email text,
    name text,
    role text DEFAULT 'operador'::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: atacarejo_chart_of_accounts atacarejo_chart_of_accounts_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_chart_of_accounts
    ADD CONSTRAINT atacarejo_chart_of_accounts_name_key UNIQUE (name);


--
-- Name: atacarejo_chart_of_accounts atacarejo_chart_of_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_chart_of_accounts
    ADD CONSTRAINT atacarejo_chart_of_accounts_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_coupons atacarejo_coupons_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_coupons
    ADD CONSTRAINT atacarejo_coupons_code_key UNIQUE (code);


--
-- Name: atacarejo_coupons atacarejo_coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_coupons
    ADD CONSTRAINT atacarejo_coupons_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_customers atacarejo_customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_customers
    ADD CONSTRAINT atacarejo_customers_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_deliveries atacarejo_deliveries_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_deliveries
    ADD CONSTRAINT atacarejo_deliveries_order_id_key UNIQUE (order_id);


--
-- Name: atacarejo_deliveries atacarejo_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_deliveries
    ADD CONSTRAINT atacarejo_deliveries_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_delivery_payment_options atacarejo_delivery_payment_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_delivery_payment_options
    ADD CONSTRAINT atacarejo_delivery_payment_options_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_employees atacarejo_employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_employees
    ADD CONSTRAINT atacarejo_employees_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_financial_transactions atacarejo_financial_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_financial_transactions
    ADD CONSTRAINT atacarejo_financial_transactions_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_interactions atacarejo_interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_interactions
    ADD CONSTRAINT atacarejo_interactions_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_juridico_anexos atacarejo_juridico_anexos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_anexos
    ADD CONSTRAINT atacarejo_juridico_anexos_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_juridico_contratos atacarejo_juridico_contratos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_contratos
    ADD CONSTRAINT atacarejo_juridico_contratos_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_juridico_documentos atacarejo_juridico_documentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_documentos
    ADD CONSTRAINT atacarejo_juridico_documentos_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_juridico_lgpd_politica atacarejo_juridico_lgpd_politica_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_lgpd_politica
    ADD CONSTRAINT atacarejo_juridico_lgpd_politica_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_juridico_lgpd_solicitacoes atacarejo_juridico_lgpd_solicitacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_lgpd_solicitacoes
    ADD CONSTRAINT atacarejo_juridico_lgpd_solicitacoes_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_juridico_obrigacoes_fiscais atacarejo_juridico_obrigacoes_fiscais_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_obrigacoes_fiscais
    ADD CONSTRAINT atacarejo_juridico_obrigacoes_fiscais_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_juridico_reclamacoes atacarejo_juridico_reclamacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_reclamacoes
    ADD CONSTRAINT atacarejo_juridico_reclamacoes_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_module_settings atacarejo_module_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_module_settings
    ADD CONSTRAINT atacarejo_module_settings_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_order_items atacarejo_order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_order_items
    ADD CONSTRAINT atacarejo_order_items_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_orders atacarejo_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_orders
    ADD CONSTRAINT atacarejo_orders_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_payment_settings atacarejo_payment_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_payment_settings
    ADD CONSTRAINT atacarejo_payment_settings_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_payroll_items atacarejo_payroll_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_payroll_items
    ADD CONSTRAINT atacarejo_payroll_items_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_payroll_runs atacarejo_payroll_runs_mes_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_payroll_runs
    ADD CONSTRAINT atacarejo_payroll_runs_mes_key UNIQUE (mes);


--
-- Name: atacarejo_payroll_runs atacarejo_payroll_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_payroll_runs
    ADD CONSTRAINT atacarejo_payroll_runs_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_products atacarejo_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_products
    ADD CONSTRAINT atacarejo_products_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_purchase_invoice_items atacarejo_purchase_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_purchase_invoice_items
    ADD CONSTRAINT atacarejo_purchase_invoice_items_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_purchase_invoices atacarejo_purchase_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_purchase_invoices
    ADD CONSTRAINT atacarejo_purchase_invoices_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_shipping_rules atacarejo_shipping_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_shipping_rules
    ADD CONSTRAINT atacarejo_shipping_rules_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_suppliers atacarejo_suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_suppliers
    ADD CONSTRAINT atacarejo_suppliers_pkey PRIMARY KEY (id);


--
-- Name: atacarejo_support_tickets atacarejo_support_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_support_tickets
    ADD CONSTRAINT atacarejo_support_tickets_pkey PRIMARY KEY (id);


--
-- Name: banco_alegre_aplicacoes banco_alegre_aplicacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_aplicacoes
    ADD CONSTRAINT banco_alegre_aplicacoes_pkey PRIMARY KEY (id);


--
-- Name: banco_alegre_clientes banco_alegre_clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_clientes
    ADD CONSTRAINT banco_alegre_clientes_pkey PRIMARY KEY (id);


--
-- Name: banco_alegre_contas banco_alegre_contas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_contas
    ADD CONSTRAINT banco_alegre_contas_pkey PRIMARY KEY (id);


--
-- Name: banco_alegre_emprestimo_parcelas banco_alegre_emprestimo_parcelas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_emprestimo_parcelas
    ADD CONSTRAINT banco_alegre_emprestimo_parcelas_pkey PRIMARY KEY (id);


--
-- Name: banco_alegre_emprestimos banco_alegre_emprestimos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_emprestimos
    ADD CONSTRAINT banco_alegre_emprestimos_pkey PRIMARY KEY (id);


--
-- Name: banco_alegre_managers banco_alegre_managers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_managers
    ADD CONSTRAINT banco_alegre_managers_pkey PRIMARY KEY (id);


--
-- Name: banco_alegre_parametros_credito banco_alegre_parametros_credito_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_parametros_credito
    ADD CONSTRAINT banco_alegre_parametros_credito_pkey PRIMARY KEY (id);


--
-- Name: banco_alegre_produtos_captacao banco_alegre_produtos_captacao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_produtos_captacao
    ADD CONSTRAINT banco_alegre_produtos_captacao_pkey PRIMARY KEY (id);


--
-- Name: banco_alegre_transacoes banco_alegre_transacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_transacoes
    ADD CONSTRAINT banco_alegre_transacoes_pkey PRIMARY KEY (id);


--
-- Name: chart_of_accounts chart_of_accounts_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_of_accounts
    ADD CONSTRAINT chart_of_accounts_name_key UNIQUE (name);


--
-- Name: chart_of_accounts chart_of_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_of_accounts
    ADD CONSTRAINT chart_of_accounts_pkey PRIMARY KEY (id);


--
-- Name: coupons coupons_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_code_key UNIQUE (code);


--
-- Name: coupons coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: deliveries deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliveries
    ADD CONSTRAINT deliveries_pkey PRIMARY KEY (id);


--
-- Name: delivery_payment_options delivery_payment_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_payment_options
    ADD CONSTRAINT delivery_payment_options_pkey PRIMARY KEY (id);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- Name: expense_category_types expense_category_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_category_types
    ADD CONSTRAINT expense_category_types_pkey PRIMARY KEY (category);


--
-- Name: financial_transactions financial_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_transactions
    ADD CONSTRAINT financial_transactions_pkey PRIMARY KEY (id);


--
-- Name: governo_desembolsos governo_desembolsos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governo_desembolsos
    ADD CONSTRAINT governo_desembolsos_pkey PRIMARY KEY (id);


--
-- Name: governo_extrato governo_extrato_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governo_extrato
    ADD CONSTRAINT governo_extrato_pkey PRIMARY KEY (id);


--
-- Name: governo_managers governo_managers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governo_managers
    ADD CONSTRAINT governo_managers_pkey PRIMARY KEY (id);


--
-- Name: governo_pastas governo_pastas_nome_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governo_pastas
    ADD CONSTRAINT governo_pastas_nome_key UNIQUE (nome);


--
-- Name: governo_pastas governo_pastas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governo_pastas
    ADD CONSTRAINT governo_pastas_pkey PRIMARY KEY (id);


--
-- Name: interactions interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactions
    ADD CONSTRAINT interactions_pkey PRIMARY KEY (id);


--
-- Name: juridico_anexos juridico_anexos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.juridico_anexos
    ADD CONSTRAINT juridico_anexos_pkey PRIMARY KEY (id);


--
-- Name: juridico_contratos juridico_contratos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.juridico_contratos
    ADD CONSTRAINT juridico_contratos_pkey PRIMARY KEY (id);


--
-- Name: juridico_documentos juridico_documentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.juridico_documentos
    ADD CONSTRAINT juridico_documentos_pkey PRIMARY KEY (id);


--
-- Name: juridico_lgpd_politica juridico_lgpd_politica_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.juridico_lgpd_politica
    ADD CONSTRAINT juridico_lgpd_politica_pkey PRIMARY KEY (id);


--
-- Name: juridico_lgpd_solicitacoes juridico_lgpd_solicitacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.juridico_lgpd_solicitacoes
    ADD CONSTRAINT juridico_lgpd_solicitacoes_pkey PRIMARY KEY (id);


--
-- Name: juridico_obrigacoes_fiscais juridico_obrigacoes_fiscais_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.juridico_obrigacoes_fiscais
    ADD CONSTRAINT juridico_obrigacoes_fiscais_pkey PRIMARY KEY (id);


--
-- Name: juridico_reclamacoes juridico_reclamacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.juridico_reclamacoes
    ADD CONSTRAINT juridico_reclamacoes_pkey PRIMARY KEY (id);


--
-- Name: module_settings module_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.module_settings
    ADD CONSTRAINT module_settings_pkey PRIMARY KEY (id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: payment_settings payment_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_settings
    ADD CONSTRAINT payment_settings_pkey PRIMARY KEY (id);


--
-- Name: payroll_items payroll_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT payroll_items_pkey PRIMARY KEY (id);


--
-- Name: payroll_runs payroll_runs_mes_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_mes_key UNIQUE (mes);


--
-- Name: payroll_runs payroll_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: purchase_invoice_items purchase_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_pkey PRIMARY KEY (id);


--
-- Name: purchase_invoices purchase_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_invoices
    ADD CONSTRAINT purchase_invoices_pkey PRIMARY KEY (id);


--
-- Name: shipping_rules shipping_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipping_rules
    ADD CONSTRAINT shipping_rules_pkey PRIMARY KEY (id);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: support_tickets support_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_pkey PRIMARY KEY (id);


--
-- Name: system_users system_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_users
    ADD CONSTRAINT system_users_pkey PRIMARY KEY (id);


--
-- Name: idx_atacarejo_juridico_anexos_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_atacarejo_juridico_anexos_categoria ON public.atacarejo_juridico_anexos USING btree (categoria);


--
-- Name: idx_deliveries_order; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_deliveries_order ON public.deliveries USING btree (order_id);


--
-- Name: idx_deliveries_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deliveries_status ON public.deliveries USING btree (status);


--
-- Name: idx_financial_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_financial_category ON public.financial_transactions USING btree (category);


--
-- Name: idx_financial_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_financial_due_date ON public.financial_transactions USING btree (due_date);


--
-- Name: idx_financial_payment_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_financial_payment_date ON public.financial_transactions USING btree (payment_date);


--
-- Name: idx_financial_settlement_group; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_financial_settlement_group ON public.financial_transactions USING btree (settlement_group_id);


--
-- Name: idx_financial_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_financial_status ON public.financial_transactions USING btree (status);


--
-- Name: idx_governo_desembolsos_pasta; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_governo_desembolsos_pasta ON public.governo_desembolsos USING btree (pasta_id);


--
-- Name: idx_governo_extrato_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_governo_extrato_data ON public.governo_extrato USING btree (data);


--
-- Name: idx_governo_extrato_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_governo_extrato_empresa ON public.governo_extrato USING btree (empresa);


--
-- Name: idx_interactions_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interactions_customer ON public.interactions USING btree (customer_id);


--
-- Name: idx_juridico_anexos_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_anexos_categoria ON public.juridico_anexos USING btree (categoria);


--
-- Name: idx_juridico_contratos_data_fim; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_contratos_data_fim ON public.juridico_contratos USING btree (data_fim);


--
-- Name: idx_juridico_contratos_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_contratos_status ON public.juridico_contratos USING btree (status);


--
-- Name: idx_juridico_contratos_tipo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_contratos_tipo ON public.juridico_contratos USING btree (tipo_contrato);


--
-- Name: idx_juridico_documentos_validade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_documentos_validade ON public.juridico_documentos USING btree (data_validade);


--
-- Name: idx_juridico_lgpd_prazo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_lgpd_prazo ON public.juridico_lgpd_solicitacoes USING btree (prazo_resposta);


--
-- Name: idx_juridico_lgpd_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_lgpd_status ON public.juridico_lgpd_solicitacoes USING btree (status);


--
-- Name: idx_juridico_obrigacoes_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_obrigacoes_status ON public.juridico_obrigacoes_fiscais USING btree (status);


--
-- Name: idx_juridico_obrigacoes_vencimento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_obrigacoes_vencimento ON public.juridico_obrigacoes_fiscais USING btree (vencimento);


--
-- Name: idx_juridico_reclamacoes_canal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_reclamacoes_canal ON public.juridico_reclamacoes USING btree (canal);


--
-- Name: idx_juridico_reclamacoes_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_juridico_reclamacoes_status ON public.juridico_reclamacoes USING btree (status);


--
-- Name: idx_orders_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_created_at ON public.orders USING btree (created_at);


--
-- Name: idx_orders_order_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_orders_order_number ON public.orders USING btree (order_number);


--
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_status ON public.orders USING btree (status);


--
-- Name: idx_parcelas_vencimento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_parcelas_vencimento ON public.banco_alegre_emprestimo_parcelas USING btree (data_vencimento, status);


--
-- Name: idx_purchase_invoices_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_purchase_invoices_status ON public.purchase_invoices USING btree (status);


--
-- Name: idx_purchase_items_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_purchase_items_invoice ON public.purchase_invoice_items USING btree (purchase_invoice_id);


--
-- Name: idx_shipping_rules_cep; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipping_rules_cep ON public.shipping_rules USING btree (cep_start, cep_end);


--
-- Name: idx_tickets_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tickets_status ON public.support_tickets USING btree (status);


--
-- Name: idx_transacoes_conta; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transacoes_conta ON public.banco_alegre_transacoes USING btree (conta_id, created_at);


--
-- Name: atacarejo_order_tax_view _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.atacarejo_order_tax_view AS
 SELECT o.id AS order_id,
    o.order_number,
    o.created_at,
    o.customer_id,
    o.payment_method,
    o.delivery_payment_option,
    o.total AS order_total,
    o.tax_settled,
    o.tax_settlement_id,
    COALESCE(sum(
        CASE
            WHEN ( SELECT COALESCE(atacarejo_module_settings.enabled, false) AS "coalesce"
               FROM public.atacarejo_module_settings
              WHERE (atacarejo_module_settings.id = 'modo_comissao'::text)) THEN ((GREATEST(((oi.unit_price * (oi.quantity)::numeric) - ((oi.quantity)::numeric * COALESCE(p.cost_price, (0)::numeric))), (0)::numeric) * COALESCE(p.tax_pct, (0)::numeric)) / (100)::numeric)
            ELSE (((oi.unit_price * (oi.quantity)::numeric) * COALESCE(p.tax_pct, (0)::numeric)) / (100)::numeric)
        END), (0)::numeric) AS tax_amount,
    (o.total - COALESCE(sum(((oi.quantity)::numeric * p.cost_price)), (0)::numeric)) AS valor_comissao
   FROM (((public.atacarejo_orders o
     JOIN public.atacarejo_deliveries d ON (((d.order_id = o.id) AND (d.status = 'entregue'::text))))
     LEFT JOIN public.atacarejo_order_items oi ON ((oi.order_id = o.id)))
     LEFT JOIN public.atacarejo_products p ON ((p.id = oi.product_id)))
  GROUP BY o.id;


--
-- Name: governo_pastas_view _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.governo_pastas_view AS
 SELECT p.id,
    p.nome,
    p.orcamento,
    p.ativa,
    COALESCE(sum(d.valor), (0)::numeric) AS realizado,
    (p.orcamento - COALESCE(sum(d.valor), (0)::numeric)) AS a_realizar
   FROM (public.governo_pastas p
     LEFT JOIN public.governo_desembolsos d ON ((d.pasta_id = p.id)))
  GROUP BY p.id;


--
-- Name: order_tax_view _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.order_tax_view AS
 SELECT o.id AS order_id,
    o.order_number,
    o.created_at,
    o.customer_id,
    o.payment_method,
    o.delivery_payment_option,
    o.total AS order_total,
    o.tax_settled,
    o.tax_settlement_id,
    COALESCE(sum(
        CASE
            WHEN ( SELECT COALESCE(module_settings.enabled, false) AS "coalesce"
               FROM public.module_settings
              WHERE (module_settings.id = 'modo_comissao'::text)) THEN ((GREATEST(((oi.unit_price * (oi.quantity)::numeric) - ((oi.quantity)::numeric * COALESCE(p.cost_price, (0)::numeric))), (0)::numeric) * COALESCE(p.tax_pct, (0)::numeric)) / (100)::numeric)
            ELSE (((oi.unit_price * (oi.quantity)::numeric) * COALESCE(p.tax_pct, (0)::numeric)) / (100)::numeric)
        END), (0)::numeric) AS tax_amount,
    (o.total - COALESCE(sum(((oi.quantity)::numeric * p.cost_price)), (0)::numeric)) AS valor_comissao
   FROM (((public.orders o
     JOIN public.deliveries d ON (((d.order_id = o.id) AND (d.status = 'entregue'::text))))
     LEFT JOIN public.order_items oi ON ((oi.order_id = o.id)))
     LEFT JOIN public.products p ON ((p.id = oi.product_id)))
  GROUP BY o.id;


--
-- Name: atacarejo_orders trg_atacarejo_create_delivery; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_atacarejo_create_delivery AFTER INSERT ON public.atacarejo_orders FOR EACH ROW EXECUTE FUNCTION public.atacarejo_create_delivery_record();


--
-- Name: atacarejo_financial_transactions trg_atacarejo_credit_governo_on_tax_payment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_atacarejo_credit_governo_on_tax_payment AFTER UPDATE OF status ON public.atacarejo_financial_transactions FOR EACH ROW EXECUTE FUNCTION public.atacarejo_credit_governo_on_tax_payment();


--
-- Name: atacarejo_deliveries trg_atacarejo_generate_receivable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_atacarejo_generate_receivable AFTER UPDATE OF status ON public.atacarejo_deliveries FOR EACH ROW EXECUTE FUNCTION public.atacarejo_generate_receivable_on_delivery();


--
-- Name: atacarejo_juridico_obrigacoes_fiscais trg_atacarejo_juridico_conta_a_pagar; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_atacarejo_juridico_conta_a_pagar AFTER INSERT ON public.atacarejo_juridico_obrigacoes_fiscais FOR EACH ROW EXECUTE FUNCTION public.atacarejo_juridico_gerar_conta_a_pagar();


--
-- Name: atacarejo_financial_transactions trg_atacarejo_processar_baixa_folha_ir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_atacarejo_processar_baixa_folha_ir AFTER UPDATE OF status ON public.atacarejo_financial_transactions FOR EACH ROW EXECUTE FUNCTION public.atacarejo_processar_baixa_folha_ir();


--
-- Name: atacarejo_deliveries trg_atacarejo_sync_order_status; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_atacarejo_sync_order_status AFTER UPDATE OF status ON public.atacarejo_deliveries FOR EACH ROW EXECUTE FUNCTION public.atacarejo_sync_order_status_with_delivery();


--
-- Name: orders trg_create_delivery; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_create_delivery AFTER INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.create_delivery_record();


--
-- Name: financial_transactions trg_credit_governo_on_tax_payment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_credit_governo_on_tax_payment AFTER UPDATE OF status ON public.financial_transactions FOR EACH ROW EXECUTE FUNCTION public.credit_governo_on_tax_payment();


--
-- Name: deliveries trg_generate_receivable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_generate_receivable AFTER UPDATE ON public.deliveries FOR EACH ROW EXECUTE FUNCTION public.generate_receivable_on_delivery();


--
-- Name: juridico_obrigacoes_fiscais trg_juridico_gerar_conta_a_pagar; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_juridico_gerar_conta_a_pagar AFTER INSERT ON public.juridico_obrigacoes_fiscais FOR EACH ROW EXECUTE FUNCTION public.juridico_gerar_conta_a_pagar();


--
-- Name: financial_transactions trg_processar_baixa_folha_ir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_processar_baixa_folha_ir AFTER UPDATE OF status ON public.financial_transactions FOR EACH ROW EXECUTE FUNCTION public.processar_baixa_folha_ir();


--
-- Name: atacarejo_customers trg_sync_atacarejo_customer_address; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_atacarejo_customer_address BEFORE INSERT OR UPDATE OF street, street_number, complement, neighborhood, city, state, zip_code ON public.atacarejo_customers FOR EACH ROW EXECUTE FUNCTION public.sync_atacarejo_customer_address();


--
-- Name: customers trg_sync_customer_address; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_customer_address BEFORE INSERT OR UPDATE OF street, street_number, complement, neighborhood, city, state, zip_code ON public.customers FOR EACH ROW EXECUTE FUNCTION public.sync_customer_address();


--
-- Name: deliveries trg_sync_order_status; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_order_status AFTER UPDATE OF status ON public.deliveries FOR EACH ROW EXECUTE FUNCTION public.sync_order_status_with_delivery();


--
-- Name: atacarejo_deliveries atacarejo_deliveries_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_deliveries
    ADD CONSTRAINT atacarejo_deliveries_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.atacarejo_orders(id) ON DELETE CASCADE;


--
-- Name: atacarejo_employees atacarejo_employees_banco_alegre_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_employees
    ADD CONSTRAINT atacarejo_employees_banco_alegre_cliente_id_fkey FOREIGN KEY (banco_alegre_cliente_id) REFERENCES public.banco_alegre_clientes(id) ON DELETE SET NULL;


--
-- Name: atacarejo_financial_transactions atacarejo_financial_transactions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_financial_transactions
    ADD CONSTRAINT atacarejo_financial_transactions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.atacarejo_orders(id) ON DELETE SET NULL;


--
-- Name: atacarejo_interactions atacarejo_interactions_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_interactions
    ADD CONSTRAINT atacarejo_interactions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.atacarejo_customers(id) ON DELETE CASCADE;


--
-- Name: atacarejo_juridico_contratos atacarejo_juridico_contratos_funcionario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_contratos
    ADD CONSTRAINT atacarejo_juridico_contratos_funcionario_id_fkey FOREIGN KEY (funcionario_id) REFERENCES public.atacarejo_employees(id) ON DELETE SET NULL;


--
-- Name: atacarejo_juridico_reclamacoes atacarejo_juridico_reclamacoes_pedido_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_reclamacoes
    ADD CONSTRAINT atacarejo_juridico_reclamacoes_pedido_id_fkey FOREIGN KEY (pedido_id) REFERENCES public.atacarejo_orders(id) ON DELETE SET NULL;


--
-- Name: atacarejo_juridico_reclamacoes atacarejo_juridico_reclamacoes_sac_chamado_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_juridico_reclamacoes
    ADD CONSTRAINT atacarejo_juridico_reclamacoes_sac_chamado_id_fkey FOREIGN KEY (sac_chamado_id) REFERENCES public.atacarejo_support_tickets(id) ON DELETE SET NULL;


--
-- Name: atacarejo_order_items atacarejo_order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_order_items
    ADD CONSTRAINT atacarejo_order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.atacarejo_orders(id) ON DELETE CASCADE;


--
-- Name: atacarejo_order_items atacarejo_order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_order_items
    ADD CONSTRAINT atacarejo_order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.atacarejo_products(id) ON DELETE SET NULL;


--
-- Name: atacarejo_orders atacarejo_orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_orders
    ADD CONSTRAINT atacarejo_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.atacarejo_customers(id) ON DELETE SET NULL;


--
-- Name: atacarejo_orders atacarejo_orders_delivery_payment_option_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_orders
    ADD CONSTRAINT atacarejo_orders_delivery_payment_option_fkey FOREIGN KEY (delivery_payment_option) REFERENCES public.delivery_payment_options(id);


--
-- Name: atacarejo_orders atacarejo_orders_tax_settlement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_orders
    ADD CONSTRAINT atacarejo_orders_tax_settlement_id_fkey FOREIGN KEY (tax_settlement_id) REFERENCES public.atacarejo_financial_transactions(id) ON DELETE SET NULL;


--
-- Name: atacarejo_payroll_items atacarejo_payroll_items_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_payroll_items
    ADD CONSTRAINT atacarejo_payroll_items_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.atacarejo_employees(id) ON DELETE RESTRICT;


--
-- Name: atacarejo_payroll_items atacarejo_payroll_items_payroll_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_payroll_items
    ADD CONSTRAINT atacarejo_payroll_items_payroll_run_id_fkey FOREIGN KEY (payroll_run_id) REFERENCES public.atacarejo_payroll_runs(id) ON DELETE CASCADE;


--
-- Name: atacarejo_payroll_runs atacarejo_payroll_runs_financial_transaction_folha_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_payroll_runs
    ADD CONSTRAINT atacarejo_payroll_runs_financial_transaction_folha_id_fkey FOREIGN KEY (financial_transaction_folha_id) REFERENCES public.atacarejo_financial_transactions(id) ON DELETE SET NULL;


--
-- Name: atacarejo_payroll_runs atacarejo_payroll_runs_financial_transaction_ir_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_payroll_runs
    ADD CONSTRAINT atacarejo_payroll_runs_financial_transaction_ir_id_fkey FOREIGN KEY (financial_transaction_ir_id) REFERENCES public.atacarejo_financial_transactions(id) ON DELETE SET NULL;


--
-- Name: atacarejo_purchase_invoice_items atacarejo_purchase_invoice_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_purchase_invoice_items
    ADD CONSTRAINT atacarejo_purchase_invoice_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.atacarejo_products(id) ON DELETE RESTRICT;


--
-- Name: atacarejo_purchase_invoice_items atacarejo_purchase_invoice_items_purchase_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_purchase_invoice_items
    ADD CONSTRAINT atacarejo_purchase_invoice_items_purchase_invoice_id_fkey FOREIGN KEY (purchase_invoice_id) REFERENCES public.atacarejo_purchase_invoices(id) ON DELETE CASCADE;


--
-- Name: atacarejo_purchase_invoices atacarejo_purchase_invoices_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_purchase_invoices
    ADD CONSTRAINT atacarejo_purchase_invoices_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.atacarejo_suppliers(id) ON DELETE SET NULL;


--
-- Name: atacarejo_support_tickets atacarejo_support_tickets_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.atacarejo_support_tickets
    ADD CONSTRAINT atacarejo_support_tickets_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.atacarejo_orders(id) ON DELETE SET NULL;


--
-- Name: banco_alegre_aplicacoes banco_alegre_aplicacoes_conta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_aplicacoes
    ADD CONSTRAINT banco_alegre_aplicacoes_conta_id_fkey FOREIGN KEY (conta_id) REFERENCES public.banco_alegre_contas(id) ON DELETE RESTRICT;


--
-- Name: banco_alegre_aplicacoes banco_alegre_aplicacoes_produto_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_aplicacoes
    ADD CONSTRAINT banco_alegre_aplicacoes_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES public.banco_alegre_produtos_captacao(id);


--
-- Name: banco_alegre_contas banco_alegre_contas_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_contas
    ADD CONSTRAINT banco_alegre_contas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.banco_alegre_clientes(id) ON DELETE RESTRICT;


--
-- Name: banco_alegre_emprestimo_parcelas banco_alegre_emprestimo_parcelas_emprestimo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_emprestimo_parcelas
    ADD CONSTRAINT banco_alegre_emprestimo_parcelas_emprestimo_id_fkey FOREIGN KEY (emprestimo_id) REFERENCES public.banco_alegre_emprestimos(id) ON DELETE CASCADE;


--
-- Name: banco_alegre_emprestimos banco_alegre_emprestimos_conta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_emprestimos
    ADD CONSTRAINT banco_alegre_emprestimos_conta_id_fkey FOREIGN KEY (conta_id) REFERENCES public.banco_alegre_contas(id) ON DELETE RESTRICT;


--
-- Name: banco_alegre_transacoes banco_alegre_transacoes_conta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banco_alegre_transacoes
    ADD CONSTRAINT banco_alegre_transacoes_conta_id_fkey FOREIGN KEY (conta_id) REFERENCES public.banco_alegre_contas(id) ON DELETE RESTRICT;


--
-- Name: deliveries deliveries_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliveries
    ADD CONSTRAINT deliveries_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: employees employees_banco_alegre_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_banco_alegre_cliente_id_fkey FOREIGN KEY (banco_alegre_cliente_id) REFERENCES public.banco_alegre_clientes(id) ON DELETE SET NULL;


--
-- Name: financial_transactions financial_transactions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_transactions
    ADD CONSTRAINT financial_transactions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: juridico_contratos fk_juridico_contratos_funcionario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.juridico_contratos
    ADD CONSTRAINT fk_juridico_contratos_funcionario FOREIGN KEY (funcionario_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: juridico_reclamacoes fk_juridico_reclamacoes_sac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.juridico_reclamacoes
    ADD CONSTRAINT fk_juridico_reclamacoes_sac FOREIGN KEY (sac_chamado_id) REFERENCES public.support_tickets(id) ON DELETE SET NULL;


--
-- Name: governo_desembolsos governo_desembolsos_pasta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governo_desembolsos
    ADD CONSTRAINT governo_desembolsos_pasta_id_fkey FOREIGN KEY (pasta_id) REFERENCES public.governo_pastas(id) ON DELETE RESTRICT;


--
-- Name: interactions interactions_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactions
    ADD CONSTRAINT interactions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: orders orders_delivery_payment_option_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_delivery_payment_option_fkey FOREIGN KEY (delivery_payment_option) REFERENCES public.delivery_payment_options(id);


--
-- Name: orders orders_tax_settlement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_tax_settlement_id_fkey FOREIGN KEY (tax_settlement_id) REFERENCES public.financial_transactions(id) ON DELETE SET NULL;


--
-- Name: payroll_items payroll_items_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT payroll_items_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE RESTRICT;


--
-- Name: payroll_items payroll_items_payroll_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT payroll_items_payroll_run_id_fkey FOREIGN KEY (payroll_run_id) REFERENCES public.payroll_runs(id) ON DELETE CASCADE;


--
-- Name: payroll_runs payroll_runs_financial_transaction_folha_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_financial_transaction_folha_id_fkey FOREIGN KEY (financial_transaction_folha_id) REFERENCES public.financial_transactions(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_financial_transaction_ir_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_financial_transaction_ir_id_fkey FOREIGN KEY (financial_transaction_ir_id) REFERENCES public.financial_transactions(id) ON DELETE SET NULL;


--
-- Name: purchase_invoice_items purchase_invoice_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: purchase_invoice_items purchase_invoice_items_purchase_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_purchase_invoice_id_fkey FOREIGN KEY (purchase_invoice_id) REFERENCES public.purchase_invoices(id) ON DELETE CASCADE;


--
-- Name: purchase_invoices purchase_invoices_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_invoices
    ADD CONSTRAINT purchase_invoices_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;


--
-- Name: support_tickets support_tickets_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: support_tickets support_tickets_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: system_users system_users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_users
    ADD CONSTRAINT system_users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: support_tickets Qualquer um pode abrir um chamado; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Qualquer um pode abrir um chamado" ON public.support_tickets FOR INSERT WITH CHECK (true);


--
-- Name: order_items Qualquer um pode criar itens de pedido; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Qualquer um pode criar itens de pedido" ON public.order_items FOR INSERT WITH CHECK (true);


--
-- Name: orders Qualquer um pode criar pedido; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Qualquer um pode criar pedido" ON public.orders FOR INSERT WITH CHECK (true);


--
-- Name: orders Qualquer um pode ler pedido recém-criado; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Qualquer um pode ler pedido recém-criado" ON public.orders FOR SELECT USING (true);


--
-- Name: customers Qualquer um pode se cadastrar como cliente; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Qualquer um pode se cadastrar como cliente" ON public.customers FOR INSERT WITH CHECK (true);


--
-- Name: payment_settings Qualquer um pode ver as configurações de pagamento; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Qualquer um pode ver as configurações de pagamento" ON public.payment_settings FOR SELECT USING (true);


--
-- Name: customers Qualquer um pode ver o próprio cadastro por telefone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Qualquer um pode ver o próprio cadastro por telefone" ON public.customers FOR SELECT USING (true);


--
-- Name: products Qualquer um pode ver produtos ativos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Qualquer um pode ver produtos ativos" ON public.products FOR SELECT USING ((active = true));


--
-- Name: payment_settings Usuários autenticados podem alterar configurações de pagamen; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem alterar configurações de pagamen" ON public.payment_settings FOR UPDATE USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: support_tickets Usuários autenticados podem gerenciar chamados; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar chamados" ON public.support_tickets USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: customers Usuários autenticados podem gerenciar clientes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar clientes" ON public.customers USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: coupons Usuários autenticados podem gerenciar cupons; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar cupons" ON public.coupons USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: deliveries Usuários autenticados podem gerenciar entregas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar entregas" ON public.deliveries USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: employees Usuários autenticados podem gerenciar funcionários; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar funcionários" ON public.employees USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: interactions Usuários autenticados podem gerenciar interações; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar interações" ON public.interactions USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: order_items Usuários autenticados podem gerenciar itens de pedido; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar itens de pedido" ON public.order_items USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: financial_transactions Usuários autenticados podem gerenciar o financeiro; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar o financeiro" ON public.financial_transactions USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: chart_of_accounts Usuários autenticados podem gerenciar o plano de contas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar o plano de contas" ON public.chart_of_accounts USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: orders Usuários autenticados podem gerenciar pedidos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar pedidos" ON public.orders USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: products Usuários autenticados podem gerenciar produtos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar produtos" ON public.products USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: expense_category_types Usuários autenticados podem gerenciar tipos de despesa; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem gerenciar tipos de despesa" ON public.expense_category_types USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: system_users Usuários autenticados podem ver e gerenciar usuários do siste; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuários autenticados podem ver e gerenciar usuários do siste" ON public.system_users USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: atacarejo_customers anon_insert_customers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_insert_customers ON public.atacarejo_customers FOR INSERT TO anon WITH CHECK (true);


--
-- Name: customers anon_insert_customers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_insert_customers ON public.customers FOR INSERT TO anon WITH CHECK (true);


--
-- Name: atacarejo_order_items anon_insert_order_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_insert_order_items ON public.atacarejo_order_items FOR INSERT TO anon WITH CHECK (true);


--
-- Name: order_items anon_insert_order_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_insert_order_items ON public.order_items FOR INSERT TO anon WITH CHECK (true);


--
-- Name: atacarejo_orders anon_insert_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_insert_orders ON public.atacarejo_orders FOR INSERT TO anon WITH CHECK (true);


--
-- Name: orders anon_insert_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_insert_orders ON public.orders FOR INSERT TO anon WITH CHECK (true);


--
-- Name: atacarejo_customers anon_select_customers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_customers ON public.atacarejo_customers FOR SELECT TO anon USING (true);


--
-- Name: customers anon_select_customers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_customers ON public.customers FOR SELECT TO anon USING (true);


--
-- Name: atacarejo_deliveries anon_select_deliveries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_deliveries ON public.atacarejo_deliveries FOR SELECT TO anon USING (true);


--
-- Name: deliveries anon_select_deliveries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_deliveries ON public.deliveries FOR SELECT TO anon USING (true);


--
-- Name: atacarejo_delivery_payment_options anon_select_delivery_payment_options; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_delivery_payment_options ON public.atacarejo_delivery_payment_options FOR SELECT TO anon USING ((enabled = true));


--
-- Name: delivery_payment_options anon_select_delivery_payment_options; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_delivery_payment_options ON public.delivery_payment_options FOR SELECT TO anon USING ((enabled = true));


--
-- Name: atacarejo_juridico_lgpd_politica anon_select_lgpd_politica; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_lgpd_politica ON public.atacarejo_juridico_lgpd_politica FOR SELECT TO anon USING (true);


--
-- Name: juridico_lgpd_politica anon_select_lgpd_politica; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_lgpd_politica ON public.juridico_lgpd_politica FOR SELECT TO anon USING (true);


--
-- Name: atacarejo_module_settings anon_select_module_settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_module_settings ON public.atacarejo_module_settings FOR SELECT TO anon USING (true);


--
-- Name: module_settings anon_select_module_settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_module_settings ON public.module_settings FOR SELECT TO anon USING (true);


--
-- Name: atacarejo_order_items anon_select_order_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_order_items ON public.atacarejo_order_items FOR SELECT TO anon USING (true);


--
-- Name: order_items anon_select_order_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_order_items ON public.order_items FOR SELECT TO anon USING (true);


--
-- Name: atacarejo_orders anon_select_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_orders ON public.atacarejo_orders FOR SELECT TO anon USING (true);


--
-- Name: orders anon_select_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_orders ON public.orders FOR SELECT TO anon USING (true);


--
-- Name: atacarejo_payment_settings anon_select_payment_settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_payment_settings ON public.atacarejo_payment_settings FOR SELECT TO anon USING (true);


--
-- Name: payment_settings anon_select_payment_settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_payment_settings ON public.payment_settings FOR SELECT TO anon USING (true);


--
-- Name: atacarejo_products anon_select_products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_products ON public.atacarejo_products FOR SELECT TO anon USING ((active = true));


--
-- Name: products anon_select_products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_products ON public.products FOR SELECT TO anon USING ((active = true));


--
-- Name: atacarejo_shipping_rules anon_select_shipping_rules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_shipping_rules ON public.atacarejo_shipping_rules FOR SELECT TO anon USING ((active = true));


--
-- Name: shipping_rules anon_select_shipping_rules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_select_shipping_rules ON public.shipping_rules FOR SELECT TO anon USING ((active = true));


--
-- Name: atacarejo_customers anon_update_customers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_update_customers ON public.atacarejo_customers FOR UPDATE TO anon USING (true) WITH CHECK (true);


--
-- Name: customers anon_update_customers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_update_customers ON public.customers FOR UPDATE TO anon USING (true) WITH CHECK (true);


--
-- Name: atacarejo_chart_of_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_chart_of_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_coupons; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_coupons ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_customers ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_deliveries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_deliveries ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_delivery_payment_options; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_delivery_payment_options ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_employees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_employees ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_financial_transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_financial_transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_interactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_interactions ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_juridico_anexos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_juridico_anexos ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_juridico_contratos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_juridico_contratos ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_juridico_documentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_juridico_documentos ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_juridico_lgpd_politica; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_juridico_lgpd_politica ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_juridico_lgpd_solicitacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_juridico_lgpd_solicitacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_juridico_obrigacoes_fiscais; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_juridico_obrigacoes_fiscais ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_juridico_reclamacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_juridico_reclamacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_module_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_module_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_payment_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_payment_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_payroll_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_payroll_items ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_payroll_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_payroll_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_products ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_purchase_invoice_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_purchase_invoice_items ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_purchase_invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_purchase_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_shipping_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_shipping_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_suppliers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_suppliers ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_support_tickets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.atacarejo_support_tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: atacarejo_chart_of_accounts authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_chart_of_accounts TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_coupons authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_coupons TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_customers authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_customers TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_deliveries authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_deliveries TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_delivery_payment_options authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_delivery_payment_options TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_employees authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_employees TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_financial_transactions authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_financial_transactions TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_interactions authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_interactions TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_juridico_anexos authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_juridico_anexos TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_juridico_contratos authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_juridico_contratos TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_juridico_documentos authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_juridico_documentos TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_juridico_lgpd_politica authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_juridico_lgpd_politica TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_juridico_lgpd_solicitacoes authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_juridico_lgpd_solicitacoes TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_juridico_obrigacoes_fiscais authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_juridico_obrigacoes_fiscais TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_juridico_reclamacoes authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_juridico_reclamacoes TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_module_settings authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_module_settings TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_order_items authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_order_items TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_orders authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_orders TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_payment_settings authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_payment_settings TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_payroll_items authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_payroll_items TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_payroll_runs authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_payroll_runs TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_products authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_products TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_purchase_invoice_items authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_purchase_invoice_items TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_purchase_invoices authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_purchase_invoices TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_shipping_rules authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_shipping_rules TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_suppliers authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_suppliers TO authenticated USING (true) WITH CHECK (true);


--
-- Name: atacarejo_support_tickets authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.atacarejo_support_tickets TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_aplicacoes authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.banco_alegre_aplicacoes TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_clientes authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.banco_alegre_clientes TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_contas authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.banco_alegre_contas TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_emprestimo_parcelas authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.banco_alegre_emprestimo_parcelas TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_emprestimos authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.banco_alegre_emprestimos TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_managers authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.banco_alegre_managers TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_parametros_credito authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.banco_alegre_parametros_credito TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_produtos_captacao authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.banco_alegre_produtos_captacao TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_transacoes authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.banco_alegre_transacoes TO authenticated USING (true) WITH CHECK (true);


--
-- Name: chart_of_accounts authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.chart_of_accounts TO authenticated USING (true) WITH CHECK (true);


--
-- Name: coupons authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.coupons TO authenticated USING (true) WITH CHECK (true);


--
-- Name: customers authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.customers TO authenticated USING (true) WITH CHECK (true);


--
-- Name: deliveries authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.deliveries TO authenticated USING (true) WITH CHECK (true);


--
-- Name: delivery_payment_options authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.delivery_payment_options TO authenticated USING (true) WITH CHECK (true);


--
-- Name: employees authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.employees TO authenticated USING (true) WITH CHECK (true);


--
-- Name: expense_category_types authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.expense_category_types TO authenticated USING (true) WITH CHECK (true);


--
-- Name: financial_transactions authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.financial_transactions TO authenticated USING (true) WITH CHECK (true);


--
-- Name: governo_desembolsos authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.governo_desembolsos TO authenticated USING (true) WITH CHECK (true);


--
-- Name: governo_extrato authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.governo_extrato TO authenticated USING (true) WITH CHECK (true);


--
-- Name: governo_managers authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.governo_managers TO authenticated USING (true) WITH CHECK (true);


--
-- Name: governo_pastas authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.governo_pastas TO authenticated USING (true) WITH CHECK (true);


--
-- Name: interactions authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.interactions TO authenticated USING (true) WITH CHECK (true);


--
-- Name: juridico_anexos authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.juridico_anexos TO authenticated USING (true) WITH CHECK (true);


--
-- Name: juridico_contratos authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.juridico_contratos TO authenticated USING (true) WITH CHECK (true);


--
-- Name: juridico_documentos authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.juridico_documentos TO authenticated USING (true) WITH CHECK (true);


--
-- Name: juridico_lgpd_politica authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.juridico_lgpd_politica TO authenticated USING (true) WITH CHECK (true);


--
-- Name: juridico_lgpd_solicitacoes authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.juridico_lgpd_solicitacoes TO authenticated USING (true) WITH CHECK (true);


--
-- Name: juridico_obrigacoes_fiscais authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.juridico_obrigacoes_fiscais TO authenticated USING (true) WITH CHECK (true);


--
-- Name: juridico_reclamacoes authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.juridico_reclamacoes TO authenticated USING (true) WITH CHECK (true);


--
-- Name: module_settings authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.module_settings TO authenticated USING (true) WITH CHECK (true);


--
-- Name: order_items authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.order_items TO authenticated USING (true) WITH CHECK (true);


--
-- Name: orders authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.orders TO authenticated USING (true) WITH CHECK (true);


--
-- Name: payment_settings authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.payment_settings TO authenticated USING (true) WITH CHECK (true);


--
-- Name: payroll_items authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.payroll_items TO authenticated USING (true) WITH CHECK (true);


--
-- Name: payroll_runs authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.payroll_runs TO authenticated USING (true) WITH CHECK (true);


--
-- Name: products authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.products TO authenticated USING (true) WITH CHECK (true);


--
-- Name: purchase_invoice_items authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.purchase_invoice_items TO authenticated USING (true) WITH CHECK (true);


--
-- Name: purchase_invoices authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.purchase_invoices TO authenticated USING (true) WITH CHECK (true);


--
-- Name: shipping_rules authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.shipping_rules TO authenticated USING (true) WITH CHECK (true);


--
-- Name: suppliers authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.suppliers TO authenticated USING (true) WITH CHECK (true);


--
-- Name: support_tickets authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.support_tickets TO authenticated USING (true) WITH CHECK (true);


--
-- Name: system_users authenticated_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_full_access ON public.system_users TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banco_alegre_aplicacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banco_alegre_aplicacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: banco_alegre_clientes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banco_alegre_clientes ENABLE ROW LEVEL SECURITY;

--
-- Name: banco_alegre_contas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banco_alegre_contas ENABLE ROW LEVEL SECURITY;

--
-- Name: banco_alegre_emprestimo_parcelas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banco_alegre_emprestimo_parcelas ENABLE ROW LEVEL SECURITY;

--
-- Name: banco_alegre_emprestimos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banco_alegre_emprestimos ENABLE ROW LEVEL SECURITY;

--
-- Name: banco_alegre_managers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banco_alegre_managers ENABLE ROW LEVEL SECURITY;

--
-- Name: banco_alegre_parametros_credito; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banco_alegre_parametros_credito ENABLE ROW LEVEL SECURITY;

--
-- Name: banco_alegre_produtos_captacao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banco_alegre_produtos_captacao ENABLE ROW LEVEL SECURITY;

--
-- Name: banco_alegre_transacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banco_alegre_transacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: chart_of_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.chart_of_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: coupons; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: deliveries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;

--
-- Name: delivery_payment_options; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.delivery_payment_options ENABLE ROW LEVEL SECURITY;

--
-- Name: employees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

--
-- Name: expense_category_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expense_category_types ENABLE ROW LEVEL SECURITY;

--
-- Name: financial_transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.financial_transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: governo_desembolsos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.governo_desembolsos ENABLE ROW LEVEL SECURITY;

--
-- Name: governo_extrato; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.governo_extrato ENABLE ROW LEVEL SECURITY;

--
-- Name: governo_managers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.governo_managers ENABLE ROW LEVEL SECURITY;

--
-- Name: governo_pastas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.governo_pastas ENABLE ROW LEVEL SECURITY;

--
-- Name: interactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.interactions ENABLE ROW LEVEL SECURITY;

--
-- Name: juridico_anexos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.juridico_anexos ENABLE ROW LEVEL SECURITY;

--
-- Name: juridico_contratos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.juridico_contratos ENABLE ROW LEVEL SECURITY;

--
-- Name: juridico_documentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.juridico_documentos ENABLE ROW LEVEL SECURITY;

--
-- Name: juridico_lgpd_politica; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.juridico_lgpd_politica ENABLE ROW LEVEL SECURITY;

--
-- Name: juridico_lgpd_solicitacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.juridico_lgpd_solicitacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: juridico_obrigacoes_fiscais; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.juridico_obrigacoes_fiscais ENABLE ROW LEVEL SECURITY;

--
-- Name: juridico_reclamacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.juridico_reclamacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: module_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.module_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_items ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_invoice_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_invoice_items ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: shipping_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shipping_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: suppliers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- Name: support_tickets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: system_users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.system_users ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--



