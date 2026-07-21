import { Baloo_2, Inter } from "next/font/google";
import "./globals.css";
import { CartProvider } from "../context/CartContext";
import { AuthProvider } from "../context/AuthContext";
import BottomNav from "../components/BottomNav";
const baloo = Baloo_2({ subsets: ["latin"], variable: "--font-display", weight: ["600", "700", "800"] });
const inter = Inter({ subsets: ["latin"], variable: "--font-body", weight: ["400", "500", "600", "700"] });
export const metadata = {
  title: "Minha Loja · Tudo para o seu pet",
  description: "Ração, brinquedos e acessórios para o seu melhor amigo, com entrega rápida.",
};
export default function RootLayout({ children }) {
  return (
    <html lang="pt-BR" className={`${baloo.variable} ${inter.variable}`}>
      <body className="font-body">
        <AuthProvider>
          <CartProvider>
            <div className="pb-16 md:pb-0">
              {children}
              <footer
                style={{
                  textAlign: "center",
                  fontSize: 11,
                  color: "#a3a3a3",
                  padding: "18px 16px 24px",
                }}
              >
                Site desenvolvido por Fabrício da Silva Franca, para fins educativos
              </footer>
            </div>
            <BottomNav />
          </CartProvider>
        </AuthProvider>
      </body>
    </html>
  );
}
