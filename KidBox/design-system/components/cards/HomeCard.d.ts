import * as React from "react";

/**
 * Tinted Home-grid category tile. Fills its tint at 10%, borders at 18%.
 */
export interface HomeCardProps {
  title: string;
  subtitle?: string;
  /** Icon node (Lucide/SF-style glyph); inherits the tint color. */
  icon?: React.ReactNode;
  /** Category color — a --kb-cat-* token or hex. */
  tint?: string;
  /** Red count badge (0 hides it). */
  badge?: number;
  /** Show a small lock (gated feature). */
  locked?: boolean;
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  style?: React.CSSProperties;
}

export function HomeCard(props: HomeCardProps): JSX.Element;
