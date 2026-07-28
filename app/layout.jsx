import { Baloo_2, Inter } from "next/font/google";
import "./globals.css";
import { CartProvider } from "../context/CartContext";
import { AuthProvider } from "../context/AuthContext";
import BottomNav from "../components/BottomNav";
const baloo = Baloo_2({ subsets: ["latin"], variable: "--font-display", weight: ["600", "700", "800"] });
const inter = Inter({ subsets: ["latin"], variable: "--font-body", weight: ["400", "500", "600", "700"] });
export const metadata = {
  title: "Cão&Cão · Tudo para o seu pet",
  description: "Ração, brinquedos e acessórios para o seu melhor amigo, com entrega rápida.",
};
export default function RootLayout({ children }) {
  return (
    <html lang="pt-BR" className={`${baloo.variable} ${inter.variable}`}>
      <body className="font-body">
        <AuthProvider>
          <CartProvider>
            <div className="pb-16 md:pb-0">{children}</div>
            <footer
              style={{
                textAlign: "center",
                fontSize: 11,
                color: "#a3a3a3",
                padding: "18px 16px 24px",
              }}
            >
              <a href="/politica-privacidade" style={{ textDecoration: "underline" }}>Política de Privacidade</a>
              <br />
              Desenvolvido por Fabrício da Silva França, para fins didáticos
            </footer>
            <BottomNav />
            <svg className="walking-dog" viewBox="0 0 64 40" aria-hidden="true">
              <ellipse cx="30" cy="30" rx="18" ry="8" fill="#16243D" />
              <rect x="14" y="18" width="30" height="14" rx="7" fill="#FF6B1A" />
              <circle cx="44" cy="16" r="9" fill="#FF6B1A" />
              <ellipse cx="38" cy="9" rx="3" ry="5" fill="#FF6B1A" transform="rotate(-25 38 9)" />
              <ellipse cx="49" cy="9" rx="3" ry="5" fill="#FF6B1A" transform="rotate(25 49 9)" />
              <circle cx="47" cy="15" r="1.6" fill="#16243D" />
              <ellipse cx="50" cy="19" rx="2" ry="1.4" fill="#16243D" />
              <rect x="18" y="30" width="4" height="8" rx="2" fill="#16243D" />
              <rect x="28" y="30" width="4" height="8" rx="2" fill="#16243D" />
              <rect x="36" y="30" width="4" height="8" rx="2" fill="#16243D" />
              <path d="M14 22 Q4 20 8 30" stroke="#16243D" strokeWidth="4" fill="none" strokeLinecap="round" />
            </svg>
          </CartProvider>
        </AuthProvider>

        <style jsx global>{`
          .walking-dog {
            position: fixed;
            bottom: 72px;
            left: -60px;
            width: 56px;
            height: 35px;
            z-index: 20;
            pointer-events: none;
            animation: walk-across 16s linear infinite, bob 0.5s ease-in-out infinite;
          }
          @keyframes walk-across {
            0% { left: -60px; }
            45% { left: 100vw; }
            45.01% { left: -60px; opacity: 0; }
            48% { opacity: 0; }
            48.01% { opacity: 1; }
            100% { left: -60px; opacity: 1; }
          }
          @keyframes bob {
            0%, 100% { transform: translateY(0); }
            50% { transform: translateY(-4px); }
          }
          @media (min-width: 768px) {
            .walking-dog { display: none; }
          }
        `}</style>
      </body>
    </html>
  );
}
