import { supabase } from "./supabaseClient";

function faixaSize(rule) {
  return Number(rule.cep_end) - Number(rule.cep_start);
}

function fmtMoney(v) {
  return `R$ ${Number(v).toFixed(2).replace(".", ",")}`;
}

/**
 * Calcula o frete com base no CEP digitado e no valor do carrinho.
 * Busca todas as faixas cadastradas que cobrem esse CEP, e decide o
 * resultado seguindo esta prioridade:
 *   1) Alguma faixa "sempre grátis" cobre esse CEP → grátis
 *   2) Alguma faixa "grátis a partir de X" cobre esse CEP e o carrinho
 *      já bateu o valor mínimo → grátis
 *   3) Alguma faixa de "preço fixo" cobre esse CEP → usa esse preço
 *   4) Nenhuma faixa cobre esse CEP → frete a combinar
 *
 * Quando há mais de uma faixa aplicável no mesmo grupo, usa a mais
 * específica (a de menor abrangência de CEPs).
 */
export async function calculateShipping(cep, cartTotal) {
  const cleanCep = (cep || "").replace(/\D/g, "");

  if (cleanCep.length !== 8) {
    return { cost: null, message: "Digite seu CEP para calcular o frete." };
  }

  const { data: rules, error } = await supabase
    .from("shipping_rules")
    .select("*")
    .eq("active", true)
    .lte("cep_start", cleanCep)
    .gte("cep_end", cleanCep);

  if (error) {
    return { cost: null, message: "Não foi possível calcular o frete agora. Tente novamente." };
  }

  if (!rules || rules.length === 0) {
    return { cost: null, message: "Ainda não entregamos nesse CEP. Fale com a gente para combinar a entrega." };
  }

  const gratisSempre = rules.filter((r) => r.mode === "gratis_sempre");
  if (gratisSempre.length > 0) {
    return { cost: 0, message: "Seu pedido tem frete grátis para essa região!" };
  }

  const gratisAPartir = rules
    .filter((r) => r.mode === "gratis_a_partir_de")
    .sort((a, b) => faixaSize(a) - faixaSize(b));
  const regraValorMinimo = gratisAPartir[0];

  if (regraValorMinimo && cartTotal >= Number(regraValorMinimo.min_purchase_value)) {
    return { cost: 0, message: "Seu pedido tem frete grátis para essa região!" };
  }

  const precoFixo = rules
    .filter((r) => r.mode === "preco_fixo")
    .sort((a, b) => faixaSize(a) - faixaSize(b))[0];

  if (precoFixo) {
    const faltaParaGratis = regraValorMinimo
      ? Math.max(Number(regraValorMinimo.min_purchase_value) - cartTotal, 0)
      : 0;
    return {
      cost: Number(precoFixo.price),
      message: faltaParaGratis > 0
        ? `Frete: ${fmtMoney(precoFixo.price)}. Faltam ${fmtMoney(faltaParaGratis)} para o frete grátis nessa região.`
        : `Frete: ${fmtMoney(precoFixo.price)}`,
      missing: faltaParaGratis,
    };
  }

  if (regraValorMinimo) {
    const faltaParaGratis = Math.max(Number(regraValorMinimo.min_purchase_value) - cartTotal, 0);
    return {
      cost: null,
      message: `Faltam ${fmtMoney(faltaParaGratis)} para o frete grátis nessa região.`,
      missing: faltaParaGratis,
    };
  }

  return { cost: null, message: "Frete a combinar." };
}
