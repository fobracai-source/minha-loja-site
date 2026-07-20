"use client";

import Link from "next/link";
import { Search, ShoppingBag, User } from "lucide-react";
import { useCart } from "../context/CartContext";

export default function Header({ search, onSearchChange }) {
  const { itemCount } = useCart();

  return (
    <header className="sticky top-0 z-30 bg-ink">
      <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3">
        <Link href="/" className="flex items-center gap-1.5 shrink-0">
          <span className="text-2xl">🐾</span>
          <span className="font-display text-xl font-extrabold text-white">
            Minha<span className="text-brand">Loja</span>
          </span>
        </Link>

        {onSearchChange && (
          <div className="hidden flex-1 md:flex">
            <div className="flex w-full items-center gap-2 rounded-full bg-white/10 px-4 py-2.5 focus-within:bg-white/15">
              <Search size={17} className="text-white/60 shrink-0" />
              <input
                value={search}
                onChange={(e) => onSearchChange(e.target.value)}
                placeholder="Buscar ração, brinquedos, acessórios…"
                className="w-full bg-transparent text-sm text-white placeholder:text-white/50 outline-none"
              />
            </div>
          </div>
        )}

        <div className="ml-auto hidden items-center gap-5 md:flex">
          <Link href="/conta" className="flex items-center gap-1.5 text-sm font-semibold text-white/90 hover:text-white">
            <User size={19} /> Conta
          </Link>
          <Link href="/carrinho" className="relative flex items-center gap-1.5 text-sm font-semibold text-white/90 hover:text-white">
            <ShoppingBag size={19} />
            Carrinho
            {itemCount > 0 && (
              <span className="absolute -right-3 -top-2 flex h-4 min-w-4 items-center justify-center rounded-full bg-brand px-1 text-[10px] font-bold text-white">
                {itemCount}
              </span>
            )}
          </Link>
        </div>
      </div>

      {onSearchChange && (
        <div className="px-4 pb-3 md:hidden">
          <div className="flex items-center gap-2 rounded-full bg-white/10 px-4 py-2.5">
            <Search size={17} className="text-white/60 shrink-0" />
            <input
              value={search}
              onChange={(e) => onSearchChange(e.target.value)}
              placeholder="Buscar produtos…"
              className="w-full bg-transparent text-sm text-white placeholder:text-white/50 outline-none"
            />
          </div>
        </div>
      )}
    </header>
  );
}
