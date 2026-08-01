// app/api/webhooks/dropify/route.js
//
// Rota que recebe as notificacoes automaticas (webhooks) enviadas pela
// Dropify sempre que um produto muda de estoque, preco, ou disponibilidade
// para envio imediato.
//
// Como configurar: depois de publicado, informe este endereco completo
// para a Dropify (ex: https://seusite.com/api/webhooks/dropify) no painel
// deles, na secao de configuracao de Webhook.
//
// Documentacao oficial: https://docs.dropify.com.br/webhook/

import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

async function handleStockUpdate(payload) {
  const { sku, quantity } = payload;
  const { error } = await supabase
    .from("products")
    .update({ stock: quantity })
    .eq("external_sku", sku)
    .eq("dropshipping_source", "dropify");

  if (error) {
    throw new Error("Falha ao atualizar estoque do SKU " + sku + ": " + error.message);
  }
}

async function handlePriceUpdate(payload) {
  const { sku, newSuggestedPrice } = payload;

  // A Dropify envia o preco multiplicado por 100 (em centavos),
  // entao convertemos para reais antes de salvar.
  const precoEmReais = newSuggestedPrice / 100;

  const { error } = await supabase
    .from("products")
    .update({ price: precoEmReais })
    .eq("external_sku", sku)
    .eq("dropshipping_source", "dropify");

  if (error) {
    throw new Error("Falha ao atualizar preco do SKU " + sku + ": " + error.message);
  }
}

async function handleImmediateShipmentUpdate(payload) {
  const { sku, immediateShipment } = payload;
  const { error } = await supabase
    .from("products")
    .update({ immediate_shipment: immediateShipment })
    .eq("external_sku", sku)
    .eq("dropshipping_source", "dropify");

  if (error) {
    throw new Error("Falha ao atualizar disponibilidade de envio do SKU " + sku + ": " + error.message);
  }
}

export async function POST(request) {
  let payload;

  try {
    payload = await request.json();
  } catch (error) {
    return Response.json(
      { sucesso: false, mensagem: "Corpo da requisicao invalido (JSON esperado)." },
      { status: 400 }
    );
  }

  try {
    switch (payload.type) {
      case "webhook-verification-code":
        console.log("Codigo de verificacao recebido da Dropify:", payload.verificationCode);
        return Response.json({ sucesso: true });

      case "stock":
        await handleStockUpdate(payload);
        return Response.json({ sucesso: true });

      case "price":
        await handlePriceUpdate(payload);
        return Response.json({ sucesso: true });

      case "immediate-shipment":
        await handleImmediateShipmentUpdate(payload);
        return Response.json({ sucesso: true });

      default:
        console.log("Tipo de webhook nao tratado:", payload.type);
        return Response.json({ sucesso: true, aviso: "Tipo nao tratado" });
    }
  } catch (error) {
    return Response.json(
      { sucesso: false, mensagem: error.message },
      { status: 500 }
    );
  }
}