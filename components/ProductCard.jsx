"use client";

import Link from "next/link";
import { Plus } from "lucide-react";
import { useCart } from "../context/CartContext";

export default function ProductCard({ product }) {
  const { addItem } = useCart();
  const hasDiscount = product.promotional_price && product.promotional_price !== product.price;
  const effectivePrice = product.promotional_price ?? product.price;
  const discountPercent = hasDiscount
    ? Math.round(((product.price - product.promotional_price) / product.price) * 100)
    : null;
  const outOfStock = product.stock === 0;

  return (
    <div className="group relative flex flex-col overflow-hidden rounded-xl2 border border-ink/8 bg-white transition-shadow hover:shadow-lg hover:shadow-ink/5">
      <Link href={`/produto/${product.id}`} className="relative block aspect-square bg-brand-light/40">
        {product.image_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={product.image_url} alt={product.name} className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full w-full items-center justify-center text-3xl">🐾</div>
        )}
        {hasDiscount && (
          <span className="absolute left-2 top-2 rounded-full bg-success px-2 py-0.5 text-[11px] font-bold text-white">
            -{discountPercent}%
          </span>
        )}
        {outOfStock && (
          <div className="absolute inset-0 flex items-center justify-center bg-white/70 backdrop-blur-[1px]">
            <span className="rounded-full bg-ink px-3 py-1 text-[11px] font-bold text-white">Esgotado</span>
          </div>
        )}
      </Link>

      <div className="flex flex-1 flex-col p-3">
        {product.category && (
          <span className="text-[10.5px] font-bold uppercase tracking-wide text-brand-dark">{product.category}</span>
        )}
        <Link href={`/produto/${product.id}`} className="mt-0.5 line-clamp-2 min-h-[2.4em] text-[13.5px] font-semibold leading-tight text-ink">
          {product.name}
        </Link>

        <div className="mt-auto flex items-end justify-between pt-2">
          <div>
            {hasDiscount && (
              <div className="text-[11px] text-ink-soft/60 line-through">
                R$ {Number(product.price).toFixed(2).replace(".", ",")}
              </div>
            )}
            <div className="font-display text-[17px] font-bold text-ink">
              R$ {Number(effectivePrice).toFixed(2).replace(".", ",")}
            </div>
          </div>
          <button
            onClick={() => !outOfStock && addItem({ ...product, price: effectivePrice, originalPrice: product.price })}
            disabled={outOfStock}
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-brand text-white transition-transform active:scale-90 disabled:bg-ink/10 disabled:text-ink/30"
          >
            <Plus size={18} strokeWidth={2.5} />
          </button>
        </div>
      </div>
    </div>
  );
}
