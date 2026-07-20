"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { CheckCircle2 } from "lucide-react";
import Header from "../../../components/Header";

export default function CheckoutSuccessPage() {
  const params = useSearchParams();
  const orderNumber = params.get("numero");

  return (
    <div className="min-h-screen bg-cream">
      <Header />
      <div className="mx-auto flex max-w-md flex-col items-center px-6 py-20 text-center">
        <CheckCircle2 size={56} className="text-success" />
        <h1 className="mt-5 font-display text-2xl font-extrabold text-ink">Pedido confirmado!</h1>
        {orderNumber && (
          <p className="mt-2 text-lg font-bold text-brand-dark">Pedido nº {orderNumber}</p>
        )}
        <p className="mt-3 text-sm text-ink-soft">
          Se você informou um e-mail, enviamos os detalhes por lá. Em breve entraremos em contato
          para combinar a entrega.
        </p>
        <Link href="/" className="mt-8 rounded-full bg-brand px-6 py-3 text-sm font-bold text-white">
          Voltar para a loja
        </Link>
      </div>
    </div>
  );
}
