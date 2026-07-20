"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { ArrowLeft, ZoomIn, X } from "lucide-react";
import Header from "../../../components/Header";
import { supabase } from "../../../lib/supabaseClient";
import { useCart } from "../../../context/CartContext";

export default function ProductDetailPage() {
  const { id } = useParams();
  const router = useRouter();
  const { addItem } = useCart();

  const [product, setProduct] = useState(null);
  const [loading, setLoading] = useState(true);
  const [activeImage, setActiveImage] = useState(0);
  const [zoomOpen, setZoomOpen] = useState(false);
  const [added, setAdded] = useState(false);

  useEffect(() => {
    async function loadProduct() {
      const { data } = await supabase.from("products").select("*").eq("id", id).single();
      setProduct(data);
      setLoading(false);
    }
    loadProduct();
  }, [id]);

  if (loading) {
    return (
      <div className="min-h-screen bg-cream">
        <Header />
        <div className="mx-auto max-w-3xl animate-pulse px-4 py-8">
          <div className="aspect-square rounded-xl2 bg-ink/5" />
        </div>
      </div>
    );
  }

  if (!product) {
    return (
      <div className="min-h-screen bg-cream">
        <Header />
        <p className="p-8 text-center text-ink-soft">Produto não encontrado.</p>
      </div>
    );
  }

  const images = product.image_urls?.length ? product.image_urls : product.image_url ? [product.image_url] : [];
  const hasDiscount = product.promotional_price && product.promotional_price !== product.price;
  const effectivePrice = product.promotional_price ?? product.price;
  const outOfStock = product.stock === 0;

  function handleAddToCart() {
    if (outOfStock) return;
    addItem({ ...product, price: effectivePrice, originalPrice: product.price });
    setAdded(true);
    setTimeout(() => setAdded(false), 1800);
  }

  return (
    <div className="min-h-screen bg-cream pb-28 md:pb-10">
      <Header />

      <div className="mx-auto max-w-5xl px-4 py-4 md:grid md:grid-cols-2 md:gap-10 md:py-8">
        {/* Galeria */}
        <div>
          <div className="flex items-center gap-2 md:hidden">
            <button onClick={() => router.back()} className="flex items-center gap-1 text-sm font-semibold text-ink-soft">
              <ArrowLeft size={16} /> Voltar
            </button>
          </div>

          <button
            onClick={() => images.length > 0 && setZoomOpen(true)}
            className="relative mt-2 block aspect-square w-full overflow-hidden rounded-xl2 bg-brand-light/40"
          >
            {images.length > 0 ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={images[activeImage]} alt={product.name} className="h-full w-full object-cover" />
            ) : (
              <div className="flex h-full items-center justify-center text-5xl">🐾</div>
            )}
            {images.length > 0 && (
              <span className="absolute bottom-3 right-3 flex items-center gap-1 rounded-full bg-ink/70 px-3 py-1.5 text-[11px] font-semibold text-white">
                <ZoomIn size={13} /> Ampliar
              </span>
            )}
          </button>

          {images.length > 1 && (
            <div className="scrollbar-hide mt-3 flex gap-2 overflow-x-auto">
              {images.map((url, i) => (
                <button
                  key={url + i}
                  onClick={() => setActiveImage(i)}
                  className={`h-16 w-16 shrink-0 overflow-hidden rounded-lg border-2 ${
                    i === activeImage ? "border-brand" : "border-transparent"
                  }`}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={url} alt="" className="h-full w-full object-cover" />
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Informações */}
        <div className="mt-5 md:mt-0">
          {product.category && (
            <span className="text-[11px] font-bold uppercase tracking-wide text-brand-dark">{product.category}</span>
          )}
          <h1 className="mt-1 font-display text-2xl font-extrabold text-ink">{product.name}</h1>
          {product.brand && <p className="mt-1 text-sm text-ink-soft">Marca: {product.brand}</p>}

          <div className="mt-4 flex items-end gap-2">
            {hasDiscount && (
              <span className="text-sm text-ink-soft/60 line-through">
                R$ {Number(product.price).toFixed(2).replace(".", ",")}
              </span>
            )}
            <span className="font-display text-3xl font-extrabold text-ink">
              R$ {Number(effectivePrice).toFixed(2).replace(".", ",")}
            </span>
          </div>

          {outOfStock ? (
            <span className="mt-3 inline-block rounded-full bg-red-50 px-3 py-1 text-xs font-bold text-red-600">
              Fora de estoque
            </span>
          ) : product.stock <= 5 ? (
            <span className="mt-3 inline-block text-xs font-bold text-amber-600">Últimas {product.stock} unidades</span>
          ) : null}

          {product.description && (
            <>
              <h2 className="mt-6 font-display text-base font-bold text-ink">Descrição</h2>
              <p className="mt-1.5 whitespace-pre-line text-sm leading-relaxed text-ink-soft">{product.description}</p>
            </>
          )}

          {(product.weight_kg || product.height_cm || product.width_cm || product.depth_cm) && (
            <>
              <h2 className="mt-5 font-display text-base font-bold text-ink">Dimensões</h2>
              <p className="mt-1.5 text-sm text-ink-soft">
                {product.weight_kg && `Peso: ${product.weight_kg}kg  `}
                {product.height_cm && `Altura: ${product.height_cm}cm  `}
                {product.width_cm && `Largura: ${product.width_cm}cm  `}
                {product.depth_cm && `Profundidade: ${product.depth_cm}cm`}
              </p>
            </>
          )}

          <button
            onClick={handleAddToCart}
            disabled={outOfStock}
            className="mt-8 hidden w-full rounded-2xl bg-brand py-3.5 font-display text-base font-bold text-white transition-transform active:scale-[0.98] disabled:bg-ink/15 disabled:text-ink/40 md:block"
          >
            {outOfStock ? "Indisponível" : added ? "Adicionado! ✓" : "Adicionar ao carrinho"}
          </button>
        </div>
      </div>

      {/* Botão fixo no mobile */}
      <div className="fixed bottom-16 left-0 right-0 z-30 border-t border-ink/10 bg-white p-3 md:hidden">
        <button
          onClick={handleAddToCart}
          disabled={outOfStock}
          className="w-full rounded-2xl bg-brand py-3.5 font-display text-base font-bold text-white transition-transform active:scale-[0.98] disabled:bg-ink/15 disabled:text-ink/40"
        >
          {outOfStock ? "Indisponível" : added ? "Adicionado! ✓" : "Adicionar ao carrinho"}
        </button>
      </div>

      {/* Zoom em tela cheia */}
      {zoomOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/90 p-4" onClick={() => setZoomOpen(false)}>
          <button className="absolute right-4 top-4 text-white" onClick={() => setZoomOpen(false)}>
            <X size={28} />
          </button>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={images[activeImage]} alt={product.name} className="max-h-full max-w-full object-contain" />
        </div>
      )}
    </div>
  );
}
