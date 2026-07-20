"use client";

import { useEffect, useState } from "react";
import { Phone, User, LogOut, Package } from "lucide-react";
import Header from "../../components/Header";
import { useAuth } from "../../context/AuthContext";
import { supabase } from "../../lib/supabaseClient";

const STATUS_LABELS = {
  pendente: "Pendente", confirmado: "Confirmado", enviado: "Enviado", entregue: "Entregue", cancelado: "Cancelado",
};

function LoginForm() {
  const { loginWithPhone } = useAuth();
  const [phone, setPhone] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    const digits = phone.replace(/\D/g, "");
    if (digits.length < 10) {
      setError("Informe o DDD + telefone (ex: 11987654321).");
      return;
    }
    setError("");
    setSubmitting(true);
    try {
      await loginWithPhone(digits);
    } catch (err) {
      setError(err.message || "Não foi possível entrar. Tente novamente.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mx-auto flex max-w-sm flex-col items-center px-6 py-10 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-full bg-ink">
        <Phone size={24} className="text-white" />
      </div>
      <h1 className="mt-4 font-display text-xl font-extrabold text-ink">Entrar na sua conta</h1>
      <p className="mt-2 text-sm text-ink-soft">
        Digite seu telefone com DDD. Não precisa de senha — usamos o número pra guardar seus pedidos e dados de entrega.
      </p>
      <input
        value={phone}
        onChange={(e) => setPhone(e.target.value)}
        placeholder="DDD + telefone (ex: 11987654321)"
        className="input mt-5 w-full"
      />
      {error && <p className="mt-2 text-xs font-semibold text-red-600">{error}</p>}
      <button
        type="submit"
        disabled={submitting}
        className="mt-4 w-full rounded-2xl bg-brand py-3.5 font-display text-base font-bold text-white disabled:opacity-60"
      >
        {submitting ? "Entrando…" : "Entrar"}
      </button>
      <style jsx global>{`
        .input {
          border: 1px solid rgba(22, 36, 61, 0.12);
          border-radius: 14px;
          padding: 12px 14px;
          font-size: 14px;
          outline: none;
        }
      `}</style>
    </form>
  );
}

function ProfileAndOrders() {
  const { customer, logout } = useAuth();
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadOrders() {
      const { data } = await supabase
        .from("orders")
        .select("*, order_items(product_name, quantity)")
        .eq("customer_id", customer.id)
        .order("created_at", { ascending: false });
      setOrders(data || []);
      setLoading(false);
    }
    if (customer) loadOrders();
  }, [customer]);

  return (
    <div className="mx-auto max-w-xl px-4 py-6">
      <div className="flex items-center gap-3 rounded-xl2 border border-ink/8 bg-white p-4">
        <div className="flex h-11 w-11 items-center justify-center rounded-full bg-ink">
          <User size={20} className="text-white" />
        </div>
        <div className="flex-1">
          <p className="text-sm font-bold text-ink">{customer.name || "Sem nome cadastrado"}</p>
          <p className="text-xs text-ink-soft">{customer.phone}</p>
        </div>
        <button onClick={logout} className="text-red-500"><LogOut size={18} /></button>
      </div>

      <h2 className="mt-6 font-display text-lg font-bold text-ink">Meus pedidos</h2>

      {loading ? (
        <div className="mt-4 space-y-2">
          {Array.from({ length: 3 }).map((_, i) => <div key={i} className="h-16 animate-pulse rounded-xl2 bg-ink/5" />)}
        </div>
      ) : orders.length === 0 ? (
        <div className="mt-6 flex flex-col items-center py-10 text-center">
          <Package size={30} className="text-ink/20" />
          <p className="mt-3 text-sm text-ink-soft">Você ainda não fez nenhum pedido.</p>
        </div>
      ) : (
        <div className="mt-3 flex flex-col gap-2">
          {orders.map((o) => (
            <div key={o.id} className="rounded-xl2 border border-ink/8 bg-white p-3.5">
              <div className="flex justify-between text-sm">
                <span className="font-bold text-ink">Pedido #{o.order_number}</span>
                <span className="font-semibold text-ink-soft">{STATUS_LABELS[o.status] || o.status}</span>
              </div>
              <p className="mt-1 text-xs text-ink-soft">
                {new Date(o.created_at).toLocaleDateString("pt-BR")} · {o.order_items?.length || 0} item(ns)
              </p>
              <p className="mt-1.5 font-display font-bold text-ink">
                R$ {Number(o.total).toFixed(2).replace(".", ",")}
              </p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default function AccountPage() {
  const { customer, loading } = useAuth();

  return (
    <div className="min-h-screen bg-cream pb-16">
      <Header />
      {loading ? (
        <div className="p-8 text-center text-sm text-ink-soft">Carregando…</div>
      ) : customer ? (
        <ProfileAndOrders />
      ) : (
        <LoginForm />
      )}
    </div>
  );
}
