// app/api/dropify/import/route.js
//
// Rota que busca produtos disponíveis na Dropify e insere/atualiza
// na tabela `products` do Supabase, marcando cada um com
// dropshipping_source = 'dropify' e external_sku = SKU da Dropify.
//
// Como chamar: GET /api/dropify/import
// (por enquanto sem proteção de senha — vamos adicionar isso antes de ir
// pra produção, mas no ambiente de teste já serve pra validar o fluxo)

import { createClient } from "@supabase/supabase-js";
import { fetchDropifyAvailableProducts } from "../../../../lib/dropify";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

/**
 * Converte um produto no formato da Dropify para o formato
 * da nossa tabela `products`.
 */
function mapDropifyProductToRow(dropifyProduct) {
  const categoryName = dropifyProduct.categories?.[0]?.name || null;
  const imageUrl = dropifyProduct.images?.[0]?.url || null;

  return {
    name: dropifyProduct.name,
    description: dropifyProduct.description || "",
    category: categoryName,
    brand: dropifyProduct.brand || null,
    active: dropifyProduct.available === true,
    image_url: imageUrl,
    dropshipping_source: "dropify",
    external_sku: dropifyProduct.sku,
    product_type: "produto",
    fiscal_origin: "nacional",
  };
}

export async function GET() {
  try {
    let page = 1;
    let hasNextPage = true;
    let totalImportados = 0;
    let totalErros = 0;
    const erros = [];

    while (hasNextPage) {
      const result = await fetchDropifyAvailableProducts(page);

      for (const dropifyProduct of result.products) {
        const row = mapDropifyProductToRow(dropifyProduct);

        // upsert: se já existe um produto com esse external_sku, atualiza;
        // se não existe, cria um novo. Isso evita duplicar produto ao
        // rodar a importação mais de uma vez.
        const { error } = await supabase
          .from("products")
          .upsert(row, { onConflict: "external_sku" });

        if (error) {
          totalErros += 1;
          erros.push({ sku: dropifyProduct.sku, erro: error.message });
        } else {
          totalImportados += 1;
        }
      }

      hasNextPage = result.hasNextPage;
      page += 1;
    }

    return Response.json({
      sucesso: true,
      totalImportados,
      totalErros,
      erros: erros.slice(0, 10), // mostra só os 10 primeiros erros, se houver
    });
  } catch (error) {
    return Response.json(
      { sucesso: false, mensagem: error.message },
      { status: 500 }
    );
  }
}
