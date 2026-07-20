const SHIPPING_METHODS = [
  { id: "free_shipping", label: "Frete Grátis", enabled: true, minCartValue: 199.0 },
  { id: "fixed", label: "Valor Fixo", enabled: false },
  { id: "cep_region", label: "Por CEP / Região", enabled: false },
  { id: "carrier_api", label: "Transportadora (API)", enabled: false },
  { id: "weight_based", label: "Por Peso / Tamanho", enabled: false },
];

export function calculateShipping(cartTotal) {
  const freeShipping = SHIPPING_METHODS.find((m) => m.id === "free_shipping");

  if (freeShipping?.enabled && cartTotal >= freeShipping.minCartValue) {
    return { cost: 0, message: "Seu pedido tem frete grátis!" };
  }

  const fallback = SHIPPING_METHODS.find((m) => m.id !== "free_shipping" && m.enabled);
  if (fallback) {
    return { cost: null, message: "Cálculo de frete ainda não implementado para este método." };
  }

  const missing = freeShipping ? Math.max(freeShipping.minCartValue - cartTotal, 0) : 0;
  return {
    cost: null,
    message:
      missing > 0
        ? `Faltam R$ ${missing.toFixed(2).replace(".", ",")} para o frete grátis.`
        : "Frete a combinar.",
    missing,
    minCartValue: freeShipping?.minCartValue,
  };
}
