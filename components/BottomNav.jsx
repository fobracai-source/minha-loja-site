"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Home, ShoppingBag, User } from "lucide-react";
import { useCart } from "../context/CartContext";

const ITEMS = [
  { href: "/", label: "Início", icon: Home },
  { href: "/carrinho", label: "Carrinho", icon: ShoppingBag },
  { href: "/conta", label: "Conta", icon: User },
];

export default function BottomNav() {
  const pathname = usePathname();
  const { itemCount } = useCart();

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-40 flex items-center justify-around border-t border-ink/10 bg-white/95 backdrop-blur px-2 py-2 md:hidden">
      {ITEMS.map((item) => {
        const Icon = item.icon;
        const active = pathname === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
            className={`relative flex flex-col items-center gap-0.5 px-4 py-1 rounded-xl2 transition-colors ${
              active ? "text-brand" : "text-ink-soft"
            }`}
          >
            <Icon size={22} strokeWidth={active ? 2.4 : 2} />
            <span className="text-[10.5px] font-semibold">{item.label}</span>
            {item.href === "/carrinho" && itemCount > 0 && (
              <span className="absolute -top-0.5 right-2 flex h-4 min-w-4 items-center justify-center rounded-full bg-brand px-1 text-[10px] font-bold text-white">
                {itemCount}
              </span>
            )}
          </Link>
        );
      })}
    </nav>
  );
}
