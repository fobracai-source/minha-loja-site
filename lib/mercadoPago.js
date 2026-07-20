import { supabase } from "./supabaseClient";

export async function createMercadoPagoCheckout({ orderId, orderNumber, items, customerEmail }) {
  const { data, error } = await supabase.functions.invoke("create-mp-preference", {
    body: {
      orderId,
      orderNumber,
      customerEmail,
      items: items.map((i) => ({
        product_name: i.product.name,
        quantity: i.quantity,
        unit_price: i.product.price,
      })),
    },
  });

  if (error) throw new Error(error.message || "Não foi possível iniciar o pagamento.");
  if (!data?.checkoutUrl) throw new Error("O Mercado Pago não retornou o link de pagamento.");

  return data.checkoutUrl;
}
