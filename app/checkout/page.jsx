"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Tag, X } from "lucide-react";
import Header from "../../components/Header";
import PaymentMethodSelector from "../../components/PaymentMethodSelector";
import { useCart } from "../../context/CartContext";
import { useAuth } from "../../context/AuthContext";
import { supabase } from "../../lib/supabaseClient";
import { calculateShipping } from "../../lib/shipping";
import { sendOrderConfirmationEmail } from "../../lib/sendOrderEmail";
import { createMercadoPagoCheckout } from "../../lib/mercadoPago";

export default function CheckoutPage() {
  const { items, subtotal, clearCart } = useCart();
  const { customer } = useAuth();
  const router = useRouter();

  const [paymentMethod, setPaymentMethod] = useState("cod");
  const [fullName, setFullName] = useState(customer?.name || "");
  const [phone, setPhone] = useState(customer?.phone || "");
  const [email, setEmail] = useState(customer?.email || "");
  const [address, setAddress] = useState(customer?.address || "");
  const [referencePoint, setReferencePoint] = useState(customer?.reference_point || "");
  const [observation, setObservation] = useState("");

  const [couponInput, setCouponInput] = useState("");
  const [appliedCoupon, setAppliedCoupon] = useState(null);
  const [couponError, setCouponError] = useState("");
  const [checkingCoupon, setCheckingCoupon] = useState(false);

  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState("");

  const shipping = calculateShipping(subtotal);
  const shippingCost = shipping.cost ?? 0;
  const discountAmount = appliedCoupon?.discountAmount ?? 0;
  const total = Math.max(subtotal + shippingCost - discountAmount, 0);

  async function handleApplyCoupon() {
    if (!couponInput.trim()) return;
    setCouponError("");
    setCheckingCoupon(true);

    const { data, error } = await supabase
      .rpc("check_coupon", { p_code: couponInput.trim(), p_order_total: subtotal })
      .single();

    setCheckingCoupon(false);

    if (error || !data?.valid) {
      setCouponError(data?.message || "Não foi possível validar o cupom.");
      setAppliedCoupon(null);
      return;
    }
    setAppliedCoupon({ code: couponInput.trim().toUpperCase(), discountAmount: Number(data.discount_amount) });
  }

  function handleRemoveCoupon() {
    setAppliedCoupon(null);
    setCouponInput("");
    setCouponError("");
  }

  async function handleConfirm(e) {
    e.preventDefault();
    if (items.length === 0) return;

    if (!fullName.trim() || !phone.trim() || !address.trim()) {
      setFormError("Preencha ao menos nome completo, telefone e endereço.");
      return;
    }
    setFormError("");
    setSubmitting(true);

    try {
      let customerId = customer?.id || null;
      const customerPayload = {
        name: fullName.trim(),
        phone: phone.trim(),
        email: email.trim() || null,
        address: address.trim(),
        reference_point: referencePoint.trim() || null,
        stage: "cliente",
      };

      if (customerId) {
        await supabase.from("customers").update(customerPayload).eq("id", customerId);
      } else {
        const { data: existing } = await supabase
          .from("customers").select("id").eq("phone", phone.trim()).maybeSingle();
        if (existing) {
          customerId = existing.id;
          await supabase.from("customers").update(customerPayload).eq("id", customerId);
        } else {
          const { data: newCustomer, error: customerError } = await supabase
            .from("customers").insert({ ...customerPayload, source: "site" }).select("id").single();
          if (customerError) throw customerError;
          customerId = newCustomer.id;
        }
      }

      const { data: order, error: orderError } = await supabase
        .from("orders")
        .insert({
          customer_id: customerId,
          status: "pendente",
          payment_method: paymentMethod,
          shipping_cost: shippingCost,
          subtotal,
          total,
          notes: observation.trim() || null,
          coupon_code: appliedCoupon?.code || null,
          discount_amount: discountAmount,
        })
        .select("id, order_number")
        .single();
      if (orderError) throw orderError;

      const orderItems = items.map((i) => ({
        order_id: order.id,
        product_id: i.product.id,
        product_name: i.product.name,
        unit_price: i.product.price,
        quantity: i.quantity,
      }));
      const { error: itemsError } = await supabase.from("order_items").insert(orderItems);
      if (itemsError) throw itemsError;

      for (const i of items) {
        await supabase.rpc("decrement_stock", { p_product_id: i.product.id, p_quantity: i.quantity });
      }

      if (appliedCoupon) {
        await supabase.rpc("increment_coupon_usage", { p_code: appliedCoupon.code });
      }

      if (email.trim()) {
        try {
          await sendOrderConfirmationEmail({
            toEmail: email.trim(), customerName: fullName.trim(), orderNumber: order.order_number,
            items, subtotal, shippingCost, discountAmount, total, paymentMethod, address: address.trim(),
          });
        } catch (err) {
          console.warn("E-mail não enviado:", err);
        }
      }

      if (paymentMethod === "mercadopago") {
        try {
          const checkoutUrl = await createMercadoPagoCheckout({
            orderId: order.id, orderNumber: order.order_number, items, customerEmail: email.trim() || undefined,
          });
          clearCart();
          window.location.href = checkoutUrl;
          return;
        } catch (err) {
          setFormError(`Pedido nº ${order.order_number} criado, mas houve um problema com o pagamento: ${err.message}`);
          clearCart();
          setSubmitting(false);
          return;
        }
      }

      clearCart();
      router.push(`/checkout/sucesso?numero=${order.order_number}`);
    } catch (err) {
      setFormError(err.message || "Não foi possível finalizar o pedido. Tente novamente.");
      setSubmitting(false);
    }
  }

  return (
    <div className="min-h-screen bg-cream pb-10">
      <Header />
      <form onSubmit={handleConfirm} className="mx-auto max-w-2xl px-4 py-5">
        <h1 className="font-display text-2xl font-extrabold text-ink">Finalizar Pedido</h1>

        <section className="mt-5">
          <h2 className="font-display text-base font-bold text-ink">Seus dados</h2>
          <div className="mt-3 flex flex-col gap-2.5">
            <input required placeholder="Nome completo *" value={fullName} onChange={(e) => setFullName(e.target.value)} className="input" />
            <input required placeholder="Telefone / WhatsApp *" value={phone} onChange={(e) => setPhone(e.target.value)} disabled={!!customer} className="input disabled:bg-ink/5" />
            <input placeholder="E-mail (para receber a confirmação)" type="email" value={email} onChange={(e) => setEmail(e.target.value)} className="input" />
            <input required placeholder="Endereço completo *" value={address} onChange={(e) => setAddress(e.target.value)} className="input" />
            <input placeholder="Ponto de referência" value={referencePoint} onChange={(e) => setReferencePoint(e.target.value)} className="input" />
            <textarea placeholder="Observação (ex: horário de entrega, troco...)" value={observation} onChange={(e) => setObservation(e.target.value)} rows={3} className="input resize-none" />
          </div>
        </section>

        <section className="mt-6">
          <h2 className="font-display text-base font-bold text-ink">Cupom de desconto</h2>
          {appliedCoupon ? (
            <div className="mt-3 flex items-center gap-2 rounded-xl2 border border-success/30 bg-success/10 px-4 py-3">
              <Tag size={15} className="text-success" />
              <span className="flex-1 text-sm font-semibold text-success">
                {appliedCoupon.code} aplicado · -R$ {appliedCoupon.discountAmount.toFixed(2).replace(".", ",")}
              </span>
              <button type="button" onClick={handleRemoveCoupon}><X size={16} className="text-ink-soft" /></button>
            </div>
          ) : (
            <div className="mt-3 flex gap-2">
              <input
                placeholder="Digite o código"
                value={couponInput}
                onChange={(e) => setCouponInput(e.target.value)}
                className="input flex-1"
              />
              <button
                type="button"
                onClick={handleApplyCoupon}
                disabled={checkingCoupon}
                className="shrink-0 rounded-xl bg-ink px-5 text-sm font-bold text-white disabled:opacity-60"
              >
                {checkingCoupon ? "..." : "Aplicar"}
              </button>
            </div>
          )}
          {couponError && <p className="mt-1.5 text-xs text-red-600">{couponError}</p>}
        </section>

        <section className="mt-6 rounded-xl2 border border-ink/8 bg-white p-4">
          <div className="flex items-center justify-between">
            <span className="text-sm font-semibold text-ink">Frete</span>
            <span className="text-sm font-bold text-ink">
              {shipping.cost === 0 ? "Grátis" : shipping.cost === null ? "A calcular" : `R$ ${shippingCost.toFixed(2).replace(".", ",")}`}
            </span>
          </div>
          <p className="mt-1 text-xs text-ink-soft">{shipping.message}</p>
        </section>

        <section className="mt-6">
          <PaymentMethodSelector onSelect={setPaymentMethod} />
        </section>

        <section className="mt-6 rounded-xl2 border border-ink/8 bg-white p-4">
          <h2 className="font-display text-base font-bold text-ink">Resumo</h2>
          <div className="mt-3 flex flex-col gap-1.5 text-sm">
            <div className="flex justify-between text-ink-soft">
              <span>Subtotal</span><span>R$ {subtotal.toFixed(2).replace(".", ",")}</span>
            </div>
            <div className="flex justify-between text-ink-soft">
              <span>Frete</span><span>{shipping.cost === 0 ? "Grátis" : shipping.cost === null ? "—" : `R$ ${shippingCost.toFixed(2).replace(".", ",")}`}</span>
            </div>
            {discountAmount > 0 && (
              <div className="flex justify-between text-success">
                <span>Desconto</span><span>-R$ {discountAmount.toFixed(2).replace(".", ",")}</span>
              </div>
            )}
            <div className="mt-2 flex justify-between border-t border-ink/10 pt-2 font-display text-base font-extrabold text-ink">
              <span>Total</span><span>R$ {total.toFixed(2).replace(".", ",")}</span>
            </div>
          </div>
        </section>

        {formError && <p className="mt-4 text-sm font-semibold text-red-600">{formError}</p>}

        <button
          type="submit"
          disabled={submitting}
          className="mt-6 w-full rounded-2xl bg-brand py-4 font-display text-base font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-60"
        >
          {submitting ? "Processando…" : "Confirmar Pedido"}
        </button>
      </form>

      <style jsx global>{`
        .input {
          width: 100%;
          border: 1px solid rgba(22, 36, 61, 0.12);
          border-radius: 14px;
          padding: 12px 14px;
          font-size: 14px;
          outline: none;
          background: white;
        }
        .input:focus {
          border-color: #ff6b1a;
        }
      `}</style>
    </div>
  );
}
