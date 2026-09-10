/* Ícones do menu e do header. Todos desenhados na grade 24×24, só contorno —
   a cor vem do `currentColor` de quem embrulha o <svg>. */

const SHAPES = {
  dashboard: (
    <>
      <rect x="3" y="3" width="7" height="9" rx="1.6" />
      <rect x="14" y="3" width="7" height="5" rx="1.6" />
      <rect x="14" y="12" width="7" height="9" rx="1.6" />
      <rect x="3" y="16" width="7" height="5" rx="1.6" />
    </>
  ),
  families: (
    <>
      <path d="M16 19.5V18a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v1.5" />
      <circle cx="9" cy="7" r="3.2" />
      <path d="M22 19.5V18a4 4 0 0 0-3-3.87" />
      <path d="M16 4.2a4 4 0 0 1 0 7.6" />
    </>
  ),
  chat: (
    <>
      <path d="M20.5 11.6a8 8 0 0 1-8.6 8 8.6 8.6 0 0 1-3.6-.9L3.5 20.5l1.8-4.8a8 8 0 0 1-.9-3.6 8 8 0 0 1 8-8.6 8 8 0 0 1 8.1 8.1z" />
      <path d="M8.6 11.6h.01M12 11.6h.01M15.4 11.6h.01" />
    </>
  ),
  newEnroll: (
    <>
      <path d="M14.5 19.5V18a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v1.5" />
      <circle cx="8.2" cy="7" r="3.2" />
      <path d="M19 7.5v6M22 10.5h-6" />
    </>
  ),
  enrolled: (
    <>
      <path d="M21 9.4 12 5 3 9.4l9 4.4 9-4.4Z" />
      <path d="M6.8 11.6V16c0 1.5 2.3 2.7 5.2 2.7s5.2-1.2 5.2-2.7v-4.4" />
      <path d="M21 9.4v5.8" />
    </>
  ),
  automation: (
    <>
      <path d="M12 2.5v2.3" />
      <rect x="3.5" y="6.8" width="17" height="12" rx="3.4" />
      <path d="M8.6 12.2v1.6M15.4 12.2v1.6" />
      <path d="M1.8 11.6v2.9M22.2 11.6v2.9" />
    </>
  ),
  signature: (
    <>
      <path d="M14 2.8H7.4a2 2 0 0 0-2 2v14.4a2 2 0 0 0 2 2h9.2a2 2 0 0 0 2-2V7.4L14 2.8Z" />
      <path d="M14 2.8v4.6h4.6" />
      <path d="m9.2 15.4 1.9 1.9 3.7-3.9" />
    </>
  ),
  settings: (
    <>
      <circle cx="12" cy="12" r="3.2" />
      <path d="M12 2.6v2.2M12 19.2v2.2M21.4 12h-2.2M4.8 12H2.6M18.6 5.4l-1.5 1.5M6.9 17.1l-1.5 1.5M18.6 18.6l-1.5-1.5M6.9 6.9 5.4 5.4" />
    </>
  ),
  link: (
    <>
      <path d="M10 13.5a4 4 0 0 0 6 .5l2.5-2.5a4 4 0 0 0-5.7-5.7L11.4 7.2" />
      <path d="M14 10.5a4 4 0 0 0-6-.5l-2.5 2.5a4 4 0 0 0 5.7 5.7l1.4-1.4" />
    </>
  ),
  sparkle: (
    <>
      <path d="M12 3.2 13.8 9l5.8 1.8-5.8 1.8L12 18.4l-1.8-5.8L4.4 10.8 10.2 9 12 3.2Z" />
      <path d="M18.8 3v2.6M20.1 4.3h-2.6" />
    </>
  )
};

export default function Icon({ name, size = 16 }) {
  const shape = SHAPES[name];
  if (!shape) return null;
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {shape}
    </svg>
  );
}
