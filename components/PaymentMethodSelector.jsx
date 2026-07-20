"use client";

import { useEffect, useState } from "react";
import { Truck, CreditCard, Wallet, Landmark, Lock, Clock } from "lucide-react";
import { supabase } from "../lib/supabaseClient";

const PAYMENT_INFO = {
  cod: { label: "Pagar na Entrega", description: "Dinheiro, débito ou crédito com o entregador", icon: Truck },
  mercadopago: { label: "Mercado Pago", description: "Pix, boleto ou cartão via Mercado Pago", icon: Wallet },
  stripe: { label: "Cartão de Crédito (Stripe)", description: "Pagamento internacional com cartão", icon: CreditCard },
  pagbank: { label: "PagBank", description: "Pix, boleto ou cartão via PagBank", icon: Landmark },
};

export default function PaymentMethodSelector({ onSelect }) {
  const [methods, setMethods] = useState([]);
  const [selected, setSelected] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadSettings() {
      const { data } = await supabase.from("payment_settings").select("*");
      const merged = (data || [])
        .filter((s) => PAYMENT_INFO[s.id])
        .map((s) => ({ id: s.id, enabled: s.enabled, ...PAYMENT_INFO[s.id] }));
      setMethods(merged);
      const def = merged.find((m) => m.enabled)?.id ?? null;
      setSelected(def);
      if (def) onSelect?.(def);
      setLoading(false);
    }
    loadSettings();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function handleSelect(m) {
    if (!m.enabled) return;
    setSelected(m.id);
    onSelect?.(m.id);
  }

  if (loading) return <div className="h-24 animate-pulse rounded-xl2 bg-ink/5" />;

  return (
    <div>
      <h2 className="font-display text-base font-bold text-ink">Forma de pagamento</h2>
      <div className="mt-3 flex flex-col gap-2">
        {methods.map((m) => {
          const Icon = m.icon;
          const isSelected = selected === m.id;
          return (
            <button
              key={m.id}
              type="button"
              onClick={() => handleSelect(m)}
              disabled={!m.enabled}
              className={`flex items-center gap-3 rounded-xl2 border p-3.5 text-left transition-colors ${
                !m.enabled
                  ? "cursor-not-allowed border-ink/8 bg-ink/[0.02] opacity-60"
                  : isSelected
                  ? "border-brand bg-brand-light/30"
                  : "border-ink/10 hover:border-ink/20"
              }`}
            >
              <span className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full ${m.enabled ? "bg-ink text-white" : "bg-ink/10 text-ink/30"}`}>
                <Icon size={16} />
              </span>
              <span className="min-w-0 flex-1">
                <span className="flex items-center gap-2">
                  <span className="text-sm font-semibold text-ink">{m.label}</span>
                  {!m.enabled && (
                    <span className="flex items-center gap-1 rounded-full bg-ink/10 px-2 py-0.5 text-[10px] font-semibold text-ink-soft">
                      <Clock size={9} /> Indisponível
                    </span>
                  )}
                </span>
                <span className="mt-0.5 block text-xs text-ink-soft">{m.description}</span>
              </span>
              {m.enabled && (
                <span className={`h-4 w-4 shrink-0 rounded-full border-2 ${isSelected ? "border-brand bg-brand" : "border-ink/20"}`} />
              )}
            </button>
          );
        })}
      </div>
      <p className="mt-3 flex items-center gap-1.5 text-[11px] text-ink-soft/70">
        <Lock size={11} /> Seus dados de pagamento estão protegidos
      </p>
    </div>
  );
}
