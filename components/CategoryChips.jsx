"use client";

export default function CategoryChips({ categories, active, onSelect }) {
  return (
    <div className="scrollbar-hide flex gap-2 overflow-x-auto px-4 py-3">
      <button
        onClick={() => onSelect(null)}
        className={`shrink-0 rounded-full px-4 py-2 text-sm font-semibold transition-colors ${
          active === null ? "bg-ink text-white" : "bg-white text-ink-soft border border-ink/10"
        }`}
      >
        Tudo
      </button>
      {categories.map((c) => (
        <button
          key={c}
          onClick={() => onSelect(c)}
          className={`shrink-0 rounded-full px-4 py-2 text-sm font-semibold transition-colors ${
            active === c ? "bg-ink text-white" : "bg-white text-ink-soft border border-ink/10"
          }`}
        >
          {c}
        </button>
      ))}
    </div>
  );
}
