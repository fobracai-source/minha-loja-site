"use client";

import { useEffect, useMemo, useState } from "react";
import Header from "../components/Header";
import CategoryChips from "../components/CategoryChips";
import ProductCard from "../components/ProductCard";
import { supabase } from "../lib/supabaseClient";

export default function HomePage() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [activeCategory, setActiveCategory] = useState(null);

  useEffect(() => {
    async function loadProducts() {
      const { data } = await supabase
        .from("products")
        .select("*")
        .eq("active", true)
        .order("created_at", { ascending: false });
      setProducts(data || []);
      setLoading(false);
    }
    loadProducts();
  }, []);

  const categories = useMemo(
    () => [...new Set(products.map((p) => p.category).filter(Boolean))],
    [products]
  );

  const filtered = products
    .filter((p) => !activeCategory || p.category === activeCategory)
    .filter((p) => p.name.toLowerCase().includes(search.toLowerCase()));

  return (
    <div className="min-h-screen bg-cream">
      <Header search={search} onSearchChange={setSearch} />

      <section className="bg-ink px-4 pb-8 pt-2 md:pb-10">
        <div className="mx-auto max-w-6xl">
          <h1 className="font-display text-2xl font-extrabold leading-tight text-white md:text-3xl">
            Tudo para o seu <span className="text-brand">melhor amigo</span> 🐾
          </h1>
          <p className="mt-1.5 max-w-md text-sm text-white/70">
            Ração, brinquedos, higiene e acessórios com entrega rápida e o carinho que seu pet merece.
          </p>
        </div>
      </section>

      <div className="mx-auto max-w-6xl">
        <div className="-mt-5 rounded-t-[28px] bg-cream pt-1">
          <CategoryChips categories={categories} active={activeCategory} onSelect={setActiveCategory} />

          <div className="px-4 pb-24 pt-2 md:pb-10">
            {loading ? (
              <div className="grid grid-cols-2 gap-3 md:grid-cols-4 lg:grid-cols-5">
                {Array.from({ length: 8 }).map((_, i) => (
                  <div key={i} className="aspect-[3/4.2] animate-pulse rounded-xl2 bg-ink/5" />
                ))}
              </div>
            ) : filtered.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-20 text-center">
                <span className="text-4xl">🔎</span>
                <p className="mt-3 font-display text-lg font-bold text-ink">Nenhum produto encontrado</p>
                <p className="mt-1 text-sm text-ink-soft">Tente buscar por outro nome ou categoria.</p>
              </div>
            ) : (
              <div className="grid grid-cols-2 gap-3 md:grid-cols-4 lg:grid-cols-5">
                {filtered.map((p) => (
                  <ProductCard key={p.id} product={p} />
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
