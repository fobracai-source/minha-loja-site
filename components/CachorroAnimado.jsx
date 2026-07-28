import Image from 'next/image';

export default function CachorroAnimado() {
  return (
    <div className="cachorro-wrapper">
      <Image
        src="https://mqpqmkpqesqnbchucvfs.supabase.co/storage/v1/object/public/Imagens/cachorro-web.webp"
        alt="Cachorro mascote Cão&Cão"
        width={200}
        height={200}
        priority
        className="cachorro-animado"
      />
    </div>
  );
}
