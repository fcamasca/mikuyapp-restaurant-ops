import { useEffect, useRef, useState, type ReactNode } from "react";
import type { ApplicationRoute } from "../services/appRoutes";
import type { ValidatedProfileContext } from "../services/profileContext";
import AuthenticatedUserMenu from "./AuthenticatedUserMenu";
import CashNotificationBell from "./CashNotificationBell";

interface AdminShellProps {
  readonly active: ApplicationRoute;
  readonly children: ReactNode;
  readonly context: ValidatedProfileContext;
  readonly isSigningOut: boolean;
  readonly onNavigate: (route: ApplicationRoute) => void;
  readonly onSignOut: () => void;
}

const groups: ReadonlyArray<{ label: string; items: ReadonlyArray<{ icon: string; label: string; route?: ApplicationRoute }> }> = [
  { label: "", items: [{ icon: "⌂", label: "Inicio", route: "/admin/inicio" }] },
  { label: "OPERACIÓN", items: [{ icon: "!", label: "Pendientes por aprobar", route: "/admin/pendientes" }] },
  { label: "REPORTES", items: [{ icon: "$", label: "Caja", route: "/admin/caja" }, { icon: "↗", label: "Ventas", route: "/admin/ventas" }] },
  { label: "CONFIGURACIÓN", items: [{ icon: "≡", label: "Carta", route: "/admin/carta" }, { icon: "▦", label: "Mesas", route: "/admin/mesas" }, { icon: "○", label: "Usuarios" }] },
];

export default function AdminShell({ active, children, context, isSigningOut, onNavigate, onSignOut }: AdminShellProps) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const drawerRef = useRef<HTMLElement>(null);

  useEffect(() => {
    if (!drawerOpen) return;
    function closeOnEscape(event: KeyboardEvent): void {
      if (event.key === "Escape") setDrawerOpen(false);
    }
    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, [drawerOpen]);

  function navigate(route: ApplicationRoute): void {
    setDrawerOpen(false);
    onNavigate(route);
  }

  const navigation = (compact = false) => (
    <nav aria-label="Navegación administrativa" className={compact ? "space-y-3" : "space-y-5"}>
      {groups.map((group) => (
        <section className={compact && group.label ? "border-t border-stone-200 pt-3" : ""} key={group.label || "inicio"}>
          {!compact && group.label && <h2 className="mb-2 px-3 text-xs font-bold tracking-[0.14em] text-stone-500">{group.label}</h2>}
          <ul className={`space-y-1 ${!compact && group.label ? "ml-3 border-l border-stone-200 pl-2" : ""}`}>
            {group.items.map((item) => {
              const selected = item.route === active;
              return <li key={item.label}>{item.route
                ? <button aria-current={selected ? "page" : undefined} aria-label={compact ? item.label : undefined} className={`flex min-h-11 w-full items-center rounded-xl border-l-2 text-sm font-semibold transition ${compact ? "justify-center px-0" : "gap-3 px-3 text-left"} ${selected ? "border-emerald-700 bg-emerald-100 text-emerald-950" : "border-transparent text-stone-700 hover:bg-stone-100"}`} onClick={() => navigate(item.route!)} title={compact ? item.label : undefined} type="button"><span aria-hidden="true" className="flex size-6 shrink-0 items-center justify-center text-base font-bold">{item.icon}</span>{!compact && <span>{item.label}</span>}</button>
                : <button aria-disabled="true" aria-label={compact ? item.label : undefined} className={`flex min-h-11 w-full cursor-not-allowed items-center rounded-xl text-sm font-semibold text-stone-400 ${compact ? "justify-center px-0" : "gap-3 px-3 text-left"}`} disabled title="Gestión de usuarios no disponible en T16" type="button"><span aria-hidden="true" className="flex size-6 shrink-0 items-center justify-center text-base font-bold">{item.icon}</span>{!compact && <span>{item.label}</span>}</button>}
              </li>;
            })}
          </ul>
        </section>
      ))}
    </nav>
  );

  return <div className={`min-h-screen overflow-x-hidden bg-stone-100 text-stone-900 lg:grid ${sidebarCollapsed ? "lg:grid-cols-[4.5rem_minmax(0,1fr)]" : "lg:grid-cols-[15rem_minmax(0,1fr)]"}`}>
    <aside className={`hidden border-r border-stone-200 bg-white lg:block ${sidebarCollapsed ? "p-2" : "p-4"}`}>
      <div className={`mb-6 flex items-center ${sidebarCollapsed ? "flex-col gap-3" : "justify-between gap-2"}`}>
        <p className="truncate text-lg font-bold text-emerald-800">{sidebarCollapsed ? "M" : "MikuyApp"}</p>
        <button aria-expanded={!sidebarCollapsed} aria-label={sidebarCollapsed ? "Mostrar menú lateral" : "Ocultar menú lateral"} className="flex size-9 shrink-0 items-center justify-center rounded-lg text-stone-600 transition hover:bg-stone-100 hover:text-stone-950 focus:outline-none focus:ring-4 focus:ring-stone-200" onClick={() => setSidebarCollapsed((value) => !value)} title={sidebarCollapsed ? "Mostrar menú lateral" : "Ocultar menú lateral"} type="button"><svg aria-hidden="true" className="size-5" fill="none" viewBox="0 0 24 24"><rect height="16" rx="2" stroke="currentColor" strokeWidth="1.8" width="18" x="3" y="4"/><path d="M9 4v16" stroke="currentColor" strokeWidth="1.8"/><path d={sidebarCollapsed ? "m5.5 10 2 2-2 2" : "m6.5 10-2 2 2 2"} stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8"/></svg></button>
      </div>
      {navigation(sidebarCollapsed)}
    </aside>
    {drawerOpen && <div className="fixed inset-0 z-40 bg-stone-950/35 lg:hidden" onPointerDown={(event) => { if (event.target === event.currentTarget) setDrawerOpen(false); }}>
      <aside aria-modal="true" className="h-full w-[min(19rem,86vw)] overflow-y-auto bg-white p-4 shadow-2xl" ref={drawerRef} role="dialog">
        <div className="mb-6 flex items-center justify-between"><b className="text-emerald-800">MikuyApp</b><button aria-label="Cerrar menú" className="size-11 rounded-xl border border-stone-300 text-xl" onClick={() => setDrawerOpen(false)} type="button">×</button></div>
        {navigation()}
      </aside>
    </div>}
    <div className="min-w-0">
      <header className="sticky top-0 z-30 flex min-h-16 items-center justify-between gap-3 border-b border-stone-200 bg-white/95 px-3 backdrop-blur sm:px-6">
        <div className="flex min-w-0 items-center gap-3"><button aria-expanded={drawerOpen} aria-label="Abrir menú de Administración" className="size-11 shrink-0 rounded-xl border border-stone-300 text-xl lg:hidden" onClick={() => setDrawerOpen(true)} type="button">☰</button><div className="min-w-0"><b className="block truncate">Administración</b><span className="block truncate text-xs text-stone-500">{context.local.nombre}</span></div></div>
        <div className="flex items-center gap-2"><CashNotificationBell context={context} /><AuthenticatedUserMenu context={context} isSigningOut={isSigningOut} onSignOut={onSignOut} /></div>
      </header>
      <div className="min-w-0">{children}</div>
    </div>
  </div>;
}
