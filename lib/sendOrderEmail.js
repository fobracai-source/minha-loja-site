const EMAILJS_ENDPOINT = "https://api.emailjs.com/api/v1.0/email/send";

function formatCurrency(value) {
  return `R$ ${Number(value).toFixed(2).replace(".", ",")}`;
}

function buildItemsText(items) {
  return items
    .map((i) => `- ${i.quantity}x ${i.product.name} (${formatCurrency(i.product.price)} cada)`)
    .join("\n");
}

const PAYMENT_LABELS = {
  cod: "Pagar na Entrega",
  mercadopago: "Mercado Pago",
  stripe: "Cartão de Crédito (Stripe)",
  pagbank: "PagBank",
};

export async function sendOrderConfirmationEmail({
  toEmail, customerName, orderNumber, items, subtotal, shippingCost, discountAmount, total, paymentMethod, address,
}) {
  const serviceId = process.env.NEXT_PUBLIC_EMAILJS_SERVICE_ID;
  const templateId = process.env.NEXT_PUBLIC_EMAILJS_TEMPLATE_ID;
  const publicKey = process.env.NEXT_PUBLIC_EMAILJS_PUBLIC_KEY;
  const privateKey = process.env.NEXT_PUBLIC_EMAILJS_PRIVATE_KEY;

  if (!serviceId || !templateId || !publicKey) {
    console.warn("EmailJS não configurado: e-mail de confirmação não foi enviado.");
    return;
  }

  const templateParams = {
    to_email: toEmail,
    customer_name: customerName,
    order_number: orderNumber,
    items_list: buildItemsText(items),
    subtotal: formatCurrency(subtotal),
    shipping_cost: shippingCost === 0 ? "Grátis" : formatCurrency(shippingCost),
    discount: discountAmount > 0 ? formatCurrency(discountAmount) : "—",
    total: formatCurrency(total),
    payment_method: PAYMENT_LABELS[paymentMethod] || paymentMethod,
    address,
  };

  const response = await fetch(EMAILJS_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      service_id: serviceId,
      template_id: templateId,
      user_id: publicKey,
      accessToken: privateKey || undefined,
      template_params: templateParams,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Falha ao enviar e-mail (${response.status}): ${text}`);
  }
}
