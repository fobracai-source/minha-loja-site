"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { Minus, Plus, Trash2, ShoppingBag } from "lucide-react";
import Header from "../../components/Header";
import { useCart } from "../../context/CartContext";

export default function CartPage() {
  const { items, updateQuantity, removeItem, subtotal, hydrated } = useCart();
  const router = useRouter();

  if (hydrated && items.length === 0) {
    return (
      <div className="min-h-screen bg-cream">
        <Header />
        <div className="flex flex-col items-center justify-center px-6 py-24 text-center">
          <ShoppingBag size={40} className="text-ink/20" />
          <p className="mt-4 font-display text-lg font-bold text-ink">Seu carrinho está vazio</p>
          <p className="mt-1 text-sm text-ink-soft">Que tal dar uma olhada no catálogo?</p>
          <Link href="/" className="mt-5 rounded-full bg-brand px-6 py-3 text-sm font-bold text-white">
            Ver produtos
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-cream pb-40 md:pb-10">
      <Header />
      <div className="mx-auto max-w-2xl px-4 py-5">
        <h1 className="font-display text-2xl font-extrabold text-ink">Carrinho</h1>

        <div className="mt-4 flex flex-col gap-3">
          {items.map((item) => (
            <div key={item.product.id} className="flex gap-3 rounded-xl2 border border-ink/8 bg-white p-3">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              {item.product.image_url ? (
                <img src={item.product.image_url} alt="" className="h-16 w-16 shrink-0 rounded-lg object-cover" />
              ) : (
                <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-lg bg-brand-light/40 text-xl">🐾</div>
              )}
              <div className="min-w-0 flex-1">
                <p className="line-clamp-2 text-sm font-semibold text-ink">{item.product.name}</p>
                <p className="mt-1 font-display font-bold text-ink">
                  R$ {Number(item.product.price).toFixed(2).replace(".", ",")}
                </p>
                <div className="mt-2 flex items-center gap-2">
                  <button
                    onClick={() => updateQuantity(item.product.id, item.quantity - 1)}
                    className="flex h-7 w-7 items-center justify-center rounded-full border border-ink/15"
                  >
                    <Minus size={13} />
                  </button>
                  <span className="w-5 text-center text-sm font-bold">{item.quantity}</span>
                  <button
                    onClick={() => updateQuantity(item.product.id, item.quantity + 1)}
                    className="flex h-7 w-7 items-center justify-center rounded-full border border-ink/15"
                  >
                    <Plus size={13} />
                  </button>
                  <button
                    onClick={() => removeItem(item.product.id)}
                    className="ml-auto flex h-7 w-7 items-center justify-center rounded-full text-red-500"
                  >
                    <Trash2 size={15} />
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="fixed bottom-16 left-0 right-0 z-30 border-t border-ink/10 bg-white p-4 md:sticky md:bottom-0 md:mx-auto md:max-w-2xl md:rounded-t-2xl">
        <div className="mb-3 flex items-center justify-between">
          <span className="text-sm text-ink-soft">Subtotal</span>
          <span className="font-display text-lg font-extrabold text-ink">
            R$ {subtotal.toFixed(2).replace(".", ",")}
          </span>
        </div>
        <button
          onClick={() => router.push("/checkout")}
          className="w-full rounded-2xl bg-brand py-3.5 font-display text-base font-bold text-white transition-transform active:scale-[0.98]"
        >
          Finalizar Pedido
        </button>
      </div>
    </div>
  );
}
