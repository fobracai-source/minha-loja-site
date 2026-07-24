"use client";

import { useEffect, useState } from "react";
import Header from "../../components/Header";
import { useAuth } from "../../context/AuthContext";
import { supabase } from "../../lib/supabaseClient";
import { LogOut, Package, Phone, MapPin, CreditCard, Truck } from "lucide-react";

function fmtMoney(v) {
  return `R$ ${Number(v || 0).toFixed(2).replace(".", ",")}`;
}
function fmtDate(d) {
  return new Date(d).toLocaleDateString("pt-BR");
}

const STATUS_LABELS = {
  pendente: "Pendente",
  entregue: "Entregue",
  cancelado: "Cancelado",
};

const DELIVERY_STATUS_LABELS = {
  aguardando_separacao: "Aguardando separação",
  em_separacao: "Em separação",
  saiu_para_entrega: "Saiu para entrega",
  entregue: "Entregue",
  problema: "Problema na entrega",
};

const PAYMENT_METHOD_LABELS = {
  cod: "Pagar na Entrega",
  mercadopago: "Mercado Pago",
  stripe: "Cartão de Crédito",
  pagbank: "PagBank",
};

const DELIVERY_PAYMENT_LABELS = {
  dinheiro: "Dinheiro",
  cartao_credito: "Cartão de Crédito",
  cartao_debito: "Cartão de Débito",
  pix: "Pix",
  combinado: "Pagamento combinado",
};

export default function ContaPage() {
  const { customer, loading, loginWithPhone, logout } = useAuth();
  const [phone, setPhone] = useState("");
  const [entering, setEntering] = useState(false);
  const [error, setError] = useState("");

  const [orders, setOrders] = useState([]);
  const [loadingOrders, setLoadingOrders] = useState(false);

  useEffect(() => {
    async function loadOrders() {
      if (!customer?.id) return;
      setLoadingOrders(true);
      const { data } = await supabase
        .from("orders")
        .select("*, order_items(product_name, unit_price, quantity, product_id, products(image_url)), deliveries(status, carrier, tracking_code, estimated_date)")
        .eq("customer_id", customer.id)
        .order("created_at", { ascending: false });
      setOrders(data || []);
      setLoadingOrders(false);
    }
    loadOrders();
  }, [customer]);

  async function handleLogin(e) {
    e.preventDefault();
    if (!phone.trim()) return;
    setError("");
    setEntering(true);
    try {
      await loginWithPhone(phone.trim());
    } catch (err) {
      setError(err.message || "Não foi possível entrar. Tente novamente.");
    } finally {
      setEntering(false);
    }
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-cream">
        <Header />
        <p className="p-8 text-center text-ink-soft">Carregando…</p>
      </div>
    );
  }

  if (!customer) {
    return (
      <div className="min-h-screen bg-cream">
        <Header />
        <div className="mx-auto max-w-sm px-4 py-16">
          <h1 className="font-display text-2xl font-extrabold text-ink">Minha Conta</h1>
          <p className="mt-1.5 text-sm text-ink-soft">Entre com seu telefone para ver seus pedidos.</p>

          <form onSubmit={handleLogin} className="mt-6 flex flex-col gap-3">
            <div className="flex items-center gap-2 rounded-xl2 border border-ink/10 bg-white px-4 py-3">
              <Phone size={17} className="text-ink-soft" />
              <input
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="Seu telefone / WhatsApp"
                className="w-full bg-transparent text-sm outline-none"
                required
              />
            </div>
            {error && <p className="text-xs font-semibold text-red-600">{error}</p>}
            <button
              type="submit"
              disabled={entering}
              className="rounded-2xl bg-brand py-3.5 font-display text-base font-bold text-white disabled:opacity-60"
            >
              {entering ? "Entrando…" : "Entrar"}
            </button>
          </form>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-cream pb-24 md:pb-10">
      <Header />
      <div className="mx-auto max-w-2xl px-4 py-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="font-display text-2xl font-extrabold text-ink">
              Olá, {customer.name || "cliente"}!
            </h1>
            <p className="mt-1 text-sm text-ink-soft">{customer.phone}</p>
          </div>
          <button
            onClick={logout}
            className="flex items-center gap-1.5 rounded-full border border-ink/10 px-4 py-2 text-sm font-semibold text-ink-soft"
          >
            <LogOut size={15} /> Sair
          </button>
        </div>

        <h2 className="mt-8 font-display text-lg font-bold text-ink">Meus pedidos</h2>

        {loadingOrders ? (
          <p className="mt-3 text-sm text-ink-soft">Carregando…</p>
        ) : orders.length === 0 ? (
          <p className="mt-3 text-sm text-ink-soft">Você ainda não fez nenhum pedido.</p>
        ) : (
          <div className="mt-4 flex flex-col gap-4">
            {orders.map((o) => {
              const delivery = Array.isArray(o.deliveries) ? o.deliveries[0] : o.deliveries;
              const deliveryPaymentLabels = (o.delivery_payment_options || [])
                .map((id) => DELIVERY_PAYMENT_LABELS[id] || id)
                .join(" + ");

              return (
                <div key={o.id} className="rounded-xl2 border border-ink/8 bg-white p-4">
                  <div className="flex items-center justify-between">
                    <span className="flex items-center gap-2 font-display text-sm font-bold text-ink">
                      <Package size={15} /> Pedido #{o.order_number}
                    </span>
                    <span className="text-xs font-semibold text-ink-soft">{fmtDate(o.created_at)}</span>
                  </div>

                  {/* Itens com foto */}
                  <div className="mt-3 flex flex-col gap-2 border-t border-ink/8 pt-3">
                    {(o.order_items || []).map((item, i) => (
                      <div key={i} className="flex items-center gap-3">
                        {item.products?.image_url ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={item.products.image_url} alt="" className="h-12 w-12 shrink-0 rounded-lg object-cover" />
                        ) : (
                          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-lg bg-brand-light/40 text-lg">📦</div>
                        )}
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-xs font-semibold text-ink">{item.product_name}</p>
                          <p className="text-[11px] text-ink-soft">{item.quantity}x {fmtMoney(item.unit_price)}</p>
                        </div>
                        <span className="text-xs font-bold text-ink">{fmtMoney(item.unit_price * item.quantity)}</span>
                      </div>
                    ))}
                  </div>

                  {/* Pagamento */}
                  <div className="mt-3 flex items-start gap-2 border-t border-ink/8 pt-3 text-xs text-ink-soft">
                    <CreditCard size={13} className="mt-0.5 shrink-0" />
                    <span>
                      {PAYMENT_METHOD_LABELS[o.payment_method] || o.payment_method}
                      {deliveryPaymentLabels && ` — ${deliveryPaymentLabels}`}
                      {o.coupon_code && ` · Cupom ${o.coupon_code} (-${fmtMoney(o.discount_amount)})`}
                    </span>
                  </div>

                  {/* Endereço usado nesse pedido (via cliente, já que não guardamos snapshot) */}
                  {customer.street && (
                    <div className="mt-2 flex items-start gap-2 text-xs text-ink-soft">
                      <MapPin size={13} className="mt-0.5 shrink-0" />
                      <span>
                        {[customer.street, customer.street_number].filter(Boolean).join(", ")}
                        {customer.neighborhood ? ` — ${customer.neighborhood}` : ""}
                        {customer.city ? `, ${customer.city}` : ""}
                      </span>
                    </div>
                  )}

                  {/* Status de entrega */}
                  <div className="mt-2 flex items-start gap-2 text-xs text-ink-soft">
                    <Truck size={13} className="mt-0.5 shrink-0" />
                    <span>
                      {delivery ? (DELIVERY_STATUS_LABELS[delivery.status] || delivery.status) : "Aguardando processamento"}
                      {delivery?.carrier && ` · ${delivery.carrier}`}
                      {delivery?.tracking_code && ` · Rastreio: ${delivery.tracking_code}`}
                    </span>
                  </div>

                  {o.notes && (
                    <p className="mt-2 text-xs italic text-ink-soft">Obs: {o.notes}</p>
                  )}

                  {/* Resumo de valores */}
                  <div className="mt-3 flex flex-col gap-1 border-t border-ink/8 pt-3 text-xs text-ink-soft">
                    <div className="flex justify-between"><span>Subtotal</span><span>{fmtMoney(o.subtotal)}</span></div>
                    <div className="flex justify-between"><span>Frete</span><span>{o.shipping_cost === 0 ? "Grátis" : fmtMoney(o.shipping_cost)}</span></div>
                    {o.discount_amount > 0 && (
                      <div className="flex justify-between text-success"><span>Desconto</span><span>-{fmtMoney(o.discount_amount)}</span></div>
                    )}
                  </div>
                  <div className="mt-2 flex items-center justify-between border-t border-ink/8 pt-2">
                    <span className="text-xs font-semibold text-ink-soft">{STATUS_LABELS[o.status] || o.status}</span>
                    <span className="font-display text-base font-bold text-ink">{fmtMoney(o.total)}</span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
