// lib/dropify.js
//
// Funções auxiliares para autenticar e conversar com a API da Dropify.
// Documentação oficial: https://docs.dropify.com.br/api/

const DROPIFY_BASE_URL = "https://app.dropify.com.br";

/**
 * Pede um token de acesso pra Dropify usando as credenciais da loja.
 * Esse token expira depois de um tempo, então pedimos um novo a cada chamada
 * em vez de tentar guardar/reaproveitar (mais simples e mais seguro).
 */
async function getDropifyAccessToken() {
  const clientId = process.env.DROPIFY_CLIENT_ID;
  const clientSecret = process.env.DROPIFY_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    throw new Error(
      "Credenciais da Dropify não configuradas. Verifique DROPIFY_CLIENT_ID e DROPIFY_CLIENT_SECRET nas variáveis de ambiente."
    );
  }

  const response = await fetch(`${DROPIFY_BASE_URL}/oauth`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "client_credentials",
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Falha ao autenticar com a Dropify (status ${response.status}): ${errorText}`
    );
  }

  const data = await response.json();
  return data.access_token;
}

/**
 * Busca uma página de produtos disponíveis no catálogo da Dropify.
 * A API retorna os produtos em páginas (não vem tudo de uma vez).
 *
 * @param {number} page - número da página a buscar (começa em 1)
 * @returns {Promise<{products: Array, hasNextPage: boolean}>}
 */
async function fetchDropifyAvailableProducts(page = 1) {
  const accessToken = await getDropifyAccessToken();

  const response = await fetch(
    `${DROPIFY_BASE_URL}/api/products/available?page=${page}`,
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    }
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Falha ao buscar produtos da Dropify (status ${response.status}): ${errorText}`
    );
  }

  const data = await response.json();
  const products = data._embedded?.product || [];
  const hasNextPage = Boolean(data._links?.next);

  return { products, hasNextPage };
}

module.exports = {
  getDropifyAccessToken,
  fetchDropifyAvailableProducts,
};
